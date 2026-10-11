-- Traffic simulation step (server). Longitudinal control is the Intelligent Driver Model; the most
-- restrictive of these constraints wins every tick:
--   free road (lane / curve speed), leaders on the route, upcoming curve speeds, stop lines
--   (traffic lights, right of way, occupied junction paths, full exit lane, emergency vehicles),
--   non-traffic obstacles (players, their vehicles, peds), emergency vehicle reactions (els.lua).

Sim = {}

local T = TRAFFIC
local sqrt, min, max, abs = math.sqrt, math.min, math.max, math.abs
local SQRT_AB = sqrt(T.IDM_ACCEL * T.IDM_DECEL)
local approachPrev, approachNext = {}, {}   -- [conn] = { { ag, dist, committed, hold }, ... }
local commits = {}                          -- [conn] = { [agent] = true }: decided to go, not in it yet
local claims = {}                           -- [conn] = { [agent] = true }: waited long, goes next
local chain = {}

------------------------------------------------------------------------ IDM

local function accelFree(v, v0)
    if v0 < 0.3 then
        return v > 0.05 and -T.IDM_DECEL or 0
    end
    local a = T.IDM_ACCEL * (1 - (v / v0) ^ 4)
    return a < -T.IDM_DECEL and -T.IDM_DECEL or a
end

local function idm(v, v0, gap, vl)
    if gap < 0.1 then gap = 0.1 end
    local sstar = T.IDM_GAP + max(0, v * T.IDM_HEADWAY + v * (v - vl) / (2 * SQRT_AB))
    local free = v0 < 0.3 and 1 or (v / v0) ^ 4
    return T.IDM_ACCEL * (1 - free - (sstar / gap) ^ 2)
end

local function segSpeed(code)
    if code > 0 then return Net.lspeed[code] or T.SPEED_ROAD end
    local c = -code
    local s = Net.lspeed[Net.cto[c]] or T.SPEED_ROAD
    local cv = Net.cvmax[c]
    return (cv and cv < s) and cv or s
end

------------------------------------------------------------------------ junction gate

-- does b (directly or through the agents it waits for) wait for ag? Then ag must not wait for b.
local function waitsFor(b, ag)
    for _ = 1, 12 do
        b = b.blocker
        if not b then return false end
        if b == ag then return true end
    end
    return false
end

local function laneEntryBlocked(lane, ag)
    local o = Agents.occ[lane]
    if not o then return nil end
    for b in pairs(o) do
        if b ~= ag and b.plan[1].code == lane and b.s < b.len + 1.5 and b.v < 1.5 and not waitsFor(b, ag) then return b end
    end
    return nil
end

-- returns the hold reason (+ the agent it waits for) when the agent must stop before connection c
local function gate(ag, c, dStop, now)
    local v = ag.v
    if dStop < -0.5 then return nil end
    if dStop > max(35, v * v / (2 * T.IDM_DECEL) + 12) then return nil end

    -- traffic light (only the first signalled node of a multi-node intersection counts)
    local phase = Net.cphase[c]
    if phase and phase > 0 then
        local g = Net.cgroup[c]
        local inside = g > 0 and ag.passedGroup == g and now - (ag.passedAt or 0) < 20000
        if not inside then
            local light = Signals.light(phase)
            if light == "red" and dStop > v * v / (2 * T.IDM_MAX_DECEL * 0.8) then return "signal" end
            if light == "yellow" and dStop > v * v / (2 * T.IDM_DECEL) then return "signal" end
        end
    end

    -- emergency vehicle about to cross
    local hx, hy = ag.hx, ag.hy
    local jx, jy = Geo.pose(-c, 0)
    if jx and dStop > v * v / (2 * T.IDM_MAX_DECEL * 0.6) and Els.approachingJunction(ag, jx, jy, hx, hy) then
        return "els"
    end

    -- the rest only matters close to the stop line
    if dStop > max(15, v * v / (2 * T.IDM_DECEL) + 6) then return nil end

    local conf = Net.cconf[c]
    if conf then
        -- somebody on a conflicting path has been waiting longer: let it go first
        for i = 1, #conf do
            local cl = claims[conf[i]]
            if cl then
                for b in pairs(cl) do
                    if b.claim == conf[i] and Agents.list[b.id] and b.plan[1].code > 0 then
                        if b ~= ag and (not ag.claimAt or b.claimAt < ag.claimAt) and not waitsFor(b, ag) then
                            return "claim", b
                        end
                    else
                        cl[b] = nil
                    end
                end
            end
        end
        for i = 1, #conf do
            local x = conf[i]
            local o = Agents.occ[-x]
            if o then
                for b in pairs(o) do
                    if b ~= ag and b.plan[1].code == -x and not waitsFor(b, ag) then return "conflict", b end
                end
            end
            local cm = commits[x]
            if cm then
                for b in pairs(cm) do
                    if b.committed == x and Agents.list[b.id] and b.plan[1].code > 0 then
                        if b ~= ag and not waitsFor(b, ag) then return "conflict", b end
                    else
                        cm[b] = nil
                    end
                end
            end
        end
    end

    local waited = ag.stopSince and now - ag.stopSince or 0
    local yl = Net.cyield[c]
    if yl and waited < T.DEADLOCK_WAIT then
        for i = 1, #yl do
            local ap = approachPrev[yl[i]]
            if ap then
                for k = 1, #ap do
                    local e = ap[k]
                    if e.ag ~= ag and e.dist < T.YIELD_WATCH and e.hold ~= "signal" and e.hold ~= "els"
                        and (e.ag.v > 1 or e.dist < 10) and Agents.list[e.ag.id] and not waitsFor(e.ag, ag) then
                        return "yield", e.ag
                    end
                end
            end
        end
    end

    local boxed = laneEntryBlocked(Net.cto[c], ag)
    if boxed then return "box", boxed end
    return nil
