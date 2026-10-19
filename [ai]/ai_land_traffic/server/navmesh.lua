-- navmesh link (server): the road network of this resource is navmesh's (tools/build_runtime.py copies roads.nav
-- with the same lane / connection ids), so navmesh routes are driven directly. Used by:
--   scripted vehicles (lane-to-lane routes to their targets), the players' spawn area (GPS destination route),
--   emergency vehicles (their route ahead: GPS destination or lane prediction) and pulling over (walk grid:
--   is there drivable ground next to the lane?)
-- Every call goes through pcall: with navmesh stopped or a different network the traffic keeps driving at random.

Navmesh = { ok = false, pending = {} }   -- pending: [job id] = callback

local NM = Navmesh
local mtaCall = call

local function res()
    local r = getResourceFromName("navmesh")
    return r and getResourceState(r) == "running" and r or nil
end

local function nav(fn, ...)
    local r = res()
    if not r then return nil end
    local out = { pcall(mtaCall, r, fn, ...) }
    if not out[1] then return nil end
    return unpack(out, 2)
end

-- navmesh running with the network sim.dat was built from?
function Navmesh.check()
    local was = NM.ok
    NM.ok = false
    local st = nav("getNavmeshStats")
    local roads = type(st) == "table" and st.roads
    if roads and roads.ready then
        if Net.navSignature and roads.signature and roads.signature:upper() == Net.navSignature then
            NM.ok = true
        else
            outputDebugString("[ai_land_traffic] navmesh roads.nav differs from data/runtime (rerun tools/build_runtime.py): "
                .. "navmesh routes are off", 2)
        end
    end
    if NM.ok ~= was then
        outputDebugString("[ai_land_traffic] navmesh routes " .. (NM.ok and "on" or "off"))
    end
    return NM.ok
end

addEvent("onNavmeshReady")
addEvent("onNavmeshRouteReady")
addEventHandler("onNavmeshReady", root, function() if Net.ready then NM.check() end end)
addEventHandler("onResourceStop", root, function(r)
    if getResourceName(r) == "navmesh" then
        NM.ok = false
        NM.pending = {}
    end
end)

------------------------------------------------------------------------ routes

-- synchronous lane route: lanes { id, ... } and conns { [i] = connection into lanes[i] | false (lane change) },
-- or nil. opts: profile, maxNodes
function Navmesh.laneRoute(fromLane, fromU, toLane, toU, opts)
    if not NM.ok then return nil end
    local r = nav("findVehicleRoute", 0, 0, 0, 0, 0, 0, {
        startLane = fromLane, startU = fromU, goalLane = toLane, goalU = toU, lanesOnly = true,
        profile = opts and opts.profile or "car", maxNodes = opts and opts.maxNodes or TRAFFIC.SCRIPTED_MAX_NODES })
    if type(r) ~= "table" or not r.lanes then return nil end
    return r.lanes, r.connections
end

-- asynchronous route between two points (time-sliced in navmesh); cb(result | false) with result.lanes /
-- result.connections. opts as navmesh findVehicleRoute (lanesOnly is set). Returns false when navmesh is off.
function Navmesh.request(x1, y1, z1, x2, y2, z2, opts, cb)
    if not NM.ok then return false end
    opts = opts or {}
    opts.lanesOnly = true
    local id = nav("requestRoute", "vehicle", x1, y1, z1, x2, y2, z2, opts)
    if not id then return false end
    NM.pending[id] = cb
    return id
end

addEventHandler("onNavmeshRouteReady", resourceRoot, function(id, result)
    local cb = NM.pending[id]
    if not cb then return end
    NM.pending[id] = nil
    cb(type(result) == "table" and result.lanes and result or false)
end)

------------------------------------------------------------------------ following a route to a destination

local function laneDistance(id, x, y)
    local x1, y1 = Geo.lx1[id], Geo.ly1[id]
    local dx, dy = Geo.lx2[id] - x1, Geo.ly2[id] - y1
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and ((x - x1) * dx + (y - y1) * dy) / l2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = x - (x1 + dx * t), y - (y1 + dy * t)
    return math.sqrt(qx * qx + qy * qy), t * Geo.llen[id]
end

-- Keeps a vehicle on its navmesh route to (dx, dy[, dz]). t = caller-owned state table (reset it with a new one
-- when the destination changes). The route is requested asynchronously, and again (at most every `retry` ms) when
-- the vehicle left it. Returns the index of the vehicle's lane in t.lanes and s along it, or nil.
-- t: { lanes, conns, at, pending, retry }
function Navmesh.track(t, x, y, z, rz, dx, dy, dz, profile, now, retry)
    if not NM.ok then return nil end
    local lanes = t.lanes
    if lanes then
        for i = math.max(1, (t.at or 1) - 3), math.min(#lanes, (t.at or 1) + 40) do
            local id = lanes[i]
            local d, s = laneDistance(id, x, y)
            local len = Geo.llen[id]
            local lz = Geo.lz1[id] + (Geo.lz2[id] - Geo.lz1[id]) * (len > 0 and s / len or 0)
            if d < 14 and math.abs(lz - z) < 8 then
                t.at = i
                return i, s
            end
        end
        t.lanes = nil   -- left the route: a new one from here
    end
    if not t.pending and now >= (t.retry or 0) then
        t.pending, t.retry = true, now + (retry or 4000)
        local ok = NM.request(x, y, z, dx, dy, dz or false, { heading = rz, profile = profile or "car" }, function(r)
            t.pending = false
            if r then t.lanes, t.conns, t.at = r.lanes, r.connections, 1 end
        end)
        if not ok then t.pending = false end
    end
    return nil
end

------------------------------------------------------------------------ queries

-- lane under a moving vehicle: lane id, s along it, or nil. heading = MTA rotation z
function Navmesh.laneAt(x, y, z, heading, radius)
    if not NM.ok then return nil end
    local info = nav("getNearestLane", x, y, z, { heading = heading, headingTolerance = 60, radius = radius or 12, maxZ = 4 })
    if type(info) ~= "table" or not info.id or not Geo.llen[info.id] then return nil end
    return info.id, (info.u or 0) * Geo.llen[info.id]
end

-- walkable ground of the navmesh walk grid near (x, y, z): ground z and the cell info, or nil
function Navmesh.ground(x, y, z, maxDz)
    if not NM.ok then return nil end
    local gz, info = nav("getWalkableGround", x, y, z, maxDz or 1.5)
    if not gz then return nil end
    return gz, info
end
