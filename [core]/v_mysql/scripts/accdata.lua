-- v_mysql :: account data store
--
-- The `accounts` table is the ONLY home for account data. The mod no longer
-- uses MTA's built-in account system (getAccountData / setAccountData /
-- logIn / ...). Everything goes through the two exports here:
--
--   exports.v_mysql:getAccData(who [, key])
--       who = player element | account-name string
--       key given   -> the stored value, typed (string / number / boolean),
--                      or nil when it was never set
--       key omitted -> a { key = value, ... } copy of everything stored
--
--   exports.v_mysql:setAccData(who, key, value)      -- one key (nil deletes)
--   exports.v_mysql:setAccData(who, { key = value }) -- several keys, one write
--       returns true when the write was queued.
--
-- Storage: most keys live in the `account_data` column as a JSON object
--   { "money": { "v": "1500", "t": "int" }, "skin": { "v": "295", "t": "int" } }
-- A few keys are promoted to real columns (see COLUMN below) so they can be
-- read/edited from outside the game (a website, admin tooling); getAccData /
-- setAccData map them transparently, so callers never care which is which.
--
-- A per-account in-memory cache serves reads without a round trip. It is
-- filled on first access (only for accounts logged in on this server), updated
-- on every setAccData, flushed on login and dropped after onPlayerQuit (two
-- servers share this table and do not sync live, so a cached value could
-- otherwise go stale after the player leaves). prefetchAccDataAsync loads a
-- list of offline accounts in one non-blocking query for the reads right after
-- it (PERF-01, MEMO_TTL).
--
-- Writes are per key (JSON_MERGE_PATCH), never the whole blob, so one server
-- cannot overwrite keys another server changed (BUG-01). Needs MySQL >= 5.7.22
-- or MariaDB >= 10.2.25.

local TABLE = "accounts"

-- key -> column name. These never go into the JSON blob.
local COLUMN     = { email = "email", display_name = "display_name", admin_level = "admin_level", created_at = "created_at" }
local COLUMN_NUM = { admin_level = true, created_at = true }

local cache = {}   -- cache[name] = { data = { <key> = <typed value> }, exists = bool }

--------------------------------------------------------------------------------
-- Value (de)serialisation
--------------------------------------------------------------------------------

local function packValue(v)
    local t = type(v)
    if t == "boolean" then
        return tostring(v), "boolean"
    elseif t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then
            return ("%d"):format(v), "int"
        end
        return tostring(v), "float"
    end
    return tostring(v), "string"
end

local function unpackValue(value, valueType)
    if valueType == "boolean" then
        return value == "true"
    elseif valueType == "int" or valueType == "float" then
        return tonumber(value)
    end
    return tostring(value)
end

local function decodeBlob(jsonStr)
    local obj = fromJSON(jsonStr or "")
    local out = {}
    if type(obj) == "table" then
        for key, rec in pairs(obj) do
            -- Older writes stored a key's record as toJSON() made it, wrapped in an
            -- array: "k": [ {"v":..,"t":..} ]. Read both shapes.
            if type(rec) == "table" and rec.v == nil and type(rec[1]) == "table" then rec = rec[1] end
            if type(rec) == "table" and rec.v ~= nil then
                out[key] = unpackValue(rec.v, rec.t)
            end
        end
    end
    return out
end

local function encodeBlob(tbl)
    local obj = {}
    for key, value in pairs(tbl) do
        if not COLUMN[key] and value ~= nil then
            local packed, valueType = packValue(value)
            obj[key] = { v = packed, t = valueType }
        end
    end
    return next(obj) and toJSON(obj) or "{}"
end

--------------------------------------------------------------------------------
-- Identity
--------------------------------------------------------------------------------

-- who -> account-name string, or nil. Player elements resolve through the
-- "accName" element data v_accounts sets on login.
local function resolveName(who)
    if type(who) == "string" then
        return who ~= "" and who or nil
    end
    if isElement(who) and getElementType(who) == "player" then
        local n = getElementData(who, "accName")
        return (type(n) == "string" and n ~= "") and n or nil
    end
    return nil
end

--------------------------------------------------------------------------------
-- Cache / persistence
--------------------------------------------------------------------------------

-- Is an account logged in on THIS server right now?
local function isOnline(name)
    for _, p in ipairs(getElementsByType("player")) do
        if getElementData(p, "accName") == name then return true end
    end
    return false
end

