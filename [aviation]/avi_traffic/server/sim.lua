-- Traffic simulation. No vehicles are created: the aircraft exist only here and on the ATC scope.
-- Units: position = world metres, alt = feet, spd = knots, vs = feet / minute, hdg = compass deg
-- (0 = north = +y, 90 = east = +x).
--
-- Phases
--   ground departure: gate -> taxi_out -> hold -> takeoff -> air (climb-out on runway heading)
--   external entry  : air (spawned at the first route fix, at cruise level)
--   air             : DCT (controller) > flight plan fixes > approach (final fix) | exit (external)
--                     SID (avi_nav procedure) after take-off, STAR towards the arrival runway: from the
--                     controller (IFR clearance / arrival procedure) or, without one, picked by the pilots
--   final           : on the glide path to the threshold -> landing -> taxi_in -> parked -> removed
--   go-around       : final fix too high -> runway heading past the field, then a new approach

AIRCRAFT = {}          -- [id] = aircraft
local nextId = 1

addEvent("onAviTrafficSpawn")    -- source: resourceRoot, args: id, callsign
addEvent("onAviTrafficRemove")   -- source: resourceRoot, args: id, callsign, reason

local KT_MS = 0.514444

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end
local function bearing(ax, ay, bx, by) return math.deg(math.atan2(bx - ax, by - ay)) % 360 end
local function angleTo(from, to) return (to - from + 540) % 360 - 180 end

-- ---------------------------------------------------------------- squawk
local function newSquawk()
    local used = {}
    for _, ac in pairs(AIRCRAFT) do used[ac.sqk] = true end
    local reserved = { ["7500"] = true, ["7600"] = true, ["7700"] = true, ["7000"] = true, ["2000"] = true, ["1200"] = true }
    for _ = 1, 200 do
        local s = ("%d%d%d%d"):format(math.random(0, 7), math.random(0, 7), math.random(0, 7), math.random(0, 7))
        if not used[s] and not reserved[s] and s:sub(1, 2) ~= "00" then return s end
    end
    return "4321"
end

-- ---------------------------------------------------------------- helpers
local function fieldElev(ac)
    local a = airport(ac.gndApt or ac.arr) or airport(ac.dep)
    return a and a.elevation or 0
end

local function isGround(ac)
    local p = ac.phase
    return p == "gate" or p == "pushback" or p == "pushed" or p == "taxi_out" or p == "hold" or p == "lined" or p == "takeoff"
        or p == "landing" or p == "vacate" or p == "vacated" or p == "taxi_in" or p == "parked"
end
isAircraftOnGround = isGround

-- a controller has the aircraft: clearances are needed (otherwise the pilots act on their own)
local function controlled(ac)
    return controllerOf(ac) ~= nil
end

local function gateOccupied(icao, gateId, except)
    for _, ac in pairs(AIRCRAFT) do
        if ac ~= except and ac.gndApt == icao and ac.gate == gateId and isGround(ac) then return true end
    end
    return false
end