end

------------------------------------------------------------------------ obstacles

local nearBuf = {}

local function obstacleAccel(ag, v, v0, n, now)
    local L = min(T.OBSTACLE_RANGE, max(25, v * 3 + 15))
    for i = #nearBuf, 1, -1 do nearBuf[i] = nil end
    Obstacles.near(ag.x + ag.hx * L * 0.5, ag.y + ag.hy * L * 0.5, L * 0.5 + 6, nearBuf)
    local best, bestA, bestGap, bestSide = nil, nil, nil, nil
    for i = 1, #nearBuf do
        local o = nearBuf[i]
        if abs(o.z - ag.z) < 4 then
            local rx, ry = o.x - ag.x, o.y - ag.y
            local along = rx * ag.hx + ry * ag.hy
            if along > 0 and along < L and abs(rx * ag.hy - ry * ag.hx) < 8 then
                -- lateral distance from the route at that point (curves)
                local px, py, _, fx, fy = Geo.poseOnChain(chain, n, ag.s + along, 0)
                if px then
                    local h = sqrt(fx * fx + fy * fy)
                    fx, fy = fx / h, fy / h
                    local side = (o.x - px) * fy - (o.y - py) * fx
                    local gap = along - ag.half - o.hl
                    -- where the agent will be laterally when its front reaches the obstacle
                    local latThere = Geo.latAfter(ag.lat, ag.latTarget, ag.latSlope, gap > 0 and gap or 0)
                    local skip = ag.overtake and ag.overtake.el == o.el
                    if not skip and abs(side - latThere) < 1.05 + o.hw then
                        local vl = max(0, o.vx * ag.hx + o.vy * ag.hy)
                        local a = idm(v, v0, gap, vl)
                        if not bestA or a < bestA then best, bestA, bestGap, bestSide = o, a, gap, side end
                    end
                end
            end
        end
    end

    if best and bestGap < 12 and v < 0.5 and sqrt(best.vx * best.vx + best.vy * best.vy) < 0.5 then
        if ag.blockedBy ~= best.el then ag.blockedBy, ag.blockedSince = best.el, now end
        local waited = now - ag.blockedSince
        if waited > T.OVERTAKE_AFTER and not ag.overtake then
            local lat = bestSide - (best.hw + 1.0 + 1.3)
            if lat < -4.5 then lat = -4.5 end
            ag.overtake = { el = best.el, lat = lat, x = best.x, y = best.y, at = now }
        end
        if best.player and waited > T.HORN_AFTER and (not ag.lastHorn or now - ag.lastHorn > 6000) then
            ag.lastHorn, ag.horn = now, true
        end
    elseif not best then
        ag.blockedBy = nil
    end
    return bestA
end

------------------------------------------------------------------------ per agent

