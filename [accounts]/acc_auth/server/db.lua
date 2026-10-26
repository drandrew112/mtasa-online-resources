-- acc_auth :: account records
--
-- The mod no longer uses MTA's built-in account system. Accounts are rows in
-- the shared `accounts` table (see [core]/v_mysql), reached through v_mysql's
-- generic MySQL exports. This file owns everything that touches the identity
-- columns (account_name / password / email); all the OTHER per-account data
-- goes through exports.v_mysql:getAccData / setAccData.
--
-- Passwords are stored as a bcrypt hash (MTA passwordHash / passwordVerify),
-- never in clear text.

local TABLE = "accounts"

local function mysqlReady()
    local res = getResourceFromName("v_mysql")
    return (res and getResourceState(res) == "running") and true or false
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------

-- Accounts are never deleted or renamed, so a name once found stays valid:
-- known[name:lower()] = canonical name (PERF-01). Only hits are remembered - an
-- account the other server registers must be found on the next lookup.
local KNOWN_MAX = 20000
local known, knownCount = {}, 0

function rememberAccountName(canonical)
    if type(canonical) ~= "string" or canonical == "" then return end
    local key = canonical:lower()
    if known[key] then return end
    if knownCount >= KNOWN_MAX then known, knownCount = {}, 0 end
    known[key] = canonical
    knownCount = knownCount + 1
end

