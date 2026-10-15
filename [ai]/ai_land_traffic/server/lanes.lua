-- Lane discipline on multi-lane carriageways (server). Traffic keeps to the outer (rightmost) lane; the
-- inner lane is only for passing:
--   * a car in the inner lane moves back to the outer lane as soon as there is room (unless it plans to
--     turn left / u-turn soon, or it is still passing)
--   * a car held up by a clearly slower leader in the outer lane passes through the inner lane
--   * a driver giving way to an emergency vehicle (els.lua, e.right) goes to the outer lane first
-- A lane change moves the agent onto the neighbouring lane at once (Agents.changeLane) with the old
-- position as lateral offset; the offset then eases to the new lane centre (steered, no sliding).

Lanes = {}

local T = TRAFFIC
local abs, max, random = math.abs, math.max, math.random

-- is the neighbouring lane free around the agent's position? relaxed: giving way to an emergency vehicle
local function gapOK(ag, lane, s2, relaxed)
    local f = relaxed and T.LANE_GAP_RELAXED or 1
    local base, tv, tc = T.LANE_GAP * f, T.LANE_GAP_TIME * f, T.LANE_GAP_CLOSING * f
    local o = Agents.occ[lane]
    if o then
        for b in pairs(o) do
            if b ~= ag and b.plan[1].code == lane then
                local d = b.s - s2
                local need = ag.half + b.half + base
                if d >= 0 then
                    need = need + ag.v * tv + max(0, ag.v - b.v) * tc      -- b ahead of the new position
                else
                    need = need + b.v * tv + max(0, b.v - ag.v) * tc       -- b behind
                    d = -d
                end
                if d < need then return false end
            end
        end
    end
    -- traffic still on its way into the lane (curves directly in front of its start)
    if s2 < 40 then
        for _, c in ipairs(Net.lprev[lane] or {}) do
            local from = Geo.isCurve(c) and -c or Net.cfrom[c]
            local po = Agents.occ[from]
            if po then
                for b in pairs(po) do
                    if b ~= ag and b.plan[1].code == from then
                        local d = s2 + Geo.length(from) - b.s
                        if d < ag.half + b.half + base + b.v * tv + max(0, b.v - ag.v) * tc then return false end
                    end
                end
            end
        end
    end
    return true
end

-- is there a junction with right of way / signal logic within dist ahead?
local function junctionWithin(ag, dist)
    local d = -ag.s
    for _, p in ipairs(ag.plan) do
        d = d + Geo.length(p.code)
        if d > dist then return false end
        local c = p.conn
        if c and p.code > 0 and (Net.cconf[c] or (Net.cphase[c] or 0) > 0) then return true end
    end
    return false
end

-- does the planned route within dist turn one of the given kinds (string of turn letters)?
local function turnAhead(ag, kinds, dist)
    local d = -ag.s
    for _, p in ipairs(ag.plan) do
        d = d + Geo.length(p.code)
        if d > dist then return false end
        local c = p.conn
        if c and p.code > 0 then
            local t = Net.cturn[c]
            if t and kinds:find(t, 1, true) then return true end
        end
    end
    return false
end

-- an emergency vehicle made this driver want the outer lane and it has not got there yet
function Lanes.wantsRight(ag)
    local e = ag.els
    return e ~= nil and e.right == true and ag.plan[1].code > 0 and Net.lright[ag.plan[1].code] ~= nil
end

local function change(ag, to, now)
    if Agents.changeLane(ag, to, now) then
        ag.laneFree = now + T.LANE_CHANGE_COOLDOWN
        ag.slowSince = nil
        return true
    end
    return false
end

function Lanes.update(ag, now)
    if now < (ag.laneAt or 0) then return end
    ag.laneAt = now + 350 + random(150)
    local cur = ag.plan[1].code
    if cur < 0 then ag.slowSince = nil; return end
    local left, right = Net.lleft[cur], Net.lright[cur]
    if not left and not right then ag.slowSince = nil; return end

    local len = Geo.length(cur)
    -- nothing while stopped, held at a stop line, at the very end of a lane or in the middle of another manoeuvre
    if ag.v < T.LANE_MIN_SPEED or ag.hold or ag.overtake or ag.committed or len - ag.s < 8 or abs(ag.lat) > 1.5
        or now < (ag.laneFree or 0) then
        if not ag.hold then ag.slowSince = nil end
        return
    end

    local e = ag.els
    local giving = e and e.expires > now
    if giving then
        -- giving way to an emergency vehicle: into the outer lane, whatever the gaps allow (relaxed)
        if right and e.right and Net.lnext[right] then
            local s2 = ag.s * Geo.length(right) / len
            if gapOK(ag, right, s2, e.clear) then change(ag, right, now) end
        end
        return
    end

    if right then
        -- inner lane: back to the outer lane, except while passing or when a left / u-turn is planned
        if now >= (ag.passUntil or 0) and Net.lnext[right] and not junctionWithin(ag, T.LANE_JUNCTION_DIST)
            and not turnAhead(ag, "LU", T.LANE_TURN_LOOK) then
            local s2 = ag.s * Geo.length(right) / len
            if gapOK(ag, right, s2, false) then change(ag, right, now) end
        end
        return
    end

    -- outer lane: pass a clearly slower leader through the inner lane
    local b = ag.limit == "leader" and ag.blocker
    local wanted = (Net.lspeed[cur] or T.SPEED_ROAD) * ag.v0f
    if b and b.plan[1].code == cur and b.v < wanted * T.LANE_PASS_LEADER then
        ag.slowSince = ag.slowSince or now
        if now - ag.slowSince >= T.LANE_PASS_AFTER and Net.lnext[left] and not junctionWithin(ag, T.LANE_JUNCTION_DIST + 30)
            and not turnAhead(ag, "R", T.LANE_TURN_LOOK) then
            local s2 = ag.s * Geo.length(left) / len
            if gapOK(ag, left, s2, false) and change(ag, left, now) then ag.passUntil = now + T.LANE_PASS_HOLD end
        end
    else
        ag.slowSince = nil
    end
end
