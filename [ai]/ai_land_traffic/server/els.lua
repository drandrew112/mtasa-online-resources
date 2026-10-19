-- Reaction to emergency vehicles (server). A vehicle counts while its v_els emergency lights are on
-- (elementData TRAFFIC.ELS_DATA == true). Every driver in range notices it with some chance per update:
--   level 1, lights only: small chance (ELS_NOTICE_LIGHTS) -> slows down, makes some room
--   level 2, siren (sirenState / sirenHorn): high chance (ELS_NOTICE_SIREN) -> pulls over, stops when close
--
-- Where the emergency vehicle goes comes from navmesh (server/navmesh.lua):
--   * with a destination (v_radar gpsDestination on the vehicle, or setEmergencyDestination) its navmesh route
--     (emergency profile) is followed: only traffic on that route gives way, and cross traffic only waits at
--     junctions where the route crosses its path
--   * without one its lane is snapped and the road ahead is predicted (straight on where possible)
--   * no lane (off-road, navmesh off): the old straight-line test (ahead within ELS_RANGE, 14 m to the side)
-- Reactions of a driver who noticed it:
--   same direction, ahead of it on its route: back into the outer lane (multi-lane roads), then aside as far as
--     the ground next to the lane allows (navmesh walk grid: no wall, drop, water or steep slope), slow down /
--     stop. No room here (bridge, walls): turn off into a side road on the right if one is close and not on the
--     emergency route, otherwise drive on (ELS_SEEK_SPEED) to the next place with room
--   oncoming on the same road: slow down and keep right
--   cross traffic: do not enter a junction it is approaching (sim.lua gate)
--   standing emergency vehicle: pass slowly (overtaking is handled by the obstacle logic)

Els = { active = {}, list = {}, routes = {}, dest = {} }
-- active: [vehicle] = true; list: snapshot { el, x, y, z, fx, fy, speed, moving, level, path }
-- routes: [vehicle] = Navmesh.track state; dest: [vehicle] = { x, y, z } (export, wins over gpsDestination)
-- path = { lanes = { [segment code] = distance of its start from the vehicle }, links = { [link] = true },
--          nodes = { [node] = { dist, conns = { [conn] = true } } }, gps = bool }

local E = Els
local T = TRAFFIC
local sqrt, sin, cos, rad, deg, exp, random, floor, abs, max, atan2 =
    math.sqrt, math.sin, math.cos, math.rad, math.deg, math.exp, math.random, math.floor, math.abs, math.max, math.atan2
local UPDATE = 0.25   -- s between Els.update calls (main.lua)

local function sirenOn(veh)
    for _, key in ipairs(T.ELS_SIREN_DATA) do
        if getElementData(veh, key) == true then return true end
    end
    return false
end

local function consider(veh)
    if isElement(veh) and getElementType(veh) == "vehicle" and getElementData(veh, T.ELS_DATA) == true then
        E.active[veh] = true
    else
        E.active[veh] = nil
        E.routes[veh] = nil
    end
end

function Els.init()
    for _, veh in ipairs(getElementsByType("vehicle")) do consider(veh) end
    addEventHandler("onElementDataChange", root, function(key)
        if key == T.ELS_DATA then consider(source) end
    end)
    addEventHandler("onElementDestroy", root, function()
        E.active[source], E.routes[source], E.dest[source] = nil, nil, nil
    end)
end

------------------------------------------------------------------------ the emergency vehicle's path (navmesh)

local function addLane(P, id, d)
    local cur = P.lanes[id]
    if cur and cur <= d then return end
    P.lanes[id] = d
    P.links[Net.llink[id] or 0] = true
    -- it may drive in any lane of the carriageway
    for _, side in ipairs({ "lleft", "lright" }) do
        local n, guard = Net[side][id], 0
        while n and guard < 6 do
            if not P.lanes[n] or P.lanes[n] > d then P.lanes[n] = d end
            n, guard = Net[side][n], guard + 1
        end
    end
end

-- connection c taken at distance d (the lane end): junction record + curve segment; returns the next lane's start
local function addConn(P, c, d)
    local node = Net.cnode[c]
    if node then
        local pn = P.nodes[node]
        if not pn then pn = { dist = d, conns = {} }; P.nodes[node] = pn end
        pn.conns[c] = true
        if d < pn.dist then pn.dist = d end
    end
    if Geo.isCurve(c) then
        if not P.lanes[-c] or P.lanes[-c] > d then P.lanes[-c] = d end
        return d + Geo.length(-c)
    end
    return d
end