local function freeGate(a, except)
    local free = {}
    for _, g in ipairs(a.gates) do
        if not gateOccupied(a.icao, g.id, except) then free[#free + 1] = g end
    end
    if #free == 0 then return nil end
    return free[math.random(#free)]
end

-- world metres per second at the aircraft's speed, phase and height
local function worldSpeed(ac)
    local scale
    if ac.phase == "taxi_out" or ac.phase == "taxi_in" or ac.phase == "vacate" or ac.phase == "pushback" then
        scale = TR.TAXI_SCALE
    elseif ac.phase == "takeoff" or ac.phase == "landing" then
        scale = TR.ROLL_SCALE
    else
        local agl = math.max(0, ac.alt - fieldElev(ac))
        local f = clamp(agl / TR.SCALE_BLEND_FT, 0, 1)
        if ac.phase == "air" and not ac.gndApt and not ac.climbOut then f = 1 end
        scale = TR.ROLL_SCALE + (TR.AIR_SCALE - TR.ROLL_SCALE) * f
    end
    return ac.spd * KT_MS * scale
end

local function moveForward(ac, dt)
    local d = worldSpeed(ac) * dt
    local h = math.rad(ac.hdg)
    ac.x, ac.y = ac.x + math.sin(h) * d, ac.y + math.cos(h) * d
    return d
end

local function turnTowards(ac, targetHdg, dt, rate)
    local diff = angleTo(ac.hdg, targetHdg)
    local step = (rate or TR.TURN_RATE) * dt
    ac.hdg = (ac.hdg + clamp(diff, -step, step)) % 360
end

local function speedTowards(ac, target, rate, dt)
    local diff = target - ac.spd
    ac.spd = ac.spd + clamp(diff, -rate * dt, rate * dt)
end

-- ---------------------------------------------------------------- creation / removal
local function newAircraft(fl)
    local ti = typeInfo(fl.type)
    local ac = {
        id = nextId, cs = fl.callsign, type = fl.type, wake = ti.wake or "M",
        dep = fl.dep, arr = fl.arr, route = {}, ri = 1, cruise = fl.cruise,
        perf = ti, sqk = newSquawk(), age = 0, spd = 0, vs = 0, alt = 0, hdg = 0,
        plan = {},           -- the filed route (the route itself changes with SID / STAR)
    }
    for _, id in ipairs(fl.route) do
        ac.route[#ac.route + 1] = tostring(id):upper()
        ac.plan[#ac.plan + 1] = tostring(id):upper()
    end
    nextId = nextId + 1
    return ac
end

function removeAircraft(ac, reason)
    if not AIRCRAFT[ac.id] then return end
    AIRCRAFT[ac.id] = nil
    triggerEvent("onAviTrafficRemove", resourceRoot, ac.id, ac.cs, reason or "removed")
end

function isCallsignActive(cs)
    for _, ac in pairs(AIRCRAFT) do if ac.cs == cs then return true end end
    return false
end

function countActive()
    local n = 0
    for _ in pairs(AIRCRAFT) do n = n + 1 end
    return n
end

-- returns aircraft or nil, reason
function spawnFlight(fl)
    if isCallsignActive(fl.callsign) then return nil, "already active" end
    local ac = newAircraft(fl)
    local depApt = airport(fl.dep)
    if depApt then
        local g = freeGate(depApt)
        if not g then return nil, "no free gate at " .. fl.dep end
        ac.phase = "gate"
        ac.gndApt, ac.gate = depApt.icao, g.id
        ac.x, ac.y, ac.hdg = g.x, g.y, tonumber(g.hdg) or 0
        ac.alt = depApt.elevation
        ac.timer = math.random(TR.GATE_WAIT[1], TR.GATE_WAIT[2])
    else
        local first = navPoint(ac.route[1])
        if not first then return nil, "unknown entry fix " .. tostring(ac.route[1]) end
        local nxt = navPoint(ac.route[2]) or (airport(fl.arr) and { x = airport(fl.arr).arp[1], y = airport(fl.arr).arp[2] })
        ac.phase = "air"
        ac.x, ac.y = first.x, first.y
        ac.hdg = nxt and bearing(ac.x, ac.y, nxt.x, nxt.y) or 0
        ac.ri = 2
        -- inbound: enter no higher than the descent plan allows (short arrivals start lower)
        ac.alt = math.min(fl.cruise, trafficAutoLevel(ac) + 500)
        ac.cfl = ac.alt
        ac.spd = ac.alt < TR.SPEED_LIMIT_ALT and math.min(250, ac.perf.cruise) or ac.perf.cruise
    end
    AIRCRAFT[ac.id] = ac
    triggerEvent("onAviTrafficSpawn", resourceRoot, ac.id, ac.cs)
    return ac
end

-- ---------------------------------------------------------------- procedures
-- The procedure in use is shown in the waypoint field of the label (ac.proc = "VINEW1D 27L").

local function remainingRoute(ac)
    local out = {}
    for i = ac.ri, #ac.route do out[#out + 1] = ac.route[i] end
    return out
end

-- SID: climb-out / turn fixes + exit fix, then the flight plan after the exit fix (at take-off)
function applySID(ac, sidId, ident)
    local r = procedureRoute(sidId, ident)
    local p = procedure(sidId)
    if not r or not p then return false end
    local rest, found = {}, false
    for i = ac.ri, #ac.route do
        if found then rest[#rest + 1] = ac.route[i] end
        if ac.route[i] == p.fix then found = true end
    end
    if not found then rest = remainingRoute(ac) end
    ac.route, ac.ri = r, 1
    for _, f in ipairs(rest) do ac.route[#ac.route + 1] = f end
    ac.procEnd = #r
    ac.sid, ac.sidRwy = p.id, tostring(ident):upper()
    ac.proc = p.id .. " " .. ac.sidRwy
    return true
end

-- STAR: the remaining route up to the entry fix + the STAR to the final fix of `ident`. Fixes the
-- aircraft is already past are left out (the base + final fix always stay).
function applySTAR(ac, starId, ident)
    local r = procedureRoute(starId, ident)
    local p = procedure(starId)
    if not r or not p or p.type ~= "STAR" then return false end
    local before, found = {}, false
    for i = ac.ri, #ac.route do
        if ac.route[i] == p.fix then found = true break end
        before[#before + 1] = ac.route[i]
    end
    if not found then before = {} end
    if #before == 0 then
        while #r > 2 do
            local a, b = navPoint(r[1]), navPoint(r[2])
            if not (a and b) or dist(ac.x, ac.y, b.x, b.y) >= dist(a.x, a.y, b.x, b.y) then break end
            table.remove(r, 1)
        end
    end
    ac.route, ac.ri = before, 1
    for _, f in ipairs(r) do ac.route[#ac.route + 1] = f end
    ac.procEnd = #ac.route
    ac.star, ac.arrRwy = p.id, tostring(ident):upper()
    ac.proc = p.id .. " " .. ac.arrRwy
    ac.ahdg, ac.dct, ac.via, ac.approach, ac.missed = nil, nil, nil, nil, nil
    if ac.phase == "air" then ac.rwy = nil end
    return true
end

-- suggested procedures: the SID whose exit fix is the first one of the filed route, the STAR whose
-- entry fix is the last one still ahead (else the last one of the filed route)
function suggestedSID(ac)
    if not airport(ac.dep) then return nil end
    return procedureFor(ac.dep, "SID", ac.plan)
end

function suggestedSTAR(ac)
    if not airport(ac.arr) then return nil end
    return procedureFor(ac.arr, "STAR", remainingRoute(ac)) or procedureFor(ac.arr, "STAR", ac.plan)
end

-- ---------------------------------------------------------------- ground
-- Runway zones: within half the runway width + RWY_ZONE_MARGIN of a centre line (and up to
-- RWY_ZONE_EXT beyond its ends). Nobody taxies into a zone without a clearance for that runway
-- (ac.rwyClr[runwayId]); it stops at the edge = holding short. A clearance is used up when the
-- aircraft leaves the zone again.

local geomCache = {}
local function runwayGeom(a)
    local g = geomCache[a]
    if g then return g end
    g = {}
    for _, rw in ipairs(a.runways or {}) do
        local e1, e2 = rw.ends[1], rw.ends[2]
        local dx, dy = e2.x - e1.x, e2.y - e1.y
        local len = math.sqrt(dx * dx + dy * dy)
        g[#g + 1] = { id = rw.id, e1 = e1, e2 = e2, ux = dx / len, uy = dy / len, len = len,
            half = (tonumber(rw.width) or 30) / 2 + TR.RWY_ZONE_MARGIN }
    end
    geomCache[a] = g
    return g
end

-- runway id whose zone contains the point
function runwayZoneAt(a, x, y)
    if not a then return nil end
    for _, r in ipairs(runwayGeom(a)) do
        local rx, ry = x - r.e1.x, y - r.e1.y
        local t = rx * r.ux + ry * r.uy
        local off = math.abs(rx * r.uy - ry * r.ux)
        if off <= r.half and t >= -TR.RWY_ZONE_EXT and t <= r.len + TR.RWY_ZONE_EXT then return r.id end
    end
end

local function runwayById(a, id)
    for _, r in ipairs(runwayGeom(a)) do if r.id == id then return r end end
end

-- runway exits: taxiway points inside the zone of the runway, each with a clear point (on the
-- taxiway, just outside every runway zone, towards the terminal if both sides are possible)
function runwayExits(a, runwayId)
    local r = runwayById(a, runwayId)
    if not r then return {} end
    -- distance to the nearest stand (between parallel runways is not "towards the terminal")
    local function toStands(x, y)
        local best
        for _, g in ipairs(a.gates) do best = math.min(best or math.huge, dist(x, y, g.x, g.y)) end
        return best or dist(x, y, a.arp[1], a.arp[2])
    end
    local out = {}
    for _, tw in ipairs(a.taxiways) do
        local pts = tw.points or {}
        for i, p in ipairs(pts) do
            if runwayZoneAt(a, p[1], p[2]) == runwayId then
                local best, bestScore
                for _, j in ipairs({ i - 1, i + 1 }) do
                    local q = pts[j]
                    if q and runwayZoneAt(a, q[1], q[2]) ~= runwayId then
                        local d = dist(p[1], p[2], q[1], q[2])
                        local k = math.min(d, r.half + 12)
                        local cx, cy = p[1] + (q[1] - p[1]) / d * k, p[2] + (q[2] - p[2]) / d * k
                        if not runwayZoneAt(a, cx, cy) then
                            local score = toStands(cx, cy)
                            if not bestScore or score < bestScore then best, bestScore = { cx, cy }, score end
                        end
                    end
                end
                if best then
                    out[#out + 1] = { tw = tw.id, x = p[1], y = p[2], cx = best[1], cy = best[2],
                        toTerminal = toStands(best[1], best[2]) < toStands(p[1], p[2]),
                        t = (p[1] - r.e1.x) * r.ux + (p[2] - r.e1.y) * r.uy }
                end
            end
        end
    end
    return out
end

local function startTaxi(ac, toX, toY, phase)
    ac.path = callExport("avi_airports", "findTaxiRoute", ac.gndApt, ac.x, ac.y, toX, toY) or { { ac.x, ac.y }, { toX, toY } }
    ac.pi = 2
    ac.phase = phase
end

-- follows ac.path in small steps. Returns true at the end, "hold", runwayId before an
-- uncleared runway zone, false otherwise. 50 kts on a runway, 25 kts elsewhere.
local function followPath(ac, dt)
    local a = airport(ac.gndApt)
    ac.rwyClr = ac.rwyClr or {}
    speedTowards(ac, ac.onRwy and TR.RWY_TAXI_KTS or TR.TAXI_KTS, 10, dt)
    local remaining = worldSpeed(ac) * dt
    while ac.path and ac.pi <= #ac.path do
        local p = ac.path[ac.pi]
        local d = dist(ac.x, ac.y, p[1], p[2])
        if d < 0.01 then
            ac.pi = ac.pi + 1
        else
            if remaining <= 0 then return false end
            ac.hdg = bearing(ac.x, ac.y, p[1], p[2])
            local s = math.min(remaining, d, 3)
            local nx, ny = ac.x + (p[1] - ac.x) / d * s, ac.y + (p[2] - ac.y) / d * s
            local zone = runwayZoneAt(a, nx, ny)
            if zone and zone ~= ac.onRwy and not ac.rwyClr[zone] then
                ac.spd = 0
                return "hold", zone
            end
            if zone ~= ac.onRwy then
                if ac.onRwy then ac.rwyClr[ac.onRwy] = nil end     -- left that runway: clearance used up
                ac.onRwy = zone
            end
            ac.x, ac.y = nx, ny
            remaining = remaining - s
            if s >= d then ac.pi = ac.pi + 1 end
        end
    end
    return true
end

-- someone on the runway (rolling, lined up, taxiing on it), or on short final to it
local function runwayBusy(ac, icao, runwayId)
    for _, o in pairs(AIRCRAFT) do
        if o ~= ac then
            if o.onRwy == runwayId and o.gndApt == icao then return true end
            if o.phase == "final" and o.rwy and o.rwy.icao == icao and o.rwy.runway == runwayId
                    and dist(o.x, o.y, o.rwy.x, o.rwy.y) < 1500 then return true end
        end
    end
    return false
end

-- holding short of runwayId while taxiing in `resume` phase: what does the aircraft need?
--   T/O    its departure runway near the threshold (line up / take off)
--   BKTRK  its departure runway far from the threshold: backtrack to it first
--   CROSS  any other runway
local function holdKind(ac, runwayId, resume)
    if resume == "taxi_out" and ac.rwy and ac.rwy.runway == runwayId then
        local h = math.rad(ac.rwy.hdg)
        local along = (ac.x - ac.rwy.x) * math.sin(h) + (ac.y - ac.rwy.y) * math.cos(h)
        return along > TR.BACKTRACK_DIST and "BKTRK" or "TO"
    end
    return "CROSS"
end

local function taxiStep(ac, dt, phase)
    local r, zone = followPath(ac, dt)
    if r == "hold" then
        ac.phase, ac.holdRwy, ac.holdResume, ac.timer = "hold", zone, phase, TR.HOLD_TIME
        ac.holdKind = holdKind(ac, zone, phase)
        -- a take-off clearance given early lets it go straight on (not when it has to backtrack)
        if ac.holdKind == "TO" and ac.toClr then ac.rwyClr[zone] = true ac.phase = phase end
        return false
    end
    return r
end

-- pushback: tail first in an arc from the stand onto the nearest taxiway, nose towards the
-- departure runway
local function startPushback(ac)
    local a = airport(ac.gndApt)
    local best, bd, dirx, diry
    for _, tw in ipairs(a and a.taxiways or {}) do
        local pts = tw.points or {}
        for i = 1, #pts - 1 do
            local p, q = pts[i], pts[i + 1]
            local dx, dy = q[1] - p[1], q[2] - p[2]
            local l2 = dx * dx + dy * dy
            if l2 > 1 then
                local t = clamp(((ac.x - p[1]) * dx + (ac.y - p[2]) * dy) / l2, 0.05, 0.95)
                local px, py = p[1] + dx * t, p[2] + dy * t
                local d = dist(ac.x, ac.y, px, py)
                if not runwayZoneAt(a, px, py) and (not bd or d < bd) then
                    local l = math.sqrt(l2)
                    best, bd, dirx, diry = { px, py }, d, dx / l, dy / l
                end
            end
        end
    end
    local h = math.rad(ac.hdg)
    if not best or bd > 150 then
        ac.push = { p0 = { ac.x, ac.y }, p1 = { ac.x, ac.y }, p2 = { ac.x - math.sin(h) * TR.PUSH_DIST, ac.y - math.cos(h) * TR.PUSH_DIST }, t = 0, len = TR.PUSH_DIST }
    else
        -- the nose ends up pointing along the taxiway, towards the departure runway
        local rwy = callExport("avi_airports", "getActiveRunway", ac.gndApt, "dep")
        if rwy and (rwy.x - best[1]) * dirx + (rwy.y - best[2]) * diry < 0 then dirx, diry = -dirx, -diry end
        local k = math.max(15, bd * 0.7)
        ac.push = { p0 = { ac.x, ac.y }, p1 = { best[1] + dirx * k, best[2] + diry * k }, p2 = best, t = 0,
            len = bd + k * 0.6, endHdg = bearing(0, 0, dirx, diry) }
    end
    ac.phase = "pushback"
end

local function bezier(p, t)
    local u = 1 - t
    return u * u * p.p0[1] + 2 * u * t * p.p1[1] + t * t * p.p2[1], u * u * p.p0[2] + 2 * u * t * p.p1[2] + t * t * p.p2[2]
end

-- departure at the stand. Controlled: waits for the IFR clearance (initial level + route) and the
-- pushback clearance; uncontrolled: pushes back by itself after GATE_WAIT.
local function tickGate(ac, dt)
    ac.timer = ac.timer - dt
    if controlled(ac) then
        if ac.pushClr then startPushback(ac) end
        return
    end
    if ac.timer > 0 then return end
    startPushback(ac)
end

local function tickPushback(ac, dt)
    local p = ac.push
    ac.spd = TR.PUSH_KTS
    p.t = math.min(1, p.t + TR.PUSH_KTS * KT_MS * TR.TAXI_SCALE * dt / math.max(1, p.len))
    local nx, ny = bezier(p, p.t)
    if dist(ac.x, ac.y, nx, ny) > 0.05 then ac.hdg = bearing(nx, ny, ac.x, ac.y) end   -- moving tail first
    ac.x, ac.y = nx, ny
    if p.t >= 1 then
        if p.endHdg then ac.hdg = p.endHdg end
        ac.phase, ac.spd, ac.timer = "pushed", 0, 5
        ac.gate, ac.push = nil, nil
    end
end

-- pushed back: waits for the taxi clearance (to the runway the controller named, else the one in use)
local function tickPushed(ac, dt)
    ac.timer = ac.timer - dt
    if controlled(ac) then
        if not ac.taxiClr then return end
    elseif ac.timer > 0 then
        return
    end
    local rwy = ac.taxiRwy and callExport("avi_airports", "getRunwayEnd", ac.gndApt, ac.taxiRwy)
        or callExport("avi_airports", "getActiveRunway", ac.gndApt, "dep")
    if not rwy then ac.timer = 30 return end
    ac.rwy = rwy
    startTaxi(ac, rwy.x, rwy.y, "taxi_out")
end

-- at the threshold: lined up (waits for the take-off clearance) or rolling
local function tickTaxiOut(ac, dt)
    if taxiStep(ac, dt, "taxi_out") == true then
        ac.hdg, ac.spd = ac.rwy.hdg, 0
        ac.onRwy = ac.rwy.runway
        if ac.toClr then ac.phase = "takeoff" else ac.phase, ac.timer = "lined", 3 end
    end
end

-- holding short. Uncontrolled: crosses / lines up / backtracks when the runway is free.
local function tickHold(ac, dt)
    ac.timer = ac.timer - dt
    ac.spd = 0
    if controlled(ac) then
        if not ac.rwyClr[ac.holdRwy] then return end
    else
        if ac.timer > 0 or runwayBusy(ac, ac.gndApt, ac.holdRwy) then return end
        ac.rwyClr[ac.holdRwy] = true
        if ac.holdKind ~= "CROSS" then ac.toClr = true end
    end
    ac.phase = ac.holdResume
end

local function tickLined(ac, dt)
    ac.timer = ac.timer - dt
    ac.spd = 0
    if controlled(ac) then
        if not ac.toClr then return end
    elseif ac.timer > 0 then
        return
    end
    ac.phase = "takeoff"
end

local function takeOffClearance(ac)
    -- the level of the IFR clearance; without one: the standard initial climb under control, or cruise
    if ac.initAlt then
        ac.cfl = ac.initAlt
    elseif controllerOf(ac) then
        ac.cfl = math.min(ac.cruise, TR.INITIAL_CLIMB)
    else
        ac.cfl = ac.cruise
    end
end

local function tickTakeoff(ac, dt)
    local vr = (ac.perf.approach or 140) + 10
    speedTowards(ac, vr + 20, TR.ACCEL_ROLL, dt)
    moveForward(ac, dt)
    if ac.spd >= vr then
        -- the SID of the IFR clearance (for the runway actually used), or the pilots' own choice
        if ac.sid ~= false and ac.rwy then
            local sid = ac.sid or (suggestedSID(ac) or {}).id
            if sid then applySID(ac, sid, ac.rwy.ident) end
        end
        ac.phase = "air"
        ac.climbOut = true
        ac.rwy, ac.onRwy, ac.rwyClr = nil, nil, {}
        takeOffClearance(ac)
    end
end

-- landing roll down to runway taxi speed, then off at the exit the controller named (if still
-- ahead), else the first one ahead
local function chooseExit(ac)
    local a = airport(ac.gndApt)
    local e = ac.rwy
    local r = a and e and runwayById(a, e.runway)
    if not r then return end
    local h = math.rad(e.hdg)
    local hx, hy = math.sin(h), math.cos(h)
    local cur = (ac.x - e.x) * hx + (ac.y - e.y) * hy
    local named, first, firstD, last, lastD
    for _, x in ipairs(runwayExits(a, e.runway)) do
        local along = (x.x - e.x) * hx + (x.y - e.y) * hy - cur
        if along >= -5 then
            if x.tw == ac.vacateVia and (not named or along < named.along) then named = x named.along = along end
            -- exits towards the terminal first (the others mean crossing the runway again)
            local score = along + (x.toTerminal and 0 or 300)
            if not firstD or score < firstD then first, firstD = x, score end
        end
        if not lastD or along > lastD then last, lastD = x, along end
    end
    return named or first or last
end

local function tickLanding(ac, dt)
    if not ac.exit then
        speedTowards(ac, TR.RWY_TAXI_KTS, TR.DECEL_ROLL, dt)
        ac.alt, ac.vs = fieldElev(ac), 0
        moveForward(ac, dt)
        if ac.spd <= TR.RWY_TAXI_KTS + 0.5 then
            local x = chooseExit(ac)
            if not x then
                ac.phase, ac.spd, ac.timer = "vacated", 0, 3
                return
            end
            ac.exit = x
            ac.path, ac.pi = { { x.x, x.y }, { x.cx, x.cy } }, 1
            ac.phase = "vacate"
        end
    end
end

local function tickVacate(ac, dt)
    local r = taxiStep(ac, dt, "vacate")
    if r == true then
        ac.phase, ac.spd, ac.timer = "vacated", 0, 3
        ac.rwy, ac.exit = nil, nil
    end
end

-- off the runway: waits for the taxi clearance to a stand (the controller may name the stand)
local function tickVacated(ac, dt)
    ac.timer = ac.timer - dt
    if controlled(ac) then
        if not ac.taxiInClr then return end
    elseif ac.timer > 0 then
        return
    end
    local a = airport(ac.gndApt)
    local g
    if ac.taxiGate and not gateOccupied(a.icao, ac.taxiGate, ac) then
        for _, gt in ipairs(a.gates) do if gt.id == ac.taxiGate then g = gt end end
    end
    g = g or freeGate(a, ac)
    ac.gate = g and g.id
    local tx, ty
    if g then tx, ty = g.x, g.y else tx, ty = a.arp[1], a.arp[2] end
    startTaxi(ac, tx, ty, "taxi_in")
end

local function tickTaxiIn(ac, dt)
    if taxiStep(ac, dt, "taxi_in") == true then
        ac.phase, ac.spd, ac.timer = "parked", 0, TR.PARK_TIME
        local a = airport(ac.gndApt)
        if a and ac.gate then
            for _, g in ipairs(a.gates) do
                if g.id == ac.gate then ac.hdg = tonumber(g.hdg) or ac.hdg end
            end
        end
    end
end

local function tickParked(ac, dt)
    ac.timer = ac.timer - dt
    if ac.timer <= 0 then removeAircraft(ac, "parked") end
end

-- ---------------------------------------------------------------- air
-- remaining track distance from the aircraft over its plan to the final fix of its arrival runway
local function distanceToFinal(ac, finalFix)
    local d, px, py = 0, ac.x, ac.y
    if ac.dct then
        local p = navPoint(ac.dct)
        if p then d, px, py = d + dist(px, py, p.x, p.y), p.x, p.y end
    end
    for i = ac.ri, #ac.route do
        local p = navPoint(ac.route[i])
        if p then d, px, py = d + dist(px, py, p.x, p.y), p.x, p.y end
    end
    if finalFix then d = d + dist(px, py, finalFix.x, finalFix.y) end
    return d
end

local function arrivalFinal(ac)
    local rwy = ac.arrRwy and callExport("avi_airports", "getRunwayEnd", ac.arr, ac.arrRwy)
        or callExport("avi_airports", "getActiveRunway", ac.arr, "arr")
    return rwy, rwy and navPoint(rwy.final)
end

-- automatic (pilot own) cleared level: only while no controller has the aircraft
function trafficAutoLevel(ac)
    local apt = airport(ac.arr)
    if not apt then return ac.cruise end
    local _, ff = arrivalFinal(ac)
    local need = apt.elevation + TR.FINAL_AGL + distanceToFinal(ac, ff) * TR.DESCENT_FT_PER_M
    local lvl = math.floor(need / 500) * 500
    return clamp(lvl, apt.elevation + TR.FINAL_AGL, ac.cruise)
end

local function verticalTowards(ac, target, dt)
    local diff = target - ac.alt
    local vs = clamp(diff * 6, -(ac.perf.descent or 1800), ac.perf.climb or 2000)
    if math.abs(diff) < 5 then vs = 0 ac.alt = target end
    ac.vs = vs
    ac.alt = ac.alt + vs / 60 * dt
end

-- go-around: runway heading past the field, then a new approach from the side
local function goAround(ac)
    local e = ac.rwy
    local h = math.rad(e.hdg)
    local apt = airport(ac.arr)
    ac.phase = "air"
    ac.missed = true
    ac.landClr, ac.vacateVia = nil, nil
    ac.via = { { x = e.x + math.sin(h) * 1500, y = e.y + math.cos(h) * 1500 } }
    ac.cfl = math.max(ac.cfl or 0, (apt and apt.elevation or 0) + TR.MISSED_ALT_AGL)
    ac.approach = nil
    ac.rwy = nil
    -- the rest of the STAR is gone: a new approach from the missed approach point
    ac.ri = #ac.route + 1
    ac.proc, ac.star, ac.procEnd = nil, nil, nil
    ac.starTried = true
end

function trafficGoAround(ac) goAround(ac) end

-- approach set-up: a base point when the aircraft is on the airport side of the final fix
local function startApproach(ac)
    local rwy, ff = arrivalFinal(ac)
    if not rwy or not ff then return false end
    ac.rwy = rwy
    ac.approach = ff
    ac.via = ac.via or {}
    local h = math.rad(rwy.hdg)
    local ux, uy = math.sin(h), math.cos(h)
    local rx, ry = ac.x - ff.x, ac.y - ff.y
    if rx * ux + ry * uy > -200 then
        local side = (rx * uy - ry * ux) >= 0 and 1 or -1      -- + = right of the landing direction
        local nx, ny = uy * side, -ux * side
        local bx, by = ff.x - ux * 400 + nx * 800, ff.y - uy * 400 + ny * 800
        -- finals near the map edge: keep the base point inside the CTA
        local minx, miny, maxx, maxy = ctaBox()
        ac.via[#ac.via + 1] = { x = clamp(bx, minx + 100, maxx - 100), y = clamp(by, miny + 100, maxy - 100) }
    end
    return true
end

-- current navigation target {x, y}, kind
local function navTarget(ac)
    if ac.via and ac.via[1] then return ac.via[1], "via" end
    if ac.dct then
        local p = navPoint(ac.dct)
        if p then return p, "dct" end
        ac.dct = nil
    end
    while ac.ri <= #ac.route do
        local p = navPoint(ac.route[ac.ri])
        if p then
            -- a final fix of the destination in the route (end of a STAR): the approach to that runway
            if p.kind == "final" and p.airport == ac.arr and airport(ac.arr) then
                if not (ac.rwy and ac.rwy.final == p.id) then
                    ac.rwy = callExport("avi_airports", "getRunwayEnd", ac.arr, p.runway)
                end
                if ac.rwy then
                    ac.approach = p
                    return p, "final"
                end
            end
            return p, "route"
        end
        ac.ri = ac.ri + 1      -- unknown fix (e.g. a deleted VOR): skip it
    end
    if airport(ac.arr) then
        if not ac.approach and not startApproach(ac) then return nil, "none" end
        if ac.via and ac.via[1] then return ac.via[1], "via" end
        return ac.approach, "final"
    end
    return nil, "exit"
end

local function passed(ac, kind)
    if kind == "via" then
        table.remove(ac.via, 1)
    elseif kind == "dct" then
        for i = ac.ri, #ac.route do
            if ac.route[i] == ac.dct then ac.ri = i + 1 break end
        end
        ac.dct = nil
    elseif kind == "route" then
        ac.ri = ac.ri + 1
    end
    -- SID flown to its exit fix: back to the flight plan
    if ac.sid and ac.procEnd and ac.ri > ac.procEnd and not ac.star then
        ac.proc, ac.procEnd = nil, nil
    end
end

local function targetSpeed(ac, kind, target)
    local p = ac.perf
    local s = p.cruise or 280
    if ac.alt < TR.SPEED_LIMIT_ALT then s = math.min(s, 250) end
    if kind == "final" and target and dist(ac.x, ac.y, target.x, target.y) < TR.APPROACH_SLOW_DIST then
        s = math.min(s, (p.approach or 140) + 30)
    elseif (kind == "via" and ac.approach) then
        s = math.min(s, (p.approach or 140) + 30)
    end
    if ac.climbOut then s = math.min(s, (p.approach or 140) + 40) end
    return s
end

-- on a heading close to the extended centre line, flying roughly the runway direction: established
function interceptFinal(ac)
    if not airport(ac.arr) then return false end
    local rwy, ff = arrivalFinal(ac)
    if not rwy then return false end
    local h = math.rad(rwy.hdg)
    local ux, uy = math.sin(h), math.cos(h)
    local rx, ry = ac.x - rwy.x, ac.y - rwy.y
    local along = rx * ux + ry * uy
    local lateral = rx * uy - ry * ux
    local finalLen = ff and dist(ff.x, ff.y, rwy.x, rwy.y) or 1200
    if along < -250 and along > -finalLen * 1.8 and math.abs(lateral) < 250
            and math.abs(angleTo(ac.hdg, rwy.hdg)) < 60 then
        ac.ahdg, ac.dct, ac.via, ac.approach, ac.missed = nil, nil, nil, nil, nil
        ac.rwy = rwy
        ac.phase = "final"
        return true
    end
    return false
end

local function tickAir(ac, dt)
    local elev = fieldElev(ac)
    if ac.climbOut and ac.alt - elev >= TR.CLIMB_OUT_AGL then
        ac.climbOut = nil
        ac.gndApt = nil
    end

    -- radar vectors: fly the assigned heading, intercept the final of the arrival runway
    if ac.ahdg then
        turnTowards(ac, ac.ahdg, dt)
        speedTowards(ac, targetSpeed(ac, "route"), TR.ACCEL_AIR, dt)
        moveForward(ac, dt)
        if not controllerOf(ac) then ac.ahdg = nil end      -- nobody gives vectors any more
        verticalTowards(ac, ac.cfl or ac.alt, dt)
        interceptFinal(ac)
        local margin = airport(ac.arr) and TR.EXIT_MARGIN * 5 or TR.EXIT_MARGIN
        if not insideCTA(ac.x, ac.y, margin) then removeAircraft(ac, "left the CTA") end
        return
    end

    -- nobody controls it: the pilots fly the STAR of their entry fix to the runway in use
    if not ac.star and not ac.starTried and not ac.missed and not ac.climbOut and airport(ac.arr) and not controllerOf(ac) then
        local p = procedureFor(ac.arr, "STAR", remainingRoute(ac))
        local rwy = p and arrivalFinal(ac)
        if not (p and rwy and applySTAR(ac, p.id, rwy.ident)) then ac.starTried = true end
    end

    local target, kind = navTarget(ac)
    if kind == "exit" then
        removeAircraft(ac, "left the airspace")
        return
    end

    -- lateral
    if target and not ac.climbOut then
        turnTowards(ac, bearing(ac.x, ac.y, target.x, target.y), dt)
    end
    speedTowards(ac, targetSpeed(ac, kind, target), TR.ACCEL_AIR, dt)
    moveForward(ac, dt)

    -- vertical
    if not controllerOf(ac) and not ac.climbOut and not ac.missed then ac.cfl = trafficAutoLevel(ac) end
    verticalTowards(ac, ac.cfl or ac.alt, dt)

    -- fix passage: close enough, or close and already behind (would orbit it inside the turn radius)
    local td = target and not ac.climbOut and dist(ac.x, ac.y, target.x, target.y)
    if td and (td <= TR.FIX_PASS_DIST
            or (td < 400 and math.abs(angleTo(ac.hdg, bearing(ac.x, ac.y, target.x, target.y))) > 100)) then
        if kind == "final" then
            local glideAt = elev + TR.FINAL_AGL
            if ac.alt > glideAt + TR.GO_AROUND_MARGIN then
                goAround(ac)
            else
                ac.phase = "final"
                ac.missed = nil
            end
        else
            passed(ac, kind)
            if kind == "via" and ac.missed and #ac.via == 0 then
                ac.missed = nil      -- back on a normal approach (startApproach adds the base point)
            end
        end
    end

    -- outbound traffic is gone past the CTA edge; inbound ones may swing wide on a turn
    local margin = airport(ac.arr) and TR.EXIT_MARGIN * 5 or TR.EXIT_MARGIN
    if not insideCTA(ac.x, ac.y, margin) then removeAircraft(ac, "left the CTA") end
end

local function tickFinal(ac, dt)
    local e = ac.rwy
    local elev = fieldElev(ac)
    turnTowards(ac, bearing(ac.x, ac.y, e.x, e.y), dt, TR.TURN_RATE * 1.5)
    speedTowards(ac, ac.perf.approach or 140, TR.ACCEL_AIR, dt)
    moveForward(ac, dt)
    local final = navPoint(e.final)
    local finalLen = final and dist(final.x, final.y, e.x, e.y) or 1200
    local d = dist(ac.x, ac.y, e.x, e.y)
    local glide = elev + d * TR.FINAL_AGL / finalLen
    local old = ac.alt
    -- above the glide path: down at most 1.3x the normal descent rate; below it: level until it meets
    if ac.alt > glide then
        ac.alt = math.max(glide, ac.alt - (ac.perf.descent or 1800) * 1.3 / 60 * dt)
    end
    ac.alt = math.max(elev, ac.alt)
    ac.vs = (ac.alt - old) / dt * 60
    ac.cfl = nil
    -- decision point: too high, or no landing clearance from the controller = go-around
    if d < TR.LAND_DECISION_DIST and not ac.landClr then
        if ac.alt > glide + 300 or controlled(ac) then
            goAround(ac)
            return
        end
        ac.landClr = true
    end
    local h = math.rad(e.hdg)
    local along = (ac.x - e.x) * math.sin(h) + (ac.y - e.y) * math.cos(h)
    if d < 25 or along > 0 then
        ac.phase = "landing"
        ac.gndApt = ac.arr
        ac.onRwy = e.runway
        ac.rwyClr = { [e.runway] = true }
        ac.alt, ac.vs = elev, 0
        ac.hdg = e.hdg
        ac.approach = nil
        ac.proc, ac.procEnd = nil, nil
    end
end

local TICK = {
    gate = tickGate, pushback = tickPushback, pushed = tickPushed, vacate = tickVacate, vacated = tickVacated,
    lined = tickLined,
    taxi_out = tickTaxiOut, hold = tickHold, takeoff = tickTakeoff,
    air = tickAir, final = tickFinal, landing = tickLanding, taxi_in = tickTaxiIn, parked = tickParked,
}

local lastTick
local function tick()
    local now = getTickCount()
    local dt = lastTick and clamp((now - lastTick) / 1000, 0.2, 3) or TR.TICK / 1000
    lastTick = now
    refreshStaffing()
    for _, ac in pairs(AIRCRAFT) do
        ac.age = ac.age + dt
        local f = TICK[ac.phase]
        local ok, err = pcall(f, ac, dt)
        if not ok then
            outputDebugString(("[avi_traffic] %s (%s): %s"):format(ac.cs, tostring(ac.phase), tostring(err)), 1)
            removeAircraft(ac, "error")
        elseif AIRCRAFT[ac.id] then
            updateController(ac)
            if ac.age > TR.MAX_AGE then removeAircraft(ac, "timeout") end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(tick, TR.TICK, 0)
end)

-- ---------------------------------------------------------------- snapshot for the scope
local GROUND_DIR = { gate = "dep", pushback = "dep", pushed = "dep", taxi_out = "dep", lined = "dep", takeoff = "dep",
    landing = "arr", vacate = "arr", vacated = "arr", taxi_in = "arr", parked = "arr" }

-- the clearance the aircraft needs next (only matters when a controller has it); ready = waiting for it now
local function pendingClearance(ac)
    local p = ac.phase
    if p == "gate" then
        if not ac.ifr then return "IFR", ac.timer <= 0 end
        if not ac.pushClr then return "PUSH", true end
    elseif p == "pushback" or p == "pushed" then
        if not ac.taxiClr then return "TAXI", p == "pushed" end
    elseif p == "hold" then
        if ac.holdKind == "CROSS" then return "CROSS", true end
        if ac.holdKind == "BKTRK" then return "BKTRK", true end
        return "T/O", true
    elseif p == "lined" then
        if not ac.toClr then return "T/O", true end
    elseif p == "landing" or p == "vacate" or p == "vacated" then
        if not ac.taxiInClr then return "TAXI", p ~= "landing" end
    elseif (p == "final" or (p == "air" and (ac.approach or ac.ahdg))) and airport(ac.arr) and not ac.landClr then
        -- calls for the landing clearance on final / close to the final fix
        local ready = p == "final"
        if not ready and ac.approach then ready = dist(ac.x, ac.y, ac.approach.x, ac.approach.y) < TR.LAND_CALL_DIST end
        return "LAND", ready
    elseif p == "air" and airport(ac.arr) and not ac.star and not ac.missed and not ac.climbOut
            and ac.ctl and (ac.ctl == TR.CENTER_POSITION or ac.ctl:sub(-4) == "_APP") then
        -- close to its TMA entry fix without an arrival procedure (only approach / radar can give one)
        local sp = suggestedSTAR(ac)
        local f = sp and navPoint(sp.fix)
        if f and not ac.ahdg and dist(ac.x, ac.y, f.x, f.y) < TR.STAR_CALL_DIST then return "STAR", true end
    end
end

local function round(v, step) return math.floor(v / step + 0.5) * step end

function snapshot(ac)
    local remaining = {}
    for i = ac.ri, #ac.route do remaining[#remaining + 1] = ac.route[i] end
    local req, ready = pendingClearance(ac)
    -- ground direction: a holding aircraft keeps the one of the phase it holds in
    local dir = GROUND_DIR[ac.phase] or (ac.phase == "hold" and GROUND_DIR[ac.holdResume]) or nil
    return {
        id = ac.id, cs = ac.cs, type = ac.type, wake = ac.wake, dep = ac.dep, arr = ac.arr,
        x = math.floor(ac.x * 10 + 0.5) / 10, y = math.floor(ac.y * 10 + 0.5) / 10,
        alt = round(ac.alt, 10), hdg = math.floor(ac.hdg + 0.5) % 360, spd = round(ac.spd, 1),
        vs = round(ac.vs, 50), cfl = ac.cfl and round(ac.cfl, 100) or nil, dct = ac.dct, sqk = ac.sqk,
        gnd = isGround(ac), dir = dir, phase = ac.phase, ctl = ac.ctl,
        apt = isGround(ac) and ac.gndApt or nil, gate = ac.gate, route = remaining,
        rwy = ac.rwy and ac.rwy.ident or nil, ahdg = ac.ahdg,
        rfl = ac.cruise, rfirst = ac.plan[1], rlast = ac.plan[#ac.plan], proc = ac.proc,
        sugSid = not ac.ifr and isGround(ac) and ac.gndApt == ac.dep and (suggestedSID(ac) or {}).id or nil,
        sugStar = not isGround(ac) and not ac.star and (suggestedSTAR(ac) or {}).id or nil,
        holdRwy = ac.phase == "hold" and ac.holdRwy or nil, onRwy = ac.onRwy, vacateVia = ac.vacateVia,
        req = req, ready = ready or false,
        ifr = ac.ifr and true or false, initAlt = ac.initAlt, landClr = ac.landClr and true or false,
        -- world m/s along hdg (the scope extrapolates between updates)
        ws = math.floor(worldSpeed(ac) * 10 + 0.5) / 10,
    }
end
