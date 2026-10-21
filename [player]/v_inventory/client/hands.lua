-- Items in the slots: the server keeps no object for them, only the carrier's INV_DATA.SLOTS
-- ({ left = { d, u, m }, ... }). Every client creates a local object per slot item of the streamed-in
-- players and places it at the bone after the peds are processed (onClientPedsProcessed).
-- Also the put-down key.

local carried = {} -- ped -> { slot = { obj, def } }

local function destroyFor(ped)
    local objects = carried[ped]
    carried[ped] = nil
    if not objects then return end
    for _, o in pairs(objects) do
        if isElement(o.obj) then destroyElement(o.obj) end
    end
end

local function createFor(ped)
    destroyFor(ped)
    if not isElement(ped) or not isElementStreamedIn(ped) then return end
    local slots = getElementData(ped, INV_DATA.SLOTS)
    if type(slots) ~= "table" then return end
    local objects = {}
    for _, slot in ipairs(INV.SLOTS) do
        local entry = slots[slot]
        local def = type(entry) == "table" and ITEMS[entry.d]
        local model = def and tonumber(entry.m)
        if model then
            local x, y, z = getElementPosition(ped)
            local obj = createObject(model, x, y, z)
            if obj then
                setElementCollisionsEnabled(obj, false)
                setElementDimension(obj, getElementDimension(ped))
                setElementInterior(obj, getElementInterior(ped))
                if def.scale and def.scale ~= 1 then setObjectScale(obj, def.scale) end
                objects[slot] = { obj = obj, def = def }
            end
        end
    end
    carried[ped] = objects
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == INV_DATA.SLOTS and getElementType(source) == "player" then createFor(source) end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" and getElementData(source, INV_DATA.SLOTS) then createFor(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if carried[source] then destroyFor(source) end
end)

addEventHandler("onClientPlayerQuit", root, function() destroyFor(source) end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if getElementData(player, INV_DATA.SLOTS) then createFor(player) end
    end
end)

-- The offset of a slot: right / back as defined, left = the defined left or the mirrored right
local ZERO = { 0, 0, 0, 0, 0, 0 }
local mirrored = {} -- def -> mirrored right offset
local function offsetFor(def, slot)
    local o = def.offsets or {}
    if o[slot] then return o[slot] end
    if slot == "left" and o.right then
        if not mirrored[def] then
            local r = o.right
            mirrored[def] = { -r[1], r[2], r[3], r[4], -r[5], -r[6] }
        end
        return mirrored[def]
    end
    if slot == "right" and o.left then
        if not mirrored[def] then
            local l = o.left
            mirrored[def] = { -l[1], l[2], l[3], l[4], -l[5], -l[6] }
        end
        return mirrored[def]
    end
    return ZERO
end

-- Offset in the carrier's frame (x right, y forward, z up; rz added to the heading)
local function place(obj, ped, slot, def)
    local bx, by, bz = getPedBonePosition(ped, INV.BONES[slot])
    if not bx then return end
    local _, _, heading = getElementRotation(ped)
    local o = offsetFor(def, slot)
    local rad = math.rad(heading)
    local c, sn = math.cos(rad), math.sin(rad)
    -- right = (c, sn), forward = (-sn, c)
    setElementPosition(obj, bx + o[1] * c - o[2] * sn, by + o[1] * sn + o[2] * c, bz + o[3])
    setElementRotation(obj, o[4], o[5], heading + o[6])
end

addEventHandler("onClientPedsProcessed", root, function()
    for ped, objects in pairs(carried) do
        if not isElement(ped) then
            destroyFor(ped)
        else
            local hidden = isPedInVehicle(ped) or getElementAlpha(ped) == 0
            local dim, int = getElementDimension(ped), getElementInterior(ped)
            for slot, o in pairs(objects) do
                local obj = o.obj
                if isElement(obj) then
                    setElementAlpha(obj, hidden and 0 or 255)
                    if getElementDimension(obj) ~= dim then setElementDimension(obj, dim) end
                    if getElementInterior(obj) ~= int then setElementInterior(obj, int) end
                    if not hidden then place(obj, ped, slot, o.def) end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Put-down key
-- ---------------------------------------------------------------------------------------------

local lastDrop = 0
bindKey(INV.KEY_DROP, "down", function()
    local slots = getElementData(localPlayer, INV_DATA.SLOTS)
    if type(slots) ~= "table" or not (slots.left or slots.right) then return end
    if isCursorShowing() or OtherPanelOpen() then return end
    if isPedInVehicle(localPlayer) or getTickCount() - lastDrop < 800 then return end
    lastDrop = getTickCount()
    triggerServerEvent("inv:drop", resourceRoot)
end)
