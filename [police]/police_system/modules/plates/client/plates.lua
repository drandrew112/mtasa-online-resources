-- police_system / modules/plates/client/plates.lua
-- ALPR plate labels: on duty, only while sitting in a police vehicle, a dx label over the vehicles within RANGE (at
-- most MAX, the nearest, with a line of sight check). The plate in big letters on a see-through panel; under it the
-- ALPR flags of the server (plates/server/alpr.lua: stolen, expired papers, the owner's warrant / licence, no
-- plate), no model name. A 300 ms timer collects the vehicles and asks the flags of the ones not known (or older
-- than CACHE); the layer only draws while the list is not empty. The own vehicle is not shown.

local PL = POLICE.PLATES
local list = {}
local known = {}    -- [veh] = { at = tick, flags = { ... } }
local asked = {}    -- [veh] = tick of the last request
local timer

local SEVERE = { stolen = true, warrant = true }

local function collect()
    local veh0 = POL.inPoliceVehicle()
    if not veh0 then
        if #list > 0 then list = {}; POL.layers.set("plates", false) end
        return
    end
    local cx, cy, cz = getCameraMatrix()
    local x, y, z = getElementPosition(localPlayer)
    local found = {}
    for _, v in ipairs(getElementsWithinRange(x, y, z, PL.RANGE, "vehicle")) do
        if v ~= veh0 and isElementOnScreen(v) and getElementDimension(v) == getElementDimension(localPlayer) then
            local vx, vy, vz = getElementPosition(v)
            local d = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
            if isLineOfSightClear(cx, cy, cz, vx, vy, vz + 1, true, false, false, true, false, true) then
                found[#found + 1] = { v = v, d = d, plate = getVehiclePlateText(v) }
            end
        end
    end
    table.sort(found, function(a, b) return a.d < b.d end)
    for i = PL.MAX + 1, #found do found[i] = nil end
    list = found
    -- flags of the new / old ones (one request; asked again after 5 s if no answer)
    local now = getTickCount()
    local ask = {}
    for _, e in ipairs(found) do
        local k = known[e.v]
        if (not k or now - k.at > PL.CACHE) and now - (asked[e.v] or 0) > 5000 then
            asked[e.v] = now
            ask[#ask + 1] = e.v
        end
    end
    if #ask > 0 then POL.send("alpr:scan", ask) end
    POL.layers.set("plates", #list > 0)
end

POL.handle("alpr:result", function(rows)
    local now = getTickCount()
    for _, r in ipairs(rows or {}) do
        if isElement(r.v) then known[r.v] = { at = now, flags = r.f or {} } end
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if known[source] or asked[source] then known[source], asked[source] = nil, nil end
end)

local function flagText(id)
    local key = "police_system.alpr." .. id
    return L.upper(L.has(key) and L(key) or id)
end

local function draw()
    local f, f2 = POL.font(15, true), POL.font(8, true)
    local c = POL.colors
    local bg = tocolor(10, 18, 34, 120)
    for _, e in ipairs(list) do
        if isElement(e.v) then
            local x, y, z = getElementPosition(e.v)
            local sx, sy = getScreenFromWorldPosition(x, y, z + 1.4)
            if sx then
                local k = known[e.v]
                local flags = k and k.flags or {}
                local fh = POL.px(15)
                local w = dxGetTextWidth(e.plate, 1, f) + POL.px(20)
                for _, id in ipairs(flags) do w = math.max(w, dxGetTextWidth(flagText(id), 1, f2) + POL.px(16)) end
                local ph = POL.px(34)
                local h = ph + #flags * fh + (#flags > 0 and POL.px(4) or 0)
                local top = sy - h
                local alert = #flags > 0
                dxDrawRectangle(sx - w / 2, top, w, h, bg)
                dxDrawRectangle(sx - w / 2, top, w, POL.px(2), alert and c.red or c.accent)
                dxDrawText(e.plate, sx - w / 2, top, sx + w / 2, top + ph, c.white, 1, f, "center", "center")
                for i, id in ipairs(flags) do
                    local fy = top + ph + (i - 1) * fh
                    dxDrawText(flagText(id), sx - w / 2, fy, sx + w / 2, fy + fh, SEVERE[id] and c.red or c.orange, 1, f2, "center", "center")
                end
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
        list, known, asked = {}, {}, {}
        POL.layers.set("plates", false)
    end
end

POL.on("unit", refresh)
POL.on("right", refresh)
