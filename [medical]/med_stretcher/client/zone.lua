-- Load zone: while the local player pushes a stretcher, the rectangle behind its ambulance is drawn
-- on the ground: white while the stretcher is outside, orange while it is inside but does not point
-- into the ambulance, green once it can be loaded.
-- Only the pusher sees it. The server checks the same zone (shared/util.lua) when loading.

local D = STRETCHER_DATA

local DRAW_DISTANCE = 40 -- metres between the player and the ambulance
local LINE_WIDTH = 6
local LIFT = 0.04        -- above the ground, against z-fighting

-- Vehicle-local x, y -> world x, y; z is put on the ground below the vehicle
local function cornerOnGround(m, lx, ly, vz)
    local x = lx * m[1][1] + ly * m[2][1] + m[4][1]
    local y = lx * m[1][2] + ly * m[2][2] + m[4][2]
    local ground = getGroundPosition(x, y, vz + 1)
    if not ground or ground == 0 or ground > vz + 1 then ground = vz - 1 end
    return x, y, ground + LIFT
end

local function color(rgb, alpha)
    return tocolor(rgb[1], rgb[2], rgb[3], alpha)
end

addEventHandler("onClientRender", root, function()
    local stretcher = getElementData(localPlayer, D.PUSHING)
    if not isElement(stretcher) then return end
    local vehicle = getElementData(stretcher, D.VEHICLE)
    if not isElement(vehicle) or not isElementStreamedIn(vehicle) then return end
    if getElementDimension(vehicle) ~= getElementDimension(localPlayer)
        or getElementInterior(vehicle) ~= getElementInterior(localPlayer) then return end

    local px, py, pz = getElementPosition(localPlayer)
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > DRAW_DISTANCE then return end

    -- same as the server: the stretcher's yaw follows the pusher's heading
    local _, _, prz = getElementRotation(localPlayer)
    local rgb = STRETCHER.LOAD_ZONE_COLOR
    if isInLoadZone(vehicle, getElementPosition(stretcher)) then
        rgb = isLoadAligned(vehicle, prz + STRETCHER.PUSH_OFFSET[6])
            and STRETCHER.LOAD_ZONE_OK_COLOR or STRETCHER.LOAD_ZONE_ANGLE_COLOR
    end

    local m = getElementMatrix(vehicle)
    local cx, cy, halfW, halfL = getLoadZone(vehicle)
    local c = {
        { cornerOnGround(m, cx - halfW, cy - halfL, vz) },
        { cornerOnGround(m, cx + halfW, cy - halfL, vz) },
        { cornerOnGround(m, cx + halfW, cy + halfL, vz) },
        { cornerOnGround(m, cx - halfW, cy + halfL, vz) },
    }

    if dxDrawPrimitive3D then
        local fill = color(rgb, STRETCHER.LOAD_ZONE_FILL_ALPHA)
        dxDrawPrimitive3D("trianglefan", false,
            { c[1][1], c[1][2], c[1][3], fill }, { c[2][1], c[2][2], c[2][3], fill },
            { c[3][1], c[3][2], c[3][3], fill }, { c[4][1], c[4][2], c[4][3], fill })
    end
    local line = color(rgb, STRETCHER.LOAD_ZONE_LINE_ALPHA)
    for i = 1, 4 do
        local a, b = c[i], c[i % 4 + 1]
        dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], line, LINE_WIDTH)
    end
end)
