-- Account System :: account records
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

-- Canonical account_name for `name` if the account exists, else false.
-- (MySQL string compare is case-insensitive, so this also fixes up casing.)
function accountNameExists(name)
    if not mysqlReady() or type(name) ~= "string" or name == "" then return false end
    local res = exports.v_mysql:mysqlQuerySync(
        "SELECT account_name FROM `" .. TABLE .. "` WHERE account_name = ? LIMIT 1", name)
    if res and res[1] and type(res[1].account_name) == "string" then
        return res[1].account_name
    end
    return false
end

-- { account_name, ... } for every registered account (ascending).
function getAllAccountNames()
    if not mysqlReady() then return {} end
    local res = exports.v_mysql:mysqlQuerySync(
        "SELECT account_name FROM `" .. TABLE .. "` ORDER BY account_name ASC")
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

    -- Drop any "does not exist" view v_mysql may have cached before this row.
    exports.v_mysql:flushAccData(name)
    return id
end

-- Replaces an account's password hash. Returns whether the write was queued.
function setAccountHash(name, pwHash)
    if not mysqlReady() then return false end
    return exports.v_mysql:mysqlExec(
        "UPDATE `" .. TABLE .. "` SET password = ?, updated_at = ? WHERE account_name = ?",
        pwHash, getRealTime().timestamp, name)
end
