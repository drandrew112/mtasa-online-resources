-- police_system / modules/plates/client/plates.lua
-- Plate labels: with the police right a small dx label over the vehicles within RANGE (at most MAX, the nearest,
-- with a line of sight check). Client only (getVehiclePlateText), no server data. A 300 ms timer collects the
-- vehicles, the layer only draws while the list is not empty. The own vehicle's plate is not shown while sitting
-- in it (the decision).

local PL = POLICE.PLATES
local list = {}
local timer

local function collect()
    local veh0 = getPedOccupiedVehicle(localPlayer)
    local cx, cy, cz = getCameraMatrix()
    local x, y, z = getElementPosition(localPlayer)
    local found = {}
    for _, v in ipairs(getElementsWithinRange(x, y, z, PL.RANGE, "vehicle")) do
        if v ~= veh0 and isElementOnScreen(v) and getElementDimension(v) == getElementDimension(localPlayer) then
            local vx, vy, vz = getElementPosition(v)
            local d = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
            if isLineOfSightClear(cx, cy, cz, vx, vy, vz + 1, true, false, false, true, false, true) then
                found[#found + 1] = { v = v, d = d, plate = getVehiclePlateText(v), name = exports.veh_manager:getModelName(getElementModel(v)) }
            end
        end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    for i = PL.MAX + 1, #found do found[i] = nil end
    list = found
    POL.layers.set("plates", #list > 0)
end

local function draw()
    local f, f2 = POL.font(10, true), POL.font(8)
    local c = POL.colors
    for _, e in ipairs(list) do
        if isElement(e.v) then
            local x, y, z = getElementPosition(e.v)
            local sx, sy = getScreenFromWorldPosition(x, y, z + 1.4)
            if sx then
                local w = math.max(dxGetTextWidth(e.plate, 1, f), dxGetTextWidth(e.name, 1, f2)) + POL.px(14)
                local h = POL.px(32)
                dxDrawRectangle(sx - w / 2, sy - h, w, h, c.bg)
                dxDrawRectangle(sx - w / 2, sy - h, w, POL.px(2), c.accent)
                dxDrawText(e.plate, sx - w / 2, sy - h, sx + w / 2, sy - h / 2 + POL.px(2), c.white, 1, f, "center", "center")
                dxDrawText(e.name, sx - w / 2, sy - h / 2, sx + w / 2, sy, c.dim, 1, f2, "center", "center")
            end
        end
    end
end
POL.layers.add("plates", draw, 1)

local function refresh()
    local on = POL.hasRight() and POL.onDuty()
    if on and not timer then
        timer = setTimer(collect, PL.INTERVAL, 0)
    elseif not on and timer then
        killTimer(timer)
        timer = nil
        list = {}
        POL.layers.set("plates", false)
    end
end

POL.on("unit", refresh)
POL.on("right", refresh)
