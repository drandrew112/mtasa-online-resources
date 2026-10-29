if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Race helpers on the racer's client (server: mode_race/server.lua):
--   * vehicle in the water for RACE.waterMs -> asks the server to put the racer back
--   * "Return to the route" warning with its countdown (the server decides)
--   * the finish time limit after the first finisher (ui_core drawTimer)
--   * ghost vehicles: a vehicle with element data "jobs.ghost" does not collide with the other
--     vehicles of its dimension and is see-through (every client, so the physics agree)

local uicore = exports.ui_core
local RACE = JOBS_CONFIG.RACE
local screenW, screenH = guiGetScreenSize()
local SCALE = (uicore:ui(1000) or 1000) / 1000
local function S(v) return v * SCALE end

-- vehicles that may be in the water: boats, amphibians, sea planes
local WATER_OK = { [539] = true, [460] = true, [447] = true, [417] = true }

local racing, waterSince = false, nil
local offRouteUntil, limitUntil = nil, nil
local hudOn = false
local drawHud

local function setHud()
    local on = (offRouteUntil or limitUntil) and true or false
    if on == hudOn then return end
    hudOn = on
    if on then addEventHandler("onClientRender", root, drawHud) else removeEventHandler("onClientRender", root, drawHud) end
end

addEvent("jobmanager:raceRacing", true)
addEventHandler("jobmanager:raceRacing", resourceRoot, function(on)
    racing, waterSince = on == true, nil
    JobUi.racing = racing
    if not racing then offRouteUntil = nil setHud() end
end)

addEvent("jobmanager:raceOffRoute", true)
addEventHandler("jobmanager:raceOffRoute", resourceRoot, function(ms)
    offRouteUntil = tonumber(ms) and (getTickCount() + ms) or nil
    setHud()
end)

addEvent("jobmanager:raceFinishLimit", true)
addEventHandler("jobmanager:raceFinishLimit", resourceRoot, function(ms)
    limitUntil = tonumber(ms) and (getTickCount() + ms) or nil
    setHud()
end)

-- matchEnded / matchLeft also end the timers
for _, name in ipairs({ "jobmanager:matchEnded", "jobmanager:matchLeft", "jobmanager:matchQuietEnd" }) do
    addEvent(name, true)
    addEventHandler(name, resourceRoot, function()
        racing, waterSince, offRouteUntil, limitUntil = false, nil, nil, nil
        JobUi.racing = false
        setHud()
    end)
end

setTimer(function()
    if not racing then return end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle or getVehicleType(vehicle) == "Boat" or WATER_OK[getElementModel(vehicle)] then waterSince = nil return end
    if isElementInWater(vehicle) then
        waterSince = waterSince or getTickCount()
        if getTickCount() - waterSince >= RACE.waterMs then
            waterSince = nil
            triggerServerEvent("jobmanager:raceRecover", resourceRoot, "water")
        end
    else
        waterSince = nil
    end
end, 250, 0)

local function fmt(ms)
    local s = math.max(0, math.ceil(ms / 1000))
    return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

drawHud = function()
    local now = getTickCount()
    if limitUntil then
        if now > limitUntil then limitUntil = nil else uicore:drawTimer(fmt(limitUntil - now)) end
    end
    if offRouteUntil then
        local left = offRouteUntil - now
        local y = screenH * 0.28
        dxDrawText(L("v_jobmanager.mode_race.return_to_route"), 0, y, screenW, y + S(40),
            tocolor(255, 90, 70, 255), S(2.2), "default-bold", "center", "top")
        dxDrawText(tostring(math.max(0, math.ceil(left / 1000))), 0, y + S(40), screenW, y + S(110),
            tocolor(255, 255, 255, 240), S(4), "pricedown", "center", "top")
        if left < -2000 then offRouteUntil = nil end
    end
    setHud()
end

--------------------------------------------------------------------------------
-- ghost vehicles
--------------------------------------------------------------------------------

local ghosts = {}       -- vehicle -> true

local function setGhost(vehicle, on)
    local dim = getElementDimension(vehicle)
    for _, other in ipairs(getElementsByType("vehicle", root, true)) do
        if other ~= vehicle and getElementDimension(other) == dim then
            setElementCollidableWith(vehicle, other, not on)
        end
    end
    setElementAlpha(vehicle, on and 150 or 255)
    ghosts[vehicle] = on or nil
end

addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if key ~= "jobs.ghost" or getElementType(source) ~= "vehicle" then return end
    setGhost(source, new == true)
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "vehicle" then return end
    if getElementData(source, "jobs.ghost") == true then setGhost(source, true) end
    -- a vehicle streaming in next to a ghost
    for vehicle in pairs(ghosts) do
        if isElement(vehicle) and vehicle ~= source then setElementCollidableWith(vehicle, source, false) end
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if ghosts[source] then ghosts[source] = nil end
end)
