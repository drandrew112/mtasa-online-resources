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
-- otherwise go stale after the player leaves).
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

-- Only accounts logged in here are cached: an offline account may be played on
-- the other server meanwhile, so name-based reads/writes for it always hit the DB.
local function load(name)
    local c = cache[name]
    if c then return c end

    c = { data = {}, exists = false }
    local res = mysqlQuerySync(
        "SELECT account_data, email, display_name, admin_level, created_at " ..
        "FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name)
    if res and res[1] then
        c.exists = true
        c.data = decodeBlob(res[1].account_data)
        c.data.email        = (res[1].email ~= false) and res[1].email or nil
        c.data.display_name  = (res[1].display_name ~= false) and res[1].display_name or nil
        c.data.admin_level   = tonumber(res[1].admin_level) or 0
        c.data.created_at    = tonumber(res[1].created_at) or 0
    end
    if isOnline(name) then cache[name] = c end
    return c
end

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
                patchParts[#patchParts + 1] = jsonStr(key) .. ":" .. toJSON({ v = packed, t = valueType }, true)
            end
        end
    end
    local patch = "{" .. table.concat(patchParts, ",") .. "}"

    -- UPDATE of the existing row: only what changed (nil columns become literal NULL).
    local uArgs = {}
    if #patchParts > 0 then
        setParts[#setParts + 1] = "account_data = JSON_MERGE_PATCH(IF(JSON_VALID(account_data), account_data, '{}'), ?)"
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
    if type(name) == "string" then cache[name] = nil end
end
