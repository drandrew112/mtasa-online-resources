-- Traffic simulation. No vehicles are created: the aircraft exist only here and on the ATC scope.
-- Units: position = world metres, alt = feet, spd = knots, vs = feet / minute, hdg = compass deg
-- (0 = north = +y, 90 = east = +x).
--
-- Phases
--   ground departure: gate -> taxi_out -> hold -> takeoff -> air (climb-out on runway heading)
--   external entry  : air (spawned TR.ENTRY_LEAD_NM before the first route fix = the CTA border, at cruise level)
--   air             : DCT (controller) > flight plan fixes > approach (final fix) | exit (external)
--                     SID (avi_nav procedure) after take-off, STAR towards the arrival runway: from the
--                     controller (IFR clearance / arrival procedure) or, without one, picked by the pilots
--   final           : on the glide path to the threshold -> landing -> taxi_in -> parked -> removed
--   go-around       : final fix too high / no landing clearance -> the go-around procedure of the runway
--                     (avi_nav <ICAO>GA: opposite half final, circuit, final fix) at TR.GO_AROUND_ALT
--
-- Tutorial aircraft (server/tutorial.lua, ac.tut = the player): they fly in this simulation, but in a
-- world of their own. They never meet the live traffic (stands, taxi queues, runways, alerts), and
-- the live exports (snapshot, counts, callsigns) leave them out.

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

-- the live traffic and every tutorial session are separate worlds
local function sameWorld(a, b)
    return a.tut == b.tut
end

-- except: the aircraft asking (its world counts; nil = the live traffic)
local function gateOccupied(icao, gateId, except)
    local world = except and except.tut
    for _, ac in pairs(AIRCRAFT) do
        if ac ~= except and ac.tut == world and ac.gndApt == icao and ac.gate == gateId and isGround(ac) then return true end
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

-- assigned heading with a forced turn direction ("L" / "R"); the direction is dropped once the
-- heading is reached, so later corrections take the short way again
local function turnAssigned(ac, dt)
    local dir = ac.ahdgDir
    if not dir then return turnTowards(ac, ac.ahdg, dt) end
    local step = TR.TURN_RATE * dt
    local left = dir == "L" and (ac.hdg - ac.ahdg) % 360 or (ac.ahdg - ac.hdg) % 360
    if left <= step then
        ac.hdg = ac.ahdg % 360
        ac.ahdgDir = nil
    else
        ac.hdg = (ac.hdg + (dir == "L" and -step or step)) % 360
    end
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

-- live traffic only (tutorial aircraft have callsigns of their own world)
function isCallsignActive(cs)
    for _, ac in pairs(AIRCRAFT) do if ac.cs == cs and not ac.tut then return true end end
    return false
end

-- live traffic only (the traffic limits do not count tutorial aircraft)
function countActive()
    local n = 0
    for _, ac in pairs(AIRCRAFT) do
        if not ac.tut then n = n + 1 end
    end
    return n
end

-- returns aircraft or nil, reason
-- opts (tutorial.lua): tut = owner player, gateWait = s at the stand,
--   final = { x, y, hdg, alt, rwy = runway end } (airborne on the extended centre line of rwy)
function spawnFlight(fl, opts)
    opts = opts or {}
    if not opts.tut and isCallsignActive(fl.callsign) then return nil, "already active" end
    local ac = newAircraft(fl)
    ac.tut = opts.tut
    local depApt = not opts.final and airport(fl.dep)
    if opts.final then
        local f = opts.final
        ac.phase = "air"
        ac.x, ac.y, ac.hdg = f.x, f.y, f.hdg
        ac.alt, ac.cfl = f.alt, f.alt
        ac.arrRwy = f.rwy.ident
        ac.spd = math.min(250, (ac.perf.approach or 140) + 30)
    elseif depApt then
        local g = freeGate(depApt, ac)
        if not g then return nil, "no free gate at " .. fl.dep end
        ac.phase = "gate"
        ac.gndApt, ac.gate = depApt.icao, g.id
        ac.x, ac.y, ac.hdg = g.x, g.y, tonumber(g.hdg) or 0
        ac.alt = depApt.elevation
        ac.timer = opts.gateWait or math.random(TR.GATE_WAIT[1], TR.GATE_WAIT[2])
    else
        local first = navPoint(ac.route[1])
        if not first then return nil, "unknown entry fix " .. tostring(ac.route[1]) end
        local nxt = navPoint(ac.route[2]) or (airport(fl.arr) and { x = airport(fl.arr).arp[1], y = airport(fl.arr).arp[2] })
        ac.phase = "air"
        -- on the radar well before the border: TR.ENTRY_LEAD_NM out on the extended first leg, flying to the entry fix
        ac.hdg = nxt and bearing(first.x, first.y, nxt.x, nxt.y) or 0
        local lead, h = TR.ENTRY_LEAD_NM * TR.M_PER_NM, math.rad(ac.hdg)
        ac.x, ac.y = first.x - math.sin(h) * lead, first.y - math.cos(h) * lead
        ac.ri = 1
        ac.inbound = true      -- outside the CTA until it crosses the border (not removed meanwhile)
        -- inbound: enter no higher than the descent plan allows (short arrivals start lower), always
        -- on a whole thousand
        ac.alt = math.min(fl.cruise, trafficAutoLevel(ac) + 1000)
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
    ac.procStart, ac.procEnd = 1, #r
    ac.sid, ac.sidRwy = p.id, tostring(ident):upper()
    ac.proc = p.id .. " " .. ac.sidRwy
    return true
