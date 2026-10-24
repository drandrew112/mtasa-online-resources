-- eco_loan / server/collect.lua
-- The installments. Every LOAN.TICK_MS:
--   * online kinds (personal, company): every active loan whose borrower is online here (the
--     player is logged in / the company runs, i.e. its founder is online) gets the tick's seconds
--     in progress_sec; a loan with progress_sec >= interval_sec is claimed (progress_sec -=
--     interval_sec in one UPDATE) and its installment is booked
--   * real-time kinds (state): an active loan with next_due <= now is claimed (next_due +=
--     interval_sec in one UPDATE; the other instance may see it at the same time) and booked;
--     after a downtime the missed installments follow one per tick
--
-- Not enough money: the installment is missed, the penalty (penaltyRate % of the installment) is
-- added to the debt, the next one comes after the next interval. After forceAfterMissed misses in a
-- row (0 = always) the installment is taken by force: the account may go below 0.
-- A booking that v_bank cannot do now ("unavailable" ...) gives the claim back (next tick).

COLLECT = {}

local TICK_S = math.floor(LOAN.TICK_MS / 1000)

local function idList(ids)
    local out = {}
    for i, id in ipairs(ids) do out[i] = tostring(math.floor(id)) end
    return table.concat(out, ",")
end

--- gives a claim back (the installment comes on the next tick)
local function unclaim(l)
    if LOAN.KINDS[l.kind].online then
        DB.exec("UPDATE eco_loans SET progress_sec = progress_sec + interval_sec WHERE id = ?", l.id)
    else
        DB.exec("UPDATE eco_loans SET next_due = next_due - interval_sec WHERE id = ?", l.id)
    end
end

local function missed(l, err)
    local penalty = CALC.penalty(l.kind, l.installment)
    DB.exec("UPDATE eco_loans SET missed = missed + 1, missed_streak = missed_streak + 1, remaining = remaining + ?, "
        .. "total_due = total_due + ?, penalties = penalties + ? WHERE id = ?", penalty, penalty, penalty, l.id)
    l.missed, l.missedStreak = l.missed + 1, l.missedStreak + 1
    l.remaining, l.total, l.penalties = l.remaining + penalty, l.total + penalty, l.penalties + penalty
    LOANS.log(l.id, "missed", penalty, l.remaining, tostring(err), "", "loan#" .. l.id)
    NOTIFY.borrower(l, CALC.forced(l.kind, l.missedStreak) and "eco_loan.notify.missed_last" or "eco_loan.notify.missed",
        { id = l.id, amount = CALC.due(l.installment, l.remaining), penalty = penalty })
    triggerEvent("onLoanMissed", resourceRoot, l.id, l.missedStreak, penalty)
    LOANS.reload(l.id)
end

-- v_bank errors that make an installment missed (the others are retried)
local MISSED_ERR = { not_enough_money = true, frozen = true, account_closed = true }

--- books the installment of a claimed loan (fresh row from the table)
local function collect(l)
    local bank = LOAN.bank()
    if not bank then return unclaim(l) end
    -- an extra repayment of this instance may be newer than the row
    local cached = OPEN[l.id]
    if cached and cached.remaining < l.remaining then l.remaining = cached.remaining end
    if cached then OPEN[l.id] = l end

    local amount = CALC.due(l.installment, l.remaining)
    if amount <= 0 then
        LOANS.applyPayment(l, 0, "installment", "", "loan#" .. l.id)
        return
    end
    local forced = CALC.forced(l.kind, l.missedStreak)
    local key = forced and "loan.installment_forced" or "loan.installment"
    local ok, res = bank:transfer(l.borrowerAccount, l.lender or nil, amount, key,
        { loan = l.id, n = l.paidCount + 1, of = l.installments }, "loan#" .. l.id)
    if not ok then
        if MISSED_ERR[res] then return missed(l, res) end
        outputDebugString(("[eco_loan] loan #%d installment not booked: %s"):format(l.id, tostring(res)), 2)
        return unclaim(l)
    end
    local paid = LOANS.applyPayment(l, amount, forced and "forced" or "installment", res, "loan#" .. l.id)
    if not paid then
        NOTIFY.borrower(l, forced and "eco_loan.notify.forced" or "eco_loan.notify.installment",
            { id = l.id, amount = amount, remaining = l.remaining, n = l.paidCount, count = l.installments })
    end
end

--------------------------------------------------------------------------------
-- online kinds
--------------------------------------------------------------------------------

--- is the borrower of a loan online on this instance?
local function borrowerOnline(l, online)
    if l.kind == "personal" then return online[l.borrower:lower()] == true end
    if l.kind == "company" then
        local biz = LOAN.biz()
        return biz and biz:isCompanyActive(tonumber(l.borrower)) == true or false
    end
    return false
end

function COLLECT.tickOnline()
    local online = {}
    for _, p in ipairs(getElementsByType("player")) do
        local name = LOAN.accountOf(p)
        if name then online[name] = true end
    end
    local ids = {}
    for _, l in pairs(OPEN) do
        local k = LOAN.KINDS[l.kind]
        if l.status == "active" and k and k.online and borrowerOnline(l, online) then
            ids[#ids + 1] = l.id
            l.progress = l.progress + TICK_S
        end
    end
    if #ids == 0 then return end
    local list = idList(ids)
    DB.exec("UPDATE eco_loans SET progress_sec = progress_sec + ? WHERE status = 'active' AND id IN (" .. list .. ")", TICK_S)
    if not LOAN.bank() then return end   -- the seconds count, the installment waits for v_bank
    -- same connection: the SELECT sees the UPDATE above
    DB.query(function(rows)
        for _, r in ipairs(rows or {}) do
            local l = LOANS.rowLoan(r)
            DB.query(function(res, affected)
                if res ~= false and tonumber(affected) == 1 then
                    l.progress = l.progress - l.interval
                    collect(l)
                end
            end, "UPDATE eco_loans SET progress_sec = progress_sec - interval_sec WHERE id = ? AND status = 'active' AND progress_sec >= interval_sec", l.id)
        end
    end, "SELECT * FROM eco_loans WHERE status = 'active' AND progress_sec >= interval_sec AND id IN (" .. list .. ")")
end

--------------------------------------------------------------------------------
-- real-time kinds
--------------------------------------------------------------------------------

function COLLECT.tickRealTime()
    if not LOAN.bank() then return end
    local kinds = {}
    for name, k in pairs(LOAN.KINDS) do
        if not k.online then kinds[#kinds + 1] = "'" .. name .. "'" end
    end
    if #kinds == 0 then return end
    DB.query(function(rows)
        for _, r in ipairs(rows or {}) do
            local l = LOANS.rowLoan(r)
            DB.query(function(res, affected)
                if res ~= false and tonumber(affected) == 1 then
                    l.nextDue = l.nextDue + l.interval
                    collect(l)
                end
            end, "UPDATE eco_loans SET next_due = next_due + interval_sec WHERE id = ? AND status = 'active' AND next_due = ?", l.id, l.nextDue)
        end
    end, "SELECT * FROM eco_loans WHERE status = 'active' AND kind IN (" .. table.concat(kinds, ",") .. ") AND next_due <= ? ORDER BY next_due LIMIT 50", LOAN.now())
end

function COLLECT.start()
    setTimer(function()
        if not DB.ready or not LOANS.loaded then return end
        COLLECT.tickOnline()
        COLLECT.tickRealTime()
    end, LOAN.TICK_MS, 0)
end
