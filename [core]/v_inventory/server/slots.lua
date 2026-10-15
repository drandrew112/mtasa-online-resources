if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Player slots: left hand, right hand, back. The carrier's INV_DATA.SLOTS element data tells every
-- client what to hang on the bones (client/hands.lua). Items in the hands lock a few controls.
-- Nobody may enter a vehicle with anything in the hands or on the back; a script warp puts the
-- items down beside the vehicle. Death, quit and a dimension / interior change put them down too.

addEvent("inv:drop", true)

Slots = {}          -- player -> { left = item, right = item, back = item }
local locked = {}   -- player -> { control = true } switched off by us
local pending = {}  -- player -> true (sync on the next frame)

function notify(player, text, alert)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    triggerClientEvent(player, "inv:notify", resourceRoot, text, alert == true)
end

function playAnim(player, anim)
    if not anim or not isElement(player) or isPedDead(player) or isPedInVehicle(player) then return end
    setPedAnimation(player, anim[1], anim[2], anim[3], false, false, false, false)
end

local function syncControls(player, slots)
    local want = {}
    for _, slot in ipairs(INV.HANDS) do
        local item = slots and slots[slot]
        if item then
            for _, control in ipairs(defOf(item).lockControls or INV.CARRY_LOCKED_CONTROLS) do want[control] = true end
        end
    end
    local had = locked[player] or {}
    for control in pairs(had) do
        if not want[control] then toggleControl(player, control, true) end
    end
    for control in pairs(want) do
        if not had[control] then toggleControl(player, control, false) end
    end
    locked[player] = next(want) and want or nil
end

local function sync(player)
    pending[player] = nil
    if not isElement(player) then
        Slots[player], locked[player] = nil, nil
        return
    end
    local slots = Slots[player]
    local data, any = {}, false
    for _, slot in ipairs(INV.SLOTS) do
        local item = slots and slots[slot]
        if item then
            data[slot] = { d = item.def, u = item.uid, m = resolvedModel(item.def) }
            any = true
        end
    end
    if any then setElementData(player, INV_DATA.SLOTS, data) else
        Slots[player] = nil
        removeElementData(player, INV_DATA.SLOTS)
    end
    syncControls(player, slots)
end

-- Hook of server/core.lua (an item went into / out of a slot)
function onSlotsChanged(player)
    if pending[player] then return end
    pending[player] = true
    setTimer(sync, 50, 1, player)
end

function getSlots(player)
    return Slots[player]
end

function hasAnySlotItem(player)
    local slots = Slots[player]
    return slots ~= nil and next(slots) ~= nil
end

-- The slot an item would go to: the back for back-only items, else its preferred free hand
function freeSlotFor(player, item, wanted)
    local def = defOf(item)
    local slots = Slots[player] or {}
    if wanted then return (not slots[wanted]) and wanted or nil end
    if def.back and not def.holdable then return (not slots.back) and "back" or nil end
    if not def.holdable then return nil end
    local first = def.hand == "right" and "right" or "left"
    local second = first == "left" and "right" or "left"
    if not slots[first] then return first end
    if not slots[second] then return second end
    return nil
end

-- Into a free slot of the player. opts: player (a player does it), force. -> true, uid | false, reason
function giveToPlayer(item, player, slot, opts)
    local target = freeSlotFor(player, item, slot)
    if not target then
        if not defOf(item).holdable and not defOf(item).back then return false, L.msg("v_inventory.msg.not_holdable") end
        return false, L.msg("v_inventory.msg.hands_full")
    end
    local ok, result = moveItem(item, { type = "slot", player = player, slot = target }, opts)
    if ok then playAnim(player, INV.TAKE_ANIM) end
    return ok, result
end

-- ---------------------------------------------------------------------------------------------
-- Putting down
-- ---------------------------------------------------------------------------------------------

