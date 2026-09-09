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
-- filled on first access, updated on every setAccData, and dropped on
-- onPlayerQuit (two servers share this table and do not sync live, so a cached
-- value could otherwise go stale after the player leaves).

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
    cache[name] = c
    return c
end

local function persist(name, c)
    local ts = getRealTime().timestamp
    return mysqlExec(
        "INSERT INTO `" .. TABLE .. "` " ..
        "(account_name, account_data, email, display_name, admin_level, created_at, updated_at) " ..
        "VALUES (?, ?, ?, ?, ?, ?, ?) " ..
        "ON DUPLICATE KEY UPDATE " ..
        "account_data = VALUES(account_data), email = VALUES(email), " ..
        "display_name = VALUES(display_name), admin_level = VALUES(admin_level), " ..
        "updated_at = VALUES(updated_at)",
        name,
        encodeBlob(c.data),
        c.data.email,
        c.data.display_name,
        tonumber(c.data.admin_level) or 0,
        tonumber(c.data.created_at) or ts,
        ts)
end

-- Forget an account on quit so a later login reads fresh from the DB.
addEventHandler("onPlayerQuit", root, function()
    local n = getElementData(source, "accName")
    if type(n) == "string" and n ~= "" then
        cache[n] = nil
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

    if type(key) == "table" then
        for k, v in pairs(key) do
            k = tostring(k)
            if COLUMN_NUM[k] then v = tonumber(v) or 0 end
            c.data[k] = v
        end
    elseif type(key) == "string" and key ~= "" then
        if COLUMN_NUM[key] then value = tonumber(value) or 0 end
        c.data[key] = value
    else
        return false
    end

    return persist(name, c)
end

-- Internal: called by v_accounts right after it creates a row, so the cache
-- does not keep a stale "account does not exist" view.
function flushAccData(name)
    if type(name) == "string" then cache[name] = nil end
end
