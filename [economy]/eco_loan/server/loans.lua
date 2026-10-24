-- eco_loan / server/loans.lua
-- The open loans (pending / active) are cached in OPEN[id]; they are re-read every
-- LOAN.RESYNC_MS (a loan made or paid on the other server instance shows up here) and after every
-- own change. Closed loans (paid / forgiven / failed) are only in the table (history queries).
--
-- Every money movement goes through v_bank with a loan.* key (v_bank shared/keys.lua) and is one
-- eco_loan_payments row.

OPEN = {}
LOANS = { loaded = false }

local int = DB.int

local function rowLoan(r)
    local l = {
        id = int(r.id), kind = tostring(r.kind), borrower = tostring(r.borrower_ref),
        borrowerName = tostring(r.borrower_name), borrowerAccount = int(r.borrower_acc),
        lender = int(r.lender_acc) > 0 and int(r.lender_acc) or false,
        principal = int(r.principal), rate = tonumber(r.rate) or 0, total = int(r.total_due),
        installment = int(r.installment), installments = int(r.installments),
        paidCount = int(r.paid_count), paidAmount = int(r.paid_amount), remaining = int(r.remaining),
        penalties = int(r.penalties), interval = int(r.interval_sec), progress = int(r.progress_sec),
        nextDue = int(r.next_due), missed = int(r.missed), missedStreak = int(r.missed_streak),
        status = tostring(r.status), note = tostring(r.note), createdBy = tostring(r.created_by),
        createdAt = int(r.created_at), lastPaymentAt = int(r.last_payment_at),
        closedAt = int(r.closed_at), closedBy = tostring(r.closed_by),
    }
    return l
end
LOANS.rowLoan = rowLoan

--- a copy for other resources, with nextIn = seconds until the next installment
--- (online seconds for the online kinds, real seconds for the others)
function LOANS.public(l)
    if not l then return false end
    local out = {}
    for k, v in pairs(l) do out[k] = v end
    local k = LOAN.KINDS[l.kind]
    if l.status ~= "active" then
        out.nextIn = false
    elseif k and k.online then
        out.nextIn = math.max(0, l.interval - l.progress)
    else
        out.nextIn = math.max(0, l.nextDue - LOAN.now())
    end
    out.online = k and k.online or false
    return out
end

addEvent("onLoanCreated", false)   -- (loanId, kind, borrowerRef, principal, tag)
addEvent("onLoanFailed", false)    -- (kind, borrowerRef, err, tag)
addEvent("onLoanPayment", false)   -- (loanId, amount, kind "installment"|"forced"|"extra", remaining)
addEvent("onLoanMissed", false)    -- (loanId, missedStreak, penalty)
addEvent("onLoanClosed", false)    -- (loanId, status "paid"|"forgiven")

--------------------------------------------------------------------------------
-- cache
--------------------------------------------------------------------------------

function LOANS.resync()
    if not DB.ready then return end
    DB.query(function(rows)
        if rows == false then return end
        local fresh = {}
        for _, r in ipairs(rows) do
            local l = rowLoan(r)
            fresh[l.id] = l
        end
        OPEN = fresh
        LOANS.loaded = true
    end, "SELECT * FROM eco_loans WHERE status IN ('pending', 'active')")
end

--- re-reads one loan (cb(loan | nil) optional)
function LOANS.reload(id, cb)
    DB.query(function(rows)
        local r = rows and rows[1]
        local l = r and rowLoan(r)
        if l and LOAN_OPEN[l.status] then OPEN[l.id] = l else OPEN[int(id)] = nil end
        if cb then cb(l) end
    end, "SELECT * FROM eco_loans WHERE id = ? LIMIT 1", int(id))
end