-- Puts the items of the listed slots (default: the hands) down in front of the player, or beside
-- the point px, py (towards the player). onlyUids: { uid = true } limits it to those items.
-- -> number of items put down
function dropPlayerSlots(player, slotList, px, py, onlyUids, at)
    local slots = Slots[player]
    if not slots then return 0 end
    local x, y, z, dim, int
    if at then
        x, y, z, dim, int = at.x, at.y, at.z, at.dim, at.int
    else
        x, y, z = getElementPosition(player)
        dim, int = getElementDimension(player), getElementInterior(player)
    end
    local _, _, rz = getElementRotation(player)
    local count = 0
    for _, slot in ipairs(slotList or INV.HANDS) do
        local item = slots[slot]
        if item and (not onlyUids or onlyUids[item.uid]) then
            local o = INV.DROP_OFFSETS[slot]
            local wx, wy
            if px then
                local dx, dy = x - px, y - py
                local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
                dx, dy = dx / len, dy / len
                local side = o[1] < 0 and -1 or (o[1] > 0 and 1 or 0)
                wx = px + dx * 0.9 - dy * 0.45 * side
                wy = py + dy * 0.9 + dx * 0.45 * side
            else
                local rad = math.rad(rz)
                wx = x + o[1] * math.cos(rad) - o[2] * math.sin(rad)
                wy = y + o[1] * math.sin(rad) + o[2] * math.cos(rad)
            end
            if dropItemAt(item, wx, wy, z - 1.0, rz, dim, int, (not at) and player or nil) then count = count + 1 end
        end
    end
    if count > 0 and not at then playAnim(player, INV.PUT_ANIM) end
    return count
end

local lastDrop = {}
addEventHandler("inv:drop", resourceRoot, function()
    local player = client
    if isPedInVehicle(player) or isPedDead(player) then return end
    if lastDrop[player] and getTickCount() - lastDrop[player] < 700 then return end
    lastDrop[player] = getTickCount()
    dropPlayerSlots(player, INV.HANDS)
end)

-- ---------------------------------------------------------------------------------------------
-- The carrier cannot keep the items
-- ---------------------------------------------------------------------------------------------

local function dropAll(player)
    if hasAnySlotItem(player) then dropPlayerSlots(player, INV.SLOTS) end
end

addEventHandler("onPlayerQuit", root, function()
    dropAll(source)
    lastDrop[source], locked[source] = nil, nil
end)
addEventHandler("onPlayerWasted", root, function() dropAll(source) end)

-- A dimension / interior change (teleport) leaves the items at the old place
local function onWorldChange(old)
    if getElementType(source) ~= "player" or not hasAnySlotItem(source) then return end
    local x, y, z = getElementPosition(source)
    local at = { x = x, y = y, z = z, dim = getElementDimension(source), int = getElementInterior(source) }
    if eventName == "onElementDimensionChange" then at.dim = old else at.int = old end
    dropPlayerSlots(source, INV.SLOTS, nil, nil, nil, at)
end
addEventHandler("onElementDimensionChange", root, onWorldChange)
addEventHandler("onElementInteriorChange", root, onWorldChange)

-- Vehicles: refused with anything in the hands or on the back
addEventHandler("onVehicleStartEnter", root, function(player)
    if hasAnySlotItem(player) then
        cancelEvent()
        notify(player, L.msg("v_inventory.msg.put_down_before_vehicle"), true)
    end
end)

-- Warped in by a script: the items stay outside, beside the vehicle
addEventHandler("onPlayerVehicleEnter", root, function(vehicle)
    local player = source
    if not hasAnySlotItem(player) then return end
    local x, y, z = getElementPosition(vehicle)
    local at = { x = x, y = y, z = z + 0.5, dim = getElementDimension(vehicle), int = getElementInterior(vehicle) }
    local _, _, rz = getElementRotation(vehicle)
    local rad = math.rad(rz)
    at.x, at.y = x - 2.2 * math.cos(rad), y - 2.2 * math.sin(rad)  -- the left side
    dropPlayerSlots(player, INV.SLOTS, nil, nil, nil, at)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, controls in pairs(locked) do
        if isElement(player) then
            for control in pairs(controls) do toggleControl(player, control, true) end
        end
    end
    for _, player in ipairs(getElementsByType("player")) do removeElementData(player, INV_DATA.SLOTS) end
end)
