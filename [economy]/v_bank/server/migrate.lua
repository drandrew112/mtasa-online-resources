-- v_bank / server/migrate.lua
-- Runs on every start, after the schema (DESIGN.md 7). Every step is idempotent (uq_owner +
-- INSERT IGNORE / NOT EXISTS), so both server instances may run it at the same time.
--   1. the state accounts of BANK.STATE
--   2. a personal account for every player account without one, balance = the old accData
--      bank_money, + a migration.opening ledger row
--   3. bank_money is removed from the account data (the table + cache own it from now on)
--   4. a company account for every active biz_core organization without one, balance =
--      balance_clean (which is then zeroed), + owner access row + opening row
--   5. account numbers of the new rows

local function bankMoneySql()
    local k = '"bank_money"'
    return ("(CASE WHEN JSON_VALID(account_data) THEN COALESCE("
        .. "JSON_UNQUOTE(JSON_EXTRACT(account_data, '$.%s.v')), "
        .. "JSON_UNQUOTE(JSON_EXTRACT(account_data, '$.%s[0].v')), "
        .. "JSON_UNQUOTE(JSON_EXTRACT(account_data, '$[0].%s.v'))) END)"):format(k, k, k)
end

local function steps(runTag, now)
    local inst = DB.clip(BANK.instance(), 16)
    local list = {}

    -- 1. state accounts
    for _, s in ipairs(BANK.STATE) do
        list[#list + 1] = { "INSERT IGNORE INTO bank_accounts (kind, owner_ref, name, allow_negative, created_at, created_by) VALUES ('state', ?, ?, ?, ?, ?)",
            s.code, s.name, s.allowNegative and 1 or 0, now, runTag }
    end

    -- 2. personal accounts from the old bank_money
    list[#list + 1] = { "INSERT IGNORE INTO bank_accounts (kind, owner_ref, name, balance, created_at, created_by) "
        .. "SELECT 'personal', LOWER(a.account_name), a.account_name, "
        .. "COALESCE(FLOOR(CAST(" .. bankMoneySql() .. " AS DECIMAL(20,2))), 0), ?, ? "
        .. "FROM accounts a WHERE NOT EXISTS (SELECT 1 FROM bank_accounts b WHERE b.kind = 'personal' AND b.owner_ref = LOWER(a.account_name))",
        now, runTag }

    -- 3. bank_money out of the account data
    list[#list + 1] = { "UPDATE accounts a JOIN bank_accounts b ON b.kind = 'personal' AND b.owner_ref = LOWER(a.account_name) "
        .. "SET a.account_data = JSON_REMOVE(a.account_data, '$.bank_money') "
        .. "WHERE JSON_VALID(a.account_data) AND JSON_TYPE(a.account_data) = 'OBJECT' AND JSON_CONTAINS_PATH(a.account_data, 'one', '$.bank_money')" }

    -- 4. company accounts (biz_core may not have its tables yet: a failure here is not fatal)
    list[#list + 1] = { optional = true, "INSERT IGNORE INTO bank_accounts (kind, owner_ref, name, balance, created_at, created_by) "
        .. "SELECT 'company', c.id, c.name, c.balance_clean, ?, ? FROM biz_companies c "
        .. "WHERE c.status = 'active' AND NOT EXISTS (SELECT 1 FROM bank_accounts b WHERE b.kind = 'company' AND b.owner_ref = CAST(c.id AS CHAR))",
        now, runTag }
    list[#list + 1] = { optional = true, "UPDATE biz_companies c JOIN bank_accounts b ON b.kind = 'company' AND b.owner_ref = CAST(c.id AS CHAR) "
        .. "SET c.balance_clean = 0 WHERE b.created_by = ?", runTag }
    list[#list + 1] = { optional = true, "INSERT IGNORE INTO bank_account_access (account_id, account_name, role, granted_by, granted_at) "
        .. "SELECT b.id, LOWER(c.owner_account), 'owner', 'migration', ? FROM bank_accounts b "
        .. "JOIN biz_companies c ON b.kind = 'company' AND b.owner_ref = CAST(c.id AS CHAR) "
        .. "WHERE b.created_by = ? AND c.owner_account IS NOT NULL", now, runTag }

    -- opening rows of everything this run created with money on it
    list[#list + 1] = { "INSERT INTO bank_ledger (account_id, ts, amount, balance_after, tx_key, params, ref, actor, instance) "
        .. "SELECT id, ?, balance, balance, 'migration.opening', '', ?, 'migration', ? FROM bank_accounts "
        .. "WHERE created_by = ? AND balance <> 0", now, DB.clip(runTag, 32), inst, runTag }

    -- 5. numbers
    list[#list + 1] = { "UPDATE bank_accounts SET number = " .. BANK.numberSql() .. " WHERE number IS NULL" }
    return list
end

function runMigration(cb)
    local now = BANK.now()
    local runTag = DB.clip(("migration:%s:%d"):format(BANK.instance(), now), 64)
    local list = steps(runTag, now)
    local function run(i)
        if i > #list then
            -- the old key is gone from the table; drop it from v_mysql's cache of the online players too
            for _, player in ipairs(getElementsByType("player")) do
                if getElementData(player, "isLogged") == true and exports.v_mysql:getAccData(player, "bank_money") ~= nil then
                    exports.v_mysql:setAccData(player, "bank_money", nil)
                end
            end
            DB.query(function(rows)
                local n = rows and rows[1] and DB.int(rows[1].n) or 0
                if n > 0 then outputServerLog(("[v_bank] migration: %d accounts created"):format(n)) end
                cb(true)
            end, "SELECT COUNT(*) AS n FROM bank_accounts WHERE created_by = ?", runTag)
            return
        end
        local step = list[i]
        DB.query(function(ok, err)
            if ok == false then
                if step.optional then
                    outputDebugString("[v_bank] migration step " .. i .. " skipped: " .. tostring(err), 3)
                else
                    outputDebugString("[v_bank] migration step " .. i .. " failed: " .. tostring(err), 1)
                    -- retry the whole run later (every step is idempotent)
                    setTimer(runMigration, 30000, 1, cb)
                    return
                end
            end
            run(i + 1)
        end, unpack(step))
    end
    run(1)
end
