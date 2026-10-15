-- Reaction to emergency vehicles (server). A vehicle counts while its v_els emergency lights are on
-- (elementData TRAFFIC.ELS_DATA == true). Every driver in range notices it with some chance per update:
--   level 1, lights only: small chance (ELS_NOTICE_LIGHTS) -> slows down, makes some room
--   level 2, siren (sirenState / sirenHorn): high chance (ELS_NOTICE_SIREN) -> pulls over, stops when close
-- Reactions of a driver who noticed it:
--   same direction, ahead of it: back into the outer lane (multi-lane roads) / aside, slow down / stop
--   oncoming: slow down and keep right
--   cross traffic: do not enter a junction it is approaching (sim.lua gate)
--   standing emergency vehicle: pass slowly (overtaking is handled by the obstacle logic)

Els = { active = {}, list = {} }   -- active: [vehicle] = true; list: snapshot { el, x, y, z, fx, fy, speed, moving, level }

local E = Els
local sqrt, sin, cos, rad, exp, random = math.sqrt, math.sin, math.cos, math.rad, math.exp, math.random
local UPDATE = 0.25   -- s between Els.update calls (main.lua)

local function sirenOn(veh)
    for _, key in ipairs(TRAFFIC.ELS_SIREN_DATA) do
        if getElementData(veh, key) == true then return true end
    end
    return false
end

local function consider(veh)
    if isElement(veh) and getElementType(veh) == "vehicle" and getElementData(veh, TRAFFIC.ELS_DATA) == true then
        E.active[veh] = true
    else
        E.active[veh] = nil
    end
end

function Els.init()
    for _, veh in ipairs(getElementsByType("vehicle")) do consider(veh) end
    addEventHandler("onElementDataChange", root, function(key)
        if key == TRAFFIC.ELS_DATA then consider(source) end
    end)
    addEventHandler("onElementDestroy", root, function()
        if E.active[source] then E.active[source] = nil end
    end)
end

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
            list[#list + 1] = { el = veh, x = x, y = y, z = z, fx = fx, fy = fy, speed = speed, moving = moving,
                                level = sirenOn(veh) and 2 or 1 }
        else
            E.active[veh] = nil
            movingUntil[veh] = nil
        end
    end
    E.list = list
end

local cycle = 0

local function setYield(ag, vcap, lat, now, clear, right)
    local e = ag.els
    if e and e.expires > now and e.cycle == cycle then
        if clear then e.clear = true end
        if right then e.right = true end
        -- several emergency vehicles in this update: keep the strongest reaction
        if vcap < e.vcap then e.vcap = vcap end
        if math.abs(lat) > math.abs(e.lat) then e.lat = lat end
        e.expires = now + TRAFFIC.ELS_HOLD
    else
        ag.els = { vcap = vcap, lat = lat, expires = now + TRAFFIC.ELS_HOLD, cycle = cycle, clear = clear, right = right }
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
        local rate = e.level == 2 and TRAFFIC.ELS_NOTICE_SIREN or TRAFFIC.ELS_NOTICE_LIGHTS
        local close = 1.2 - dist / TRAFFIC.ELS_NOTICE_RANGE
        if close < 0.2 then close = 0.2 elseif close > 1 then close = 1 end
        if random() < 1 - exp(-rate * UPDATE * close) then have = e.level end
    end
    if have > 0 or m then
        nt[e.el] = { level = have, at = now }
    end
    -- siren switched off: the reaction falls back to the lights level
    return have > e.level and e.level or have
end

-- pulling over always means going right: a car in the inner lane of a multi-lane carriageway first
-- changes into the outer lane (second result true, lanes.lua), a car in the outer lane or on a single
-- lane road moves to the right edge of its lane
local function pullLat(ag)
    local code = ag.plan[1].code
    if code > 0 and Net.lright[code] then return 0, true end
    return TRAFFIC.ELS_PULL_RIGHT, false
end

function Els.update(now)
    cycle = cycle + 1
    snapshot(now)
    local near = {}
    local T = TRAFFIC
    for _, e in ipairs(E.list) do
        for i = #near, 1, -1 do near[i] = nil end
        Agents.near(e.x, e.y, T.ELS_NOTICE_RANGE, near)
        for _, ag in ipairs(near) do
            if math.abs(ag.z - e.z) < 6 then
                local rx, ry = ag.x - e.x, ag.y - e.y
                local level = noticed(ag, e, sqrt(rx * rx + ry * ry), now)
                if level > 0 then
                    local along = rx * e.fx + ry * e.fy
                    local side = rx * e.fy - ry * e.fx
                    local same = ag.hx * e.fx + ag.hy * e.fy
                    local inRange = along < T.ELS_RANGE
                    if e.moving then
                        -- stays pulled over until the emergency vehicle has passed (ELS_PASS_MARGIN ahead)
                        if along > -T.ELS_PASS_MARGIN and inRange and same > 0.5 and math.abs(side) < 14 then
                            if level == 2 then
                                local vcap = along < T.ELS_STOP_DIST and 0 or T.ELS_CRAWL_SPEED * 2
                                local lat, right = pullLat(ag)
                                setYield(ag, vcap, lat, now, true, right)
                            else
                                local lat, right = pullLat(ag)
                                setYield(ag, T.ELS_LIGHTS_SPEED, lat * T.ELS_LIGHTS_PULL, now, false, right)
                            end
                        elseif along > 0 and same < -0.5 and along < T.ELS_ONCOMING_RANGE and math.abs(side) < 14 then
                            setYield(ag, T.ELS_ONCOMING_SPEED * (level == 2 and 1 or 1.5), level == 2 and 1.0 or 0.6, now)
                        end
                    elseif math.abs(along) < 40 and math.abs(side) < 10 then
                        -- standing emergency vehicle (scene): pass slowly
                        setYield(ag, T.ELS_CRAWL_SPEED * 1.6, 0, now)
                    end
                end
            end
        end
    end
end

-- is a moving emergency vehicle the agent noticed about to cross the junction at (x, y)?
function Els.approachingJunction(ag, x, y, hx, hy)
    local nt = ag.notice
    if not nt then return false end
    local now = getTickCount()
    for _, e in ipairs(E.list) do
        local m = nt[e.el]
        if e.moving and m and m.level > 0 and now - m.at < 1000 then
            local dx, dy = x - e.x, y - e.y
            local r = math.max(TRAFFIC.ELS_JUNCTION_RANGE, e.speed * TRAFFIC.ELS_JUNCTION_TIME + 20)
            if dx * dx + dy * dy < r * r and dx * e.fx + dy * e.fy > -6 and hx * e.fx + hy * e.fy < 0.7 then
                return true
            end
        end
    end
    return false
end