--- the open loans of a borrower
function LOANS.ofBorrower(kind, ref)
    ref = tostring(ref or ""):lower()
    local out = {}
    for _, l in pairs(OPEN) do
        if l.kind == kind and l.borrower:lower() == ref then out[#out + 1] = l end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--- one row in eco_loan_payments
function LOANS.log(id, kind, amount, remainingAfter, info, bankRef, actor)
    DB.exec("INSERT INTO eco_loan_payments (loan_id, ts, kind, amount, remaining_after, info, bank_ref, actor) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        int(id), LOAN.now(), kind, int(amount), int(remainingAfter), DB.clip(info, 48), DB.clip(bankRef, 32), LOAN.actor(actor))
end

--------------------------------------------------------------------------------
-- borrowers / lenders
--------------------------------------------------------------------------------

--- borrower of a kind -> { ref, name, account, player } | nil, err
---   personal: a logged-in player (element or account name)
---   company:  a biz_core company id
---   state:    a state account code
function LOANS.resolveBorrower(kind, borrower)
    local bank = LOAN.bank()
    if not bank then return nil, "unavailable" end
    if kind == "personal" then
        local player = isElement(borrower) and borrower or LOAN.playerOf(borrower)
        local name = player and LOAN.accountOf(player)
        if not name then return nil, "borrower_offline" end
        local acc = bank:getPlayerAccount(player)
        if not acc then return nil, "no_account" end
        return { ref = name, name = name, account = acc, player = player }
    elseif kind == "company" then
        local id = tonumber(borrower)
        local biz = LOAN.biz()
        local c = id and biz and biz:getCompany(id)
        local acc = id and bank:getCompanyAccount(id)
        if not acc then return nil, "no_account" end
        return { ref = tostring(math.floor(id)), name = c and tostring(c.name) or ("#" .. math.floor(id)), account = acc }
    elseif kind == "state" then
        local code = tostring(borrower or "")
        local acc = code ~= "" and bank:getStateAccount(code)
        if not acc then return nil, "no_account" end
        local info = bank:getAccountInfo(acc)
        return { ref = code, name = info and info.name or code, account = acc }
    end
    return nil, "bad_kind"
end

--- a lender account id (state / company, active) -> id | false (the bank) | nil, err
local function resolveLender(lender, borrowerAcc)
    if lender == nil or lender == false or lender == 0 then return false end
    local bank = LOAN.bank()
    local info = bank and bank:getAccountInfo(int(lender))
    if not info then return nil, "bad_lender" end
    if info.kind ~= "state" and info.kind ~= "company" then return nil, "bad_lender" end
    if info.status ~= "active" then return nil, "bad_lender" end
    if info.id == borrowerAcc then return nil, "bad_lender" end
    return info.id
end

--------------------------------------------------------------------------------
-- create
--------------------------------------------------------------------------------

local creating = {}   -- "kind:ref" -> count of loans being created (maxActive guard)

--- creates and pays out a loan; cb(true, loanId) | cb(false, err)
--- options: rate, installments, interval (s), lender (bank account id), note, tag
function LOANS.create(kind, borrower, amount, options, actor, cb)
    cb = cb or function() end
    options = type(options) == "table" and options or {}
    if not DB.ready or not LOANS.loaded then return cb(false, "unavailable") end
    local k = LOAN.KINDS[kind]
    if not k then return cb(false, "bad_kind") end
    local quote, qerr = CALC.quote(kind, amount, options)
    if not quote then return cb(false, qerr) end
    local b, berr = LOANS.resolveBorrower(kind, borrower)
    if not b then return cb(false, berr) end
    local lender, lerr = resolveLender(options.lender, b.account)
    if lender == nil then return cb(false, lerr) end

    local slot = kind .. ":" .. b.ref
    if #LOANS.ofBorrower(kind, b.ref) + (creating[slot] or 0) >= k.maxActive then return cb(false, "too_many_loans") end
    creating[slot] = (creating[slot] or 0) + 1
    local function done(ok, v)
        creating[slot] = math.max(0, (creating[slot] or 1) - 1)
        if ok then
            triggerEvent("onLoanCreated", resourceRoot, v, kind, b.ref, quote.principal, options.tag)
        else
            triggerEvent("onLoanFailed", resourceRoot, kind, b.ref, v, options.tag)
        end
        cb(ok, v)
    end

    local now = LOAN.now()
    actor = LOAN.actor(actor)
    DB.insert(function(id)
        if not id then return done(false, "unavailable") end
        id = int(id)
        local bank = LOAN.bank()
        -- v_bank: true, ref | false, err
        local ok, res = false, "unavailable"
        if bank then
            ok, res = bank:transfer(lender or nil, b.account, quote.principal, "loan.payout", { loan = id }, actor)
        end
        if not ok then
            DB.exec("UPDATE eco_loans SET status = 'failed', closed_at = ?, closed_by = ?, note = ? WHERE id = ?",
                now, actor, DB.clip("payout: " .. tostring(res), LOAN.NOTE_MAX), id)
            return done(false, res)
        end
        DB.exec("UPDATE eco_loans SET status = 'active', next_due = ? WHERE id = ?", now + quote.interval, id)
        LOANS.log(id, "payout", quote.principal, quote.total, "", res, actor)
        LOANS.reload(id, function(l)
            if l then NOTIFY.borrower(l, "eco_loan.notify.created", { id = id, amount = l.principal, total = l.total, installment = l.installment, count = l.installments }) end
        end)
        done(true, id)
    end, "INSERT INTO eco_loans (kind, borrower_ref, borrower_name, borrower_acc, lender_acc, principal, rate, total_due, installment, "
        .. "installments, remaining, interval_sec, status, note, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)",
        kind, DB.clip(b.ref, 64), DB.clip(b.name, 64), b.account, lender or 0, quote.principal, quote.rate, quote.total,
        quote.installment, quote.installments, quote.total, quote.interval, DB.clip(options.note, LOAN.NOTE_MAX), actor, now)
end

--------------------------------------------------------------------------------
-- paying
--------------------------------------------------------------------------------

--- books a payment on the cache + table (after the v_bank booking succeeded)
function LOANS.applyPayment(l, amount, kind, bankRef, actor)
    local now = LOAN.now()
    local counted = kind ~= "extra" and 1 or 0
    l.remaining = math.max(0, l.remaining - amount)
    l.paidAmount = l.paidAmount + amount
    l.paidCount = l.paidCount + counted
    l.lastPaymentAt = now
    if counted == 1 then l.missedStreak = 0 end
    local paid = l.remaining <= 0
    -- MySQL evaluates SET left to right: status / closed_at see the new remaining
    DB.exec("UPDATE eco_loans SET remaining = GREATEST(0, remaining - ?), paid_amount = paid_amount + ?, paid_count = paid_count + ?, "
        .. "missed_streak = IF(? = 1, 0, missed_streak), last_payment_at = ?, "
        .. "closed_at = IF(remaining <= 0, ?, closed_at), status = IF(remaining <= 0, 'paid', status) WHERE id = ?",
        amount, amount, counted, counted, now, now, l.id)
    LOANS.log(l.id, kind, amount, l.remaining, kind == "extra" and "" or (l.paidCount .. "/" .. l.installments), bankRef, actor)
    triggerEvent("onLoanPayment", resourceRoot, l.id, amount, kind, l.remaining)
    if paid then
        l.status = "paid"
        OPEN[l.id] = nil
        NOTIFY.borrower(l, "eco_loan.notify.paid", { id = l.id, total = l.paidAmount })
        triggerEvent("onLoanClosed", resourceRoot, l.id, "paid")
    end
    LOANS.reload(l.id)
    return paid
end

--- extra (early) repayment from the borrower's account -> true, paid | false, err
--- amount nil = the whole remaining debt
function LOANS.repay(id, amount, actor)
    local l = OPEN[int(id)]
    if not l or l.status ~= "active" then return false, "no_loan" end
    local bank = LOAN.bank()
    if not bank then return false, "unavailable" end
    amount = amount == nil and l.remaining or math.min(int(amount), l.remaining)
    if amount <= 0 then return false, "bad_amount" end
    local ok, ref = bank:transfer(l.borrowerAccount, l.lender or nil, amount, "loan.extra", { loan = l.id }, LOAN.actor(actor))
    if not ok then return false, ref end
    LOANS.applyPayment(l, amount, "extra", ref, actor)
    return true, amount
end

--- cancels the remaining debt -> true | false, err
function LOANS.forgive(id, actor)
    local l = OPEN[int(id)]
    if not l or l.status ~= "active" then return false, "no_loan" end
    local now = LOAN.now()
    actor = LOAN.actor(actor)
    DB.exec("UPDATE eco_loans SET status = 'forgiven', remaining = 0, closed_at = ?, closed_by = ? WHERE id = ?", now, actor, l.id)
    LOANS.log(l.id, "forgive", l.remaining, 0, "", "", actor)
    l.status, l.remaining = "forgiven", 0
    OPEN[l.id] = nil
    NOTIFY.borrower(l, "eco_loan.notify.forgiven", { id = l.id })
    triggerEvent("onLoanClosed", resourceRoot, l.id, "forgiven")
    return true
end