local function destinationOf(veh)
    local d = E.dest[veh]
    if d then return d[1], d[2], d[3] end
    local g = getElementData(veh, "gpsDestination")
    if type(g) == "table" and tonumber(g[1]) and tonumber(g[2]) then return tonumber(g[1]), tonumber(g[2]), nil end
    return nil
end

local function pathOf(e, now)
    if not Navmesh.ok then return nil end
    local veh = e.el
    local rz = (deg(atan2(-e.fx, e.fy))) % 360
    local P = { lanes = {}, links = {}, nodes = {}, gps = false }
    local dx, dy, dz = destinationOf(veh)
    if dx then
        local t = E.routes[veh]
        if not t or t.dx ~= dx or t.dy ~= dy then
            t = { dx = dx, dy = dy }
            E.routes[veh] = t
        end
        local i, s = Navmesh.track(t, e.x, e.y, e.z, rz, dx, dy, dz, "emergency", now, T.ELS_GPS_RETRY)
        if i then
            local lanes, conns = t.lanes, t.conns
            local d = -s
            for k = i, #lanes do
                if d > T.ELS_PATH_LENGTH then break end
                local id = lanes[k]
                addLane(P, id, d)
                local c = conns[k + 1]
                if c then d = addConn(P, c, d + Geo.length(id)) end
            end
            P.gps = true
            return P
        end
    else
        E.routes[veh] = nil
    end
    -- no route (yet): the road ahead, straight on where possible
    local lane, s = Navmesh.laneAt(e.x, e.y, e.z, rz)
    if not lane then return nil end
    local queue, head = { { lane, -s } }, 1
    while queue[head] and head < 200 do
        local id, d = queue[head][1], queue[head][2]
        head = head + 1
        if not P.lanes[id] or P.lanes[id] >= d then
            addLane(P, id, d)
            local endD = d + Geo.length(id)
            if endD < T.ELS_PATH_LENGTH then
                local nexts, straight = Net.lnext[id] or {}, false
                for _, c in ipairs(nexts) do
                    if Net.cturn[c] == "S" then straight = true; break end
                end
                for _, c in ipairs(nexts) do
                    local turn = Net.cturn[c]
                    if (straight and turn == "S") or (not straight and turn ~= "U") then
                        queue[#queue + 1] = { Net.cto[c], addConn(P, c, endD) }
                    end
                end
            end
        end
    end
    return P
end

------------------------------------------------------------------------ snapshot

local movingUntil = {}   -- [vehicle] = tick: counts as moving a bit after slowing down (hysteresis)

local function snapshot(now)
    local list = {}
    for veh in pairs(E.active) do
        if isElement(veh) and getElementDimension(veh) == 0 and not Agents.byVeh[veh] then
            local x, y, z = getElementPosition(veh)
            local vx, vy = getElementVelocity(veh)
            vx, vy = vx * 50, vy * 50
            local speed = sqrt(vx * vx + vy * vy)
            local fx, fy
            if speed > 2 then
                fx, fy = vx / speed, vy / speed
            else
                local _, _, rz = getElementRotation(veh)
                fx, fy = -sin(rad(rz)), cos(rad(rz))
            end
            if speed > 1.5 then movingUntil[veh] = now + 3000 end
            local moving = (movingUntil[veh] or 0) > now
            local e = { el = veh, x = x, y = y, z = z, fx = fx, fy = fy, speed = speed, moving = moving,
                        level = sirenOn(veh) and 2 or 1 }
            e.path = pathOf(e, now)
            list[#list + 1] = e
        else
            E.active[veh] = nil
            E.routes[veh] = nil
            movingUntil[veh] = nil
        end
    end
    E.list = list
end

------------------------------------------------------------------------ pulling over

-- room next to the lane (navmesh walk grid): the largest ELS_PULL_STEPS offset where the car's centre and right
-- side stand on flat ground a few metres ahead (no wall / drop next to it, no water, no steep slope).
-- Cached per segment and 4 m of it (the map does not change).
local roomCache, roomCount = {}, 0
local chainBuf = {}

-- ground at (x, y) near the road height ref (the ground at the lane centre: lane z is GTA's node height, often
-- half a metre off the surface)
local function groundOK(x, y, z, ref)
    local gz, info = Navmesh.ground(x, y, z, 1.5)
    if not gz or abs(gz - ref) > T.ELS_GROUND_DZ then return false end
    return not (info.edge or info.steep or info.surface == "water")
end

local function shoulderRoom(ag)
    local plan = ag.plan
    local code = plan[1].code
    local bucket = floor(ag.s / 4)
    local c = roomCache[code]
    if c and c[bucket] then return c[bucket] end
    local n = #plan
    for i = 1, n do chainBuf[i] = plan[i].code end
    for i = n + 1, #chainBuf do chainBuf[i] = nil end
    local refs = {}
    for i, a in ipairs(T.ELS_PROBE_AHEAD) do
        local x, y, z = Geo.poseOnChain(chainBuf, n, ag.s + a, 0)
        refs[i] = x and (Navmesh.ground(x, y, z, 1.5) or z) or false
    end
    local room = 0
    for _, L in ipairs(T.ELS_PULL_STEPS) do
        local ok = true
        for i, a in ipairs(T.ELS_PROBE_AHEAD) do
            for _, off in ipairs({ L, L + T.ELS_CAR_HALF_WIDTH }) do
                local x, y, z = Geo.poseOnChain(chainBuf, n, ag.s + a, off)
                if not x or not refs[i] or not groundOK(x, y, z, refs[i]) then ok = false; break end
            end
            if not ok then break end
        end
        if ok then room = L; break end
    end
    if roomCount > 40000 then roomCache, roomCount = {}, 0 end
    if not roomCache[code] then roomCache[code] = {} end
    roomCache[code][bucket] = room
    roomCount = roomCount + 1
    return room
end

-- no room here: take a right turn within ELS_TURNOFF_DIST that leads off the emergency vehicle's path (random
-- traffic only; not the junction the car is already committed to). True when the plan now turns off there.
local function turnOff(ag, e)
    if ag.script or not e.path then return false end
    local plan = ag.plan
    local d = -ag.s
    for i = 1, #plan do
        local p = plan[i]
        d = d + Geo.length(p.code)
        if d > T.ELS_TURNOFF_DIST then return false end
        if p.code > 0 and d >= T.ELS_TURNOFF_MIN and not (i == 1 and ag.committed) then
            local cur = p.conn
            if cur and Net.cturn[cur] == "R" and not e.path.lanes[Net.cto[cur]] then return true end
            for _, c in ipairs(Net.lnext[p.code] or {}) do
                local to = Net.cto[c]
                if Net.cturn[c] == "R" and not e.path.lanes[to] and Net.lnext[to]
                    and bitAnd(Net.lflags[to] or 0, LF_PARKING + LF_ROADBLOCK + LF_TRAP + LF_EMERGENCY) == 0 then
                    return Agents.setExit(ag, i, c)
                end
            end
        end
    end
    return false
end

-- pulling over always means going right: a car in the inner lane of a multi-lane carriageway first changes into
-- the outer lane (second result true, lanes.lua); a car in the outer lane or on a single lane road moves aside as
-- far as there is room. Third result false: no room here, keep driving (seek / turn off)
local function pullOver(ag, e, seek)
    local code = ag.plan[1].code
    if code > 0 and Net.lright[code] then return 0, true, true end
    if not Navmesh.ok then return T.ELS_PULL_RIGHT, false, true end
    local room = shoulderRoom(ag)
    if room >= T.ELS_PULL_MIN or not seek then return room, false, true end
    turnOff(ag, e)
    return room, false, false
end

local cycle = 0

local function setYield(ag, vcap, lat, now, clear, right)
    local e = ag.els
    if e and e.expires > now and e.cycle == cycle then
        if clear then e.clear = true end
        if right then e.right = true end
        -- several emergency vehicles in this update: keep the strongest reaction
        if vcap < e.vcap then e.vcap = vcap end
        if abs(lat) > abs(e.lat) then e.lat = lat end
        e.expires = now + T.ELS_HOLD
    else
        ag.els = { vcap = vcap, lat = lat, expires = now + T.ELS_HOLD, cycle = cycle, clear = clear, right = right }
    end
end

-- has the driver noticed emergency vehicle e? Rolls the chance; returns the reaction level (0 = no)
local function noticed(ag, e, dist, now)
    local nt = ag.notice
    if not nt then nt = {}; ag.notice = nt end
    local m = nt[e.el]
    if m and now - m.at > 3000 then m = nil end   -- lost sight of it for a while: start over
    local have = m and m.level or 0
    if have < e.level then
        local rate = e.level == 2 and T.ELS_NOTICE_SIREN or T.ELS_NOTICE_LIGHTS
        local close = 1.2 - dist / T.ELS_NOTICE_RANGE
        if close < 0.2 then close = 0.2 elseif close > 1 then close = 1 end
        if random() < 1 - exp(-rate * UPDATE * close) then have = e.level end
    end
    if have > 0 or m then
        nt[e.el] = { level = have, at = now }
    end
    -- siren switched off: the reaction falls back to the lights level
    return have > e.level and e.level or have
end

-- ahead of a moving emergency vehicle in its direction, `along` metres in front of it
local function giveWay(ag, e, level, along, now)
    if level == 2 then
        local vcap = along < T.ELS_STOP_DIST and 0 or T.ELS_CRAWL_SPEED * 2
        local lat, right, room = pullOver(ag, e, true)
        if not room then vcap = max(vcap, T.ELS_SEEK_SPEED) end
        setYield(ag, vcap, lat, now, true, right)
    else
        local lat, right = pullOver(ag, e, false)
        setYield(ag, T.ELS_LIGHTS_SPEED, lat * T.ELS_LIGHTS_PULL, now, false, right)
    end
end

local function oncoming(ag, level, now)
    setYield(ag, T.ELS_ONCOMING_SPEED * (level == 2 and 1 or 1.5), level == 2 and 1.0 or 0.6, now)
end

function Els.update(now)
    cycle = cycle + 1
    snapshot(now)
    local near = {}
    for _, e in ipairs(E.list) do
        for i = #near, 1, -1 do near[i] = nil end
        Agents.near(e.x, e.y, T.ELS_NOTICE_RANGE, near)
        local P = e.path
        for _, ag in ipairs(near) do
            if abs(ag.z - e.z) < 6 or P then
                local rx, ry = ag.x - e.x, ag.y - e.y
                local level = noticed(ag, e, sqrt(rx * rx + ry * ry), now)
                if level > 0 then
                    local along = rx * e.fx + ry * e.fy
                    local side = rx * e.fy - ry * e.fx
                    local same = ag.hx * e.fx + ag.hy * e.fy
                    local code = ag.plan[1].code
                    local onPath = P and P.lanes[code]
                    if P then
                        -- along the road: curves, parallel roads and overpasses sorted out by the lanes
                        if onPath then
                            local d = onPath + ag.s
                            if e.moving then
                                if d > -T.ELS_PASS_MARGIN and d < T.ELS_RANGE then giveWay(ag, e, level, d, now) end
                            elseif abs(d) < 40 then
                                setYield(ag, T.ELS_CRAWL_SPEED * 1.6, 0, now)
                            end
                        elseif e.moving and code > 0 and P.links[Net.llink[code] or 0] and same < -0.5
                            and along > 0 and along < T.ELS_ONCOMING_RANGE then
                            oncoming(ag, level, now)
                        elseif not e.moving and abs(along) < 40 and abs(side) < 10 and abs(ag.z - e.z) < 4 then
                            setYield(ag, T.ELS_CRAWL_SPEED * 1.6, 0, now)
                        end
                    elseif e.moving then
                        -- no lane for the emergency vehicle: straight-line test
                        if along > -T.ELS_PASS_MARGIN and along < T.ELS_RANGE and same > 0.5 and abs(side) < 14 then
                            giveWay(ag, e, level, along, now)
                        elseif along > 0 and same < -0.5 and along < T.ELS_ONCOMING_RANGE and abs(side) < 14 then
                            oncoming(ag, level, now)
                        end
                    elseif abs(along) < 40 and abs(side) < 10 then
                        -- standing emergency vehicle (scene): pass slowly
                        setYield(ag, T.ELS_CRAWL_SPEED * 1.6, 0, now)
                    end
                end
            end
        end
    end
end

-- is a moving emergency vehicle the agent noticed about to cross junction connection c at (x, y)? With a known
-- route only where that route's path through the junction conflicts with c.
function Els.approachingJunction(ag, c, x, y, hx, hy)
    local nt = ag.notice
    if not nt then return false end
    local now = getTickCount()
    for _, e in ipairs(E.list) do
        local m = nt[e.el]
        if e.moving and m and m.level > 0 and now - m.at < 1000 then
            local r = max(T.ELS_JUNCTION_RANGE, e.speed * T.ELS_JUNCTION_TIME + 20)
            if e.path and e.path.gps then
                local pn = e.path.nodes[Net.cnode[c] or 0]
                if pn and not pn.conns[c] and pn.dist > -6 and pn.dist < r then
                    for _, x2 in ipairs(Net.cconf[c] or {}) do
                        if pn.conns[x2] then return true end
                    end
                end
            else
                local dx, dy = x - e.x, y - e.y
                if dx * dx + dy * dy < r * r and dx * e.fx + dy * e.fy > -6 and hx * e.fx + hy * e.fy < 0.7 then
                    return true
                end
            end
        end
    end
    return false
end

------------------------------------------------------------------------ exports

-- where an emergency vehicle is going (e.g. a dispatch target): its navmesh route decides who gives way.
-- false / nil clears it (then the v_radar gpsDestination of the vehicle counts, if any)
function setEmergencyDestination(veh, x, y, z)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return false end
    x, y = tonumber(x), tonumber(y)
    E.dest[veh] = (x and y) and { x, y, tonumber(z) } or nil
    E.routes[veh] = nil
    return true
end
