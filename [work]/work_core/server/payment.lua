-- Work payments. Every work resource computes its own amounts and calls payWork() with an
-- itemised breakdown; this module only totals the items, deposits the total to the player's
-- bank account (exports.v_bank:giveBankMoney) and shows a timed, itemised receipt on the
-- client (client/payment.lua). v_bank is a soft dependency: payWork() fails cleanly while it
-- is not running, same as every other resource that pays into the bank.
--
-- Event (source = the player):
--   onPlayerWorkPaid (workId, total, items, reason)

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
            amount = math.floor(amount + (amount >= 0 and 0.5 or -0.5))
            if amount ~= 0 then
                out[#out + 1] = { label = tostring(label), amount = amount }
                total = total + amount
            end
        end
    end
    return out, total
end

-- payWork(player, workId, items [, reason]) -> true, total | false, errorText
--   items = { { label = "Base pay", amount = 150 }, { label = "Distance bonus", amount = 40 },
--             { label = "Equipment fee", amount = -20 }, ... }  -- shown in this order
--   Only a positive total is paid out (exports.v_bank:giveBankMoney); a total <= 0 still shows
--   the receipt (e.g. to explain why nothing was paid) but nothing is transferred. workId does
--   not have to be a currently registered work (it is only used for the name/colour shown on
--   the receipt; unknown ids fall back to the id text and the default colour). reason: optional
--   text shown under the total (e.g. "Shift ended", "Call cancelled").
function payWork(player, workId, items, reason)
    if not isElement(player) or getElementType(player) ~= "player" then
        return false, "bad player"
    end
    local list, total = normaliseItems(items)
    if #list == 0 then return false, "no payment items" end

    if total > 0 then
        if not isResourceRunning("v_bank") then return false, "v_bank is not running" end
        if exports.v_bank:giveBankMoney(player, total) ~= true then
            return false, "payment failed"
        end
    end

    triggerEvent("onPlayerWorkPaid", player, workId, total, list, reason)
    if isPlayerReady(player) then
        local work = Works[workId]
        triggerClientEvent(player, "work:payment", resourceRoot,
            work and work.name or tostring(workId), work and work.color or WORK.DEFAULT_COLOR,
            list, total, reason and tostring(reason) or nil)
    end
    return true, total
end
