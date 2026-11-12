-- police_system / modules/pathfinder/server/pathfinder.lua
-- Where an AI service vehicle (prisoner transport, ambulance, tow truck) appears and where it stops, so it is on scene
-- within its cfg.ARRIVAL = { min, max } seconds (2026-11-12):
--   1. goal: the navmesh lane beside the scene on the scene's side of the road (the scene to the right of the driving
--      direction, outer lane, nearest); its point nearest to the scene is the stop
--   2. spawn: navmesh findVehicleSpawnPoints towards exactly that lane (travel time window of the profile), the first
--      candidate no player sees (ai_land_traffic findHiddenRoadSpawn); the candidate's lane gives the direction
--   3. ai_land_traffic gets both as exact lanes (createScriptedVehicle / addScriptedStop lane + u), so the vehicle
--      faces the way its route starts and stops on the scene's side instead of snapping to the nearest lane
--   4. watch: not there GRACE s after the window (stuck, lost route) and nobody sees it -> put on a closer spawn point
--      (ai_land_traffic relocateScriptedVehicle, RESCUE window); a dropped stop (no route) is added again
-- No navmesh / nothing hidden: the old random hidden road point (SPAWN_MIN..SPAWN_MAX) + the nearest-lane stop.
--
-- POL.pathfinder.dispatch(t, cfg, x, y, z, o) -> vehicle, driver, plan | false
--   t = exports.ai_land_traffic, cfg = { ARRIVAL, SPAWN_MIN, SPAWN_MAX }, o = { model, profile (navmesh profile:
--   "emergency" | "truck" ...), toward (element / {x, y} for the fallback), vehicle = createScriptedVehicle options,
--   stop = addScriptedStop options (tag, hold...) }
-- POL.pathfinder.plan(t, x, y, z, cfg, profile) -> { goal = {lane, u, x, y, z, heading}, spawn = {x, y, z, rot, lane,
--   u, time} } | nil
-- POL.pathfinder.release(veh): stop watching it (the owner took it over)

local PF = POL.module("pathfinder", { watched = {} })
local P = POLICE.PATHFINDER
local sqrt, deg, atan2, min = math.sqrt, math.deg, math.atan2, math.min

local function navmesh(fn)
    if not POL.running("navmesh") then return nil end
    local ok, r = pcall(fn, exports.navmesh)
    if not ok then outputDebugString("[police_system] pathfinder navmesh: " .. tostring(r), 2) return nil end
    return r
end

local function copy(t)
    local o = {}
    if type(t) == "table" then for k, v in pairs(t) do o[k] = v end end
    return o
end

------------------------------------------------------------------------ goal: the side of the road

-- navmesh lanes near the scene, best first: { {lane, u, x, y, z, heading, score}, ... }
function PF.goals(x, y, z)
    local lanes = navmesh(function(n)
        return n:getNearestLanes(x, y, z, { radius = P.GOAL_RADIUS, count = 12, skipTrap = true })
    end)
    if type(lanes) ~= "table" then return {} end
    local out = {}
    for _, l in ipairs(lanes) do
        if not l.trap and not l.parking and not l.emergencyOnly and l.start and l.finish then
            local fx, fy = l.finish[1] - l.start[1], l.finish[2] - l.start[2]
            local len = sqrt(fx * fx + fy * fy)
            if len > 0.5 then
                fx, fy = fx / len, fy / len
                -- > 0: the scene is to the right of the driving direction (doors / back towards it, right-hand traffic)
                local side = (x - l.x) * fy - (y - l.y) * fx
                local score = (l.distance or 0)
                if side < -0.5 then score = score + P.LEFT_PENALTY end
                if l.right then score = score + P.INNER_PENALTY end
                if l.class == "service" then score = score + P.SERVICE_PENALTY end
                out[#out + 1] = { lane = l.id, u = l.u or 0, x = l.x, y = l.y, z = l.z,
                                  heading = (deg(atan2(-fx, fy)) + 360) % 360, score = score }
            end
        end
    end
    table.sort(out, function(a, b) return a.score < b.score end)
    return out
end

------------------------------------------------------------------------ spawn: travel time towards the goal lane

-- navmesh candidates reaching goal in window = { min, max } s (players farther than PLAYER_DIST_MIN)
local function candidates(goal, x, y, z, profile, window)
    local r = navmesh(function(n)
        return n:findVehicleSpawnPoints(x, y, z, window[1], window[2], {
            profile = profile, goalLane = goal.lane, goalU = goal.u, count = P.COUNT, spacing = P.SPACING,
            minDistance = P.MIN_DISTANCE, avoidPlayers = P.PLAYER_DIST_MIN, classes = P.CLASSES, emergencyOnly = false })
    end)
    return type(r) == "table" and type(r.points) == "table" and #r.points > 0 and r.points or nil
end

-- the first candidate nobody sees: PLAYER_DIST first, then PLAYER_DIST_MIN
local function hidden(t, points, x, y, z, dists)
    for _, pd in ipairs(dists) do
        local ok, sx, sy, sz, rot, i = pcall(function()
            return t:findHiddenRoadSpawn(x, y, z, { points = points, playerDist = pd, priority = true })
        end)
        if ok and sx then
            local p = points[i] or {}
            return { x = sx, y = sy, z = sz, rot = rot, lane = tonumber(p.lane), u = tonumber(p.u), time = p.time }
        end
    end
    return nil
end

