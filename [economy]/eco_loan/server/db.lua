-- eco_loan / server/db.lua
-- Tables, the async MySQL lib and small helpers. The schema runs on start; when it is done the
-- open loans are loaded (server/loans.lua) and the collector starts (server/collect.lua).

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

DB = { ready = false }

local SCHEMA = {
    -- borrower_ref: personal = account name (lower-case), company = biz_core company id,
    --   state = state account code; borrower_acc = its v_bank account id (fixed at creation)
    -- lender_acc: v_bank state / company account id, 0 = the bank itself (system)
    -- progress_sec: online seconds since the last installment (personal / company)
    -- next_due: timestamp of the next installment (state)
    [[CREATE TABLE IF NOT EXISTS eco_loans (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT,
        kind VARCHAR(16) NOT NULL,
        borrower_ref VARCHAR(64) NOT NULL,
        borrower_name VARCHAR(64) NOT NULL DEFAULT '',
        borrower_acc INT UNSIGNED NOT NULL,
        lender_acc INT UNSIGNED NOT NULL DEFAULT 0,
        principal BIGINT NOT NULL,
        rate DECIMAL(6,2) NOT NULL DEFAULT 0,
        total_due BIGINT NOT NULL,
        installment BIGINT NOT NULL,
        installments INT UNSIGNED NOT NULL,
        paid_count INT UNSIGNED NOT NULL DEFAULT 0,
        paid_amount BIGINT NOT NULL DEFAULT 0,
        remaining BIGINT NOT NULL,
        penalties BIGINT NOT NULL DEFAULT 0,
        interval_sec INT UNSIGNED NOT NULL,
        progress_sec INT UNSIGNED NOT NULL DEFAULT 0,
        next_due INT UNSIGNED NOT NULL DEFAULT 0,
        missed INT UNSIGNED NOT NULL DEFAULT 0,
        missed_streak INT UNSIGNED NOT NULL DEFAULT 0,
        status VARCHAR(16) NOT NULL DEFAULT 'pending',
        note VARCHAR(64) NOT NULL DEFAULT '',
        created_by VARCHAR(64) NOT NULL DEFAULT '',
        created_at INT UNSIGNED NOT NULL DEFAULT 0,
        last_payment_at INT UNSIGNED NOT NULL DEFAULT 0,
        closed_at INT UNSIGNED NOT NULL DEFAULT 0,
        closed_by VARCHAR(64) NOT NULL DEFAULT '',
        PRIMARY KEY (id),
        KEY idx_borrower (kind, borrower_ref, status),
        KEY idx_status (status, kind),
        KEY idx_due (status, next_due)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],

    -- every money movement / event of a loan
    -- kind: payout | installment | forced | extra | missed | forgive
    [[CREATE TABLE IF NOT EXISTS eco_loan_payments (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        loan_id INT UNSIGNED NOT NULL,
        ts INT UNSIGNED NOT NULL,
        kind VARCHAR(16) NOT NULL,
        amount BIGINT NOT NULL DEFAULT 0,
        remaining_after BIGINT NOT NULL DEFAULT 0,
        info VARCHAR(48) NOT NULL DEFAULT '',
        bank_ref VARCHAR(32) NOT NULL DEFAULT '',
        actor VARCHAR(64) NOT NULL DEFAULT '',
        PRIMARY KEY (id),
        KEY idx_loan (loan_id, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

addEvent("eco_loan:dbReady", false)

local function runSchema(i)
    if i > #SCHEMA then
        DB.ready = true
        triggerEvent("eco_loan:dbReady", resourceRoot)
        return
    end
    MYSQL.query(function(ok, err)
        if ok == false then
            outputDebugString("[eco_loan] schema " .. i .. " failed: " .. tostring(err), 1)
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
    if not isResourceRunning("v_mysql") then return false end
    return exports.v_mysql:mysqlExec(sql, ...)
end

function DB.query(cb, sql, ...)
    return MYSQL.query(cb, sql, ...)
end

function DB.insert(cb, sql, ...)
    return MYSQL.insert(cb, sql, ...)
end

function DB.int(v)
    return math.floor(tonumber(v) or 0)
end

function DB.clip(s, n)
    s = tostring(s or "")
    if #s > n then s = s:sub(1, n) end
    return s
end

function LOAN.now()
    return getRealTime().timestamp
end

function isResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

--- exports.v_bank when it is running and has its accounts loaded, else nil
function LOAN.bank()
    if not isResourceRunning("v_bank") then return nil end
    local bank = exports.v_bank
    if not bank:isBankReady() then return nil end
    return bank
end

function LOAN.biz()
    return isResourceRunning("biz_core") and exports.biz_core or nil
end

--- account name of a logged-in player (lower-case), or nil
function LOAN.accountOf(player)
    if not isElement(player) or getElementType(player) ~= "player" then return nil end
    if getElementData(player, "isLogged") ~= true then return nil end
    local name = getElementData(player, "accName")
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end

--- the logged-in player of an account name, or nil
function LOAN.playerOf(accountName)
    accountName = tostring(accountName or ""):lower()
    for _, p in ipairs(getElementsByType("player")) do
        if LOAN.accountOf(p) == accountName then return p end
    end
    return nil
end

--- a text actor ("" / account name) of a player or a string
function LOAN.actor(actor)
    if isElement(actor) then return LOAN.accountOf(actor) or "" end
    return DB.clip(actor, 64)
end
