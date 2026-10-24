-- eco_loan unit tests (run by tests/run.py after stubs + the resource files)

local check = TEST.check

DB.ready = true
LOANS.loaded = true

local function row(over)
    local r = {
        id = 7, kind = "personal", borrower_ref = "bob", borrower_name = "bob", borrower_acc = 5, lender_acc = 0,
        principal = 10000, rate = "10.00", total_due = 11000, installment = 459, installments = 24,
        paid_count = 0, paid_amount = 0, remaining = 11000, penalties = 0, interval_sec = 3600,
        progress_sec = 3600, next_due = 0, missed = 0, missed_streak = 0, status = "active", note = "",
        created_by = "", created_at = 0, last_payment_at = 0, closed_at = 0, closed_by = "",
    }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

--- DB answers for the collector: the due SELECT gives rows, every claim UPDATE succeeds
local function dueDb(rows)
    return function(sql)
        if sql:find("^SELECT %* FROM eco_loans WHERE status = 'active'") then return rows end
        if sql:find("^UPDATE eco_loans SET") then return true, 1 end
        if sql:find("WHERE id = %? LIMIT 1") then return rows end
        return {}
    end
end

-- quotes ---------------------------------------------------------------------
do
    local q = CALC.quote("personal", 10000)
    check("quote total", q and q.total == 11000, q and q.total)
    check("quote installment", q and q.installment == 459, q and q.installment)
    check("quote interval", q and q.interval == 3600)
    local s = CALC.quote("state", 1000000, { installments = 10, rate = 0 })
    check("state quote", s and s.total == 1000000 and s.installment == 100000 and s.interval == 86400)
    local _, e1 = CALC.quote("personal", 10)
    check("too small", e1 == "bad_amount", e1)
    local _, e2 = CALC.quote("personal", 10000, { installments = 0 })
    check("bad installments", e2 == "bad_installments", e2)
    local _, e3 = CALC.quote("personal", 10000, { rate = 500 })
    check("bad rate", e3 == "bad_rate", e3)
    local _, e4 = CALC.quote("nope", 10000)
    check("bad kind", e4 == "bad_kind", e4)
    check("due last", CALC.due(459, 100) == 100)
    check("penalty", CALC.penalty("personal", 459) == 23, CALC.penalty("personal", 459))
    check("state no penalty", CALC.penalty("state", 459) == 0)
    check("forced after 3", not CALC.forced("personal", 2) and CALC.forced("personal", 3))
    check("state always forced", CALC.forced("state", 0))
end

local bob = TEST.player("bob", 5)

-- create ---------------------------------------------------------------------
do
    TEST.reset()
    TEST.db = function(sql) if sql:find("WHERE id = %? LIMIT 1") then return { row({ id = 42, progress_sec = 0 }) } end return {} end
    local okRes, errRes
    LOANS.create("personal", bob, 10000, nil, bob, function(ok, v) okRes, errRes = ok, v end)
    check("create ok", okRes == true and errRes == 42, tostring(okRes) .. " " .. tostring(errRes))
    local t = TEST.transfers[1]
    check("payout booked", t and t.from == nil and t.to == 5 and t.amount == 10000 and t.key == "loan.payout" and t.params.loan == 42)
    check("activated", TEST.exec("status = 'active'") ~= nil)
    check("payout logged", TEST.exec("INSERT INTO eco_loan_payments") ~= nil)
    check("event", TEST.firedEvent("onLoanCreated") ~= nil)
    check("cached", OPEN[42] ~= nil)
    check("notified", TEST.notes[1] and TEST.notes[1].msg.key == "eco_loan.notify.created")
end

-- failed payout --------------------------------------------------------------
do
    TEST.reset()
    TEST.bankAnswer = function() return false, "not_enough_money" end
    TEST.accounts[90] = { id = 90, kind = "state", status = "active", name = "State Treasury" }
    local okRes, errRes
    LOANS.create("personal", "bob", 10000, { lender = 90 }, "admin", function(ok, v) okRes, errRes = ok, v end)
    check("payout fails", okRes == false and errRes == "not_enough_money", tostring(errRes))
    check("lender pays", TEST.transfers[1] and TEST.transfers[1].from == 90)
    check("marked failed", TEST.exec("status = 'failed'") ~= nil)
    check("failed event", TEST.firedEvent("onLoanFailed") ~= nil)
end

-- limits / borrowers -----------------------------------------------------------
do
    TEST.reset()
    OPEN[43] = LOANS.rowLoan(row({ id = 43 }))   -- 42 + 43 = maxActive 2
    local errRes
    LOANS.create("personal", bob, 10000, nil, bob, function(_, v) errRes = v end)
    check("too many", errRes == "too_many_loans", errRes)
    LOANS.create("personal", "alice", 10000, nil, "x", function(_, v) errRes = v end)
    check("offline borrower", errRes == "borrower_offline", errRes)
    LOANS.create("company", 99, 100000, nil, "x", function(_, v) errRes = v end)
    check("no company account", errRes == "no_account", errRes)
    LOANS.create("state", "treasury", 100000, { lender = 90 }, "x", function(_, v) errRes = v end)
    check("lender = borrower", errRes == "bad_lender", errRes)
    OPEN = {}
end

