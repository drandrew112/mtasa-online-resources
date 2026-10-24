if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Work payments. Every work resource computes its own amounts and calls payWork() with an
-- itemised breakdown; this module totals the items, applies the work's /gov wage multiplier, the
-- weekly multiplier and the income tax (v_gov rate key of the work), books the wage into the
-- player's bank account from the work's payer (v_gov: system / treasury / state or private
-- company) and shows a timed, itemised receipt on the client (client/payment.lua). v_bank is a
-- soft dependency: payWork() fails cleanly while it is not running. Without v_gov the fallbacks
-- of WORK.GOV_FALLBACK apply.
--
-- Event (source = the player):
--   onPlayerWorkPaid (workId, total, items, reason)   total = what the player got (after tax)

addEvent("onPlayerWorkPaid")

local function normaliseItems(list)
    local out, total = {}, 0
    if type(list) ~= "table" then return out, total end
    for _, item in ipairs(list) do
        local label, amount
        if type(item) == "table" then
            label, amount = item.label or item[1], tonumber(item.amount or item[2])
        end
        if label and amount then
            -- round half away from zero (-300 stays -300)
            amount = amount >= 0 and math.floor(amount + 0.5) or -math.floor(-amount + 0.5)
            if amount ~= 0 then
                out[#out + 1] = { label = tostring(label), amount = amount }
                total = total + amount
            end
        end
    end
    return out, total
end

function isResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function gov() return isResourceRunning("v_gov") and exports.v_gov or nil end

--- v_bank account id the income tax goes to, or nil = it disappears (the /gov Taxes page)
local function incomeTaxTarget()
    local g = gov()
    return g and tonumber(g:getTaxTarget("income")) or nil
end

--- the /gov wage multiplier of the work (1 = none)
local function govMultiplier(workId)
    local g = gov()
    return g and tonumber(g:getWorkMultiplier(workId)) or 1
end

--- income tax rate (0..1) and its key
local function incomeTax(workId)
    local g = gov()
    if g then
        local rate, key = g:getIncomeTaxRate(workId)
        if tonumber(rate) then return tonumber(rate), key end
    end
    local f = WORK.GOV_FALLBACK
    if f.exempt[workId] then return 0, "exempt" end
    return f.incomeTax, "standard"
end

--- v_bank account id of the work's payer, or nil = system (money from nothing)
local function payerOf(workId)
    local g = gov()
    local id = g and g:getWorkPayer(workId)
    return tonumber(id)
end

-- payWork(player, workId, items [, reason [, opts]]) -> true, total | false, errorText
--   items = { { label = "Base pay", amount = 150 }, { label = "Distance bonus", amount = 40 },
--             { label = "Equipment fee", amount = -20 }, ... }  -- shown in this order
--   A positive total gets the /gov wage multiplier and the weekly multiplier (one receipt line
--   each), then the income tax (a negative line); the gross is booked as work.pay from the payer,
--   the tax as tax.income to the state account set on the /gov Taxes page (none = disappears). total returned = what the player got.
--   A total <= 0 still shows the receipt but pays nothing; with opts.chargeNegative = true a
--   negative total is taken from the player (work.deduction, may go into debt) and goes to the
--   payer. workId does not have to be a currently registered work (only used for the
--   name/colour). reason: optional text shown under the total.
function payWork(player, workId, items, reason, opts)
    if not isElement(player) or getElementType(player) ~= "player" then
        return false, "bad player"
    end
    opts = type(opts) == "table" and opts or {}
    local list, total = normaliseItems(items)
    if #list == 0 then return false, "no payment items" end

    -- /gov wage multiplier of the work
    local m = govMultiplier(workId)
    if total > 0 and m ~= 1 then
        local amount = math.floor(total * (m - 1) + 0.5)
        if amount ~= 0 then
            list[#list + 1] = { label = L.msg("work_core.payment.wage_multiplier", { mult = formatMultiplier(m) }), amount = amount }
            total = total + amount
        end
    end

    -- weekly work multiplier (server/multipliers.lua): one extra item on top of the total
    local bonus = workMultiplierItem(workId, total)
    if bonus then
        list[#list + 1] = bonus
        total = total + bonus.amount
    end

    -- income tax on the whole positive wage (multipliers included)
    local tax, rate, taxKey = 0, incomeTax(workId)
    if total > 0 and rate > 0 then
        tax = math.floor(total * rate)
        if tax > 0 then
            list[#list + 1] = { label = L.msg("work_core.payment.income_tax", { rate = math.floor(rate * 100 + 0.5) }), amount = -tax }
        end
    end

    local work = Works[workId]
    local workName = work and work.name or tostring(workId)
    local paid = total
    if total > 0 then
        if not isResourceRunning("v_bank") then return false, "v_bank is not running" end
        local ok = exports.v_bank:giveBankMoney(player, total, "work.pay", { work = workName }, payerOf(workId))
        if ok ~= true then return false, "payment failed: " .. tostring(ok) end
        if tax > 0 then
            exports.v_bank:forceTakeMoney(player, tax, "tax.income",
                { work = workName, key = taxKey, rate = math.floor(rate * 100 + 0.5) }, incomeTaxTarget())
            paid = total - tax
        end
    elseif total < 0 and opts.chargeNegative then
        if not isResourceRunning("v_bank") then return false, "v_bank is not running" end
        local ok = exports.v_bank:forceTakeMoney(player, -total, "work.deduction", { work = workName }, payerOf(workId))
        if ok ~= true then return false, "deduction failed: " .. tostring(ok) end
    end

    triggerEvent("onPlayerWorkPaid", player, workId, paid, list, reason)
    if isPlayerReady(player) then
        triggerClientEvent(player, "work:payment", resourceRoot,
            workName, work and work.color or WORK.DEFAULT_COLOR,
            list, paid, reason and tostring(reason) or nil)
    end
    return true, paid
end

function testEMSPayment(player)
    return payWork(player, "ems", {
        { label = L.msg("work_core.payment.patient_treatment"), amount = 2500 },
        { label = L.msg("work_core.payment.emergency_response_bonus"), amount = 750 },
        { label = L.msg("work_core.payment.medical_supplies_fee"), amount = -300 },
    }, L.msg("work_core.payment.shift_completed"))
end

addCommandHandler("testemsreceipt", function(player)
    local success, result = testEMSPayment(player)

    if success then
        outputChatBox("EMS receipt test completed. Total: €" .. result, player, 0, 255, 0)
    else
        outputChatBox("EMS receipt test failed: " .. tostring(result), player, 255, 0, 0)
    end
end)