-- Offline accounts are not cached, but prefetchAccDataAsync can load a list of
-- them in one non-blocking query into a short-lived memo (PERF-01): the reads
-- right after it (same callback) are then served from memory. Only the
-- prefetch fills the memo, so a plain read of an offline account is as fresh
-- as before; MEMO_TTL bounds how old a prefetched value can get. Writes made on
-- THIS server update the memo entry in place, so they are always seen here.
--   memo[name] = { c = <entry like cache[name]>, expires = tick }
local MEMO_TTL      = 1000
local MEMO_MAX_LIST = 500     -- names per prefetch query
local memo    = {}
local dirtyAt = {}            -- dirtyAt[name] = tick of the last setAccData here (prefetch race guard)

local SELECT_COLS = "account_name, account_data, email, display_name, admin_level, created_at"

local function rowToEntry(row)
    local c = { data = {}, exists = false }
    if row then
        c.exists = true
        c.data = decodeBlob(row.account_data)
        c.data.email        = (row.email ~= false) and row.email or nil
        c.data.display_name  = (row.display_name ~= false) and row.display_name or nil
        c.data.admin_level   = tonumber(row.admin_level) or 0
        c.data.created_at    = tonumber(row.created_at) or 0
    end
    return c
end

-- set of the account names logged in on this server
local function onlineNames()
    local set = {}
    for _, p in ipairs(getElementsByType("player")) do
        local n = getElementData(p, "accName")
        if type(n) == "string" then set[n] = true end
    end
    return set
end

local function memoGet(name)
    local m = memo[name]
    if m and m.expires > getTickCount() then return m.c end
    return nil
end

-- Only accounts logged in here are cached: an offline account may be played on
-- the other server meanwhile, so it is read fresh (unless just prefetched).
local function load(name)
    local c = cache[name]
    if c then return c end

    local online = isOnline(name)
    if not online then
        c = memoGet(name)
        if c then return c end
    end

    local res = mysqlQuerySync(
        "SELECT " .. SELECT_COLS .. " FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name)
    if res == false then
        -- The query FAILED (no connection, timeout, ...): this is not "the account is
        -- empty". Never cache it and never let it be written back (setAccData refuses
        -- a failed entry), else the player is treated as brand new and the defaults
        -- overwrite the real data.
        mysqlLog("getAccData: load of '%s' failed, data unavailable", name)
        return { data = {}, exists = false, failed = true }
    end
    c = rowToEntry(res[1])
    if online then
        cache[name] = c
        memo[name] = nil
    end
    return c
end

-- Drop expired memo entries and old write marks now and then.
setTimer(function()
    local now = getTickCount()
    for name, m in pairs(memo) do
        if m.expires <= now then memo[name] = nil end
    end
    for name, t in pairs(dirtyAt) do
        if now - t > 60000 then dirtyAt[name] = nil end
    end
end, 30000, 0)

-- JSON string literal for a key (control chars, quotes and backslashes escaped).
local function jsonStr(str)
    return '"' .. (str:gsub('[%c"\\]', function(ch) return ("\\u%04x"):format(ch:byte()) end)) .. '"'
end