-- online collection: paid ------------------------------------------------------
do
    TEST.reset()
    OPEN = { [7] = LOANS.rowLoan(row({ progress_sec = 3540 })) }
    TEST.db = dueDb({ row() })
    COLLECT.tickOnline()
    check("progress counted", TEST.exec("progress_sec = progress_sec + ?") ~= nil)
    local t = TEST.transfers[1]
    check("installment booked", t and t.from == 5 and t.to == nil and t.amount == 459 and t.key == "loan.installment"
        and t.params.n == 1 and t.params.of == 24)
    check("payment written", TEST.exec("paid_count = paid_count + ?") ~= nil)
    local p = TEST.firedEvent("onLoanPayment")
    check("payment event", p and p.args[2] == 459 and p.args[4] == 11000 - 459)
    check("installment notice", TEST.notes[1] and TEST.notes[1].msg.key == "eco_loan.notify.installment")
end

-- offline borrower: nothing counted -------------------------------------------
do
    TEST.reset()
    OPEN = { [8] = LOANS.rowLoan(row({ id = 8, borrower_ref = "alice" })) }
    COLLECT.tickOnline()
    check("offline not counted", #TEST.execs == 0 and #TEST.transfers == 0)
end

-- company runs = counted ------------------------------------------------------
do
    TEST.reset()
    OPEN = { [9] = LOANS.rowLoan(row({ id = 9, kind = "company", borrower_ref = "3", borrower_acc = 30 })) }
    TEST.db = dueDb({ row({ id = 9, kind = "company", borrower_ref = "3", borrower_acc = 30 }) })
    COLLECT.tickOnline()
    check("company installment", TEST.transfers[1] and TEST.transfers[1].from == 30)
end

-- missed, then forced ---------------------------------------------------------
do
    TEST.reset()
    OPEN = { [7] = LOANS.rowLoan(row()) }
    TEST.db = dueDb({ row() })
    TEST.bankAnswer = function() return false, "not_enough_money" end
    COLLECT.tickOnline()
    local m = TEST.exec("missed = missed + 1")
    check("missed written", m and m.args[1] == 23, m and m.args[1])
    check("missed event", TEST.firedEvent("onLoanMissed") ~= nil)
    check("missed notice", TEST.notes[1] and TEST.notes[1].msg.key == "eco_loan.notify.missed")

    TEST.reset()
    TEST.db = dueDb({ row({ missed_streak = 2 }) })
    TEST.bankAnswer = function() return false, "not_enough_money" end
    COLLECT.tickOnline()
    check("last warning", TEST.notes[1] and TEST.notes[1].msg.key == "eco_loan.notify.missed_last")

    TEST.reset()
    TEST.db = dueDb({ row({ missed_streak = 3 }) })
    COLLECT.tickOnline()
    check("forced key", TEST.transfers[1] and TEST.transfers[1].key == "loan.installment_forced")
end

-- unavailable bank: claim given back ------------------------------------------
do
    TEST.reset()
    OPEN = { [7] = LOANS.rowLoan(row()) }
    TEST.db = dueDb({ row() })
    TEST.bankAnswer = function() return false, "unavailable" end
    COLLECT.tickOnline()
    check("unclaimed", TEST.exec("progress_sec = progress_sec + interval_sec") ~= nil)
    check("not missed", TEST.exec("missed = missed + 1") == nil)
end

-- state: real time --------------------------------------------------------------
do
    TEST.reset()
    OPEN = {}
    local st = row({ id = 11, kind = "state", borrower_ref = "treasury", borrower_acc = 90, installment = 100000,
        remaining = 100000, installments = 10, interval_sec = 86400, next_due = TEST.now - 5 })
    TEST.db = dueDb({ st })
    COLLECT.tickRealTime()
    local t = TEST.transfers[1]
    check("state forced", t and t.from == 90 and t.key == "loan.installment_forced" and t.amount == 100000)
    check("state paid", TEST.firedEvent("onLoanClosed") ~= nil)
end

-- extra repayment / forgive ---------------------------------------------------
do
    TEST.reset()
    OPEN = { [7] = LOANS.rowLoan(row({ remaining = 1000 })) }
    -- the re-read after a payment gives what the table now holds
    TEST.db = function()
        local l = OPEN[7]
        return { row({ remaining = l and l.remaining or 0, status = l and l.status or "paid" }) }
    end
    local ok, paid = LOANS.repay(7, 400, bob)
    check("repay part", ok and paid == 400 and OPEN[7] and OPEN[7].remaining == 600)
    check("repay key", TEST.transfers[1].key == "loan.extra")
    ok, paid = LOANS.repay(7, nil, bob)
    check("pay off", ok and paid == 600 and OPEN[7] == nil)
    check("closed paid", TEST.firedEvent("onLoanClosed").args[2] == "paid")
    local ok2, err = LOANS.repay(7, 1, bob)
    check("no loan", not ok2 and err == "no_loan")

    TEST.reset()
    OPEN = { [12] = LOANS.rowLoan(row({ id = 12 })) }
    check("forgive", LOANS.forgive(12, "admin") == true and OPEN[12] == nil)
    check("forgive written", TEST.exec("status = 'forgiven'") ~= nil)
end

-- exports ---------------------------------------------------------------------
do
    OPEN = { [7] = LOANS.rowLoan(row({ progress_sec = 600 })), [9] = LOANS.rowLoan(row({ id = 9, kind = "company", borrower_ref = "3" })) }
    local list = getPlayerLoans(bob)
    check("player loans", #list == 1 and list[1].id == 7 and list[1].nextIn == 3000)
    check("company loans", #getCompanyLoans(3) == 1)
    check("debt", getDebt("personal", bob) == 11000)
end
