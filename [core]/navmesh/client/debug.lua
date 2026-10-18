-- /navmesh debug view (client): draws the data server/debug.lua sends around the admin.
-- The render handler is attached only while the view is on. Debug tool: English only (v_locals D14).

local Dbg = {
    on = false, data = nil, route = nil, routeKinds = nil, routeMode = nil,
    layers = { roads = true, peds = true, walk = true, boats = true, signals = true },
    walkVerts = nil, walkAt = nil, cells = nil,
}
local sqrt, floor = math.sqrt, math.floor
local DRAW_DIST = 140

local CLASS_COLOR = {
    [1] = tocolor(255, 70, 70, 230),    -- highway
    [2] = tocolor(255, 160, 0, 230),    -- ramp
    [3] = tocolor(235, 235, 235, 210),  -- road
    [4] = tocolor(140, 140, 140, 210),  -- service
}
local C_UNPAVED = tocolor(180, 125, 60, 220)
local C_EMERGENCY = tocolor(90, 140, 255, 220)
local C_TRAP = tocolor(190, 60, 255, 230)
local C_FORCED = tocolor(255, 0, 200, 255)
local PED_COLOR = { tocolor(0, 200, 255, 220), tocolor(60, 220, 60, 220), tocolor(255, 230, 0, 240), tocolor(255, 120, 0, 240) }
local C_BOAT = tocolor(40, 90, 255, 220)
local CONN_COLOR = { [0] = tocolor(200, 200, 200, 110), tocolor(120, 255, 120, 160), tocolor(120, 220, 255, 160) }
local C_ROUTE = tocolor(255, 0, 255, 255)
local WALK_CLASS = {
    [0] = { 255, 255, 255 }, { 120, 120, 120 }, { 205, 205, 195 }, { 70, 170, 60 }, { 165, 120, 70 }, { 90, 120, 210 },
    { 80, 210, 230 }, { 130, 140, 50 },
}

local function notify(text)
    local ui = getResourceFromName("ui_core")
    if ui and getResourceState(ui) == "running" then
        exports.ui_core:addNotification("Navmesh", text)
    else
        outputConsole("[navmesh] " .. text)
    end
end
addEvent("navmesh:notify", true)
addEventHandler("navmesh:notify", resourceRoot, notify)

------------------------------------------------------------------------ walk cells -> triangle batches

local function cellColor(f)
    local c = WALK_CLASS[bitAnd(f, 7)]
    local r, g, b = c[1], c[2], c[3]
    if bitAnd(f, NAV_WF.ROAD) ~= 0 then r, g, b = 60, 60, 60 end
    if bitAnd(f, NAV_WF.PED) ~= 0 then r, g, b = 225, 70, 205 end
    if bitAnd(f, NAV_WF.CROSS) ~= 0 then r, g, b = 245, 225, 40 end
    if bitAnd(f, NAV_WF.STEEP) ~= 0 then r, g, b = r * 0.7, g * 0.7, b * 0.7 end
    local a = bitAnd(f, NAV_WF.EDGE) ~= 0 and 200 or 120
    if bitAnd(f, NAV_WF.EDGE) ~= 0 then r, g, b = r * 0.4, g * 0.4, b * 0.4 end
    return tocolor(r, g, b, a)
end

local function unpackTiles()
    Dbg.cells = {}
    local d = Dbg.data
    if not d or not d.walk then return end
    for _, t in ipairs(d.tiles) do
        local tx, ty, L, s = t[1], t[2], t[3], t[4]
        local z, f = {}, {}
        for i = 1, L * 1024 do
            local a, b, c = s:byte(i * 3 - 2, i * 3)
            z[i] = a + b * 256 - 32768
            f[i] = c
        end
        Dbg.cells[ty * 10000 + tx] = { L = L, z = z, f = f }
    end
end

