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

-- opts: profile (NAV.VEHICLE key, "car"), heading (start facing, GTA rotZ), destHeading, radius (40), maxNodes
function Nav.vehicleRoute(x1, y1, z1, x2, y2, z2, opts)
    if not Roads.ready then return nil, "not_loaded" end
    opts = opts or {}
    local prof = NAV.VEHICLE[opts.profile or "car"]
    if not prof then return nil, "unknown_profile" end
    local radius = opts.radius or 40
    local starts = Roads.nearestLanes(x1, y1, z1, { radius = radius, heading = opts.heading, maxZ = 8 })
    if #starts == 0 and opts.heading then starts = Roads.nearestLanes(x1, y1, z1, { radius = radius, maxZ = 8 }) end
    local goals = Roads.nearestLanes(x2, y2, z2, { radius = radius, heading = opts.destHeading, maxZ = 8 })
    if #starts == 0 then return nil, "no_start_lane" end
    if #goals == 0 then return nil, "no_goal_lane" end
    for i = #starts, 7, -1 do starts[i] = nil end
    for i = #goals, 7, -1 do goals[i] = nil end
    local r, why = Roads.search(starts, goals, prof, opts.maxNodes)
    if not r then return nil, why end
    local res = Roads.buildResult(r, x1, y1, z1, x2, y2, z2)
    res.kind = "vehicle"
    res.profile = opts.profile or "car"
    if opts.gpsNodes then res.gpsNodes = Roads.routeGpsNodes(res.lanes) end
    return res
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