-- Canonical account_name for `name` if the account exists, else false.
-- (MySQL string compare is case-insensitive, so this also fixes up casing.)
-- Blocks only for a name not seen before.
function accountNameExists(name)
    if type(name) ~= "string" or name == "" or name:sub(1, 1) == "#" then return false end -- "#..." = pool row
    local hit = known[name:lower()]
    if hit then return hit end
    if not mysqlReady() then return false end
    local res = exports.v_mysql:mysqlQuerySync(
        "SELECT account_name FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name)
    if res and res[1] and type(res[1].account_name) == "string" then
        rememberAccountName(res[1].account_name)
        return res[1].account_name
    end
    return false
end

-- The canonical name when it was already seen, else nil. Never blocks.
function knownAccountName(name)
    return type(name) == "string" and known[name:lower()] or nil
end

-- Non-blocking name lookup: the row arrives as
-- triggerEvent(eventName, resourceRoot, requestId, rows | false).
-- -> true if the query was queued
function fetchAccountNameAsync(name, eventName, requestId)
    if not mysqlReady() or type(name) ~= "string" or name == "" then return false end
    return exports.v_mysql:mysqlQueryAsync(eventName, requestId,
        "SELECT account_name FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name) == true
end

-- { account_name, ... } for every registered account (ascending).
function getAllAccountNames()
    if not mysqlReady() then return {} end
    local res = exports.v_mysql:mysqlQuerySync(
        "SELECT account_name FROM `" .. TABLE .. "` WHERE account_name NOT LIKE '#%' ORDER BY account_name ASC")
    local out = {}
    for _, row in ipairs(res or {}) do
        if type(row.account_name) == "string" then out[#out + 1] = row.account_name end
    end
    return out
end

-- { id = <number>, password = <hash string> } for an account, or nil.
function fetchAccountAuth(name)
    if not mysqlReady() or type(name) ~= "string" then return nil end
    local res = exports.v_mysql:mysqlQuerySync(
        "SELECT id, password FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name)
    if res and res[1] then
        return { id = tonumber(res[1].id) or 0, password = res[1].password }
    end
    return nil
end

-- Non-blocking variant for the login: one query for the canonical name, id and
-- hash. The row arrives as triggerEvent(eventName, resourceRoot, requestId, rows|false).
-- -> true if the query was queued
function fetchAccountAuthAsync(name, eventName, requestId)
    if not mysqlReady() or type(name) ~= "string" then return false end
    return exports.v_mysql:mysqlQueryAsync(eventName, requestId,
        "SELECT id, account_name, password FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name) == true
end

--------------------------------------------------------------------------------
-- Writes
--------------------------------------------------------------------------------

-- Creates a fresh account row. `pwHash` must already be a bcrypt hash.
-- Returns the new row id, or false.
function createAccountRow(name, pwHash, email)
    if not mysqlReady() then return false end
    local ts = getRealTime().timestamp
    local id = exports.v_mysql:mysqlInsert(
        "INSERT INTO `" .. TABLE .. "` " ..
        "(account_name, password, email, display_name, admin_level, account_data, created_at, updated_at) " ..
        "VALUES (?, ?, ?, ?, 0, '{}', ?, ?)",
        name, pwHash, email, name, ts, ts)
    if type(id) ~= "number" then return false end

    accountRowCreated(name)
    return id
end

-- Non-blocking createAccountRow (PERF-01). The answer is
--   triggerEvent(eventName, resourceRoot, requestId, id | false, err)
-- err names a duplicate key when the name is already taken (account_name is
-- UNIQUE). Call accountRowCreated(name) once it succeeded.
-- -> true if the insert was sent (false: no answer event will come, unless
--    the database is down, in which case it already came)
function createAccountRowAsync(name, pwHash, email, eventName, requestId)
    if not mysqlReady() then return false end
    local ts = getRealTime().timestamp
    return exports.v_mysql:mysqlInsertAsync(eventName, requestId,
        "INSERT INTO `" .. TABLE .. "` " ..
        "(account_name, password, email, display_name, admin_level, account_data, created_at, updated_at) " ..
        "VALUES (?, ?, ?, ?, 0, '{}', ?, ?)",
        name, pwHash, email, name, ts, ts) == true
end

function accountRowCreated(name)
    rememberAccountName(name)
    -- Drop any "does not exist" view v_mysql may have cached before this row.
    exports.v_mysql:flushAccData(name)
end

-- Replaces an account's password hash. Returns whether the write was queued.
function setAccountHash(name, pwHash)
    if not mysqlReady() then return false end
    return exports.v_mysql:mysqlExec(
        "UPDATE `" .. TABLE .. "` SET password = ?, updated_at = ? WHERE account_name = ?",
        pwHash, getRealTime().timestamp, name)
end

--------------------------------------------------------------------------------
-- Email (accounts.email, UNIQUE; NULL = no email)
--------------------------------------------------------------------------------

-- One-off at start: empty strings become NULL and the column gets its UNIQUE
-- index (several NULLs are allowed). Logged, not fatal, when duplicates exist.
function ensureEmailIndex()
    if not mysqlReady() or exports.v_mysql:mysqlIsConnected() ~= true then return end
    exports.v_mysql:mysqlExec("UPDATE `" .. TABLE .. "` SET email = NULL WHERE email = ''")
    local rows = exports.v_mysql:mysqlQuerySync("SHOW INDEX FROM `" .. TABLE .. "` WHERE Key_name = 'uniq_email'")
    if type(rows) == "table" and not rows[1] then
        -- mysqlInsertAsync is the exported write with an answer (id is 0 here)
        exports.v_mysql:mysqlInsertAsync("acc_auth:emailIndex", 0,
            "ALTER TABLE `" .. TABLE .. "` ADD UNIQUE KEY `uniq_email` (`email`)")
    end
end

addEvent("acc_auth:emailIndex")
addEventHandler("acc_auth:emailIndex", resourceRoot, function(_, result, err)
    if result == false then
        outputServerLog("[acc_auth] could not add the UNIQUE email index (duplicate emails in `accounts`?): " .. tostring(err))
    end
end)

-- Row { id, account_name, password, email } of an account, async:
-- triggerEvent(eventName, resourceRoot, requestId, rows | false). -> queued?
function fetchAccountRowAsync(name, eventName, requestId)
    if not mysqlReady() or type(name) ~= "string" then return false end
    return exports.v_mysql:mysqlQueryAsync(eventName, requestId,
        "SELECT id, account_name, password, email FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name) == true
end

-- Row { id, account_name, email } of the account using this email, async.
function fetchAccountByEmailAsync(email, eventName, requestId)
    if not mysqlReady() or type(email) ~= "string" then return false end
    return exports.v_mysql:mysqlQueryAsync(eventName, requestId,
        "SELECT id, account_name, email FROM `" .. TABLE .. "` WHERE email = ? LIMIT 1", email) == true
end

-- email = nil removes it. Returns whether the write was queued.
function setAccountEmail(name, email)
    if not mysqlReady() then return false end
    return exports.v_mysql:mysqlExec(
        "UPDATE `" .. TABLE .. "` SET email = ?, updated_at = ? WHERE account_name = ?",
        email, getRealTime().timestamp, name)
end
