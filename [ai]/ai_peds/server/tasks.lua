-- Tasks: what a calm ped does (civilians all the time, enemies while they have no target).
--
-- p.task = { name = "idle" | "wander" | "goto" | "patrol" | "guard" | "follow", ...options }
--   wander  sidewalk random walk on the navmesh ped graph (ped traffic); { walk = navmesh walk result (optional) }
--   goto    { x, y, z, speed, role, tag, direct }: onAIPedArrived(tag, x, y, z) / onAIPedTaskFailed(tag, reason)
--   patrol  { points = { {x, y, z}, ... }, loop (true) } or { x, y, z, radius }; wait = { min, max } ms at each point
--   guard   { x, y, z, rot }: stands there, walks back when pushed away
--   follow  { element, distance (3) }
--   idle    { fx, fy } (face that point)

Tasks = {}

local T = AIPEDS
local random, sqrt, cos, sin, rad, pi = math.random, math.sqrt, math.cos, math.sin, math.rad, math.pi
local DIRECT = 8          -- shorter moves need no route
local ARRIVE = 2.0
local MAX_ATTEMPTS = 3

------------------------------------------------------------------------ moving to a point (goto, patrol, guard)

local function finishRoute(p, t, mv, res)
    if p.removed or not p.taskActive or p.task ~= t or t.mv ~= mv then return end
    if res and res.points and #res.points > 0 then
        local pts = res.points
        pts[#pts + 1] = { mv.x, mv.y, mv.z }
        Route.start(p, Route.new(pts, Route.crossingMap(res.crossings), mv.speed))
        mv.state = "moving"
    elseif Peds.dist2D(p, mv.x, mv.y) < 60 then
        Route.start(p, Route.new({ { mv.x, mv.y, mv.z } }, nil, mv.speed))   -- no route: straight on
        mv.state = "moving"
    else
        mv.state = "failed"
    end
end

local function routeTo(p, t, mv)
    mv.attempts = mv.attempts + 1
    if mv.direct or Peds.dist2D(p, mv.x, mv.y) < DIRECT then
        Route.start(p, Route.new({ { mv.x, mv.y, mv.z } }, nil, mv.speed))
        mv.state = "moving"
        return
    end
    mv.state = "routing"
    Peds.idle(p)
    local ok = Nav.requestPedRoute(p.x, p.y, p.z, mv.x, mv.y, mv.z, t.role or p.role, function(res)
        finishRoute(p, t, mv, res)
    end)
    if not ok then finishRoute(p, t, mv, nil) end
end

function Tasks.moveTo(p, t, x, y, z, speed, direct)
    local mv = { x = x, y = y, z = z, speed = speed or t.speed or p.speed, attempts = 0, direct = direct }
    t.mv = mv
    routeTo(p, t, mv)
end

-- "moving" | "arrived" | "failed"
function Tasks.moveUpdate(p, t, now)
    local mv = t.mv
    if not mv then return "failed" end
    if mv.state == "failed" then return "failed" end
    if mv.state == "routing" then return "moving" end
    if Peds.dist2D(p, mv.x, mv.y) < ARRIVE then
        t.mv = nil
        return "arrived"
    end
    if Route.update(p, now) == "done" then
        if mv.attempts >= MAX_ATTEMPTS then mv.state = "failed"; return "failed" end
        routeTo(p, t, mv)   -- the route ended short of the point (pushed away, stuck): again
    end
    return "moving"
end

-- the syncer reported the ped stuck: a new route
function Tasks.stuck(p)
    local t = p.task
    if t and t.mv and t.mv.state == "moving" then
        if t.mv.attempts >= MAX_ATTEMPTS then t.mv.state = "failed" else routeTo(p, t, t.mv) end
    elseif t and t.name == "wander" then
        t.route = nil
    end
end

------------------------------------------------------------------------ wander (sidewalks)

-- walk points shifted to the right side of the sidewalk
local function sidePoints(p, walk)
    local pts, w = walk.points, walk.widths or {}
    local out, n = {}, #pts
    p.side = p.side or (0.6 + random() * 0.7)
    for i = 1, n do
        local a, b = pts[i > 1 and i - 1 or i], pts[i < n and i + 1 or i]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local l = sqrt(dx * dx + dy * dy)
        local off = math.min((w[i] or 2) * T.WALK_SIDE * p.side, 1.6)
        if l > 0.01 then
            out[i] = { pts[i][1] + dy / l * off, pts[i][2] - dx / l * off, pts[i][3] }
        else
            out[i] = { pts[i][1], pts[i][2], pts[i][3] }
        end
    end
    return out
end

-- start a new walk (walk given: from the spawner) or continue the current one from its last node
local function wanderFetch(p, t, continue)
    local walk
    if continue and t.nodes and #t.nodes >= 2 then
        walk = Nav.randomWalk(p.x, p.y, p.z, T.WALK_LENGTH, { node = t.nodes[#t.nodes], prev = t.nodes[#t.nodes - 1] })
    else
        walk = t.walk or Nav.randomWalk(p.x, p.y, p.z, T.WALK_LENGTH)
        t.walk = nil
    end
    if not walk or not walk.points or #walk.points < 2 then return false end
    local pts = sidePoints(p, walk)
    local cross = Route.crossingMap(walk.crossings)
    if continue and p.route and t.nodes then
        -- keep the rest of the current route, the new walk starts at its last node (dropped: same point)
        local r, c = p.route, p.cmd
        local from = math.max(1, c.i - 1)
        local keep, kc = {}, {}
        for i = from, #r.pts do
            keep[#keep + 1] = r.pts[i]
            if r.crossings[i] and not r.passed[i] then kc[#keep] = r.crossings[i] end
        end
        local base = #keep - 1
        for i = 2, #pts do keep[#keep + 1] = pts[i] end
        for k, v in pairs(cross) do kc[k + base] = v end
        Route.start(p, Route.new(keep, kc, "walk"), from == c.i and 1 or 2)
    else
        Route.start(p, Route.new(pts, cross, "walk"))
    end
    t.nodes = walk.nodes
    return true
end

------------------------------------------------------------------------ tasks

Tasks.idle = {
    start = function(p, t) Peds.idle(p, t.fx, t.fy) end,
    update = function() end,
}

Tasks.wander = {
    start = function(p, t)
        t.ok = wanderFetch(p, t, false)
        if not t.ok then Peds.idle(p) end
        t.retry = getTickCount() + 3000
    end,
    update = function(p, t, now)
        if not t.ok then
            if now > t.retry then
                t.retry = now + 5000
                t.ok = wanderFetch(p, t, false)
            end
            return
        end
        local st = Route.update(p, now)
        if st == "waiting" then return end
        local r = p.route
        if st == "done" or not r then
            t.ok = wanderFetch(p, t, true) or wanderFetch(p, t, false)
        elseif #r.pts - p.cmd.i < 2 then
            wanderFetch(p, t, true)
        end
    end,
}

Tasks["goto"] = {
    start = function(p, t)
        Tasks.moveTo(p, t, t.x, t.y, t.z, t.speed, t.direct)
    end,
    update = function(p, t, now)
        if t.done then return end
        local st = Tasks.moveUpdate(p, t, now)
        if st == "arrived" then
            t.done = true
            Peds.idle(p)
            triggerEvent("onAIPedArrived", p.el, t.tag or false, t.x, t.y, t.z)
        elseif st == "failed" then
            t.done = true
            Peds.idle(p)
            triggerEvent("onAIPedTaskFailed", p.el, t.tag or false, "no_route")
        end
    end,
}

local function patrolPoint(t)
    if t.points then
        t.idx = (t.idx or 0) + 1
        if t.idx > #t.points then
            if t.loop == false then return nil end
            t.idx = 1
        end
        local pt = t.points[t.idx]
        return pt[1], pt[2], pt[3]
    end
    for _ = 1, 8 do
        local a, d = random() * 2 * pi, sqrt(random()) * (t.radius or 20)
        local x, y = t.x + cos(a) * d, t.y + sin(a) * d
        local z = Nav.ground(x, y, t.z, 6)
        if z then return x, y, z end
        if not Nav.available() then return x, y, t.z end
    end
    return t.x, t.y, t.z
end

Tasks.patrol = {
    start = function(p, t)
        t.waitUntil = nil
        local x, y, z = patrolPoint(t)
        if x then Tasks.moveTo(p, t, x, y, z, t.speed) else t.finished = true; Peds.idle(p) end
    end,
    update = function(p, t, now)
        if t.finished then return end
        if t.waitUntil then
            if now < t.waitUntil then return end
            t.waitUntil = nil
            local x, y, z = patrolPoint(t)
            if not x then
                t.finished = true
                triggerEvent("onAIPedArrived", p.el, t.tag or "patrol_end", p.x, p.y, p.z)
                return
            end
            Tasks.moveTo(p, t, x, y, z, t.speed)
            return
        end
        local st = Tasks.moveUpdate(p, t, now)
        if st == "arrived" or st == "failed" then
            Peds.idle(p)
            local w = t.wait or { 2000, 6000 }
            t.waitUntil = now + random(w[1], math.max(w[1], w[2]))
        end
    end,
}

Tasks.guard = {
    start = function(p, t) t.mv = nil end,
    update = function(p, t, now)
        if t.mv then
            local st = Tasks.moveUpdate(p, t, now)
            if st == "moving" then return end
            t.mv = nil
        end
        if Peds.dist2D(p, t.x, t.y) > 2.5 then
            Tasks.moveTo(p, t, t.x, t.y, t.z, t.speed or "walk")
        elseif p.cmd.m ~= "idle" or not p.cmd.fx then
            local r = rad(t.rot or 0)
            Peds.idle(p, p.x - sin(r) * 5, p.y + cos(r) * 5)
        end
    end,
}

Tasks.follow = {
    start = function(p, t) t.next = 0 end,
    update = function(p, t, now)
        local el = t.element
        if not isElement(el) then return end
        local x, y, z = getElementPosition(el)
        local d = Peds.dist2D(p, x, y)
        local keep = t.distance or 3
        if d <= keep then
            if p.cmd.m ~= "idle" then Peds.idle(p, x, y) end
        elseif now >= t.next then
            t.next = now + 700
            local sp = d > 12 and "run" or (t.speed or "walk")
            Peds.setCmd(p, { m = "move", pts = { { x, y } }, sp = sp })
        end
    end,
}

-- start the ped's task (calm state); name / opts replace the current task when given
function Tasks.run(p, name, opts)
    if name then
        opts = opts or {}
        opts.name = name
        p.task = opts
    end
    p.task = p.task or { name = "idle" }
    p.route = nil
    p.taskActive = true
    local def = Tasks[p.task.name] or Tasks.idle
    def.start(p, p.task)
end

function Tasks.update(p, now)
    local t = p.task
    if not t then return end
    local def = Tasks[t.name] or Tasks.idle
    def.update(p, t, now)
end
