-- ui_browser :: core/bank_loans.lua
-- The Loans part of Liberty Bank (core/bank.lua calls BANKLOAN.markup): the open and the last
-- closed loans of the selected account's borrower, a new loan (amount + installments -> check ->
-- take) and early repayment. Personal account = personal loans, private company account =
-- company loans; state accounts have none (state loans: /gov Loans page).
-- Data comes from the server (ui_browser:loan -> eco_loan exports, bank_loans.lua).

BANKLOAN = {
    account = nil,      -- bank account id the data belongs to
    data = nil,         -- { kind, open, closed, limits, canUse, unavailable } | false (no loans here)
    form = { amount = 0, installments = nil },
    quote = nil,        -- checked terms of a new loan
    msg = nil,          -- { text, ok }
    requestedAt = -100000,
}

local function esc(s)
    return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function money(n) return BR.formatMoney(n) end

local function request(op, ...)
    triggerServerEvent("ui_browser:loan", resourceRoot, op, BANKLOAN.account, ...)
end

local function errText(err)
    err = tostring(err or "failed")
    for _, key in ipairs({ "eco_loan.error." .. err, "v_bank.error." .. err }) do
        if L.has(key) then return L.text(key) end
    end
    return L.text("eco_loan.error.unavailable")
end

local function resetForm()
    BANKLOAN.form = { amount = 0, installments = nil }
    BANKLOAN.quote = nil
end

--------------------------------------------------------------------------------
-- server answers
--------------------------------------------------------------------------------

addEvent("ui_browser:loans", true)
addEventHandler("ui_browser:loans", root, function(accountId, data)
    if accountId ~= BANKLOAN.account then return end
    BANKLOAN.data = type(data) == "table" and data or false
    BR.refresh()
end)

addEvent("ui_browser:loanResult", true)
addEventHandler("ui_browser:loanResult", root, function(stage, data)
    data = type(data) == "table" and data or {}
    if stage == "quote" then
        BANKLOAN.quote, BANKLOAN.msg = data, nil
    elseif stage == "taken" then
        resetForm()
        BANKLOAN.msg = { text = ("Loan #%s: %s paid out to the account."):format(tostring(data.id), money(data.amount)), ok = true }
    elseif stage == "repaid" then
        BANKLOAN.msg = { text = ("Loan #%s: %s repaid."):format(tostring(data.id), money(data.amount)), ok = true }
    else
        BANKLOAN.quote = nil
        BANKLOAN.msg = { text = errText(data.error), ok = false }
    end
    BR.refresh()
end)

--------------------------------------------------------------------------------
-- page actions and text inputs
--------------------------------------------------------------------------------

local inputs = {}   -- [token] = field

local function ask(field, title, maxLen, default, placeholder)
    local ok, token = pcall(function()
        return exports.ui_core:openTextInput(title, maxLen, default, placeholder)
    end)
    if ok and token then inputs[token] = field end
end

local function digits(text)
    return math.max(0, math.floor(tonumber((tostring(text):gsub("[^%d]", ""))) or 0))
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    local field = inputs[token]
    if not field then return end
    inputs[token] = nil
    if text == false or text == nil then return end
    if field == "amount" then
        BANKLOAN.form.amount = digits(text)
        BANKLOAN.quote, BANKLOAN.msg = nil, nil
    else
        local id = tonumber(field:match("^repay:(%d+)$"))
        local amount = digits(text)
        if id and amount > 0 then request("repay", id, amount) end
    end
    BR.refresh()
end)

local function findOpen(id)
    for _, l in ipairs(BANKLOAN.data and BANKLOAN.data.open or {}) do
        if l.id == id then return l end
    end
end

