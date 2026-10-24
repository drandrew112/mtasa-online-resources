-- v_bank unit tests (tests/run.py loads stubs.lua and the resource scripts first)

local results = { pass = 0, fail = 0, lines = {} }
local function check(name, cond, info)
    if cond then results.pass = results.pass + 1
    else
        results.fail = results.fail + 1
        results.lines[#results.lines + 1] = "FAIL " .. name .. (info and (": " .. tostring(info)) or "")
    end
end

local function acc(id, kind, ref, balance, extra)
    local a = { id = id, number = "LB-" .. id, kind = kind, ownerRef = ref, name = ref, balance = balance,
                status = "active", allowNegative = false, sync = 0 }
    for k, v in pairs(extra or {}) do a[k] = v end
    ACC[id] = a
    return a
end

local function ledgerRows()
    local n = 0
    for _, e in ipairs(TEST.execs) do if e.sql:find("INSERT INTO bank_ledger") then n = n + 1 end end
    return n
end

BANK.started = true
DB.ready = true
local treasury = acc(1, "state", "treasury", 0, { allowNegative = true })
local sac = acc(2, "state", "sacontrol", 0, { allowNegative = true })
local alice = acc(10, "personal", "alice", 1000)
local bob = acc(11, "personal", "bob", 0)
local co = acc(20, "company", "5", 500)
-- the rows of the re-read: every cached account as the database has it (fromRow fills the owner
-- index findAcc works through)
local function rowsOf(over)
    local rows = {}
    for _, a in pairs(ACC) do
        rows[#rows + 1] = { id = a.id, number = a.number, kind = a.kind, owner_ref = a.ownerRef, name = a.name,
            balance = (over and over[a.id]) or a.balance, allow_negative = a.allowNegative and 1 or 0, status = a.status }
    end
    return rows
end
local function index()
    TEST.db = function() return rowsOf() end
    resyncAccounts()
    TEST.db = function() return {} end
end
index()

---------------------------------------------------------------- basics
local ok, err = BOOK.move(nil, 10, 250, "work.pay", { work = "EMS" }, "x")
check("credit from system", ok and alice.balance == 1250, err)
check("ledger row written", ledgerRows() == 1, ledgerRows())

ok, err = BOOK.move(10, nil, 5000, "shop.weapon", { item = "AK" }, "x")
check("not enough money", not ok and err == "not_enough_money", err)
check("balance unchanged", alice.balance == 1250)

ok, err = BOOK.move(10, nil, 2000, "fine.hospital_bay", { hospital = "ASGH" }, "x")
check("force key goes negative", ok and alice.balance == -750, alice.balance)

ok, err = BOOK.move(nil, 10, 100, "unknown.key", nil, "x")
check("unknown key refused", not ok and err == "bad_key", err)

ok, err = BOOK.move(20, nil, 100, "shop.weapon", nil, "x")
check("company on a personal key refused", not ok and err == "bad_key", err)

ok, err = BOOK.move(nil, 10, 0, "work.pay", nil, "x")
check("zero amount refused", not ok and err == "bad_amount", err)

---------------------------------------------------------------- treasury and sides
local before = ledgerRows()
ok, err = BOOK.move(nil, 1, 1500, "fine.hospital_bay_income", { player = "Alice", hospital = "ASGH", count = 3 }, "x")
check("settled income goes to the chosen account (treasury)", ok and treasury.balance == 1500, err)
check("one row only", ledgerRows() == before + 1, ledgerRows() - before)

ok, err = BOOK.move(1, nil, 99999, "health.care", { patient = "Bob" }, "x")
check("treasury may go negative", ok and treasury.balance == 1500 - 99999, treasury.balance)

ok, err = BOOK.move(nil, 20, 300, "health.care", { patient = "Bob" }, "x")
check("healthcare from nothing to a private hospital", ok and co.balance == 800, co.balance)
ok, err = BOOK.move(20, 1, 300, "health.care", { patient = "Bob" }, "x")
check("healthcare company -> state", ok and co.balance == 500, co.balance)
ok, err = BOOK.move(11, 1, 300, "health.care", nil, "x")
check("healthcare payer is never personal", not ok and err == "bad_key", err)
ok, err = BOOK.move(20, 1, 300, "gov.company_payment", nil, "x")
check("payment only state -> company", not ok and err == "bad_key", err)
ok, err = BOOK.move(20, 1, 200, "gov.collection", { note = "t" }, "x")
check("collection from a company", ok and co.balance == 300, co.balance)
ok, err = BOOK.move(1, 20, 200, "gov.company_payment", { note = "t" }, "x")
check("payment to a company", ok and co.balance == 500, co.balance)

ok, err = BOOK.move(nil, 2, 2000, "atc.fee_landing", { callsign = "SAX1" }, "x")
check("airspace fee to SA Control", ok and sac.balance == 2000, err)

ok, err = BOOK.move(2, 11, 700, "work.pay", { work = "ATC" }, "x")
check("SA Control pays a wage", ok and sac.balance == 1300 and bob.balance == 700, err)

---------------------------------------------------------------- transfers
before = ledgerRows()
ok, err = BOOK.move(11, 20, 200, "biz.deposit", { company = "X", player = "bob" }, "bob")
check("deposit into a company", ok and bob.balance == 500 and co.balance == 700, err)
check("two rows for a transfer", ledgerRows() == before + 2)
local refs = {}
for i = #TEST.execs, 1, -1 do
    local e = TEST.execs[i]
    if e.sql:find("INSERT INTO bank_ledger") then refs[#refs + 1] = e.args[6] end
    if #refs == 2 then break end
end
check("same ref on both rows", refs[1] and refs[1] == refs[2], tostring(refs[1]) .. "/" .. tostring(refs[2]))

ok, err = BOOK.move(11, 11, 10, "transfer.account", nil, "bob")
check("same account refused", not ok and err == "same_account", err)

-- an offline personal account: receiving works (blind delta), paying does not
before = #TEST.execs
ok, err = BOOK.move(11, 99, 100, "transfer.account", { note = "hi" }, "bob")
check("transfer to an uncached account", ok and bob.balance == 400, err)
check("blind row has NULL balance_after", TEST.execs[#TEST.execs].sql:find("NULL") ~= nil)
ok, err = BOOK.move(99, 11, 100, "transfer.account", nil, "x")
check("paying from an uncached account refused", not ok and err == "unavailable", err)
ok, err = BOOK.move(99, nil, 100, "admin.debit", { note = "n" }, "admin")
check("admin may book an uncached account", ok, err)

---------------------------------------------------------------- status / overdraft list
bob.status = "frozen"
ok, err = BOOK.move(11, nil, 10, "shop.weapon", nil, "bob")
check("frozen refuses", not ok and err == "frozen", err)
ok, err = BOOK.move(nil, 11, 10, "admin.credit", { note = "n" }, "admin")
check("admin works on frozen", ok and bob.balance == 410, err)
bob.status = "active"

co.balance = 0
ok, err = BOOK.move(20, nil, 100, "biz.upkeep", nil, "x")
check("company may not go negative", not ok and err == "not_enough_money", err)
co.allowNegative = true
ok, err = BOOK.move(20, nil, 100, "biz.upkeep", nil, "x")
check("overdraft list lets it", ok and co.balance == -100, err)
co.allowNegative = false

---------------------------------------------------------------- params filter
local e
BOOK.move(nil, 10, 10, "shop.weapon_refund", { item = "AK", evil = "x" }, "x")
for i = #TEST.execs, 1, -1 do if TEST.execs[i].sql:find("INSERT INTO bank_ledger") then e = TEST.execs[i] break end end
check("params json without unknown keys", e and e.args[5]:find("evil") == nil and e.args[5]:find("AK") ~= nil, e and e.args[5])

---------------------------------------------------------------- taxes to the chosen state account
do
    local before, tb = co.balance, treasury.balance
    local ok1 = BOOK.move(20, nil, 10, "tax.company_income", {}, "x")
    check("tax without a target disappears", ok1 and co.balance == before - 10 and treasury.balance == tb)
    local ok2 = BOOK.move(20, 2, 10, "tax.company_income", {}, "x")
    check("tax to a chosen state account", ok2 and sac.balance >= 10)
    local ok3, e3 = BOOK.move(20, 10, 10, "tax.company_income", {}, "x")
    check("tax to a personal account refused", not ok3 and e3 == "bad_key", e3)
end

---------------------------------------------------------------- resync with deltas in flight
co.balance, co.sync = 1000, 0
local answer
TEST.db = function()
    -- the SELECT went out; a booking happens before the answer arrives
    BOOK.move(nil, 20, 50, "biz.property_sell", { property = "p" }, "x")
    answer = rowsOf({ [20] = 1000 + 300 })
    return answer
end
resyncAccounts()
TEST.db = function() return {} end
check("resync: other instance's +300 and own +50 both kept", co.balance == 1350, co.balance)

---------------------------------------------------------------- resync after rows deleted by hand
local ghost = acc(30, "state", "ghost", 0)
index()
check("ghost cached", findAcc("state", "ghost") == ghost)
local recreated = false
local rereadDone = false
TEST.db = function(sql, ...)
    local args = { ... }
    if sql:find("INSERT IGNORE INTO bank_accounts") and args[2] == "treasury" then recreated = true end
    if rereadDone then return {} end
    rereadDone = true
    local rows = {}
    for _, r in ipairs(rowsOf()) do if r.id ~= 30 and r.id ~= 1 then rows[#rows + 1] = r end end
    return rows
end
resyncAccounts()
TEST.db = function() return {} end
check("deleted account forgotten", findAcc("state", "ghost") == nil and ACC[30] == nil)
check("deleted treasury forgotten", ACC[1] == nil)
check("treasury recreated", recreated)
ACC[1], treasury.sync = treasury, 0
index()

---------------------------------------------------------------- player wrappers
local p = TEST.player("carol")
local carol = acc(30, "personal", "carol", 100)
carol.player = p
PLAYER_ACC[p] = 30
p.cash = 500
check("deposit", depositMoney(p, 200) == true and carol.balance == 300 and p.cash == 300)
check("deposit without cash", depositMoney(p, 1000) == "not_enough_cash")
check("withdraw", withdrawMoney(p, 50) == true and carol.balance == 250 and p.cash == 350)
local okPay, from = payMoney(p, 300, "shop.weapon", { item = "Colt" })
check("pay from cash first", okPay and from == "cash" and p.cash == 50 and carol.balance == 250)
okPay, from = payMoney(p, 200, "shop.weapon", { item = "Colt" })
check("pay from the bank", okPay and from == "bank" and carol.balance == 50)
check("take refuses force keys", takeBankMoney(p, 10, "fine.hospital_bay") == "bad_key")
local fok, newBal = forceTakeMoney(p, 100, "fine.hospital_bay", { hospital = "h" })
check("force take", fok == true and newBal == -50)
check("mirror element data", getElementData(p, "bank_money") == -50)
check("money HUD shown", #TEST.shown > 0)

TEST.result = results
