--autor: Emanuel
--04/2021
--Cableway system :D

-- The rocks (879, 880) on Mount Chiliad collide with the top station
local ROCK_MODELS = { 879, 880 }
local ROCK_RADIUS = 10000

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, model in ipairs(ROCK_MODELS) do
        removeWorldModel(model, ROCK_RADIUS, 0, 0, 0)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, model in ipairs(ROCK_MODELS) do
        restoreWorldModel(model, ROCK_RADIUS, 0, 0, 0)
    end
end)

-- The two cables. They are drawn only while the camera is near them: they run along a long,
-- narrow line, so the check is the distance from the line itself (not a circle around it),
-- once a second; the margin covers that delay at speed.
local CABLE_A = { -2130.3, -2553.55 }       -- ground station (between the two cables)
local CABLE_B = { -2260.5, -1778.58 }       -- top station
local CABLE_DRAW_DIST = 500                 -- m from the line (dxDrawLine3D 10 px stays visible far)
local CABLE_COLOR = tocolor(0, 0, 0, 255)
local cableShown = false

local function drawCables()
    dxDrawLine3D(-2124.80688, -2552.63257, 46.5, -2255.23218, -1777.85, 464.6, CABLE_COLOR, 10)
    dxDrawLine3D(-2135.83423, -2554.47144, 46.5, -2265.81909, -1779.30981, 464.6, CABLE_COLOR, 10)
end

local function distToCable(px, py)
    local ax, ay, bx, by = CABLE_A[1], CABLE_A[2], CABLE_B[1], CABLE_B[2]
    local dx, dy = bx - ax, by - ay
    local t = ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)
    t = math.max(0, math.min(1, t))
    return getDistanceBetweenPoints2D(px, py, ax + dx * t, ay + dy * t)
end

setTimer(function()
    local cx, cy = getCameraMatrix()
    local on = getElementDimension(localPlayer) == 0 and getElementInterior(localPlayer) == 0
        and distToCable(cx, cy) < CABLE_DRAW_DIST
    if on == cableShown then return end
    cableShown = on
    if on then
        addEventHandler("onClientRender", root, drawCables)
    else
        removeEventHandler("onClientRender", root, drawCables)
    end
end, 1000, 0)
