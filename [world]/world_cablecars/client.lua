--autor: Emanuel 
--04/2021
--Cableway system :D

--CABLE WAY / Teleférico

local radius, x, y, z = 10000,0,0,0 

--remove rocks in mount chiliad
addEventHandler('onClientResourceStop', resourceRoot, 
function()
	restoreWorldModel(879,  radius, x, y, z)
	restoreWorldModel(880, radius, x, y, z )
end)

addEventHandler('onClientResourceStart', resourceRoot, 
function()
	removeWorldModel(879,  radius, x, y, z )
	removeWorldModel(880,  radius, x, y, z )
end)

function cableforcableway()
dxDrawLine3D(-2124.80688, -2552.63257, 46.5, -2255.23218, -1777.85, 464.6, tocolor(0,0,0,255), 10)
dxDrawLine3D(-2135.83423, -2554.47144, 46.5, -2265.81909, -1779.30981, 464.6, tocolor(0,0,0,255), 10)
end

-- The cables are drawn only while the camera is near them. They run along a long, narrow line,
-- so the check is the distance from the line itself (not a circle around it), once a second;
-- the margin covers that delay at speed.
local CABLE_A = { -2130.3, -2553.55 }       -- ground station (between the two cables)
local CABLE_B = { -2260.5, -1778.58 }       -- top station
local CABLE_DRAW_DIST = 500                 -- m from the line (dxDrawLine3D 10 px stays visible far)
local cableShown = false

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
        addEventHandler("onClientRender", root, cableforcableway)
    else
        removeEventHandler("onClientRender", root, cableforcableway)
    end
end, 1000, 0)

--show line in map not zoom bug xd
function cableforcablewayinmap()
if (isPlayerMapVisible()) then
	dxDrawLine(225, 617, 240, 709, tocolor(0, 0, 0, 255), 1, true)
end
end
addEventHandler("onClientRender", root, cableforcablewayinmap)