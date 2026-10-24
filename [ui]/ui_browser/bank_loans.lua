-- ui_browser :: bank_loans.lua
-- Liberty Bank loans (core/bank_loans.lua on the client) on top of the eco_loan exports:
--   personal account -> personal loans of the player
--   company account  -> loans of that private (biz_core) company; state accounts get none
--                       (state loans are taken on the /gov Loans page, gov_loans)
-- The page asks with ui_browser:loan; the answers are ui_browser:loans / ui_browser:loanResult.

local function loanReady()
    local res = getResourceFromName("eco_loan")
    return res and getResourceState(res) == "running" and exports.eco_loan:isLoanReady() == true
end

local function bankReady()
    local res = getResourceFromName("v_bank")
    return res and getResourceState(res) == "running"
end

local function accountName(player)
    local name = getElementData(player, "accName")
    return type(name) == "string" and name ~= "" and name:lower() or nil
end

--- the borrower of a bank account the player sees -> kind, ref | nil
---   need = "view" | "use" (taking / repaying a loan)
local function borrowerOf(player, accountId, need)
    accountId = tonumber(accountId)
    if not accountId or not bankReady() then return nil end
    if not exports.v_bank:hasAccess(player, accountId, need) then return nil end
    if exports.v_bank:getPlayerAccount(player) == accountId then
        local name = accountName(player)
        return name and "personal", name
    end
    local info = exports.v_bank:getAccountInfo(accountId)
    if info and info.kind == "company" then return "company", tostring(info.ownerRef) end
    return nil   -- state accounts: no loans on the bank website
end

--------------------------------------------------------------------------------
-- eco_loan:loanCall answers (history, create)
--------------------------------------------------------------------------------

local pending, seq = {}, 0
addEvent("ui_browser:remoteResult", false)
addEventHandler("ui_browser:remoteResult", resourceRoot, function(id, result)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(type(result) == "table" and result or { ok = false, error = "failed" }) end
end)

local function loanCall(action, args, actor, cb)
    seq = seq + 1
    local id = "loan:" .. seq
    pending[id] = cb
    if not exports.eco_loan:loanCall(id, action, args, actor) then
        pending[id] = nil
        cb({ ok = false, error = "unavailable" })
    end
end

--------------------------------------------------------------------------------
-- answers to the page
--------------------------------------------------------------------------------

local function toClient(player, event, ...)
    if isElement(player) then triggerClientEvent(player, event, resourceRoot, ...) end
end

local function result(player, stage, data)
    toClient(player, "ui_browser:loanResult", stage, data or {})
end

--- open + the last closed loans of the account's borrower, with the kind's limits
local function sendLoans(player, accountId)
    local kind, ref = borrowerOf(player, accountId, "view")
    if not kind then return toClient(player, "ui_browser:loans", tonumber(accountId), false) end
    if not loanReady() then return toClient(player, "ui_browser:loans", tonumber(accountId), { kind = kind, unavailable = true }) end
    local cfg = exports.eco_loan:getLoanConfig()[kind] or {}
    local open = exports.eco_loan:getLoans({ kind = kind, borrower = ref })
    loanCall("history", { kind = kind, borrower = ref, status = "closed", limit = 10 }, "", function(r)
        toClient(player, "ui_browser:loans", tonumber(accountId), {
            kind = kind, open = open, closed = r.ok and r.loans or {},
            canUse = exports.v_bank:hasAccess(player, tonumber(accountId), "use") == true,
            limits = { minAmount = cfg.minAmount, maxAmount = cfg.maxAmount, rate = cfg.rate,
                installments = cfg.installments, maxInstallments = cfg.maxInstallments, interval = cfg.interval,
                maxActive = cfg.maxActive, penaltyRate = cfg.penaltyRate, forceAfterMissed = cfg.forceAfterMissed },
        })
    end)
end

addEvent("ui_browser:loan", true)
addEventHandler("ui_browser:loan", resourceRoot, function(op, accountId, a1, a2)
    local player = client
    if not isElement(player) then return end
    if op == "list" then return sendLoans(player, accountId) end
    if not loanReady() then return result(player, "error", { error = "unavailable" }) end

    local kind, ref = borrowerOf(player, accountId, "use")
    if not kind then return result(player, "error", { error = "no_access" }) end
    local actor = accountName(player) or ""

    if op == "quote" or op == "take" then
        local amount = math.floor(tonumber(a1) or 0)
        local options = { installments = math.floor(tonumber(a2) or 0) }
        local q, err = exports.eco_loan:quoteLoan(kind, amount, options)
        if not q then return result(player, "error", { error = err }) end
        if op == "quote" then return result(player, "quote", q) end
        loanCall("create", { kind = kind, borrower = ref, amount = amount, options = options }, actor, function(r)
            if not r.ok then return result(player, "error", { error = r.error }) end
            result(player, "taken", { id = r.id, amount = amount })
            exports.v_bank:requestBankAccounts(player)
            -- eco_loan re-reads the new loan into its cache asynchronously
            setTimer(function() if isElement(player) then sendLoans(player, accountId) end end, 1000, 1)
        end)
    elseif op == "repay" then
        -- a2 = amount | false (the whole remaining debt)
        local loan = exports.eco_loan:getLoan(tonumber(a1))
        if not loan or loan.kind ~= kind or tostring(loan.borrower):lower() ~= tostring(ref):lower() then
            return result(player, "error", { error = "no_loan" })
        end
        local ok, v
        if tonumber(a2) then
            ok, v = exports.eco_loan:repayLoan(loan.id, math.floor(tonumber(a2)), actor)
        else
            ok, v = exports.eco_loan:payOffLoan(loan.id, actor)
        end
        if not ok then return result(player, "error", { error = v }) end
        result(player, "repaid", { id = loan.id, amount = v })
        exports.v_bank:requestBankAccounts(player)
        sendLoans(player, accountId)
    end
end)