-- registered here too: this file loads before core/browser.lua (see core/bank.lua)
addEvent("ui_browser:action", false)
addEventHandler("ui_browser:action", localPlayer, function(_, verb, arg)
    if verb == "bank_loan_amount" then
        local lim = BANKLOAN.data and BANKLOAN.data.limits or {}
        ask("amount", ("Loan amount (%s - %s)"):format(money(lim.minAmount or 0), money(lim.maxAmount or 0)), 12,
            BANKLOAN.form.amount > 0 and tostring(BANKLOAN.form.amount) or "", tostring(lim.minAmount or ""))
    elseif verb == "bank_loan_n" then
        BANKLOAN.form.installments = tonumber(arg)
        BANKLOAN.quote, BANKLOAN.msg = nil, nil
        BR.refresh()
    elseif verb == "bank_loan_check" or verb == "bank_loan_take" then
        if BANKLOAN.form.amount <= 0 then
            BANKLOAN.msg = { text = "Set the loan amount first.", ok = false }
            BR.refresh()
            return
        end
        local n = BANKLOAN.form.installments or (BANKLOAN.data and BANKLOAN.data.limits.installments)
        request(verb == "bank_loan_take" and "take" or "quote", BANKLOAN.form.amount, n)
    elseif verb == "bank_loan_cancel" then
        BANKLOAN.quote, BANKLOAN.msg = nil, nil
        BR.refresh()
    elseif verb == "bank_loan_repay" then
        local l = findOpen(tonumber(arg))
        if l then ask("repay:" .. l.id, ("Repay loan #%d (max %s)"):format(l.id, money(l.remaining)), 12, tostring(l.installment), "") end
    elseif verb == "bank_loan_payoff" then
        local l = findOpen(tonumber(arg))
        if l then request("repay", l.id, false) end
    end
end)

--------------------------------------------------------------------------------
-- markup
--------------------------------------------------------------------------------

--- "every online hour" (personal) / "every hour the company runs" (company)
local function every(sec, kind)
    sec = sec or 3600
    local unit = sec == 3600 and "hour" or sec % 86400 == 0 and ((sec / 86400) .. " days") or (math.floor(sec / 60 + 0.5) .. " min")
    if kind == "company" then return "every " .. unit .. " the company runs" end
    return "every online " .. unit
end

local function nextText(l)
    if l.status ~= "active" or not l.nextIn then return L.text("eco_loan.status." .. l.status) end
    local m = math.ceil(l.nextIn / 60)
    return ("next in %d min%s"):format(m, l.online and " (online)" or "")
end