end

-- STAR: the remaining route up to the entry fix + the STAR to the final fix of `ident`. Fixes the
-- aircraft is already past are left out (the base + final fix always stay).
-- override (given by a controller): like a direct, the STAR replaces the whole flight plan, the
-- aircraft joins it at the first fix still ahead of it (no filed fixes before the entry fix).
function applySTAR(ac, starId, ident, override)
    local r = procedureRoute(starId, ident)
    local p = procedure(starId)
    if not r or not p or p.type ~= "STAR" then return false end
    local before, found = {}, false
    if not override then
        for i = ac.ri, #ac.route do
            if ac.route[i] == p.fix then found = true break end
            before[#before + 1] = ac.route[i]
        end
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
    ac.procStart, ac.procEnd = #before + 1, #ac.route
    ac.star, ac.arrRwy = p.id, tostring(ident):upper()
    ac.proc = p.id .. " " .. ac.arrRwy
    ac.ahdg, ac.dct, ac.via, ac.approach, ac.missed, ac.ga = nil, nil, nil, nil, nil, nil
    if override then
        ac.sid, ac.sidRwy, ac.starTried = nil, nil, nil
        if ac.climbOut then ac.climbOut, ac.gndApt = nil, nil end
    end
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

-- ---------------------------------------------------------------- taxi spacing
-- Taxiing aircraft keep TAXI_SEP behind anything on their path (queue at the holding point).
-- Only aircraft off the runways count and wait: the runway clearances separate the rest.
local TAXI_OBSTACLE = { pushback = true, pushed = true, taxi_out = true, taxi_in = true, vacate = true, vacated = true, hold = true }
local TAXI_MOVING = { taxi_out = true, taxi_in = true, vacate = true }

-- is (x, y) on ac's path within `len` m ahead (and not beside / behind the aircraft)?
local function onPathAhead(ac, x, y, len)
    if not ac.path then return false end
    local px, py, cum = ac.x, ac.y, 0
    for i = ac.pi, #ac.path do
        local q = ac.path[i]
        local d = dist(px, py, q[1], q[2])
        if d > 0.01 then
            local s = math.min(d, len - cum)
            local ex, ey = px + (q[1] - px) / d * s, py + (q[2] - py) / d * s
            local t = clamp(((x - px) * (ex - px) + (y - py) * (ey - py)) / (s * s), 0, 1)
            local cx, cy = px + (ex - px) * t, py + (ey - py) * t
            if cum + t * s > 2 and dist(x, y, cx, cy) < TR.TAXI_SEP_LAT then return true end
            cum = cum + s
            if cum >= len then return false end
            px, py = ex, ey
        end
    end
    return false
end

-- does the chain of waiting aircraft starting at o lead back to ac? (deadlock: ac goes on)
local function waitsFor(o, ac)
    for _ = 1, 10 do
        if not o.taxiWaitFor then return false end
        if o.taxiWaitFor == ac.id then return true end
        o = AIRCRAFT[o.taxiWaitFor]
        if not o then return false end
    end
    return false
end

-- the aircraft ac has to wait for, if any. Two aircraft that see each other (head-on, or meeting
-- at an intersection): the older one (lower id) goes first.
local function taxiBlocker(ac)
    if ac.onRwy then return nil end
    for _, o in pairs(AIRCRAFT) do
        if o ~= ac and sameWorld(o, ac) and o.gndApt == ac.gndApt and TAXI_OBSTACLE[o.phase] and not o.onRwy
                and dist(ac.x, ac.y, o.x, o.y) < TR.TAXI_SEP + 10 and onPathAhead(ac, o.x, o.y, TR.TAXI_SEP) then
            local mutual = TAXI_MOVING[o.phase] and onPathAhead(o, ac.x, ac.y, TR.TAXI_SEP)
            if not (mutual and ac.id < o.id) and not (TAXI_MOVING[o.phase] and waitsFor(o, ac)) then return o end
        end
    end
end

-- follows ac.path in small steps. Returns true at the end, "hold", runwayId before an
-- uncleared runway zone, false otherwise. 50 kts on a runway, 25 kts elsewhere.
local function followPath(ac, dt)
    local a = airport(ac.gndApt)
    ac.rwyClr = ac.rwyClr or {}
    local blocker = taxiBlocker(ac)
    ac.taxiWaitFor = blocker and blocker.id or nil
    if blocker then
        ac.spd = 0
        return false
    end
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
        if o ~= ac and sameWorld(o, ac) then
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

-- an uncontrolled aircraft does not push back while someone taxies / waits near its push-back end point
local function pushbackBlocked(ac)
    local saved = { ac.phase, ac.push }
    startPushback(ac)
    local p2 = ac.push.p2
    ac.phase, ac.push = saved[1], saved[2]
    for _, o in pairs(AIRCRAFT) do
        if o ~= ac and sameWorld(o, ac) and o.gndApt == ac.gndApt and TAXI_OBSTACLE[o.phase] and not o.onRwy
                and dist(o.x, o.y, p2[1], p2[2]) < TR.TAXI_SEP then return true end
    end
    return false
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
    if ac.timer > 0 or pushbackBlocked(ac) then return end
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
    if ac.tut then return end      -- the tutorial removes its own aircraft
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
    local lvl = math.floor(need / 1000) * 1000
    return clamp(lvl, apt.elevation + TR.FINAL_AGL, ac.cruise)
end

local function verticalTowards(ac, target, dt)
    local diff = target - ac.alt
    local vs = clamp(diff * 6, -(ac.perf.descent or 1800), ac.perf.climb or 2000)
    if math.abs(diff) < 5 then vs = 0 ac.alt = target end
    ac.vs = vs
    ac.alt = ac.alt + vs / 60 * dt
end

-- go-around: the go-around procedure of the runway (avi_nav <ICAO>GA): straight ahead to the half
-- final of the opposite end, round the circuit (parallel fixes) and back to the final fix, climbing to
-- TR.GO_AROUND_ALT. Pilots on their own keep that level until only the base + final fix are left, then
-- descend for the new approach; a controller has to clear them lower. Without a procedure: runway
-- heading past the field, then a new approach from the side.
local function goAround(ac)
    local e = ac.rwy
    ac.phase = "air"
    ac.missed = true
    ac.landClr, ac.vacateVia, ac.appClr = nil, nil, nil
    ac.ahdg, ac.ahdgDir, ac.dct = nil, nil, nil
    ac.cfl = TR.GO_AROUND_ALT
    ac.approach = nil
    ac.rwy = nil
    ac.proc, ac.star, ac.sid, ac.procStart, ac.procEnd, ac.ga = nil, nil, nil, nil, nil, nil
    ac.starTried = true
    local route, gaId = goAroundRoute(ac.arr, e.ident)
    if route then
        ac.via = nil
        ac.route, ac.ri = route, 1
        ac.procStart, ac.procEnd = 1, #route
        ac.ga, ac.arrRwy = gaId, e.ident
        ac.proc = "GA " .. e.ident
        return
    end
    local h = math.rad(e.hdg)
    ac.via = { { x = e.x + math.sin(h) * 1500, y = e.y + math.cos(h) * 1500 } }
    -- the rest of the STAR is gone: a new approach from the missed approach point
    ac.ri = #ac.route + 1
end

function trafficGoAround(ac) goAround(ac) end

-- approach set-up: a base point when the aircraft is on the airport side of the final fix
-- (rwy / ff: that runway end and its final fix, default = the arrival runway)
local function startApproach(ac, rwy, ff)
    if not rwy then rwy, ff = arrivalFinal(ac) end
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

-- the point flown to after the current target (nil when not known yet, e.g. before the approach set-up)
local function nextTarget(ac, kind)
    if kind == "final" then return ac.rwy end
    if kind == "via" then return ac.via[2] or ac.approach end
    local i = ac.ri
    if kind == "dct" then
        for j = ac.ri, #ac.route do
            if ac.route[j] == ac.dct then i = j + 1 break end
        end
    elseif kind == "route" then
        i = ac.ri + 1
    end
    for j = i, #ac.route do
        local p = navPoint(ac.route[j])
        if p then return p end
    end
end

-- distance at which the target counts as passed. Fly-over fixes (fix flag `flyover`, or listed in the
-- procedure's `flyover`): right over the fix, the turn starts after it. Every other point is fly-by:
-- the turn to the next leg starts this far before it, so the turn circle (radius = world speed / turn
-- rate) touches both legs instead of overshooting the next one.
local function passDistance(ac, kind, target)
    if kind == "route" or kind == "dct" then
        if target.flyover or isFlyover(ac.sid, target.id) or isFlyover(ac.star, target.id) then
            return TR.FLYOVER_PASS_DIST
        end
    end
    local nxt = nextTarget(ac, kind)
    if not nxt then return TR.FIX_PASS_DIST end
    local turn = math.abs(angleTo(ac.hdg, bearing(target.x, target.y, nxt.x, nxt.y)))
    local radius = worldSpeed(ac) / math.rad(TR.TURN_RATE)
    return math.max(TR.FIX_PASS_DIST, radius * math.tan(math.rad(math.min(turn, TR.FLYBY_MAX_TURN) / 2)))
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
    if ac.climbOut or ac.ga then s = math.min(s, (p.approach or 140) + 40) end
    return s
end

-- approach clearance: an uncontrolled aircraft (pilots on their own) always has it
function approachCleared(ac)
    return ac.appClr or ac.landClr or not controlled(ac) or false
end

-- does the radar heading intercept the extended centre line of this runway end ahead of the threshold,
-- at most TR.APP_CLR_ANGLE deg, within TR.APP_CLR_FAR final lengths? true, or false + the reason
local function headingIntercepts(ac, rwy, ff)
    local hdg = ac.ahdg
    local h = math.rad(rwy.hdg)
    local ux, uy = math.sin(h), math.cos(h)
    local rx, ry = ac.x - rwy.x, ac.y - rwy.y
    local along = rx * ux + ry * uy
    local lateral = rx * uy - ry * ux
    local finalLen = ff and dist(ff.x, ff.y, rwy.x, rwy.y) or 1200
    local ang = math.abs(angleTo(hdg, rwy.hdg))
    if ang > TR.APP_CLR_ANGLE then
        return false, ("intercept angle %d deg, max %d"):format(math.floor(ang + 0.5), TR.APP_CLR_ANGLE)
    end
    if along > -250 then return false, "already past the final" end
    if math.abs(lateral) >= 250 then
        local v = math.rad(hdg)
        local vx, vy = math.sin(v), math.cos(v)
        local latv, alv = vx * uy - vy * ux, vx * ux + vy * uy
        if latv * lateral >= 0 then return false, "heading does not intercept the centre line" end
        local at = along + (-lateral / latv) * alv      -- along-track position where the heading meets the centre line
        if at > -250 then return false, "intercepts too late (past the threshold)" end
        if at < -finalLen * TR.APP_CLR_FAR then return false, "intercept too far from the runway" end
    elseif along < -finalLen * TR.APP_CLR_FAR then
        return false, "too far from the runway"
    end
    return true
end

-- runway ends (with a final fix) of the arrival airport: { {rwy, ff}, ... }
local function arrivalEnds(ac)
    local out = {}
    local apt = airport(ac.arr)
    for _, rw in ipairs(apt and apt.runways or {}) do
        for _, e in ipairs(rw.ends or {}) do
            local ff = e.final and navPoint(e.final)
            if ff then out[#out + 1] = { e, ff } end
        end
    end
    return out
end

-- the runway end whose final the radar heading intercepts (the arrival runway first), or nil
local function interceptedFinal(ac)
    local rwy, ff = arrivalFinal(ac)
    if rwy and headingIntercepts(ac, rwy, ff) then return rwy end
    for _, r in ipairs(arrivalEnds(ac)) do
        if headingIntercepts(ac, r[1], r[2]) then return r[1] end
    end
end

-- the runway end of the arrival airport with the nearest final fix: rwy, ff, distance (m)
local function nearestFinal(ac)
    local best, bestFf, bestD
    for _, r in ipairs(arrivalEnds(ac)) do
        local d = dist(ac.x, ac.y, r[2].x, r[2].y)
        if not bestD or d < bestD then best, bestFf, bestD = r[1], r[2], d end
    end
    return best, bestFf, bestD
end

-- "cleared approach" (airborne arrival, no arrival procedure needed):
--   on a STAR / go-around procedure / already heading for a final fix: it flies that one on
--   radar heading intercepting a final (APP_CLR_ANGLE, APP_CLR_FAR): it keeps the heading and intercepts
--   anything else: direct to the nearest final fix of the destination (with a base point when it is on
--   the airport side of it), the rest of the route / heading is dropped
function clearApproach(ac)
    if ac.phase ~= "air" then return false, "not airborne / already on final" end
    if not airport(ac.arr) then return false, "not an arrival" end
    if ac.ahdg then
        local e = interceptedFinal(ac)
        if e then
            ac.arrRwy, ac.appClr = e.ident, true
            return true
        end
    elseif ac.star or ac.approach or ac.ga then
        ac.appClr = true
        return true
    end
    local rwy, ff = nearestFinal(ac)
    if not rwy then return false, "no final fix at " .. ac.arr end
    ac.ahdg, ac.ahdgDir, ac.dct, ac.via, ac.approach, ac.missed, ac.ga = nil, nil, nil, nil, nil, nil, nil
    ac.ri = #ac.route + 1
    ac.star, ac.procStart, ac.procEnd, ac.starTried = nil, nil, nil, true
    ac.arrRwy = rwy.ident
    ac.rwy = rwy
    ac.proc = ff.id
    startApproach(ac, rwy, ff)
    ac.approach = ff
    ac.appClr = true
    return true
end

-- on a heading close to the extended centre line, flying roughly the runway direction: established
function interceptFinal(ac)
    if not airport(ac.arr) then return false end
    if not approachCleared(ac) then return false end      -- no approach clearance: flies through the centre line
    local rwy, ff = arrivalFinal(ac)
    if not rwy then return false end
    local h = math.rad(rwy.hdg)
    local ux, uy = math.sin(h), math.cos(h)
    local rx, ry = ac.x - rwy.x, ac.y - rwy.y
    local along = rx * ux + ry * uy
    local lateral = rx * uy - ry * ux
    local finalLen = ff and dist(ff.x, ff.y, rwy.x, rwy.y) or 1200
    if along < -250 and along > -finalLen * (ac.appClr and TR.APP_CLR_FAR or 1.8) and math.abs(lateral) < 250
            and math.abs(angleTo(ac.hdg, rwy.hdg)) < 60 then
        ac.ahdg, ac.dct, ac.via, ac.approach, ac.missed = nil, nil, nil, nil, nil
        ac.ga, ac.proc = nil, nil
        ac.rwy = rwy
        ac.phase = "final"
        return true
    end
    return false
end

-- outbound traffic is gone past the CTA edge; arrivals may swing wide on a turn. A new entry is
-- outside until it crosses the border (spawned TR.ENTRY_LEAD_NM before it).
function checkLeftCTA(ac)
    if ac.inbound then
        if insideCTA(ac.x, ac.y, 0) then ac.inbound = nil end
        return
    end
    local margin = airport(ac.arr) and TR.EXIT_MARGIN * 5 or TR.EXIT_MARGIN
    if not insideCTA(ac.x, ac.y, margin) then removeAircraft(ac, "left the CTA") end
end

local function tickAir(ac, dt)
    local elev = fieldElev(ac)
    if ac.climbOut and ac.alt - elev >= TR.CLIMB_OUT_AGL then
        ac.climbOut = nil
        ac.gndApt = nil
    end

    -- radar vectors: fly the assigned heading, intercept the final of the arrival runway
    if ac.ahdg then
        ac.navTgt = nil
        turnAssigned(ac, dt)
        speedTowards(ac, targetSpeed(ac, "route"), TR.ACCEL_AIR, dt)
        moveForward(ac, dt)
        if not controllerOf(ac) then ac.ahdg = nil end      -- nobody gives vectors any more
        verticalTowards(ac, ac.cfl or ac.alt, dt)
        interceptFinal(ac)
        checkLeftCTA(ac)
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

    ac.navTgt = not ac.climbOut and target or nil     -- route deviation check (alerts.lua)

    -- climbing out on runway heading over a SID fix on the centre line (e.g. the half final of the
    -- opposite end): it counts as passed once it is behind, the aircraft does not turn back for it
    if ac.climbOut and kind == "route" and target
            and math.abs(angleTo(ac.hdg, bearing(ac.x, ac.y, target.x, target.y))) > 90 then
        passed(ac, kind)
        target, kind = navTarget(ac)
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
    if td and (td <= passDistance(ac, kind, target)
            or (td < 400 and math.abs(angleTo(ac.hdg, bearing(ac.x, ac.y, target.x, target.y))) > 100)) then
        if kind == "final" and not approachCleared(ac) then
            -- no approach clearance at the final fix: it flies on, the controller has to vector it
            ac.ahdg, ac.ahdgDir = math.floor(ac.hdg + 0.5) % 360, nil
            if ac.ahdg == 0 then ac.ahdg = 360 end
            ac.approach, ac.via, ac.ri = nil, nil, #ac.route + 1
            ac.proc, ac.star, ac.ga, ac.procEnd, ac.starTried = nil, nil, nil, nil, true
        elseif kind == "final" then
            local glideAt = elev + TR.FINAL_AGL
            if ac.alt > glideAt + TR.GO_AROUND_MARGIN then
                goAround(ac)
            else
                ac.phase = "final"
                ac.missed, ac.ga, ac.proc = nil, nil, nil
            end
        else
            passed(ac, kind)
            if kind == "via" and ac.missed and #ac.via == 0 then
                ac.missed = nil      -- back on a normal approach (startApproach adds the base point)
            end
            -- go-around circuit: past the parallel fix only the base + final fix are left, the own
            -- descent for the new approach starts (without a controller)
            if ac.ga and ac.missed and #ac.route - ac.ri < 2 then ac.missed = nil end
        end
    end

    checkLeftCTA(ac)
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
        ac.approach, ac.appClr = nil, nil
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
    updateAlerts(dt)
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
    elseif p == "air" and airport(ac.arr) and (ac.approach or ac.ahdg) and not ac.appClr and not ac.landClr then
        -- calls for the approach clearance close to the final fix / when the vectors intercept the final
        local ready = false
        if ac.approach then ready = dist(ac.x, ac.y, ac.approach.x, ac.approach.y) < TR.APP_CALL_DIST
        elseif ac.ahdg then
            local _, _, d = nearestFinal(ac)
            ready = interceptedFinal(ac) ~= nil or (d ~= nil and d < TR.APP_CALL_DIST)
        end
        return "APP", ready
    elseif (p == "final" or (p == "air" and (ac.approach or ac.ahdg))) and airport(ac.arr) and not ac.landClr then
        -- calls for the landing clearance on final / close to the final fix
        local ready = p == "final"
        if not ready and ac.approach then ready = dist(ac.x, ac.y, ac.approach.x, ac.approach.y) < TR.LAND_CALL_DIST end
        return "LAND", ready
    elseif p == "air" and airport(ac.arr) and not ac.star and not ac.missed and not ac.climbOut
            and ac.ctl and (isCenterPosition(ac.ctl) or ac.ctl:sub(-4) == "_APP") then
        -- close to its TMA entry fix without an arrival procedure (only approach / radar can give one)
        local sp = suggestedSTAR(ac)
        local f = sp and navPoint(sp.fix)
        if f and not ac.ahdg and dist(ac.x, ac.y, f.x, f.y) < TR.STAR_CALL_DIST then return "STAR", true end
    end
end

local function round(v, step) return math.floor(v / step + 0.5) * step end

-- deg / s in the air (the controller scope draws the turn preview with it)
function getTurnRate()
    return TR.TURN_RATE
end

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
        rwy = ac.rwy and ac.rwy.ident or nil, ahdg = ac.ahdg, ahdgDir = ac.ahdg and ac.ahdgDir or nil,
        rfl = ac.cruise, rfirst = ac.plan[1], rlast = ac.plan[#ac.plan], proc = ac.proc,
        sugSid = not ac.ifr and isGround(ac) and ac.gndApt == ac.dep and (suggestedSID(ac) or {}).id or nil,
        sugStar = not isGround(ac) and not ac.star and (suggestedSTAR(ac) or {}).id or nil,
        holdRwy = ac.phase == "hold" and ac.holdRwy or nil, onRwy = ac.onRwy, vacateVia = ac.vacateVia,
        req = req, ready = ready or false, alert = ac.alert,
        ifr = ac.ifr and true or false, initAlt = ac.initAlt, landClr = ac.landClr and true or false, appClr = ac.appClr and true or false,
        -- world m/s along hdg (the scope extrapolates between updates)
        ws = math.floor(worldSpeed(ac) * 10 + 0.5) / 10,
    }
end
