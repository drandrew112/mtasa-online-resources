-- Following a point route on the server side: progress, crossings (wait for the ped light / for cars), end.
--
-- route = { pts = { {x, y, z}, ... }, crossings = { [k] = { light, phase } } (edge pts[k] -> pts[k + 1]),
--           speed, passed = { [k] = true }, waitK, waitSince }

Route = {}

local sqrt = math.sqrt
local T = AIPEDS

function segDist2D(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local L2 = dx * dx + dy * dy
    local u = 0
    if L2 > 1e-9 then
        u = ((px - ax) * dx + (py - ay) * dy) / L2
        if u < 0 then u = 0 elseif u > 1 then u = 1 end
    end
    local qx, qy = ax + dx * u - px, ay + dy * u - py
    return sqrt(qx * qx + qy * qy), u
end

-- navmesh crossings list ({index, light, phase}) -> lookup by start index
function Route.crossingMap(list, offset)
    local m = {}
    for _, c in ipairs(list or {}) do m[c.index + (offset or 0)] = { light = c.light, phase = c.phase } end
    return m
end

function Route.new(pts, crossings, speed)
    return { pts = pts, crossings = crossings or {}, speed = speed or "walk", passed = {} }
end

function Route.start(p, r, fromIndex)
    p.route = r
    Peds.setCmd(p, { m = "move", pts = Peds.pts2D(r.pts), i = fromIndex or 1, sp = r.speed })
end

-- a vehicle that will drive over the crossing segment within ~3 s
local function carsComing(ax, ay, az, bx, by)
    for _, v in ipairs(getElementsWithinRange(ax, ay, az, T.CROSSING_CAR_RANGE, "vehicle")) do
        local vx, vy = getElementVelocity(v)
        vx, vy = vx * 50, vy * 50
        if vx * vx + vy * vy > T.CROSSING_CAR_SPEED ^ 2 then
            local x, y = getElementPosition(v)
            for t = 0, 3, 0.75 do
                if segDist2D(x + vx * t, y + vy * t, ax, ay, bx, by) < 3.5 then return true end
            end
        end
    end
    return false
end

local function crossingOpen(r, k)
    local c = r.crossings[k]
    local a, b = r.pts[k], r.pts[k + 1]
    if not b then return true end
    if c.light and not Nav.isCrossingOpen(c.phase) then return false end
    return not carsComing(a[1], a[2], a[3], b[1], b[2])
end

-- returns "moving" | "waiting" | "done"
function Route.update(p, now)
    local r = p.route
    if not r then return "done" end
    local c = p.cmd
    if c.m == "wait" and r.waitK then
        local k = r.waitK
        if crossingOpen(r, k) or now - r.waitSince > T.CROSSING_MAX_WAIT then
            r.passed[k] = true
            r.waitK = nil
            Peds.setCmd(p, { m = "move", pts = Peds.pts2D(r.pts), i = k + 1, sp = r.speed })
        end
        return "waiting"
    end
    if c.m ~= "move" then return "done" end
    Peds.track(p)
    if Peds.atEnd(p) then return "done" end
    for k = c.i - 1, c.i do
        if r.crossings[k] and not r.passed[k] then
            local a = r.pts[k]
            local d = Peds.dist2D(p, a[1], a[2])
            if d < T.CROSSING_WAIT_DIST + 0.6 then
                if crossingOpen(r, k) then
                    r.passed[k] = true
                else
                    local b = r.pts[k + 1]
                    r.waitK, r.waitSince = k, now
                    Peds.setCmd(p, { m = "wait", pts = c.pts, i = k + 1, fx = b[1], fy = b[2] })
                    return "waiting"
                end
            end
        end
    end
    return "moving"
end