--- the installment choices of a kind: half, default, double, four times (within the maximum)
local function installmentChoices(lim)
    local out, seen = {}, {}
    for _, f in ipairs({ 0.5, 1, 2, 4 }) do
        local n = math.max(1, math.min(lim.maxInstallments or 1, math.floor((lim.installments or 1) * f)))
        if not seen[n] then seen[n] = true; out[#out + 1] = n end
    end
    return out
end

local function openMarkup(b, d)
    b[#b + 1] = '<card>'
    b[#b + 1] = ('<h3>%s</h3>'):format(esc(d.kind == "company" and "Company loans" or "Your loans"))
    if #d.open == 0 then
        b[#b + 1] = '<p class="muted">No open loans.</p>'
    end
    for _, l in ipairs(d.open) do
        b[#b + 1] = '<hr />'
        b[#b + 1] = '<row gap="8">'
        local sub = { ("%d/%d installments of %s"):format(l.paidCount, l.installments, money(l.installment)), nextText(l) }
        if l.missedStreak and l.missedStreak > 0 then sub[#sub + 1] = ("%d missed"):format(l.missedStreak) end
        b[#b + 1] = ('<col><p>#%d · %s · %s</p><small>%s</small></col>'):format(l.id,
            esc(L.text("eco_loan.kind." .. l.kind)), esc(money(l.principal)), esc(table.concat(sub, " · ")))
        b[#b + 1] = ('<col><p align="right" color="#f87171">%s</p><small align="right">%s</small></col>')
            :format(esc(money(l.remaining)), esc("of " .. money(l.total) .. " (" .. tostring(l.rate) .. " %)"))
        b[#b + 1] = '</row>'
        if d.canUse and l.status == "active" then
            b[#b + 1] = '<buttons gap="8">'
            b[#b + 1] = ('<button class="btn-dark" action="bank_loan_repay:%d">Repay amount</button>'):format(l.id)
            b[#b + 1] = ('<button class="btn-buy" action="bank_loan_payoff:%d">Pay off %s</button>'):format(l.id, esc(money(l.remaining)))
            b[#b + 1] = '</buttons>'
        end
    end
    if #(d.closed or {}) > 0 then
        b[#b + 1] = '<hr />'
        b[#b + 1] = '<small class="muted">CLOSED LOANS</small>'
        for _, l in ipairs(d.closed) do
            local t = getRealTime(l.closedAt > 0 and l.closedAt or l.createdAt)
            b[#b + 1] = ('<small>#%d · %s · %s · %s · %04d-%02d-%02d</small>'):format(l.id, esc(L.text("eco_loan.kind." .. l.kind)),
                esc(money(l.principal)), esc(L.text("eco_loan.status." .. l.status)), t.year + 1900, t.month + 1, t.monthday)
        end
    end
    b[#b + 1] = '</card>'
end

local function newLoanMarkup(b, d)
    local lim = d.limits or {}
    b[#b + 1] = '<card>'
    b[#b + 1] = ('<h3>%s</h3>'):format(esc(d.kind == "company" and "New company loan" or "New personal loan"))
    b[#b + 1] = ('<small class="muted">%s - %s · %s %% interest · one installment %s</small>')
        :format(esc(money(lim.minAmount or 0)), esc(money(lim.maxAmount or 0)), tostring(lim.rate or 0), every(lim.interval, d.kind))
    b[#b + 1] = ('<small class="muted">A missed installment adds %s %% to the debt; after %d missed in a row the bank collects it even if the account goes negative.</small>')
        :format(tostring(lim.penaltyRate or 0), lim.forceAfterMissed or 0)
    if #d.open >= (lim.maxActive or 1) then
        b[#b + 1] = ('<p class="muted">At most %d open loans at a time.</p>'):format(lim.maxActive or 1)
    else
        local n = BANKLOAN.form.installments or lim.installments
        b[#b + 1] = ('<p>Amount: %s</p>'):format(esc(BANKLOAN.form.amount > 0 and money(BANKLOAN.form.amount) or "-"))
        b[#b + 1] = '<buttons gap="8">'
        b[#b + 1] = '<button class="btn-dark" action="bank_loan_amount">Amount</button>'
        for _, c in ipairs(installmentChoices(lim)) do
            b[#b + 1] = ('<button class="%s" action="bank_loan_n:%d">%d installments</button>')
                :format(c == n and "btn-primary" or "btn-dark", c, c)
        end
        b[#b + 1] = '<button class="btn-primary" action="bank_loan_check">Check</button>'
        b[#b + 1] = '</buttons>'
        local q = BANKLOAN.quote
        if q then
            b[#b + 1] = '<hr />'
            b[#b + 1] = ('<p>You get %s now and repay %s (interest %s, %s %%) in %d installments of %s, %s.</p>')
                :format(esc(money(q.principal)), esc(money(q.total)), esc(money(q.interest)), tostring(q.rate),
                    q.installments, esc(money(q.installment)), every(q.interval, d.kind))
            b[#b + 1] = '<buttons gap="10">'
            b[#b + 1] = '<button class="btn-buy" action="bank_loan_take">Take the loan</button>'
            b[#b + 1] = '<button class="btn-dark" action="bank_loan_cancel">Cancel</button>'
            b[#b + 1] = '</buttons>'
        end
    end
    b[#b + 1] = '</card>'
end

--- the Loans part of the selected account (called by BR.buildBank)
function BANKLOAN.markup(b, a)
    if a.id ~= BANKLOAN.account then
        BANKLOAN.account, BANKLOAN.data, BANKLOAN.msg = a.id, nil, nil
        resetForm()
        BANKLOAN.requestedAt = -100000
    end
    if getTickCount() - BANKLOAN.requestedAt > 5000 then
        BANKLOAN.requestedAt = getTickCount()
        request("list")
    end
    local d = BANKLOAN.data
    if d == false or (d == nil and a.kind == "state") then return end   -- no loans for this account
    b[#b + 1] = '<space h="6" />'
    if d == nil then
        b[#b + 1] = '<card><h3>Loans</h3><p class="muted">Loading...</p></card>'
        return
    end
    if d.unavailable then
        b[#b + 1] = ('<card><h3>Loans</h3><p class="muted">%s</p></card>'):format(esc(L.text("eco_loan.error.unavailable")))
        return
    end
    d.open = d.open or {}
    b[#b + 1] = '<row gap="16">'
    openMarkup(b, d)
    if d.canUse and a.status == "active" then newLoanMarkup(b, d) end
    b[#b + 1] = '</row>'
    if BANKLOAN.msg then
        b[#b + 1] = ('<p color="%s">%s</p>'):format(BANKLOAN.msg.ok and "#4ade80" or "#f87171", esc(BANKLOAN.msg.text))
    end
end
