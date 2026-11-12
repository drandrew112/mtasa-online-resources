-- Traffic stop pull-over (server), 2026-11-12. A vehicle the police stops (pullOverTrafficVehicle) never stops in the
-- road: it drives on until it finds a place where it can leave the carriageway completely, steers out there (onto
-- the shoulder / pavement if needed) and stands beside the lane, where the other traffic passes it.
--
--   seek    drives on (PULL_SEEK_SPEED, a bit to the right) and scans its planned route PULL_MIN_AHEAD..PULL_MAX_AHEAD m
--           ahead every PULL_SCAN ms for a spot:
--             * the outermost lane (a car in an inner lane first changes right: the lane change of the ELS reaction)
--             * not a parking / road block / trap / emergency lane
--             * at least PULL_AFTER_JUNCTION m after and PULL_BEFORE_JUNCTION m before a junction (a lane end with
--               more than one way on, a signal, a give-way or conflict, a turn)
--             * flat ground beside the lane (navmesh walk grid) for the whole car at a lateral offset of
--               PULL_LATS (car fully outside the lane), kerbs up to PULL_GROUND_DZ are fine
--             * no other stopped car / player / player vehicle there
--   pull    its own stop point (sc.pullLane / pullS, braked for in sim.lua) is the spot; within PULL_LEAD m it steers out to the
--           spot's offset (steering needs forward motion: ELS_MANEUVER_SPEED until aside)
--   parked  stands at the offset; it is no leader for the traffic behind (sim.lua). onTrafficVehiclePulledOver once.
--   merge   after releaseTrafficHold: waits beside the lane while traffic comes from behind, then steers back in.
--
-- The pull-over owns the vehicle's yield state (ag.els): the ELS reaction (els.lua) skips held vehicles completely,
-- so the police car's lights never make it stop where it is.

Pull = {}

local T = TRAFFIC
local sqrt, abs, max, min, floor = math.sqrt, math.abs, math.max, math.min, math.floor

addEvent("onTrafficVehiclePulledOver")   -- source: root; (vehicle)

------------------------------------------------------------------------ spot checks

local BLOCK = LF_PARKING + LF_ROADBLOCK + LF_TRAP + LF_EMERGENCY

local function junctionConn(c)
    if not c then return false end
    if Net.cconf[c] or Net.cyield[c] or (Net.cphase[c] or 0) > 0 then return true end
    local turn = Net.cturn[c]
    return turn ~= nil and turn ~= "S"
end

-- does the lane end / start at a junction?
local junctionEnd, junctionStart = {}, {}
local function endsAtJunction(code)
    local v = junctionEnd[code]
    if v == nil then
        local nx = Net.lnext[code]
        v = not nx or #nx ~= 1 or junctionConn(nx[1])
        junctionEnd[code] = v
    end
    return v
end
local function startsAtJunction(code)
    local v = junctionStart[code]
    if v == nil then
        local pv = Net.lprev[code]
        v = not pv or #pv ~= 1 or junctionConn(pv[1])
        junctionStart[code] = v
    end
    return v
end

local function groundOK(x, y, z, ref)
    local gz, info = Navmesh.ground(x, y, z + 0.6, 1.8)
    if not gz or abs(gz - ref) > T.PULL_GROUND_DZ then return false end
    return not (info and (info.steep or info.surface == "water"))
end

-- the lateral offset (from the lane centre, + = right) where a car at s on lane `code` stands fully beside the
-- lane on flat ground, 0 = none. Cached per lane and 4 m (the map does not change).
local roomCache, roomCount = {}, 0
local function spotRoom(code, s)
    local bucket = floor(s / 4)
    local c = roomCache[code]
    if c and c[bucket] ~= nil then return c[bucket] end
    local room = 0
    if Navmesh.ok then
        local refs, ok = {}, true
        for i, a in ipairs(T.PULL_PROBE) do
            local x, y, z = Geo.pose(code, s + a, 0)
            if not x then ok = false; break end
            refs[i] = Navmesh.ground(x, y, z + 0.6, 1.8) or z
        end
        if ok then
            for _, L in ipairs(T.PULL_LATS) do
                local good = true
                for i, a in ipairs(T.PULL_PROBE) do
                    -- the way out (no wall between) and the car's whole width at the offset
                    for _, off in ipairs({ T.PULL_LANE_HALF + 0.3, L - T.ELS_CAR_HALF_WIDTH, L, L + T.ELS_CAR_HALF_WIDTH }) do
                        local x, y, z = Geo.pose(code, s + a, off)
                        if not x or not groundOK(x, y, z, refs[i]) then good = false; break end
                    end
                    if not good then break end
                end
                if good then room = L; break end
            end
        end
    end
    if roomCount > 20000 then roomCache, roomCount = {}, 0 end
    if not roomCache[code] then roomCache[code] = {} end
    roomCache[code][bucket] = room
    roomCount = roomCount + 1
    return room
