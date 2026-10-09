-- Carried items: the server keeps no object for them, only the carrier's BAG_DATA.HANDS
-- ({ bag = model, monitor = model }). Every client creates a local object for each streamed-in
-- carrier and hangs it from the hand bone after the ped bones are updated (onClientPedsProcessed).
-- Also: the put-down key and the ground snap of dropped items.

local carried = {} -- ped -> { bag = object, monitor = object }

local function destroyFor(ped)
    local objects = carried[ped]
    carried[ped] = nil
    if not objects then return end
    for _, obj in pairs(objects) do
        if isElement(obj) then destroyElement(obj) end
    end
end

local function createFor(ped)
    destroyFor(ped)
    if not isElement(ped) or not isElementStreamedIn(ped) then return end
    local hands = getElementData(ped, BAG_DATA.HANDS)
    if type(hands) ~= "table" then return end
    local objects = {}
    for _, kind in ipairs(BAG.KINDS) do
        local model = tonumber(hands[kind])
        if model then
            local x, y, z = getElementPosition(ped)
            local obj = createObject(model, x, y, z)
            if obj then
                setElementCollisionsEnabled(obj, false)
                setElementDimension(obj, getElementDimension(ped))
                setElementInterior(obj, getElementInterior(ped))
                local scale = BAG.MODELS[kind].scale
                if scale and scale ~= 1 then setObjectScale(obj, scale) end
                objects[kind] = obj
            end
        end
    end
    carried[ped] = objects
end

addEventHandler("onClientElementDataChange", root, function(key)
    if key == BAG_DATA.HANDS and getElementType(source) == "player" then createFor(source) end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" and getElementData(source, BAG_DATA.HANDS) then createFor(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if carried[source] then destroyFor(source) end
end)

addEventHandler("onClientPlayerQuit", root, function() destroyFor(source) end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if getElementData(player, BAG_DATA.HANDS) then createFor(player) end
    end
end)

-- The item hangs from the hand bone: offset in the carrier's frame (BAG.MODELS[kind].hand)
local function placeAtHand(obj, ped, kind)
    local hx, hy, hz = getPedBonePosition(ped, BAG.BONES[kind])
    if not hx then return end
    local _, _, heading = getElementRotation(ped)
    local o = BAG.MODELS[kind].hand
    local rad = math.rad(heading)
    local c, sn = math.cos(rad), math.sin(rad)
    -- right = (c, sn), forward = (-sn, c)
    setElementPosition(obj, hx + o[1] * c - o[2] * sn, hy + o[1] * sn + o[2] * c, hz + o[3])
    setElementRotation(obj, o[4], o[5], heading + o[6])
end

addEventHandler("onClientPedsProcessed", root, function()
    for ped, objects in pairs(carried) do
        if not isElement(ped) then
            destroyFor(ped)
        else
            local hidden = isPedInVehicle(ped) or getElementAlpha(ped) == 0
            local dim, int = getElementDimension(ped), getElementInterior(ped)
            for kind, obj in pairs(objects) do
                if isElement(obj) then
                    setElementAlpha(obj, hidden and 0 or 255)
                    if getElementDimension(obj) ~= dim then setElementDimension(obj, dim) end
                    if getElementInterior(obj) ~= int then setElementInterior(obj, int) end
                    if not hidden then placeAtHand(obj, ped, kind) end
                end
            end
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Put-down key
-- ---------------------------------------------------------------------------------------------

local lastDrop = 0

bindKey(BAG.DROP_KEY, "down", function()
    if not getElementData(localPlayer, BAG_DATA.HANDS) then return end
    if isChatBoxInputActive() or isConsoleActive() or isCursorShowing() or isMainMenuActive() then return end
    if isPedInVehicle(localPlayer) or getTickCount() - lastDrop < 800 then return end
    lastDrop = getTickCount()
    triggerServerEvent("bag:drop", resourceRoot)
end)

-- ---------------------------------------------------------------------------------------------
-- Ground snap: the server places a dropped item at foot level, this client corrects the height
-- ---------------------------------------------------------------------------------------------

addEvent("bag:snap", true)
addEventHandler("bag:snap", resourceRoot, function(obj, heightAboveGround)
    if not isElement(obj) then return end
    local x, y, z = getElementPosition(obj)
    local hit, _, _, hz = processLineOfSight(x, y, z + 1.5, x, y, z - 3, true, false, false, true, false,
        false, false, false, obj)
    local ground = hit and hz or getGroundPosition(x, y, z + 1.5)
    if not ground or ground == 0 then return end
    triggerServerEvent("bag:snapResult", resourceRoot, obj, ground + (heightAboveGround or 0))
end)