-- Writes ONLY the keys in `changed` (set of key -> true) so a write never
-- overwrites keys another server changed meanwhile (BUG-01). Blob keys go
-- through JSON_MERGE_PATCH on the stored document: `"k": {...}` sets, `"k": null`
-- removes. Promoted columns are updated individually. The row is created when
-- missing: UPDATE first, guarded INSERT only if nothing matched (no upsert, see below).
local function persist(name, c, changed)
    local ts = getRealTime().timestamp

    local setParts, patchParts = {}, {}
    for key in pairs(changed) do
        if not COLUMN[key] then
            local value = c.data[key]
            if value == nil then
                patchParts[#patchParts + 1] = jsonStr(key) .. ":null"
            else
                local packed, valueType = packValue(value)
                patchParts[#patchParts + 1] = jsonStr(key) .. ":{\"v\":" .. jsonStr(packed) .. ",\"t\":\"" .. valueType .. "\"}"
            end
        end
    end
    local patch = "{" .. table.concat(patchParts, ",") .. "}"

    -- UPDATE of the existing row: only what changed (nil columns become literal NULL).
    local uArgs = {}
    if #patchParts > 0 then
        setParts[#setParts + 1] = "account_data = JSON_MERGE_PATCH(IF(account_data IS NULL OR account_data = '', '{}', account_data), ?)"
        uArgs[#uArgs + 1] = patch
    end
    for _, col in ipairs({ "email", "display_name", "admin_level" }) do
        if changed[col] then
            local v = c.data[col]
            if v == nil then
                setParts[#setParts + 1] = col .. " = NULL"
            else
                setParts[#setParts + 1] = col .. " = ?"
                uArgs[#uArgs + 1] = (col == "admin_level") and (tonumber(v) or 0) or v
            end
        end
    end
    setParts[#setParts + 1] = "updated_at = ?"
    uArgs[#uArgs + 1] = ts
    uArgs[#uArgs + 1] = name

    -- INSERT of a brand-new row, only when the UPDATE matched nothing. It is
    -- INSERT ... SELECT ... WHERE NOT EXISTS, not ON DUPLICATE KEY UPDATE: that
    -- form reserves an AUTO_INCREMENT id before it notices the duplicate, so
    -- every save of an existing account used up one `accounts.id`.
    local iArgs = { name }
    local insertBlob = {}
    for key in pairs(changed) do
        if not COLUMN[key] and c.data[key] ~= nil then insertBlob[key] = c.data[key] end
    end
    iArgs[#iArgs + 1] = encodeBlob(insertBlob)
    local function colSql(col)
        local v = c.data[col]
        if v == nil then return "NULL" end
        iArgs[#iArgs + 1] = v
        return "?"
    end
    local emailSql   = colSql("email")
    local displaySql = colSql("display_name")
    iArgs[#iArgs + 1] = tonumber(c.data.admin_level) or 0
    iArgs[#iArgs + 1] = tonumber(c.data.created_at) or ts
    iArgs[#iArgs + 1] = ts
    iArgs[#iArgs + 1] = name
    local insertSql =
        "INSERT INTO `" .. TABLE .. "` " ..
        "(account_name, account_data, email, display_name, admin_level, created_at, updated_at) " ..
        "SELECT ?, ?, " .. emailSql .. ", " .. displaySql .. ", ?, ?, ? FROM DUAL " ..
        "WHERE NOT EXISTS (SELECT 1 FROM `" .. TABLE .. "` WHERE account_name = ?)"
    local updateSql =
        "UPDATE `" .. TABLE .. "` SET " .. table.concat(setParts, ", ") .. " WHERE account_name = ?"

    return mysqlExecCb(function(ok, affected)
        if not ok or affected > 0 then return end
        -- No row was changed: either it does not exist yet, or MySQL reported 0
        -- because every value was identical. The guarded INSERT is a no-op in the
        -- second case.
        mysqlExecCb(nil, insertSql, unpack(iArgs))
    end, updateSql, unpack(uArgs))
end

-- Forget an account on quit so a later login reads fresh from the DB. Deferred
-- one tick: other resources' onPlayerQuit handlers (v_accounts save_all, ...)
-- run after this one and would otherwise re-fill the cache for good.
addEventHandler("onPlayerQuit", root, function()
    local n = getElementData(source, "accName")
    if type(n) == "string" and n ~= "" then
        setTimer(function()
            if not isOnline(n) then cache[n] = nil end
        end, 50, 1)
    end
end)

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

function getAccData(who, key)
    local name = resolveName(who)
    if not name then return nil end
    local c = load(name)

    if key == nil then
        local copy = {}
        for k, v in pairs(c.data) do copy[k] = v end
        return copy
    end
    return c.data[tostring(key)]
end

function setAccData(who, key, value)
    local name = resolveName(who)
    if not name then return false end

    local c = load(name)
    if c.failed then return false end -- the stored data could not be read: do not write over it
    dirtyAt[name] = getTickCount()

    local changed = {}
    if type(key) == "table" then
        for k, v in pairs(key) do
            k = tostring(k)
            if COLUMN_NUM[k] then v = tonumber(v) or 0 end
            c.data[k] = v
            changed[k] = true
        end
    elseif type(key) == "string" and key ~= "" then
        if COLUMN_NUM[key] then value = tonumber(value) or 0 end
        c.data[key] = value
        changed[key] = true
    else
        return false
    end

    return persist(name, c, changed)
end

-- Internal: called by v_accounts right after it creates a row, so the cache
-- does not keep a stale "account does not exist" view.
function flushAccData(name)
    if type(name) == "string" then
        cache[name] = nil
        memo[name] = nil
    end
end

-- Non-blocking load of an account that is ABOUT to log in (v_accounts): reads the
-- row fresh, puts it into the session cache and answers
--   triggerEvent(eventName, <caller resourceRoot>, requestId, ok)
-- ok = false: the data could not be read, the login must be refused (a login on
-- empty data would reset the player). The cache entry stays until the player
-- quits; call flushAccData(name) if the login is abandoned.
function loadAccDataAsync(eventName, requestId, name)
    local caller = sourceResource
    if type(eventName) ~= "string" or type(name) ~= "string" or name == "" or not caller then return false end
    local target = getResourceRootElement(caller)
    local function reply(ok)
        if isElement(target) then triggerEvent(eventName, target, requestId, ok) end
    end
    cache[name], memo[name] = nil, nil
    local sentAt = getTickCount()
    local queued = mysqlQuery(function(rows)
        if type(rows) ~= "table" then
            mysqlLog("loadAccDataAsync: load of '%s' failed", name)
            return reply(false)
        end
        if (dirtyAt[name] or -1) >= sentAt then return reply(false) end -- written meanwhile: retry
        local row = rows[1]
        -- The caller authenticated this account a moment ago, so the row MUST exist.
        if not row then
            mysqlLog("loadAccDataAsync: '%s' has no row, refusing the data (login would start empty)", name)
            return reply(false)
        end
        local entry = rowToEntry(row)
        local raw = tostring(row.account_data or "")
        local parsed = (raw ~= "") and fromJSON(raw) or nil
        local keys = 0
        for k in pairs(entry.data) do if not COLUMN[k] then keys = keys + 1 end end
        local created, updated = tonumber(row.created_at) or 0, tonumber(row.updated_at) or 0
        if raw ~= "" and raw ~= "{}" and type(parsed) ~= "table" then
            mysqlLog("loadAccDataAsync: account_data of '%s' is not readable JSON (%d bytes), refusing", name, #raw)
            return reply(false)
        end
        -- A saved account always has keys (save_all runs at register). Zero keys on an
        -- account that was written to after creation means the data was lost or not read.
        if keys == 0 and updated > created + 5 then
            mysqlLog("loadAccDataAsync: '%s' has NO data keys although it was saved before (created %d, updated %d, %d bytes), refusing",
                name, created, updated, #raw)
            return reply(false)
        end
        mysqlLog("loadAccDataAsync: '%s' loaded, %d data keys, %d bytes", name, keys, #raw)
        cache[name] = entry
        reply(true)
    end, "SELECT " .. SELECT_COLS .. ", updated_at FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name)
    return queued
end

-- Non-blocking warm-up for reads of OFFLINE accounts (PERF-01): loads every
-- listed account that is neither cached nor memoised with ONE query, memoises
-- them for MEMO_TTL, then answers with an event on the caller's resource root:
--   triggerEvent(eventName, <caller resourceRoot>, requestId, ok)
-- After ok = true, getAccData(name, ...) for those names is served from memory
-- (until MEMO_TTL runs out). ok = false: the query failed, nothing was memoised.
-- Online accounts are skipped (their cache is always fresh). At most
-- MEMO_MAX_LIST names per call; the rest simply load on demand.
function prefetchAccDataAsync(eventName, requestId, names)
    local caller = sourceResource
    if type(eventName) ~= "string" or type(names) ~= "table" or not caller then return false end
    local target = getResourceRootElement(caller)
    local function reply(ok)
        if isElement(target) then triggerEvent(eventName, target, requestId, ok) end
    end

    local onlineSet = onlineNames()
    local want, marks, seen = {}, {}, {}
    for _, n in ipairs(names) do
        if #want >= MEMO_MAX_LIST then break end
        if type(n) == "string" and n ~= "" and not seen[n] then
            seen[n] = true
            if not cache[n] and not onlineSet[n] and not memoGet(n) then
                want[#want + 1], marks[#marks + 1] = n, "?"
            end
        end
    end
    if #want == 0 then
        reply(true)
        return true
    end

    local sentAt = getTickCount()
    return mysqlQuery(function(rows)
        if type(rows) ~= "table" then return reply(false) end
        local byLower = {}
        for _, row in ipairs(rows) do
            if type(row.account_name) == "string" then byLower[row.account_name:lower()] = row end
        end
        local expires = getTickCount() + MEMO_TTL
        local nowOnline = onlineNames()
        for _, n in ipairs(want) do
            -- Skip names that were loaded, written or logged in meanwhile: the
            -- answer was read before that and would be older.
            if not cache[n] and not memoGet(n) and not nowOnline[n]
                and (dirtyAt[n] or -1) < sentAt then
                memo[n] = { c = rowToEntry(byLower[n:lower()]), expires = expires }
            end
        end
        reply(true)
    end, "SELECT " .. SELECT_COLS .. " FROM `" .. TABLE .. "` WHERE account_name IN (" ..
        table.concat(marks, ",") .. ")", unpack(want))
end
