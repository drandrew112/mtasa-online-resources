loadstring(exports.gov_core:importLib())()
-- gov_loans / server/panel.lua
-- The Loans page of /gov: state loans (eco_loan kind "state") of the treasury and the state
-- companies. The bank lends; the installments are collected every 24 h by eco_loan, always (the
-- state account may go negative). loans.view shows the open loans, the closed ones and the
-- payments of a loan; gov.<target>.loans (target = "treasury" | state company id) takes a new
-- loan for that account and repays its loans early.

local A = GOV.A

local function int(v) return DB.int(v) end

local function loans()
    if not isResourceRunning("eco_loan") then return nil end
    local l = exports.eco_loan
    return l:isLoanReady() == true and l or nil
end

-- eco_loan:loanCall answers with "<this resource>:remoteResult" like v_bank's bankCall; the lib's
-- handler only knows its own (numeric) ids, these are "loan:<n>"
local pending, seq = {}, 0
addEventHandler(GOV.RES .. ":remoteResult", resourceRoot, function(id, result)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(type(result) == "table" and result or { ok = false, error = "failed" }) end
end)

local function loanCall(action, args, actor, cb)
    local l = loans()
    if not l then return cb({ ok = false, error = "unavailable" }) end
    seq = seq + 1
    local id = "loan:" .. seq
    pending[id] = cb
    if not l:loanCall(id, action, args, actor) then
        pending[id] = nil
        cb({ ok = false, error = "unavailable" })
    end
end

--- the state account code of a bank account id (treasury or an active state company) | nil
local function codeOf(accountId)
    local a = GOV.isStateAccount(tonumber(accountId))
    if not a or a.status ~= "active" then return nil end
    return a.ownerRef, a
end

--- an open state loan by id | nil
local function stateLoan(id)
    local l = loans()
    local loan = l and l:getLoan(int(id))
    return loan and loan.kind == "state" and loan or nil
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

--- open + recently closed state loans, the state accounts and the terms of the bank
function A.loans(p, args, reply, actor)
    local l = loans()
    if not l then return reply(false, "eco_loan.error.unavailable") end
    local open = l:getLoans({ kind = "state" })
    local debt = 0
    for _, x in ipairs(open) do debt = debt + x.remaining end
    for _, x in ipairs(open) do x.target = GOV.codeTarget(x.borrower) end
    local states = GOV.stateAccounts()
    for _, a in ipairs(states) do a.target = GOV.accountTarget(a.id) end
    loanCall("history", { kind = "state", status = "closed", limit = 25 }, actor, function(r)
        reply({ open = open, closed = r.ok and r.loans or {}, debt = debt, states = states,
            limits = l:getLoanConfig().state })
    end)
end

--- the payments of one state loan (open or closed): { id }
function A.loanPayments(p, args, reply, actor)
    loanCall("payments", { id = int(args.id) }, actor, function(r)
        if not r.ok then return reply(false, "eco_loan.error." .. tostring(r.error)) end
        if r.loan.kind ~= "state" then return reply(false, "eco_loan.error.no_loan") end
        reply({ loan = r.loan, payments = r.payments })
    end)
end

--- a new loan from the bank: { account (state bank account id), amount, installments, note }
function A.takeLoan(p, args, reply, actor)
    local l = loans()
    if not l then return reply(false, "eco_loan.error.unavailable") end
    local code, acc = codeOf(args.account)
    if not code then return reply(false, "bad_company") end
    if not GOV.has(p, "gov." .. tostring(GOV.codeTarget(code)) .. ".loans") then return reply(false, "no_right") end
    local amount = int(args.amount)
    local options = { installments = int(args.installments), note = DB.clip(tostring(args.note or ""), 48) }
    local q, err = l:quoteLoan("state", amount, options)
    if not q then return reply(false, "eco_loan.error." .. tostring(err)) end
    loanCall("create", { kind = "state", borrower = code, amount = amount, options = options }, actor, function(r)
        if not r.ok then return reply(false, "eco_loan.error." .. tostring(r.error)) end
        GOV.log(actor, "loan.take", { id = r.id, account = acc.name, amount = q.principal, total = q.total,
            installments = q.installments, note = options.note })
        reply({ id = r.id })
    end)
end

--- early repayment from the borrowing state account: { id, amount (nil = the whole debt) }
function A.repayLoan(p, args, reply, actor)
    local l = loans()
    local loan = stateLoan(args.id)
    if not l or not loan then return reply(false, "eco_loan.error.no_loan") end
    if not GOV.has(p, "gov." .. tostring(GOV.codeTarget(loan.borrower)) .. ".loans") then return reply(false, "no_right") end
    local ok, v
    if args.amount ~= nil then
        local amount = int(args.amount)
        if amount <= 0 then return reply(false, "eco_loan.error.bad_amount") end
        ok, v = l:repayLoan(loan.id, amount, actor)
    else
        ok, v = l:payOffLoan(loan.id, actor)
    end
    if not ok then
        local key = "eco_loan.error." .. tostring(v)
        return reply(false, L.has(key) and key or ("v_bank.error." .. tostring(v)))
    end
    GOV.log(actor, "loan.repay", { id = loan.id, account = loan.borrowerName, amount = v })
    reply({ paid = v })
end

GOV.module({
    perms = {
        { "loans.view", "economy", 0 },
    },
    -- targets: "treasury" + the state companies (gov_core)
    families = {
        { "gov.*.loans", "economy", 3 },
    },
    actions = { loans = "loans.view", loanPayments = "loans.view", takeLoan = "gov.*.loans", repayLoan = "gov.*.loans" },
    pages = {
        { id = "loans", category = "economy", order = 40, script = "web/js/pages.js", need = "loans.view" },
    },
})
