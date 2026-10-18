-- /navmesh debug view (admin_level >= NAV.ADMIN_LEVEL): sends the network data around the admin to the client
-- (client/debug.lua draws it). Debug tool: English only, not in the v_locals catalogue (v_locals D14).
--   /navmesh                 toggle the view
--   /navmesh roads|peds|walk|boats|signals   toggle a layer (client side)
--   /navmesh info            what is under you (lane, ped path, walk cell) + stats
--   /navmesh from            mark the route start here
--   /navmesh to [mode]       route from the mark to here; mode = car|truck|bike|bus|emergency|offroad|gps (vehicle)
--                            or ped|civilian|police|hiker|free (ped roles) or boat; default car (on foot: civilian)
--   /navmesh clear           remove the test route

local viewers = {}       -- [player] = { x, y, z sent at }
local marks = {}         -- [player] = { x, y, z }
local sqrt = math.sqrt

local function isAdmin(p)
    return (tonumber(getElementData(p, "admin_level")) or 0) >= NAV.ADMIN_LEVEL
end

local function notify(p, text)
    triggerClientEvent(p, "navmesh:notify", resourceRoot, text)
end

local function r1(v) return math.floor(v * 10 + 0.5) / 10 end

local function collect(x, y, z)
    local R, P, B = Roads, Peds, Boats
    local rad = NAV.DEBUG_RADIUS
    local data = { lanes = {}, conns = {}, signals = {}, peds = {}, boats = {}, tiles = {}, cx = x, cy = y }
    if R.ready then
        local seen = {}
        R.index:each(x, y, rad, function(id)
            if seen[id] then return end
            seen[id] = true
            if (R.ax1[id] - x) ^ 2 + (R.ay1[id] - y) ^ 2 > rad * rad and (R.ax2[id] - x) ^ 2 + (R.ay2[id] - y) ^ 2 > rad * rad then return end
            local k = R.alink[id]
            data.lanes[#data.lanes + 1] = { r1(R.ax1[id]), r1(R.ay1[id]), r1(R.az1[id]), r1(R.ax2[id]), r1(R.ay2[id]), r1(R.az2[id]),
                R.kclass[k], R.kfl[k], R.afl[id], (R.kab[k] == 0 or R.kba[k] == 0) and 1 or 0, id }
            for _, c in ipairs(R.anext[id]) do
                local pts = Roads.connPoints(c, { { R.ax2[id], R.ay2[id], R.az2[id] } }, 4)
                local flat = {}
                for _, p in ipairs(pts) do flat[#flat + 1] = r1(p[1]); flat[#flat + 1] = r1(p[2]); flat[#flat + 1] = r1(p[3]) end
                data.conns[#data.conns + 1] = { flat, R.csig[c], R.cturn[c] }
            end
        end)
        for g = 1, R.groupCount do
            if R.sx[g] and (R.sx[g] - x) ^ 2 + (R.sy[g] - y) ^ 2 < rad * rad then
                data.signals[#data.signals + 1] = { R.sx[g], R.sy[g], R.sz[g], g }
            end
        end
    end
    if P.ready then
        local seen = {}
        P.index:each(x, y, rad, function(e)
            if seen[e] then return end
            seen[e] = true
            local a, b = P.ea[e], P.eb[e]
            data.peds[#data.peds + 1] = { r1(P.nx[a]), r1(P.ny[a]), r1(P.nz[a]), r1(P.nx[b]), r1(P.ny[b]), r1(P.nz[b]), P.ekind[e], P.ephase[e] }
        end)
    end
    if B.ready then
        for _, e in ipairs(B.edges) do
            local a, b = e[1], e[2]
            if (B.nx[a] - x) ^ 2 + (B.ny[a] - y) ^ 2 < rad * rad * 4 then
                data.boats[#data.boats + 1] = { B.nx[a], B.ny[a], B.nz[a], B.nx[b], B.ny[b], B.nz[b] }
            end
        end
    end
    if Walk.ready then
        local T = Walk.TILE
        local gx, gy = Walk.cellOf(x, y)
        local wr = NAV.DEBUG_WALK_RADIUS
        for tx = math.floor((gx - wr) / T), math.floor((gx + wr) / T) do
            for ty = math.floor((gy - wr) / T), math.floor((gy + wr) / T) do
                local t = Walk.tile(tx, ty)
                if t then
                    -- packed: 3 bytes per cell and layer (z + 32768 as 2 bytes, flags)
                    local parts, char = {}, string.char
                    local z, f = t.z, t.f
                    for i = 1, t.L * 1024, 256 do
                        local buf = {}
                        for j = i, i + 255 do
                            local v = z[j] + 32768
                            buf[#buf + 1] = char(v % 256, math.floor(v / 256), f[j])
                        end
                        parts[#parts + 1] = table.concat(buf)
                    end
                    data.tiles[#data.tiles + 1] = { tx, ty, t.L, table.concat(parts) }
                end
            end
        end
        data.walk = { ox = Walk.OX, oy = Walk.OY, tile = T }
    end
    return data
end

local function send(p)
    local x, y, z = getElementPosition(p)
    viewers[p] = { x, y, z }
    triggerLatentClientEvent(p, "navmesh:debugData", 500000, false, resourceRoot, collect(x, y, z))
end

setTimer(function()
    for p, at in pairs(viewers) do
        if not isElement(p) then
            viewers[p] = nil
        else
            local x, y = getElementPosition(p)
            if (x - at[1]) ^ 2 + (y - at[2]) ^ 2 > NAV.DEBUG_REFRESH_MOVE ^ 2 then send(p) end
        end
    end
end, 1000, 0)

addEventHandler("onPlayerQuit", root, function()
    viewers[source] = nil
    marks[source] = nil
end)

local VEHICLE_MODES = { car = true, truck = true, bike = true, bus = true, emergency = true, offroad = true, gps = true }
local PED_MODES = { ped = "civilian", civilian = "civilian", police = "police", hiker = "hiker", free = "free", medic = "emergency" }

local function info(p)
    local x, y, z = getElementPosition(p)
    local lines = {}
    local lane = getNearestLane(x, y, z, { radius = 15 })
    if lane then
        lines[#lines + 1] = ("lane %d (%s, %s, %d/%d lanes%s%s), %.0f km/h, %.1f m away"):format(lane.id, lane.class,
            lane.oneway and "one-way" or "two-way", lane.index + 1, lane.count, lane.unpaved and ", unpaved" or "",
            lane.trap and ", TRAP" or "", lane.speed * 3.6, lane.distance)
    end
    local px, py, pz, pi = getNearestPedPath(x, y, z, 30)
    if px then lines[#lines + 1] = ("ped %s edge %d, %.1f m away, width %.1f"):format(pi.kind, pi.edge, pi.distance, pi.width) end
    local gz, wi = getWalkableGround(x, y, z - 1, 3)
    if gz then
        lines[#lines + 1] = ("cell z %.1f layer %d: %s%s%s%s%s%s"):format(gz, wi.layer, wi.surface, wi.road and " road" or "",
            wi.crossing and " crossing" or "", wi.pedPath and " pedpath" or "", wi.edge and " edge" or "", wi.steep and " steep" or "")
    else
        lines[#lines + 1] = "no walkable cell here"
    end
    local s = getNavmeshStats()
    lines[#lines + 1] = ("walk tiles cached %d, reads %d"):format(s.walk.cachedTiles, s.walk.tileReads)
    notify(p, table.concat(lines, "\n"))
end

addCommandHandler("navmesh", function(p, _, arg, mode)
    if not isAdmin(p) then return end
    if not arg or arg == "" then
        if viewers[p] then
            viewers[p] = nil
            triggerClientEvent(p, "navmesh:debugOff", resourceRoot)
            notify(p, "Navmesh view off")
        else
            send(p)
            notify(p, "Navmesh view on (/navmesh roads|peds|walk|boats|signals|info|from|to|clear)")
        end
    elseif arg == "roads" or arg == "peds" or arg == "walk" or arg == "boats" or arg == "signals" then
        triggerClientEvent(p, "navmesh:debugLayer", resourceRoot, arg)
    elseif arg == "info" then
        info(p)
    elseif arg == "from" then
        local x, y, z = getElementPosition(p)
        marks[p] = { x, y, z }
        notify(p, ("Route start marked at %.0f, %.0f, %.0f"):format(x, y, z))
    elseif arg == "to" then
        local m = marks[p]
        if not m then notify(p, "Mark the start first: /navmesh from"); return end
        local x, y, z = getElementPosition(p)
        if not mode then mode = isPedInVehicle(p) and "car" or "civilian" end
        local t0 = getTickCount()
        local res, why
        if VEHICLE_MODES[mode] then
            res, why = findVehicleRoute(m[1], m[2], m[3], x, y, z, { profile = mode })
        elseif PED_MODES[mode] then
            res, why = findPedRoute(m[1], m[2], m[3], x, y, z, { role = PED_MODES[mode] })
        elseif mode == "boat" then
            res, why = findBoatRoute(m[1], m[2], m[3], x, y, z)
        else
            notify(p, "Unknown mode " .. tostring(mode)); return
        end
        local ms = getTickCount() - t0
        if not res then notify(p, ("No route (%s), %d ms"):format(tostring(why), ms)); return end
        triggerLatentClientEvent(p, "navmesh:debugRoute", 200000, false, resourceRoot, res.points, res.pointKinds or false, mode)
        local extra = res.method and (" via " .. res.method) or ""
        if res.instructions then extra = extra .. (", %d instructions"):format(#res.instructions) end
        if res.time then extra = extra .. (", ~%.0f s"):format(res.time) end
        notify(p, ("Route %s: %.0f m, %d points%s, %d ms"):format(mode, res.length, #res.points, extra, ms))
    elseif arg == "clear" then
        triggerClientEvent(p, "navmesh:debugRoute", resourceRoot, false)
    end
end)