local function accelOf(ag, now)
    local plan = ag.plan
    local v = ag.v
    local v0 = segSpeed(plan[1].code) * ag.v0f
    ag.hold = nil
    ag.blocker = nil

    local e = ag.els
    if e then
        if e.expires < now then ag.els = nil
        else
            local cap = e.vcap
            -- pull over first (steering needs forward motion), stop only when aside
            if cap < T.ELS_MANEUVER_SPEED and abs(ag.lat - e.lat) > 0.3 then cap = T.ELS_MANEUVER_SPEED end
            if cap < v0 then v0 = cap end
        end
    end
    local ov = ag.overtake
    if ov then
        local passed = (ov.x - ag.x) * ag.hx + (ov.y - ag.y) * ag.hy < -8
        if passed or now - ov.at > 25000 or not isElement(ov.el) then
            ag.overtake = nil
        elseif T.OVERTAKE_SPEED < v0 then
            v0 = T.OVERTAKE_SPEED
        end
    end

    local aMin = accelFree(v, v0)
    local limit = "free"
    local look = max(T.LOOKAHEAD_MIN, v * v / (2 * T.IDM_DECEL) + 25)
    local dist = -ag.s
    local gateDone = plan[1].code < 0
    local n = #plan
    for i = 1, n do chain[i] = plan[i].code end
    for i = n + 1, #chain do chain[i] = nil end

    for i = 1, n do
        if dist > look then break end
        local p = plan[i]
        local code = p.code
        local len = Geo.length(code)

        if i >= 2 then
            -- entering a slower segment (curve, lane type)
            local sl = segSpeed(code) * ag.v0f
            if dist > 0 then
                local allowed = sqrt(sl * sl + 2 * T.IDM_DECEL * dist)
                if allowed < v0 then
                    local a = accelFree(v, allowed)
                    if a < aMin then aMin, limit = a, "curve" end
                end
            elseif sl < v0 then
                local a = accelFree(v, sl)
                if a < aMin then aMin, limit = a, "curve" end
            end
            -- junction gate before the first curve ahead
            if code < 0 and not gateDone then
                gateDone = true
                local c = p.conn
                local dStop = dist - T.STOP_LINE - ag.half
                local reason, by
                if ag.committed ~= c then
                    reason, by = gate(ag, c, dStop, now)
                    if (reason == "conflict" or reason == "yield" or reason == "claim") and not ag.claimAt
                        and ag.stopSince and now - ag.stopSince > T.CLAIM_AFTER then
                        ag.claim, ag.claimAt = c, now
                        local cl = claims[c]
                        if not cl then cl = {}; claims[c] = cl end
                        cl[ag] = true
                    end
                    if not reason and dStop < 2.5 then
                        ag.claim, ag.claimAt = nil, nil
                        ag.committed = c
                        local cm = commits[c]
                        if not cm then cm = {}; commits[c] = cm end
                        cm[ag] = true
                    end
                end
                if dist < T.YIELD_WATCH + 10 then
                    local ap = approachNext[c]
                    if not ap then ap = {}; approachNext[c] = ap end
                    ap[#ap + 1] = { ag = ag, dist = dStop, committed = ag.committed == c, hold = reason }
                end
                if reason then
                    ag.hold = reason
                    ag.blocker = by
                    local a = idm(v, v0, max(dStop, 0.05), 0)
                    if a < aMin then aMin, limit = a, "gate" end
                    break
                end
            end
        end

        -- leaders on this segment
        local o = Agents.occ[code]
        if o then
            local best, bestD
            for b in pairs(o) do
                if b ~= ag and b.plan[1].code == code then
                    local bs = b.s
                    if i > 1 or bs > ag.s or (bs == ag.s and b.id > ag.id) then
                        local d = dist + bs
                        if d > 0 and (not bestD or d < bestD) then best, bestD = b, d end
                    end
                end
            end
            if best then
                ag.blocker = best
                local a = idm(v, v0, bestD - ag.half - best.half, best.v)
                if a < aMin then aMin, limit = a, "leader" end
                break
            end
        end

        dist = dist + len
        -- end of the route (sink / dead end without u-turn)
        if i == n and not (code > 0 and p.conn) and code > 0 and not Net.lnext[code] then
            local a = idm(v, v0, dist - ag.half - 0.5, 0)
            if a < aMin then aMin, limit = a, "end" end
            ag.atEnd = dist < 30
        end
    end

    local oa = obstacleAccel(ag, v, v0, n, now)
    if oa and oa < aMin then aMin, limit = oa, "obstacle" end
    ag.limit = limit

    if aMin < -T.IDM_MAX_DECEL then aMin = -T.IDM_MAX_DECEL end
    if aMin > T.IDM_ACCEL then aMin = T.IDM_ACCEL end
    return aMin
end

-- lateral offset target + steering slope; the offset itself only changes with distance driven
local function moveLateral(ag, ds)
    local target, slope = 0, T.RETURN_SLOPE
    if ag.els and ag.els.lat ~= 0 then target, slope = ag.els.lat, T.ELS_SLOPE
    elseif ag.overtake then target, slope = ag.overtake.lat, T.OVERTAKE_SLOPE end
    if target ~= ag.latTarget then
        ag.latTarget = target
        ag.latSlope = slope
    end
    if ds > 0 and ag.lat ~= target then
        ag.lat = Geo.latAfter(ag.lat, target, ag.latSlope, ds)
    end
end

function Sim.step(dt, now)
    Signals.update(now)
    approachPrev, approachNext = approachNext, {}
    for _, ag in pairs(Agents.list) do
        ag.a = accelOf(ag, now)
    end
    for _, ag in pairs(Agents.list) do
        local v0 = ag.v
        local v1 = v0 + ag.a * dt
        if v1 < 0 then v1 = 0 end
        ag.v = v1
        local ds = (v0 + v1) * 0.5 * dt
        ag.s = ag.s + ds
        if not Agents.advance(ag) then ag.v = 0 end
        moveLateral(ag, ds)
        Agents.updatePose(ag)
        if ag.v < 0.3 then ag.stopSince = ag.stopSince or now else ag.stopSince = nil end
    end
    Agents.rebuildHash()
end
