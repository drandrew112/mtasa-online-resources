-- Hands rule with v_inventory (optional, no include): a weapon cannot be drawn while an item is
-- in a hand, and an item cannot be taken into a hand while a weapon is drawn. A script move that
-- skips the events (forced / silent) puts the weapon away instead.

addEvent("onInventoryItemMove") -- v_inventory: source resourceRoot; (uid, defId, from, to, player|false, amount) cancelable

local HANDS_KEY = "inv.slots" -- v_inventory INV_DATA.SLOTS: { left = {...}, right = {...}, back = {...} }

local function inventoryRunning()
    local res = getResourceFromName("v_inventory")
    return res and getResourceState(res) == "running"
end

function handsFree(player)
    if not inventoryRunning() then return true end
    local ok, free = pcall(function() return exports.v_inventory:isPlayerHandsFree(player) end)
    return not ok or free ~= false
end

addEventHandler("onInventoryItemMove", root, function(uid, defId, from, to)
    if type(to) ~= "table" or to.type ~= "slot" or (to.slot ~= "left" and to.slot ~= "right") then return end
    local player = to.player
    local s = isElement(player) and Players[player]
    if s and s.current then
        cancelEvent(true, L.forPlayer(player, "wp_manager.msg.holster_first"))
    end
end)

addEventHandler("onElementDataChange", root, function(key, _, new)
    if key ~= HANDS_KEY or getElementType(source) ~= "player" then return end
    local s = Players[source]
    if s and s.current and type(new) == "table" and (new.left or new.right) then
        s.current = nil
        apply(source)
    end
end)