end

local nearBuf, agBuf = {}, {}
local function spotFree(ag, x, y)
    for i = #nearBuf, 1, -1 do nearBuf[i] = nil end
    Obstacles.near(x, y, T.PULL_SPOT_CLEAR, nearBuf)
    for i = 1, #nearBuf do
        local o = nearBuf[i]
        if (o.x - x) ^ 2 + (o.y - y) ^ 2 < T.PULL_SPOT_CLEAR ^ 2 then return false end
    end
    for i = #agBuf, 1, -1 do agBuf[i] = nil end
    Agents.near(x, y, T.PULL_SPOT_CLEAR + 4, agBuf)
    for i = 1, #agBuf do
        local b = agBuf[i]
        if b ~= ag and b.pull and (b.pull.phase == "parked" or b.pull.phase == "pull")
            and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (T.PULL_SPOT_CLEAR + 3) ^ 2 then return false end
    end
    return true
end

-- the first good spot on the agent's planned route -> { code, s, lat, x, y } | nil
local function findSpot(ag)
    local plan = ag.plan
    local minAhead = max(T.PULL_MIN_AHEAD, ag.v * ag.v / (2 * T.IDM_DECEL) + 6)
    local dist = -ag.s
    for i = 1, #plan do
        local code = plan[i].code
        local len = Geo.length(code)
        if dist > T.PULL_MAX_AHEAD then break end
        if code > 0 and not Net.lright[code] and bitAnd(Net.lflags[code] or 0, BLOCK) == 0 then
            local s0 = startsAtJunction(code) and T.PULL_AFTER_JUNCTION or 4
            local s1 = len - (endsAtJunction(code) and T.PULL_BEFORE_JUNCTION or 4)
            -- the spot lies on this lane, ahead of the agent by minAhead at least
            local s = max(s0, minAhead - dist)
            s = 4 * math.ceil(s / 4)
            while s <= s1 and dist + s <= T.PULL_MAX_AHEAD do
                local lat = spotRoom(code, s)
                if lat > 0 then
                    local x, y = Geo.pose(code, s, lat)
                    if x and spotFree(ag, x, y) then return { code = code, s = s, lat = lat, x = x, y = y } end
                end
                s = s + 4
            end
        end
        dist = dist + len
    end
    return nil
end

------------------------------------------------------------------------ actuator (the yield state sim.lua reads)

local function drive(ag, now, vcap, lat, right)
    ag.els = { vcap = vcap, lat = lat, expires = now + 1000, cycle = -1, clear = false, right = right == true }
end

-- distance along the plan from the agent to s on lane code (nil = not on the plan)
local function distTo(ag, code, s)
    local d = -ag.s
    for i = 1, #ag.plan do
        local c = ag.plan[i].code
        if c == code then return d + s end
        d = d + Geo.length(c)
    end
    return nil
end

-- the pull-over's own stop point (sim.lua brakes for sc.pullLane / pullS like for a scripted stop; kept apart from
-- stopLane, which the target logic of scripted.lua rewrites)
local function setStop(ag, code, s)
    local sc = ag.script
    if not sc then return end
    sc.pullLane, sc.pullS = code, s
end

------------------------------------------------------------------------ states

function Pull.start(ag, byVeh)
    ag.pull = { phase = "seek", since = getTickCount(), by = byVeh, scanAt = 0 }
    ag.merge = nil
    if ag.script then ag.script.pullLane, ag.script.pullS = nil, nil end
end