function PF.plan(t, x, y, z, cfg, profile)
    local A = cfg.ARRIVAL
    if not A then return nil end
    local goals = PF.goals(x, y, z)
    local windows = { { A[1], A[2] }, { A[2], A[2] + P.LATE_EXTRA } }
    for _, w in ipairs(windows) do
        for gi = 1, min(#goals, P.GOAL_TRIES) do
            local goal = goals[gi]
            local pts = candidates(goal, x, y, z, profile, w)
            local sp = pts and hidden(t, pts, x, y, z, { P.PLAYER_DIST, P.PLAYER_DIST_MIN })
            if sp then return { goal = goal, spawn = sp, window = w } end
        end
    end
    return nil
end

------------------------------------------------------------------------ watch: on scene in time

local timer

local function stopOpts(w)
    local o = copy(w.stopOpts)
    if w.goal then o.lane, o.u = w.goal.lane, w.goal.u
    else o.radius = o.radius or 40 end
    return o
end

-- a late vehicle closer, unseen: true when moved
local function rescue(w, veh, t, now)
    if t:isElementSeenByPlayers(veh) then return false end
    local vx, vy, vz = POL.pos(veh)
    if #getElementsWithinRange(vx, vy, vz, P.RESCUE_PLAYER_DIST, "player") > 0 then return false end
    local goal = w.goal or PF.goals(w.x, w.y, w.z)[1]
    if not goal then return false end
    local pts = candidates(goal, w.x, w.y, w.z, w.profile, P.RESCUE)
    local sp = pts and hidden(t, pts, w.x, w.y, w.z, { P.PLAYER_DIST, P.PLAYER_DIST_MIN })
    if not sp then return false end
    local ok = t:relocateScriptedVehicle(veh, sp.x, sp.y, sp.z, { lane = sp.lane, u = sp.u, heading = sp.rot })
    if not ok then return false end
    if w.lost then
        -- the stop was dropped (no route): again, on the goal lane
        w.goal = goal
        t:addScriptedStop(veh, w.x, w.y, w.z, stopOpts(w))
        w.lost = nil
    end
    return true
end

local function tick()
    local t = POL.running("ai_land_traffic") and exports.ai_land_traffic
    local now = getTickCount()
    for veh, w in pairs(PF.watched) do
        if not isElement(veh) or not t or not t:isScriptedVehicle(veh) then
            PF.watched[veh] = nil
        elseif POL.dist2D(veh, w.x, w.y) <= P.ARRIVED then
            PF.watched[veh] = nil
        elseif now >= w.deadline then
            if w.rescues >= P.MAX_RESCUES then
                outputDebugString(("[police_system] pathfinder: %s still not on scene after %d moves"):format(
                    tostring(w.stopOpts.tag), w.rescues), 2)
                PF.watched[veh] = nil
            elseif rescue(w, veh, t, now) then
                w.rescues = w.rescues + 1
                w.deadline = now + (P.RESCUE[2] + P.GRACE) * 1000
            end
        end
    end
    if not next(PF.watched) and timer then killTimer(timer); timer = nil end
end

function PF.watch(veh, w)
    w.rescues = 0
    PF.watched[veh] = w
    if not timer then
        timer = setTimer(function()
            local ok, err = pcall(tick)
            if not ok then outputDebugString("[police_system] pathfinder: " .. tostring(err), 1) end
        end, P.CHECK, 0)
    end
end

function PF.release(veh) PF.watched[veh] = nil end

addEvent("onTrafficVehicleTargetReached")
addEventHandler("onTrafficVehicleTargetReached", root, function(veh, id, kind, tag)
    local w = PF.watched[veh]
    if w and tag == w.stopOpts.tag then PF.watched[veh] = nil end
end)

addEvent("onTrafficVehicleTargetFailed")
addEventHandler("onTrafficVehicleTargetFailed", root, function(veh, id, kind, tag)
    local w = PF.watched[veh]
    if not w or tag ~= w.stopOpts.tag then return end
    -- no route to the stop: moved (unseen) and the stop added again at the next check
    w.lost = true
    w.deadline = 0
end)

addEvent("onTrafficVehicleRemoved")
addEventHandler("onTrafficVehicleRemoved", root, function(veh) PF.watched[veh] = nil end)

------------------------------------------------------------------------ dispatch

function PF.dispatch(t, cfg, x, y, z, o)
    local plan = PF.plan(t, x, y, z, cfg, o.profile)
    local vopts = copy(o.vehicle)
    local sx, sy, sz, rot
    if plan then
        local sp = plan.spawn
        sx, sy, sz = sp.x, sp.y, sp.z
        vopts.heading, vopts.lane, vopts.u = sp.rot, sp.lane, sp.u
    else
        sx, sy, sz, rot = t:findHiddenRoadSpawn(x, y, z, { minDist = cfg.SPAWN_MIN, maxDist = cfg.SPAWN_MAX,
            toward = o.toward or { x, y } })
        if not sx then return false end
        vopts.heading = rot
    end
    local veh, driver = t:createScriptedVehicle(o.model, sx, sy, sz, vopts)
    if not veh then return false end
    local w = { x = x, y = y, z = z, goal = plan and plan.goal, profile = o.profile, stopOpts = copy(o.stop) }
    t:addScriptedStop(veh, x, y, z, stopOpts(w))
    local A = cfg.ARRIVAL or { 20, 40 }
    local maxT = plan and plan.window[2] or A[2]
    w.deadline = getTickCount() + (maxT + P.GRACE) * 1000
    PF.watch(veh, w)
    return veh, driver, plan
end
