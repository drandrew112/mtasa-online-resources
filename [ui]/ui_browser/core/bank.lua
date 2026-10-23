-- ui_browser :: core/bank.lua
-- Liberty Bank (libertybank.eu) on top of v_bank (v_bank DESIGN 8): the accounts the player can
-- use (own personal + company / state accounts with access), the statement of the selected one
-- (filter by category, older pages) and transfers to an account number (check -> confirm).
-- Data comes from the server (ui_browser:bank -> v_bank exports -> v_bank:* client events);
-- the ledger texts are v_bank's keys, shown in the player's language.

BANK = {
    accounts = nil,     -- { {id, number, kind, name, balance, status, role}, ... }
    selected = nil,     -- account id
    rows = {}, more = false, group = nil,
    form = { to = "", amount = 0, note = "" },
    preview = nil,      -- recipient data of a checked transfer
    msg = nil,          -- { text, ok }
    requestedAt = -100000,
}

local function esc(s)
    return (tostring(s or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function money(n) return BR.formatMoney(n) end

local function request(op, ...)
    triggerServerEvent("ui_browser:bank", resourceRoot, op, ...)
end

local function selectedAccount()
    for _, a in ipairs(BANK.accounts or {}) do
        if a.id == BANK.selected then return a end
    end
    return nil
end

local function canUse(a) return a and (a.role == "owner" or a.role == "manager") end

local function requestLedger(before)
    if BANK.selected then request("ledger", BANK.selected, before or false, BANK.group or false) end
end

--------------------------------------------------------------------------------
-- server answers
--------------------------------------------------------------------------------

addEvent("v_bank:accounts", true)
addEventHandler("v_bank:accounts", root, function(list)
    BANK.accounts = type(list) == "table" and list or {}
    local keep = false
    for _, a in ipairs(BANK.accounts) do if a.id == BANK.selected then keep = true end end
    if not keep then
        BANK.selected = nil
        for _, a in ipairs(BANK.accounts) do
            if a.kind == "personal" then BANK.selected = a.id end
        end
        BANK.selected = BANK.selected or (BANK.accounts[1] and BANK.accounts[1].id)
        BANK.rows, BANK.more = {}, false
    end
    requestLedger()
    BR.refresh()
end)

addEvent("v_bank:ledger", true)
addEventHandler("v_bank:ledger", root, function(id, rows, more, before)
    if id ~= BANK.selected then return end
    rows = type(rows) == "table" and rows or {}
    if before then
        for _, r in ipairs(rows) do BANK.rows[#BANK.rows + 1] = r end
    else
        BANK.rows = rows
    end
    BANK.more = more == true
    BR.refresh()
end)

addEvent("v_bank:transfer", true)
addEventHandler("v_bank:transfer", root, function(stage, data)
    data = type(data) == "table" and data or {}
    if stage == "preview" then
        BANK.preview, BANK.msg = data, nil
    elseif stage == "done" then
        BANK.preview = nil
        BANK.form = { to = "", amount = 0, note = "" }
        BANK.msg = { text = ("Sent %s to %s (%s)."):format(money(data.amount), tostring(data.toName), tostring(data.to)), ok = true }
        request("accounts")
    else
        BANK.preview = nil
        local key = "v_bank.error." .. tostring(data.error or "failed")
        BANK.msg = { text = L.has(key) and L.text(key) or L.text("v_bank.error.failed"), ok = false }
    end
    BR.refresh()
end)

--------------------------------------------------------------------------------
-- page actions (buttons) and text inputs
--------------------------------------------------------------------------------

local inputs = {}   -- [token] = field

local function ask(field, title, maxLen, default, placeholder)
    local ok, token = pcall(function()
        return exports.ui_core:openTextInput(title, maxLen, default, placeholder)
    end)
    if ok and token then inputs[token] = field end
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    local field = inputs[token]
    if not field then return end
    inputs[token] = nil
    if text == false or text == nil then return end
    if field == "to" then
        BANK.form.to = tostring(text):upper():gsub("%s", "")
    elseif field == "amount" then
        BANK.form.amount = math.max(0, math.floor(tonumber((tostring(text):gsub("[^%d]", ""))) or 0))
    elseif field == "note" then
        BANK.form.note = tostring(text)
    end
    BANK.preview, BANK.msg = nil, nil
    BR.refresh()
end)

addEventHandler("ui_browser:action", localPlayer, function(_, verb, arg)
    if verb == "bank_select" then
        BANK.selected = tonumber(arg)
        BANK.rows, BANK.more, BANK.preview, BANK.msg = {}, false, nil, nil
        requestLedger()
        BR.refresh()
    elseif verb == "bank_group" then
        BANK.group = (arg ~= "" and arg ~= "all") and arg or nil
        BANK.rows, BANK.more = {}, false
        requestLedger()
        BR.refresh()
    elseif verb == "bank_more" then
        local last = BANK.rows[#BANK.rows]
        if last then requestLedger(last.id) end
    elseif verb == "bank_tf_to" then
        ask("to", "Recipient account number", 20, BANK.form.to, "LB-1-000042")
    elseif verb == "bank_tf_amount" then
        ask("amount", "Amount (€)", 12, BANK.form.amount > 0 and tostring(BANK.form.amount) or "", "1000")
    elseif verb == "bank_tf_note" then
        ask("note", "Note for the recipient", 60, BANK.form.note, "")
    elseif verb == "bank_tf_check" or verb == "bank_tf_confirm" then
        if BANK.form.to == "" or BANK.form.amount <= 0 then
            BANK.msg = { text = "Set the recipient and the amount first.", ok = false }
            BR.refresh()
            return
        end
        request("transfer", BANK.selected, BANK.form.to, BANK.form.amount, BANK.form.note, verb == "bank_tf_confirm")
    elseif verb == "bank_tf_cancel" then
        BANK.preview, BANK.msg = nil, nil
        BR.refresh()
    end
end)

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

local GROUPS = { "all", "cash", "transfer", "work", "tax", "fine", "shop", "biz", "health", "atc", "gov", "admin" }

local function rowText(r)
    local base = "v_bank.tx." .. tostring(r.key)
    local dir = base .. (r.amount < 0 and ".out" or ".in")
    local key = L.has(dir) and dir or base
    if not L.has(key) then return tostring(r.key) end
    return L.text(key, r.params or {})
end

local function stamp(ts)
    local t = getRealTime(ts)
    return ("%04d-%02d-%02d %02d:%02d"):format(t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute)
end

local function ledgerMarkup(b)
    b[#b + 1] = '<card>'
    b[#b + 1] = '<h3>Statement</h3>'
    b[#b + 1] = '<buttons gap="6">'
    for _, g in ipairs(GROUPS) do
        local on = (g == "all" and not BANK.group) or g == BANK.group
        b[#b + 1] = ('<button class="%s" action="bank_group:%s">%s</button>')
            :format(on and "btn-primary" or "btn-dark", g, esc(L.text("v_bank.group." .. g)))
    end
    b[#b + 1] = '</buttons>'
    if #BANK.rows == 0 then
        b[#b + 1] = '<p class="muted">No transactions.</p>'
    end
    for _, r in ipairs(BANK.rows) do
        local sub = { stamp(r.ts) }
        if r.counter and r.counter.number then
            sub[#sub + 1] = (r.amount < 0 and "to " or "from ") .. r.counter.name .. " (" .. r.counter.number .. ")"
        end
        if r.params and r.params.note and r.params.note ~= "" then sub[#sub + 1] = '"' .. r.params.note .. '"' end
        b[#b + 1] = '<hr />'
        b[#b + 1] = '<row gap="8">'
        b[#b + 1] = ('<col><p>%s</p><small>%s</small></col>'):format(esc(rowText(r)), esc(table.concat(sub, " · ")))
        b[#b + 1] = ('<col><p align="right" color="%s">%s%s</p><small align="right">%s</small></col>')
            :format(r.amount < 0 and "#f87171" or "#4ade80", r.amount > 0 and "+" or "", esc(money(r.amount)),
                r.balance and esc("Balance " .. money(r.balance)) or "")
        b[#b + 1] = '</row>'
    end
    if BANK.more then
        b[#b + 1] = '<space h="6" />'
        b[#b + 1] = '<button class="btn-dark" action="bank_more">Older transactions</button>'
    end
    b[#b + 1] = '</card>'
end

local function transferMarkup(b, a)
    b[#b + 1] = '<card>'
    b[#b + 1] = '<h3>Transfer</h3>'
    b[#b + 1] = ('<p>To: %s</p>'):format(esc(BANK.form.to ~= "" and BANK.form.to or "-"))
    b[#b + 1] = ('<p>Amount: %s</p>'):format(esc(BANK.form.amount > 0 and money(BANK.form.amount) or "-"))
    b[#b + 1] = ('<p>Note: %s</p>'):format(esc(BANK.form.note ~= "" and BANK.form.note or "-"))
    b[#b + 1] = '<buttons gap="10">'
    b[#b + 1] = '<button class="btn-dark" action="bank_tf_to">Recipient</button>'
    b[#b + 1] = '<button class="btn-dark" action="bank_tf_amount">Amount</button>'
    b[#b + 1] = '<button class="btn-dark" action="bank_tf_note">Note</button>'
    b[#b + 1] = '<button class="btn-primary" action="bank_tf_check">Check</button>'
    b[#b + 1] = '</buttons>'
    local p = BANK.preview
    if p then
        b[#b + 1] = '<hr />'
        b[#b + 1] = ('<p>Send %s from %s to %s (%s, %s)?</p>'):format(esc(money(p.amount)), esc(p.from), esc(p.toName),
            esc(p.to), esc(L.text("v_bank.kind." .. tostring(p.toKind))))
        b[#b + 1] = '<buttons gap="10">'
        b[#b + 1] = '<button class="btn-buy" action="bank_tf_confirm">Confirm transfer</button>'
        b[#b + 1] = '<button class="btn-dark" action="bank_tf_cancel">Cancel</button>'
        b[#b + 1] = '</buttons>'
    end
    if BANK.msg then
        b[#b + 1] = ('<p color="%s">%s</p>'):format(BANK.msg.ok and "#4ade80" or "#f87171", esc(BANK.msg.text))
    end
    b[#b + 1] = '</card>'
end

function BR.buildBank(query)
    -- fresh data every time the page is opened (and at most every 5 s on re-renders)
    if getTickCount() - BANK.requestedAt > 5000 then
        BANK.requestedAt = getTickCount()
        request("accounts")
    end

    local b = {}
    b[#b + 1] = '<page bg="#0a1a3a" text="#e8f0fc" heading="#ffffff" muted="#9ab5d8" ' ..
        'link="#7cc4ff" accent="#38bdf8" card="#12244a" cardline="#2a3f66">'
    b[#b + 1] = '<siteheader title="Liberty Bank" tagline="Accounts, statements and transfers" accent="#38bdf8" />'

    if not BANK.accounts then
        b[#b + 1] = '<card><p class="muted">Loading your accounts...</p></card>'
        b[#b + 1] = '<link href="home">Back to search</link>'
        b[#b + 1] = '</page>'
        return table.concat(b, "\n")
    end

    -- account switcher
    if #BANK.accounts > 1 then
        b[#b + 1] = '<buttons gap="8">'
        for _, a in ipairs(BANK.accounts) do
            b[#b + 1] = ('<button class="%s" action="bank_select:%d">%s</button>')
                :format(a.id == BANK.selected and "btn-primary" or "btn-dark", a.id,
                    esc(a.kind == "personal" and "Personal" or a.name))
        end
        b[#b + 1] = '</buttons>'
    end

    local a = selectedAccount()
    if not a then
        b[#b + 1] = '<card><p class="muted">No bank account yet.</p></card>'
        b[#b + 1] = '<link href="home">Back to search</link>'
        b[#b + 1] = '</page>'
        return table.concat(b, "\n")
    end

    b[#b + 1] = '<row gap="16">'
    b[#b + 1] = ('<card accent="#0891b2"><small class="muted">%s · %s</small><h1>%s</h1><small class="muted">%s</small></card>')
        :format(esc(L.text("v_bank.kind." .. a.kind)), esc(a.number), esc(money(a.balance)),
            esc(a.kind == "personal" and "Your account" or a.name))
    if a.kind == "personal" then
        b[#b + 1] = ('<card><small class="muted">CASH ON HAND</small><h1>%s</h1></card>')
            :format(esc(money(getPlayerMoney(localPlayer) or 0)))
    end
    b[#b + 1] = '</row>'
    if a.status ~= "active" then
        b[#b + 1] = ('<p color="#f87171">%s</p>'):format(esc(L.text("v_bank.error." .. (a.status == "frozen" and "frozen" or "account_closed"))))
    end
    b[#b + 1] = '<space h="6" />'

    if a.kind == "personal" then
        b[#b + 1] = '<row gap="16">'
        b[#b + 1] = '<card><h3>Deposit cash</h3><buttons gap="8">'
        for _, amt in ipairs({ 100, 500, 1000, 5000 }) do
            b[#b + 1] = ('<button class="btn-primary" action="bank_deposit:%d">%s</button>'):format(amt, esc(money(amt)))
        end
        b[#b + 1] = '<button class="btn-dark" action="bank_deposit:all">All</button></buttons></card>'
        b[#b + 1] = '<card><h3>Withdraw cash</h3><buttons gap="8">'
        for _, amt in ipairs({ 100, 500, 1000, 5000 }) do
            b[#b + 1] = ('<button class="btn-buy" action="bank_withdraw:%d">%s</button>'):format(amt, esc(money(amt)))
        end
        b[#b + 1] = '<button class="btn-dark" action="bank_withdraw:all">All</button></buttons></card>'
        b[#b + 1] = '</row>'
    end

    if canUse(a) and a.status == "active" then transferMarkup(b, a) end
    ledgerMarkup(b)

    b[#b + 1] = '<link href="home">Back to search</link>'
    b[#b + 1] = '</page>'
    return table.concat(b, "\n")
end