function Pull.clear(ag)
    if ag.script then ag.script.pullLane, ag.script.pullS = nil, nil end
    ag.pull = nil
    ag.els = nil
end

-- back into the traffic: wait beside the lane while traffic comes from behind
function Pull.release(ag)
    local p = ag.pull
    ag.pull = nil
    if p and p.phase == "parked" then ag.merge = { since = getTickCount(), lat = ag.lat } else ag.els = nil end
end

local function seek(ag, p, now)
    if now >= p.scanAt then
        p.scanAt = now + T.PULL_SCAN
        local spot = findSpot(ag)
        if spot then
            p.spot, p.phase = spot, "pull"
            -- the car's centre stops at the spot: the stop point is the front bumper
            setStop(ag, spot.code, spot.s + ag.half)
            return
        end
    end
    -- inner lane of a multi-lane road: over to the right first
    local code = ag.plan[1].code
    local right = code > 0 and Net.lright[code] ~= nil
    drive(ag, now, T.PULL_SEEK_SPEED, right and 0 or T.PULL_SEEK_LAT, right)
end

local function pull(ag, p, now)
    local spot = p.spot
    local d = distTo(ag, spot.code, spot.s)
    if not d then
        -- the route changed under it (lane change, replan): look again
        p.phase, p.spot, p.scanAt = "seek", nil, 0
        if ag.script then ag.script.pullLane, ag.script.pullS = nil, nil end
        return seek(ag, p, now)
    end
    if d <= T.PULL_LEAD then
        drive(ag, now, T.PULL_SPEED, spot.lat, false)
        if ag.v < 0.3 and abs(ag.lat - spot.lat) < 0.35 then
            p.phase = "parked"
            p.parkedAt = now
            triggerEvent("onTrafficVehiclePulledOver", root, ag.veh)
        elseif ag.v < 0.3 and d < 1.5 and abs(ag.lat - spot.lat) >= 0.35 then
            -- stopped before it was aside: a few metres more
            p.extra = (p.extra or 0) + 1
            if p.extra > 3 then
                p.phase = "parked"
                p.parkedAt = now
                triggerEvent("onTrafficVehiclePulledOver", root, ag.veh)
            else
                spot.s = spot.s + 4
                setStop(ag, spot.code, spot.s + ag.half)
            end
        end
    else
        drive(ag, now, T.PULL_SEEK_SPEED, T.PULL_SEEK_LAT, false)
    end
end

local function parked(ag, p, now)
    local lat = p.spot and p.spot.lat or ag.lat
    drive(ag, now, 0, lat, false)
end

local behind = {}
local function merge(ag, now)
    local m = ag.merge
    if now - m.since > T.PULL_MERGE_MAX then ag.merge = nil; return end
    for i = #behind, 1, -1 do behind[i] = nil end
    Agents.near(ag.x, ag.y, T.PULL_MERGE_LOOK, behind)
    local code = ag.plan[1].code
    for i = 1, #behind do
        local b = behind[i]
        if b ~= ag and b.v > 2 and not b.pull and abs(b.lat) < 1.6 and b.plan[1].code == code then
            local along = (b.x - ag.x) * ag.hx + (b.y - ag.y) * ag.hy
            if along < 0 and along > -T.PULL_MERGE_LOOK then
                ag.els = { vcap = 0, lat = m.lat, expires = now + 600, cycle = -1, clear = false }
                return
            end
        end
    end
    ag.merge = nil
    ag.els = nil
end

function Pull.update(now)
    for _, ag in pairs(Agents.list) do
        local p = ag.pull
        if p then
            if not ag.held then
                ag.pull = nil
            elseif p.phase == "seek" then seek(ag, p, now)
            elseif p.phase == "pull" then pull(ag, p, now)
            else parked(ag, p, now) end
        elseif ag.merge then
            merge(ag, now)
        end
    end
end

-- standing beside the lane after a traffic stop: the traffic behind passes it (sim.lua leader check)
function Pull.isAside(b)
    local p = b.pull
    return p ~= nil and p.phase == "parked" and abs(b.lat) >= T.PULL_LANE_HALF
        or (b.merge ~= nil and abs(b.lat) >= T.PULL_LANE_HALF)
end