local function buildWalk(px, py, pz)
    local d = Dbg.data
    local verts = {}
    Dbg.walkAt = { px, py }
    if not d or not d.walk or not Dbg.cells then Dbg.walkVerts = verts; return end
    local W = d.walk
    local T = W.tile
    local r = NAV.DEBUG_DRAW_WALK
    local gx0, gy0 = floor(px - W.ox), floor(py - W.oy)
    local h = 0.42
    for gy = gy0 - r, gy0 + r do
        for gx = gx0 - r, gx0 + r do
            if (gx - gx0) ^ 2 + (gy - gy0) ^ 2 <= r * r then
                local t = Dbg.cells[floor(gy / T) * 10000 + floor(gx / T)]
                if t then
                    local c = (gy % T) * T + (gx % T) + 1
                    for l = 0, t.L - 1 do
                        local zdm = t.z[l * 1024 + c]
                        if zdm ~= -32768 then
                            local z = zdm / 10 + 0.06
                            if math.abs(z - pz) < 8 then
                                local col = cellColor(t.f[l * 1024 + c])
                                local x, y = W.ox + gx + 0.5, W.oy + gy + 0.5
                                verts[#verts + 1] = { x - h, y - h, z, col }
                                verts[#verts + 1] = { x + h, y - h, z, col }
                                verts[#verts + 1] = { x + h, y + h, z, col }
                                verts[#verts + 1] = { x - h, y - h, z, col }
                                verts[#verts + 1] = { x + h, y + h, z, col }
                                verts[#verts + 1] = { x - h, y + h, z, col }
                            end
                        end
                    end
                end
            end
        end
    end
    -- batches for dxDrawPrimitive3D (argument count limit)
    local batches, b = {}, nil
    for i = 1, #verts do
        if not b or #b >= 1500 then b = {}; batches[#batches + 1] = b end
        b[#b + 1] = verts[i]
    end
    Dbg.walkVerts = batches
end

------------------------------------------------------------------------ drawing

local function arrow(x1, y1, z1, x2, y2, z2, col, size)
    local dx, dy = x2 - x1, y2 - y1
    local L = sqrt(dx * dx + dy * dy)
    if L < 0.5 then return end
    dx, dy = dx / L, dy / L
    local mx, my, mz = (x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2
    local bx, by = mx - dx * size, my - dy * size
    dxDrawLine3D(mx, my, mz, bx - dy * size * 0.6, by + dx * size * 0.6, mz, col, 3)
    dxDrawLine3D(mx, my, mz, bx + dy * size * 0.6, by - dx * size * 0.6, mz, col, 3)
end

local function render()
    local d = Dbg.data
    if not d then return end
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local dd = DRAW_DIST * DRAW_DIST
    local L = Dbg.layers
    local nLanes, nPeds = 0, 0

    if L.walk and Dbg.walkVerts then
        if not Dbg.walkAt or (px - Dbg.walkAt[1]) ^ 2 + (py - Dbg.walkAt[2]) ^ 2 > 16 then buildWalk(px, py, pz) end
        for _, b in ipairs(Dbg.walkVerts) do dxDrawPrimitive3D("trianglelist", false, unpack(b)) end
    end
    if L.roads then
        for _, l in ipairs(d.lanes) do
            local mx, my = (l[1] + l[4]) / 2, (l[2] + l[5]) / 2
            if (mx - cx) ^ 2 + (my - cy) ^ 2 < dd then
                nLanes = nLanes + 1
                local col = CLASS_COLOR[l[7]] or CLASS_COLOR[3]
                if bitAnd(l[8], NAV_KF.UNPAVED) ~= 0 then col = C_UNPAVED end
                if bitAnd(l[8], NAV_KF.EMERGENCY) ~= 0 then col = C_EMERGENCY end
                if bitAnd(l[9], NAV_LF.TRAP) ~= 0 then col = C_TRAP end
                local w = l[7] == 1 and 4 or 2.5
                dxDrawLine3D(l[1], l[2], l[3] + 0.3, l[4], l[5], l[6] + 0.3, col, w)
                if bitAnd(l[8], NAV_KF.FORCED) ~= 0 then dxDrawLine3D(l[1], l[2], l[3] + 0.5, l[4], l[5], l[6] + 0.5, C_FORCED, 1.5) end
                arrow(l[1], l[2], l[3] + 0.3, l[4], l[5], l[6] + 0.3, col, 1.4)
            end
        end
        for _, c in ipairs(d.conns) do
            local p = c[1]
            if (p[1] - cx) ^ 2 + (p[2] - cy) ^ 2 < dd then
                local col = CONN_COLOR[c[2]] or CONN_COLOR[0]
                for i = 1, #p - 3, 3 do
                    dxDrawLine3D(p[i], p[i + 1], p[i + 2] + 0.3, p[i + 3], p[i + 4], p[i + 5] + 0.3, col, 1.5)
                end
            end
        end
    end
    if L.signals then
        for _, s in ipairs(d.signals) do
            if (s[1] - cx) ^ 2 + (s[2] - cy) ^ 2 < dd then
                dxDrawLine3D(s[1], s[2], s[3], s[1], s[2], s[3] + 6, tocolor(255, 60, 60, 220), 4)
                local sx, sy = getScreenFromWorldPosition(s[1], s[2], s[3] + 6.5)
                if sx then dxDrawText("signal " .. s[4], sx, sy, sx, sy, tocolor(255, 120, 120), 1.2, "default-bold", "center", "bottom") end
            end
        end
    end
    if L.peds then
        for _, e in ipairs(d.peds) do
            local mx, my = (e[1] + e[4]) / 2, (e[2] + e[5]) / 2
            if (mx - cx) ^ 2 + (my - cy) ^ 2 < dd then
                nPeds = nPeds + 1
                dxDrawLine3D(e[1], e[2], e[3] + 0.15, e[4], e[5], e[6] + 0.15, PED_COLOR[e[7]] or PED_COLOR[2], e[7] >= 3 and 3 or 2)
            end
        end
    end
    if L.boats then
        for _, e in ipairs(d.boats) do
            dxDrawLine3D(e[1], e[2], e[3] + 0.5, e[4], e[5], e[6] + 0.5, C_BOAT, 3)
        end
    end
    if Dbg.route then
        local r = Dbg.route
        for i = 2, #r do
            dxDrawLine3D(r[i - 1][1], r[i - 1][2], r[i - 1][3] + 0.8, r[i][1], r[i][2], r[i][3] + 0.8, C_ROUTE, 6)
        end
    end

    -- legend
    local sw = guiGetScreenSize()
    local x, y = sw - 330, 220
    dxDrawRectangle(x - 10, y - 8, 320, 236, tocolor(0, 0, 0, 150))
    local function line(text, col)
        dxDrawText(text, x, y, x, y, col or tocolor(255, 255, 255), 1, "default-bold")
        y = y + 16
    end
    line("NAVMESH  (/navmesh roads|peds|walk|boats|signals)")
    line(("roads %s  peds %s  walk %s  boats %s  signals %s"):format(L.roads and "on" or "off", L.peds and "on" or "off",
        L.walk and "on" or "off", L.boats and "on" or "off", L.signals and "on" or "off"), tocolor(200, 200, 200))
    line(("lanes %d / %d drawn, ped edges %d / %d"):format(nLanes, #d.lanes, nPeds, #d.peds), tocolor(200, 200, 200))
    line("highway", CLASS_COLOR[1]); line("ramp (one-way)", CLASS_COLOR[2]); line("road", CLASS_COLOR[3])
    line("service / unpaved / emergency-only", C_UNPAVED); line("trap lane (no way back) / forced one-way", C_TRAP)
    line("ped: sidewalk", PED_COLOR[1]); line("ped: path", PED_COLOR[2]); line("ped: crossing / with light", PED_COLOR[3])
    line("walk cell: grey road, pink ped path, yellow crossing", tocolor(225, 70, 205))
    if Dbg.route then line(("route %s: %d points"):format(Dbg.routeMode or "?", #Dbg.route), C_ROUTE) end
end

local function setOn(on)
    if on == Dbg.on then return end
    Dbg.on = on
    if on then addEventHandler("onClientRender", root, render)
    else
        removeEventHandler("onClientRender", root, render)
        Dbg.data, Dbg.walkVerts, Dbg.cells, Dbg.route = nil, nil, nil, nil
    end
end

addEvent("navmesh:debugData", true)
addEventHandler("navmesh:debugData", resourceRoot, function(data)
    Dbg.data = data
    unpackTiles()
    local px, py, pz = getElementPosition(localPlayer)
    buildWalk(px, py, pz)
    setOn(true)
end)

addEvent("navmesh:debugOff", true)
addEventHandler("navmesh:debugOff", resourceRoot, function() setOn(false) end)

addEvent("navmesh:debugLayer", true)
addEventHandler("navmesh:debugLayer", resourceRoot, function(layer)
    Dbg.layers[layer] = not Dbg.layers[layer]
end)

addEvent("navmesh:debugRoute", true)
addEventHandler("navmesh:debugRoute", resourceRoot, function(points, kinds, mode)
    Dbg.route, Dbg.routeKinds, Dbg.routeMode = points or nil, kinds or nil, mode
end)
