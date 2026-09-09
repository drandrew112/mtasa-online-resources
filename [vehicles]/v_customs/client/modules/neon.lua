-- v_customs :: neon underglow (client)
--
-- Two coloured tube objects attached under the chassis. The colour lives on
-- "customs:extras".neon (server) and arrives over "v_customs:neon"; restreamed
-- vehicles rebuild their tubes from that element data.

local NEON_MODELS = {
    white = 5764, blue = 5681, green = 18448, red = 18215, yellow = 18214,
    pink = 18213, orange = 14399, lightblue = 14400, rasta = 14401, ice = 14402,
}

local tubes = {}   -- [veh] = { a = obj, b = obj }

addEvent("v_customs:neon", true)

local function removeNeon(veh)
    local t = tubes[veh]
    if not t then return end
    if isElement(t.a) then destroyElement(t.a) end
    if isElement(t.b) then destroyElement(t.b) end
    tubes[veh] = nil
end

local function addNeon(veh, colorId)
    local model = NEON_MODELS[colorId]
    if not model or not isElement(veh) then return end
    removeNeon(veh)

    local x, y, z = getElementPosition(veh)
    local a = createObject(model, x, y, z)
    local b = createObject(model, x, y, z)
    setElementCollisionsEnabled(a, false)
    setElementCollisionsEnabled(b, false)
    attachElements(a, veh, 0.85, 0, -0.5)
    attachElements(b, veh, -0.85, 0, -0.5)
    tubes[veh] = { a = a, b = b }
end

local function neonOf(veh)
    local extras = getElementData(veh, "customs:extras")
    return type(extras) == "table" and extras.neon or nil
end

-- used by client/preview.lua for the live neon preview
NeonFX = { add = addNeon, remove = removeNeon }

addEventHandler("onClientResourceStart", resourceRoot, function()
    for name, model in pairs(NEON_MODELS) do
        local col = engineLoadCOL("files/neons/neonCollision.col")
        local dff = engineLoadDFF("files/neons/" .. name .. ".dff")
        if dff then engineReplaceModel(dff, model) end
        if col then engineReplaceCOL(col, model) end
    end
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        local c = neonOf(veh)
        if c then addNeon(veh, c) end
    end
end)

addEventHandler("v_customs:neon", root, function(veh, colorId)
    if not isElement(veh) then return end
    if colorId then addNeon(veh, colorId) else removeNeon(veh) end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "vehicle" then return end
    local c = neonOf(source)
    if c then addNeon(source, c) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if getElementType(source) == "vehicle" then removeNeon(source) end
end)

addEventHandler("onClientElementDestroy", root, function()
    if getElementType(source) == "vehicle" then removeNeon(source) end
end)
