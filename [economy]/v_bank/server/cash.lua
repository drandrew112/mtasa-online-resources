-- v_bank / server/cash.lua
-- Cash helpers that are not banking: the pickup sound and money bag pickups. Cash is GTA's own
-- money and is never booked (DESIGN.md 1).

--- plays the "pickup money" sound for a player (or everyone) -> true | "player_not_found"
function playPickupMoneySound(player)
    if player == nil then
        triggerClientEvent(root, "v_bank:playPickupMoneySound", root)
        return true
    end
    if not isElement(player) or getElementType(player) ~= "player" then return "player_not_found" end
    triggerClientEvent(player, "v_bank:playPickupMoneySound", player)
    return true
end

--- a money bag pickup: the player walking into it gets the cash (optional: only `player` can)
--- -> pickup | false
function createMoneyPickup(x, y, z, money, player)
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    money = BOOK.amountOf(money)
    if not (x and y and z and money) then return false end
    if player ~= nil and (not isElement(player) or getElementType(player) ~= "player") then return false end

    local moneyBag = createPickup(x, y, z, 3, 1550)
    if not moneyBag then return false end

    local collected = false
    addEventHandler("onPickupHit", moneyBag, function(hitPlayer)
        if collected then return end
        if not isElement(hitPlayer) or getElementType(hitPlayer) ~= "player" then return end
        if player and hitPlayer ~= player then return end

        collected = true
        givePlayerMoney(hitPlayer, money)
        BOOK.showMoney(hitPlayer, "add", money, "cash")
        triggerClientEvent(hitPlayer, "v_bank:playPickupMoneySound", hitPlayer)
        destroyElement(moneyBag)
    end)
    return moneyBag
end
