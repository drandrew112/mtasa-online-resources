-- v_bank / server/db.lua
-- Tables (DESIGN.md 2), the async MySQL lib and small helpers. The schema runs on start; when it is
-- done the migration (server/migrate.lua) and the account loading (server/accounts.lua) start.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

DB = { ready = false }

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS bank_accounts (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        number VARCHAR(20) NULL,
        kind VARCHAR(16) NOT NULL,
        owner_ref VARCHAR(64) NOT NULL,
        name VARCHAR(64) NOT NULL DEFAULT '',
        balance BIGINT NOT NULL DEFAULT 0,
        allow_negative TINYINT NOT NULL DEFAULT 0,
        status VARCHAR(16) NOT NULL DEFAULT 'active',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        closed_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (id),
        UNIQUE KEY uq_number (number),
        UNIQUE KEY uq_owner (kind, owner_ref),
        KEY idx_kind (kind, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS bank_account_access (
        account_id INT UNSIGNED NOT NULL,
        account_name VARCHAR(64) NOT NULL,
        role VARCHAR(16) NOT NULL,
        granted_by VARCHAR(64) NOT NULL DEFAULT '',
        granted_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (account_id, account_name),
        KEY idx_name (account_name)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    [[CREATE TABLE IF NOT EXISTS bank_ledger (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        account_id INT UNSIGNED NOT NULL,
        ts INT UNSIGNED NOT NULL,
        amount BIGINT NOT NULL,
        balance_after BIGINT NULL,
        tx_key VARCHAR(48) NOT NULL,
        params VARCHAR(255) NOT NULL DEFAULT '',
        counter_id INT UNSIGNED NULL,
        ref VARCHAR(32) NOT NULL DEFAULT '',
        actor VARCHAR(64) NOT NULL DEFAULT '',
        instance VARCHAR(16) NOT NULL DEFAULT '',
        PRIMARY KEY (id),
        KEY idx_account (account_id, id),
        KEY idx_key (tx_key, ts)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

addEvent("v_bank:dbReady", false)

local function runSchema(i)
    if i > #SCHEMA then
        DB.ready = true
        triggerEvent("v_bank:dbReady", resourceRoot)
        return
    end
    MYSQL.query(function(ok, err)
        if ok == false then
            outputDebugString("[v_bank] schema " .. i .. " failed: " .. tostring(err), 1)
            -- retry later: v_mysql may not be connected yet
            setTimer(runSchema, 10000, 1, i)
            return
        end
        runSchema(i + 1)
    end, SCHEMA[i])
end

function DB.start()
    runSchema(1)
end

function DB.exec(sql, ...)
    local res = getResourceFromName("v_mysql")
    if not res or getResourceState(res) ~= "running" then return false end
    return exports.v_mysql:mysqlExec(sql, ...)
end

function DB.query(cb, sql, ...)
    return MYSQL.query(cb, sql, ...)
end

--- integer of a DB value (MySQL BIGINT can arrive as string)
function DB.int(v)
    return math.floor(tonumber(v) or 0)
end

--- short text for VARCHAR columns
function DB.clip(s, n)
    s = tostring(s or "")
    if #s > n then s = s:sub(1, n) end
    return s
end

function BANK.now()
    return getRealTime().timestamp
end

function isResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

--- id of this server instance (v_main), "" without v_main
function BANK.instance()
    if not isResourceRunning("v_main") then return "" end
    return tostring(exports.v_main:getServerInstanceId() or "")
end

--- account name of a logged-in player (lower-case), or nil
function BANK.accountOf(player)
    if not isElement(player) or getElementType(player) ~= "player" then return nil end
    if getElementData(player, "isLogged") ~= true then return nil end
    local name = getElementData(player, "accName")
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end

--- SQL: the account number of a row, from its id and kind
function BANK.numberSql()
    return "CONCAT('LB-', CASE kind WHEN 'personal' THEN 1 WHEN 'company' THEN 2 ELSE 9 END, '-', LPAD(id, 6, '0'))"
end
