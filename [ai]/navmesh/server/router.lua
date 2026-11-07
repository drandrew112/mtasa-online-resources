-- High-level routing for the exports: vehicle routes (roads), ped routes (ped graph + walk grid), boat routes.
-- Every search can run synchronously (export call) or as an async job (coroutine, time-sliced) that answers
-- with the event onNavmeshRouteReady.

Nav = { jobs = {}, nextJob = 0, sliceStart = 0, SLICE = 8 }
local sqrt = math.sqrt

-- called by the searches every few thousand expansions: yields inside an async job when the slice is used up
function Nav.budget()
    if Nav.inJob and getTickCount() - Nav.sliceStart > Nav.SLICE then
        coroutine.yield()
        Nav.sliceStart = getTickCount()
    end
end

------------------------------------------------------------------------ vehicles

-- a given lane as the only start / goal: { {lane, 0, u} } (nil = no such lane)
local function laneEnd(id, u)
    id = tonumber(id)
    if not id or not Roads.alink[id] then return nil end
    return { { id, 0, math.max(0, math.min(1, tonumber(u) or 0)) } }
end

-- Douglas-Peucker on {x, y, z} points (2D distance): drops points closer than `tol` metres to the simplified line
local function simplifyPoints(pts, tol)
    local n = #pts
    if n < 3 or not tol or tol <= 0 then return pts end
    local keep = { [1] = true, [n] = true }
    local stack = { { 1, n } }
    local tol2 = tol * tol
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, b = seg[1], seg[2]
        local ax, ay, bx, by = pts[a][1], pts[a][2], pts[b][1], pts[b][2]
        local dx, dy = bx - ax, by - ay
        local l2 = dx * dx + dy * dy
        local best, bi = -1, nil
        for i = a + 1, b - 1 do
            local px, py = pts[i][1] - ax, pts[i][2] - ay
            local t = l2 > 0 and (px * dx + py * dy) / l2 or 0
            if t < 0 then t = 0 elseif t > 1 then t = 1 end
            local qx, qy = px - dx * t, py - dy * t
            local d2 = qx * qx + qy * qy
            if d2 > best then best, bi = d2, i end
        end
        if bi and best > tol2 then
            keep[bi] = true
            stack[#stack + 1] = { a, bi }
            stack[#stack + 1] = { bi, b }
        end
    end
    local out = {}
    for i = 1, n do if keep[i] then out[#out + 1] = pts[i] end end
    return out
end

-- opts: profile (NAV.VEHICLE key, "car"), heading (start facing, GTA rotZ), destHeading, radius (40), maxNodes,
-- startRadius / goalRadius (instead of radius per end), startFallback / goalFallback (wider radius, no height filter,
-- when nothing is in the normal radius: a map click off the roads, a player out in the hills), startLane / startU, goalLane / goalU (exact lanes, the coordinates are then only
-- used for the result), lanesOnly, simplify (metres: Douglas-Peucker on the result points, for drawing).
-- z1 / z2 may be false: no height filter for that end (a map click has no height).
function Nav.vehicleRoute(x1, y1, z1, x2, y2, z2, opts)
    if not Roads.ready then return nil, "not_loaded" end
    opts = opts or {}
    local prof = NAV.VEHICLE[opts.profile or "car"]
    if not prof then return nil, "unknown_profile" end
    local radius = opts.radius or 40
    local startRadius, goalRadius = opts.startRadius or radius, opts.goalRadius or radius
    z1, z2 = tonumber(z1) or false, tonumber(z2) or false
    local starts, goals
    if opts.startLane then
        starts = laneEnd(opts.startLane, opts.startU)
        if not starts then return nil, "bad_start_lane" end
    else
        starts = Roads.nearestLanes(x1, y1, z1, { radius = startRadius, heading = opts.heading, maxZ = 8 })
        if #starts == 0 and opts.heading then starts = Roads.nearestLanes(x1, y1, z1, { radius = startRadius, maxZ = 8 }) end
        if #starts == 0 and opts.startFallback then
            starts = Roads.nearestLanes(x1, y1, false, { radius = opts.startFallback })
        end
    end
    if opts.goalLane then
        goals = laneEnd(opts.goalLane, opts.goalU)
        if not goals then return nil, "bad_goal_lane" end
    else
        goals = Roads.nearestLanes(x2, y2, z2, { radius = goalRadius, heading = opts.destHeading, maxZ = 8 })
        if #goals == 0 and opts.goalFallback then
            goals = Roads.nearestLanes(x2, y2, false, { radius = opts.goalFallback })
        end
    end
    if #starts == 0 then return nil, "no_start_lane" end
    if #goals == 0 then return nil, "no_goal_lane" end
    for i = #starts, 7, -1 do starts[i] = nil end
    for i = #goals, 7, -1 do goals[i] = nil end
    local r, why = Roads.search(starts, goals, prof, opts.maxNodes)
    if not r then return nil, why end
    if opts.lanesOnly then
        return { kind = "vehicle", profile = opts.profile or "car", lanes = r.lanes, connections = r.conns,
                 startU = r.startU, goalU = r.goalU, loop = r.loop, cost = r.cost, expanded = r.expanded }
    end
    local res = Roads.buildResult(r, x1, y1, z1, x2, y2, z2)
    res.kind = "vehicle"
    res.profile = opts.profile or "car"
    if opts.gpsNodes then res.gpsNodes = Roads.routeGpsNodes(res.lanes) end
    if opts.simplify then res.points = simplifyPoints(res.points, tonumber(opts.simplify)) end
    return res
end

------------------------------------------------------------------------ vehicle spawn points by travel time

local function classSet(list)
    if type(list) ~= "table" then return nil end
    local set = {}
    for _, c in ipairs(list) do
        for id, name in ipairs(NAV_CLASS_NAME) do
            if name == c or id == tonumber(c) then set[id] = true end
        end
    end
    return set
end

-- something of `etype` within r metres in dimension dim (nil = any dimension)
local function occupied(x, y, z, r, etype, dim)
    if not r or r <= 0 then return false end
    for _, e in ipairs(getElementsWithinRange(x, y, z, r, etype)) do
        if not dim or getElementDimension(e) == dim then return true end
    end
    return false
end

-- Lane positions from where a vehicle reaches (x, y, z) in minTime..maxTime seconds (profile time model, the same as
-- the route cost). opts: profile ("car"), heading (arrival facing at the target, rotZ), radius (target lane radius,
-- 40), fallback (wider radius without height filter), count (10), spacing (min distance between results, 40),
-- step (sampling along lanes, 10), junctionMargin (no spawn this close to a junction node, 12), minDistance (straight
-- 2D distance from the target, 0), classes ({"highway","ramp","road","service"}: allowed spawn classes, all),
-- unpaved (true), emergencyOnly (default: only for profiles that use those lanes freely), avoidPlayers (metres, 0),
-- avoidVehicles (metres, 8), dimension (for the avoid checks, 0; false = any), order ("random" | "time" | "far"),
-- maxNodes. z may be false.
function Nav.vehicleSpawnPoints(x, y, z, minTime, maxTime, opts)
    if not Roads.ready then return nil, "not_loaded" end
    opts = type(opts) == "table" and opts or {}
    local R = Roads
    local profName = opts.profile or "car"
    local prof = NAV.VEHICLE[profName]
    if not prof then return nil, "unknown_profile" end
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or false
    minTime, maxTime = tonumber(minTime) or 0, tonumber(maxTime)
    if not x or not y or not maxTime or maxTime <= 0 or maxTime < minTime then return nil, "bad_arguments" end
    local goals = Roads.nearestLanes(x, y, z, { radius = opts.radius or 40, heading = opts.heading, maxZ = 8 })
    if #goals == 0 and opts.heading then goals = Roads.nearestLanes(x, y, z, { radius = opts.radius or 40, maxZ = 8 }) end
    if #goals == 0 and opts.fallback then goals = Roads.nearestLanes(x, y, false, { radius = opts.fallback }) end
    if #goals == 0 then return nil, "no_goal_lane" end
    for i = #goals, 7, -1 do goals[i] = nil end

    local rt, why = Roads.reachTimes(goals, prof, maxTime, opts.maxNodes)
    if not rt then return nil, why end

    local classes = classSet(opts.classes)
    local allowUnpaved = opts.unpaved ~= false
    local allowEmergency = opts.emergencyOnly
    if allowEmergency == nil then allowEmergency = prof.emergencyOnly <= 1 end
    local step = math.max(2, tonumber(opts.step) or 10)
    local margin = tonumber(opts.junctionMargin) or 12
    local minDist = tonumber(opts.minDistance) or 0
    local minDist2 = minDist * minDist

    -- candidates
    local cand, n = {}, 0
    for id in pairs(rt.T0) do
        local k = R.alink[id]
        local kfl = R.kfl[k]
        local ok = bitAnd(R.afl[id], NAV_LF.TRAP) == 0
            and (not classes or classes[R.kclass[k]])
            and (allowUnpaved or bitAnd(kfl, NAV_KF.UNPAVED) == 0)
            and (allowEmergency or bitAnd(kfl, NAV_KF.EMERGENCY) == 0)
        local len = R.alen[id]
        if ok and len >= 4 then
            local m0 = bitAnd(R.nfl[R.afrom[id]], NAV_NF.JUNCTION) ~= 0 and margin or 0
            local m1 = bitAnd(R.nfl[R.ato[id]], NAV_NF.JUNCTION) ~= 0 and margin or 0
            local s0, s1 = m0, len - m1
            if s1 < s0 then
                if len >= 2 * step then s0, s1 = len / 2, len / 2 else s1 = -1 end
            end
            local s = s0 + ((s1 - s0) % step) / 2   -- centred samples
            while s <= s1 do
                local u = s / len
                local t, goal = Roads.timeAt(rt, id, u, prof)
                if goal and t >= minTime and t <= maxTime then
                    local px, py, pz = Roads.lanePoint(id, u)
                    local d2 = (px - x) ^ 2 + (py - y) ^ 2
                    if d2 >= minDist2 then
                        n = n + 1
                        cand[n] = { id, u, t, goal, px, py, pz, sqrt(d2) }
                    end
                end
                s = s + step
            end
        end
    end

    -- order + pick with spacing and free-space checks
    local order = opts.order or "random"
    if order == "time" then
        table.sort(cand, function(a, b) return a[3] < b[3] end)
    elseif order == "far" then
        table.sort(cand, function(a, b) return a[8] > b[8] end)
    else
        for i = n, 2, -1 do
            local j = math.random(i)
            cand[i], cand[j] = cand[j], cand[i]
        end
    end
    local count = math.max(1, tonumber(opts.count) or 10)
    local spacing = tonumber(opts.spacing) or 40
    local sp2 = spacing * spacing
    local avoidPlayers, avoidVehicles = tonumber(opts.avoidPlayers) or 0, tonumber(opts.avoidVehicles) or 8
    local dim = opts.dimension
    if dim == nil then dim = 0 elseif dim == false then dim = nil end
    local out = {}
    for i = 1, n do
        local c = cand[i]
        local px, py, pz = c[5], c[6], c[7]
        local free = true
        for _, p in ipairs(out) do
            if (p.x - px) ^ 2 + (p.y - py) ^ 2 < sp2 then free = false; break end
        end
        if free and (occupied(px, py, pz, avoidPlayers, "player", dim) or occupied(px, py, pz, avoidVehicles, "vehicle", dim)) then
            free = false
        end
        if free then
            local id = c[1]
            local dx, dy = R.ax2[id] - R.ax1[id], R.ay2[id] - R.ay1[id]
            out[#out + 1] = {
                x = px, y = py, z = pz, rotation = (math.deg(math.atan2(-dx, dy)) + 360) % 360,
                lane = id, u = c[2], time = c[3], distance = c[8], class = NAV_CLASS_NAME[R.kclass[R.alink[id]]],
                goalLane = c[4], goalU = rt.goalU[c[4]],
            }
            if #out >= count then break end
        end
    end
    if #out == 0 then return nil, n == 0 and "no_candidates" or "all_blocked" end
    return { kind = "spawn", profile = profName, points = out, candidates = n, expanded = rt.expanded,
             goals = (function() local g = {} for id, u in pairs(rt.goalU) do g[#g + 1] = { lane = id, u = u } end return g end)() }
end

------------------------------------------------------------------------ peds

local function grabCells(cells, pts, kinds)
    for _, c in ipairs(cells) do
        local x, y = Walk.cellCenter(c[1], c[2])
        pts[#pts + 1] = { x, y, c[4] / 10 }
        kinds[#kinds + 1] = "walk"
    end
end

-- grid search between two world points: smoothed cells or nil
local function gridRoute(x1, y1, z1, x2, y2, z2, role, margin, maxNodes)
    local a = { Walk.nearestCell(x1, y1, z1, 4) }
    local b = { Walk.nearestCell(x2, y2, z2, 4) }
    if not a[1] then return nil, "start_not_walkable" end
    if not b[1] then return nil, "goal_not_walkable" end
    margin = margin or NAV.WALK_MARGIN
    local box = { math.min(a[1], b[1]) - margin, math.min(a[2], b[2]) - margin,
                  math.max(a[1], b[1]) + margin, math.max(a[2], b[2]) + margin }
    -- an enclosed start / goal (inside a building shell, fenced yard) fails fast with a small reverse search
    if (a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 > 60 * 60 then
        for _, ends in ipairs({ { b, a, "goal_enclosed" }, { a, b, "start_enclosed" } }) do
            local c, why = Walk.search(ends[1], ends[2], nil, { role = role, box = box, maxNodes = 4000 })
            if not c and why == "no_path" then return nil, ends[3] end
        end
    end
    -- big searches only inside async jobs (requestRoute): a sync export call must not stall the server
    if maxNodes and not Nav.inJob then maxNodes = math.min(maxNodes, NAV.WALK_MAX_NODES) end
    local cells, cost = Walk.search(a, b, nil, { role = role, box = box, maxNodes = maxNodes })
    if not cells then return nil, cost end
    return Walk.smooth(cells, role), cost
end

-- grid connector from a point to the nearest reachable ped graph nodes (reverse = from the nodes to the point)
-- returns { [node] = { cells, cost } }
local function connectors(x, y, z, role, reverse)
    local res = {}
    local near = Peds.nearestNodes(x, y, z, NAV.WALK_CONNECT, 8, 6)
    if #near == 0 then return res end
    local here = { Walk.nearestCell(x, y, z, 4) }
    if not here[1] then
        -- not on the grid (interior, water...): straight line to the nearest node
        res[near[1][1]] = { false, near[1][2] }
        return res
    end
    local goals, pts, nodeAt = {}, {}, {}
    for _, nd in ipairs(near) do
        local n = nd[1]
        local c = { Walk.nearestCell(Peds.nx[n], Peds.ny[n], Peds.nz[n], 3) }
        if c[1] then
            local k = (c[2] * Walk.CELLS_X + c[1]) * 4 + c[3]
            goals[k] = true
            nodeAt[k] = n
            pts[#pts + 1] = { c[1], c[2] }
        end
    end
    if not next(goals) then
        res[near[1][1]] = { false, near[1][2] }
        return res
    end
    local r = NAV.WALK_CONNECT + 10
    local box = { here[1] - r, here[2] - r, here[1] + r, here[2] + r }
    -- Dijkstra to every candidate node: the graph search then picks the best combination
    local found = Walk.search(here, nil, goals, { role = role, box = box, allGoals = true, maxNodes = 40000 })
    for k, fc in pairs(found or {}) do
        local n = nodeAt[k]
        local cells = Walk.smooth(fc[1], role)
        if reverse then
            local rev = {}
            for i = #cells, 1, -1 do rev[#rev + 1] = cells[i] end
            cells = rev
        end
        if not res[n] or fc[2] < res[n][2] then res[n] = { cells, fc[2] } end
    end
    if not next(res) then res[near[1][1]] = { false, near[1][2] * 3 } end
    return res
end

-- opts: role (NAV.PED key, "civilian"), graphOnly, gridOnly
function Nav.pedRoute(x1, y1, z1, x2, y2, z2, opts)
    opts = opts or {}
    local roleName = opts.role or "civilian"
    local role = NAV.PED[roleName]
    if not role then return nil, "unknown_role" end
    local pts, kinds, crossings = {}, {}, {}
    local dist2D = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local function finish(how)
        local len = 0
        for i = 2, #pts do
            len = len + sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2 + (pts[i][3] - pts[i - 1][3]) ^ 2)
        end
        return { kind = "ped", role = roleName, method = how, points = pts, pointKinds = kinds, crossings = crossings, length = len }
    end
    -- short or free routes: the grid alone (sidewalk / crossing preferences are in the cell costs)
    if Walk.ready and not opts.graphOnly and (opts.gridOnly or not role.useGraph or dist2D <= NAV.WALK_DIRECT) then
        local cells, why = gridRoute(x1, y1, z1, x2, y2, z2, role)
        if cells then
            grabCells(cells, pts, kinds)
            return finish("grid")
        end
        if opts.gridOnly or not Peds.ready then return nil, why end
    end
    if not Peds.ready then return nil, "not_loaded" end
    -- long routes: grid connector -> ped graph -> grid connector
    local sc, gc
    if Walk.ready then
        sc = connectors(x1, y1, z1, role, false)
        gc = connectors(x2, y2, z2, role, true)
    else
        sc, gc = {}, {}
        for _, nd in ipairs(Peds.nearestNodes(x1, y1, z1, NAV.WALK_CONNECT, 4, 6)) do sc[nd[1]] = { false, nd[2] } end
        for _, nd in ipairs(Peds.nearestNodes(x2, y2, z2, NAV.WALK_CONNECT, 4, 6)) do gc[nd[1]] = { false, nd[2] } end
    end
    local starts, goals = {}, {}
    for n, c in pairs(sc) do starts[#starts + 1] = { n, c[2] } end
    for n, c in pairs(gc) do goals[#goals + 1] = { n, c[2] } end
    local nodes, edges
    if #starts > 0 and #goals > 0 then nodes, edges = Peds.search(starts, goals, role) end
    if not nodes then
        -- no ped graph out here (wilderness, mountains): open terrain only, bigger search
        if Walk.ready and dist2D <= NAV.WALK_FAR then
            local cells, why = gridRoute(x1, y1, z1, x2, y2, z2, role, NAV.WALK_MARGIN * 2, NAV.WALK_FAR_NODES)
            if cells then
                grabCells(cells, pts, kinds)
                return finish("grid")
            end
            return nil, why
        end
        if #starts == 0 then return nil, "no_start_node" end
        if #goals == 0 then return nil, "no_goal_node" end
        return nil, edges
    end
    local first, last = nodes[1], nodes[#nodes]
    if sc[first][1] then grabCells(sc[first][1], pts, kinds)
    else pts[#pts + 1] = { x1, y1, z1 }; kinds[#kinds + 1] = "walk" end
    for i, n in ipairs(nodes) do
        local e = edges[i - 1]
        local k = e and Peds.ekind[e]
        pts[#pts + 1] = { Peds.nx[n], Peds.ny[n], Peds.nz[n] }
        kinds[#kinds + 1] = k and NAV_PED_KIND_NAME[k] or "node"
        if k == NAV_PED_KIND.CROSSING or k == NAV_PED_KIND.LIT then
            local a = nodes[i - 1]
            crossings[#crossings + 1] = { index = #pts - 1, light = k == NAV_PED_KIND.LIT, group = Peds.egroup[e], phase = Peds.ephase[e],
                x1 = Peds.nx[a], y1 = Peds.ny[a], z1 = Peds.nz[a], x2 = Peds.nx[n], y2 = Peds.ny[n], z2 = Peds.nz[n] }
        end
    end
    if gc[last][1] then grabCells(gc[last][1], pts, kinds)
    else pts[#pts + 1] = { x2, y2, z2 }; kinds[#kinds + 1] = "walk" end
    local res = finish("graph")
    -- the GTA ped graph has gaps (e.g. LV Strip: 210 m apart, 4.5 km on the graph): a big detour is retried on the grid
    if Walk.ready and not opts.graphOnly and dist2D <= NAV.WALK_FAR and res.length > math.max(NAV.DETOUR_FACTOR * dist2D, dist2D + 150) then
        local cells = gridRoute(x1, y1, z1, x2, y2, z2, role, NAV.WALK_MARGIN * 2, NAV.WALK_FAR_NODES)
        if cells then
            pts, kinds, crossings = {}, {}, {}
            grabCells(cells, pts, kinds)
            return finish("grid")
        end
    end
    return res
end

-- crossing light: true when peds may cross on this phase (ai_land_traffic signal cycle, else GTA's lights)
function Nav.isCrossingOpen(phase)
    if not phase or phase == 0 then return true end
    local res = getResourceFromName("ai_land_traffic")
    if res and getResourceState(res) == "running" then
        local ok, light = pcall(function() return exports.ai_land_traffic:getTrafficLight(phase) end)
        if ok and light then return light == "green" end
    end
    -- GTA light state: 0-2 = north-south green/yellow, 3-5 = east-west green/yellow (approximation)
    local s = getTrafficLightState()
    if phase == 1 then return s == 0 end
    return s == 3
end

------------------------------------------------------------------------ boats

function Nav.boatRoute(x1, y1, z1, x2, y2, z2)
    if not Boats.ready then return nil, "not_loaded" end
    local a = Boats.nearest(x1, y1, 400)
    local b = Boats.nearest(x2, y2, 400)
    if not a or not b then return nil, "no_water_path" end
    local nodes, len = Boats.search(a, b)
    if not nodes then return nil, "no_route" end
    local pts = { { x1, y1, z1 } }
    for _, n in ipairs(nodes) do pts[#pts + 1] = { Boats.nx[n], Boats.ny[n], Boats.nz[n] } end
    pts[#pts + 1] = { x2, y2, z2 }
    return { kind = "boat", points = pts, length = len }
end

------------------------------------------------------------------------ async jobs

-- runs fn(...) as a time-sliced job; when done triggers onNavmeshRouteReady(id, result|false, reason) on `target`
function Nav.startJob(target, fn, ...)
    Nav.nextJob = Nav.nextJob + 1
    local id = Nav.nextJob
    local args = { ... }
    local co = coroutine.create(function() return fn(unpack(args)) end)
    Nav.jobs[id] = { co = co, target = target }
    if not Nav.timer then Nav.timer = setTimer(Nav.runJobs, 50, 0) end
    return id
end

function Nav.runJobs()
    local start = getTickCount()
    for id, job in pairs(Nav.jobs) do
        if getTickCount() - start > 20 then return end
        Nav.inJob = true
        Nav.sliceStart = getTickCount()
        local ok, res, why = coroutine.resume(job.co)
        Nav.inJob = false
        if not ok then
            outputDebugString("[navmesh] route job failed: " .. tostring(res), 1)
            Nav.jobs[id] = nil
            if isElement(job.target) then triggerEvent("onNavmeshRouteReady", job.target, id, false, "error") end
        elseif coroutine.status(job.co) == "dead" then
            Nav.jobs[id] = nil
            if isElement(job.target) then triggerEvent("onNavmeshRouteReady", job.target, id, res or false, why) end
        end
    end
    if not next(Nav.jobs) and Nav.timer then
        killTimer(Nav.timer)
        Nav.timer = nil
    end
end
