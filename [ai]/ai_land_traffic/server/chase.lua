-- Chase motor (server): a scripted vehicle chasing a target close up. Near the target (CHASE_NEAR) it leaves the
-- lane simulation and becomes a physics vehicle; its syncer client steers the driver ped with control states
-- (client/chase.lua: follow / box / ram / pit / block). Far away (CHASE_FAR) where no camera sees it, it is taken
-- back into the simulation and follows the target there with the lane pursuit (Scripted pursuit).
--
-- setScriptedChase(veh, target, opts) -> true | false
--   target: element to chase (its vehicle when it sits in one); false = end the chase (back into the simulation
--           when a lane is near, else it stays a physics vehicle that the owner removes)
--   opts: mode ("follow" | "box" | "ram" | "pit" | "block"), aggression (0..1), maxSpeed (km/h), fire (tank cannon),
--         near / far (m, the switch distances), auto (false: always physics, no switching)
-- getScriptedChase(veh) -> { physics, mode, target } | false
-- Element data DATA_CHASE on the vehicle (broadcast, changes rarely): { t, m, a, s, f } while it is a physics vehicle.
-- The vehicle works for scripted vehicles and for physics vehicles with a ped driver (e.g. released by a crash with
-- keepDriver). Event onTrafficVehicleChaseMode (veh, "physics" | "sim").

Chase = { list = {} }

local T = TRAFFIC
local sqrt = math.sqrt
local MODES = { follow = true, box = true, ram = true, pit = true, block = true }

addEvent("onTrafficVehicleChaseMode")

local function order(c)
    return { t = c.target, m = c.mode, a = c.aggression, s = c.maxSpeed, f = c.fire or nil }
end

local function publish(c)
    if not isElement(c.veh) then return end
    if c.physics then
        local o = order(c)
        local old = getElementData(c.veh, DATA_CHASE)
        if type(old) ~= "table" or old.t ~= o.t or old.m ~= o.m or old.a ~= o.a or old.s ~= o.s or old.f ~= o.f then
            setElementData(c.veh, DATA_CHASE, o)
        end
    elseif getElementData(c.veh, DATA_CHASE) ~= nil then
        removeElementData(c.veh, DATA_CHASE)
    end
end

-- the vehicle the target sits in (or the target itself)
local function carrier(t)
    if isElement(t) and (getElementType(t) == "player" or getElementType(t) == "ped") then
        return getPedOccupiedVehicle(t) or t
    end
    return t
end

local function toPhysics(c)
    local ag = Agents.byVeh[c.veh]
    if ag then
        c.script = ag.script
        Agents.release(ag, "chase")
    end
    c.physics = true
    publish(c)
    triggerEvent("onTrafficVehicleChaseMode", c.veh, "physics")
end

local function toSim(c)
    local ag = Scripted.adoptVehicle(c.veh, c.script or { profile = "pursuit", speedFactor = 1.4, keepDriver = true })
    if not ag then return false end
    c.physics = false
    publish(c)
    if isElement(c.target) then
        setScriptedPursuit(c.veh, carrier(c.target), { engageDist = 0, closeDist = 0, lostDist = 5000, lostMs = 600000 })
    end
    triggerEvent("onTrafficVehicleChaseMode", c.veh, "sim")
    return true
end

------------------------------------------------------------------------ road path for the syncer

-- A physics chase car is steered by its syncer client, which cannot route. Every CHASE_PATH_EVERY the server
-- tracks a navmesh route (emergency profile) from the car to its target and sends the syncer the road ahead as
-- points (CHASE_PATH_STEP apart, CHASE_PATH_LENGTH long). Off the route / target moved away: a new route.
local function pathPoints(lanes, conns, i, s)
    local pts, d, step, maxLen = {}, 0, T.CHASE_PATH_STEP, T.CHASE_PATH_LENGTH
    local pos = s
    local function walk(code)
        local len = Geo.length(code)
        while pos < len and d < maxLen do
            local x, y, z = Geo.pose(code, pos, 0)
            if x then pts[#pts + 1] = x; pts[#pts + 1] = y; pts[#pts + 1] = z end
            pos, d = pos + step, d + step
        end
        pos = pos - len
        if pos < 0 then pos = 0 end
    end
    for k = i, #lanes do
        if d >= maxLen then break end
        walk(lanes[k])
        local c = conns[k + 1]
        if c and Geo.isCurve(c) and d < maxLen then walk(-c) end
    end
    return pts
end

local function updatePath(c, now)
    if now < (c.pathAt or 0) then return end
    c.pathAt = now + T.CHASE_PATH_EVERY
    local syncer = getElementSyncer(c.veh)
    if not syncer or getElementType(syncer) ~= "player" then return end
    local tx, ty, tz = getElementPosition(carrier(c.target))
    local x, y, z = getElementPosition(c.veh)
    local _, _, rz = getElementRotation(c.veh)
    -- the target moved away from the route's end: a new route is requested, the old one guides the car meanwhile
    local r = c.route
    if not c.nextRoute and (not r or (r.dx - tx) ^ 2 + (r.dy - ty) ^ 2 > T.CHASE_PATH_REROUTE ^ 2) then
        c.nextRoute = { dx = tx, dy = ty, dz = tz }
    end
    local n = c.nextRoute
    if n then
        Navmesh.track(n, x, y, z, rz, n.dx, n.dy, n.dz, "emergency", now, 1500)
        if n.lanes then c.route, c.nextRoute, r = n, nil, n end
    end
    if not r then return end
    local i, s = Navmesh.track(r, x, y, z, rz, r.dx, r.dy, r.dz, "emergency", now, 1500)
    if not i then return end
    local pts = pathPoints(r.lanes, r.conns, i, s)
    if #pts >= 6 then triggerClientEvent(syncer, EV_CHASE_PATH, resourceRoot, c.veh, pts) end
end

function Chase.step(now)
    for veh, c in pairs(Chase.list) do
        local driver = isElement(veh) and getVehicleController(veh)
        if not isElement(veh) or not driver or getElementType(driver) ~= "ped" or isPedDead(driver) then
            if isElement(veh) then removeElementData(veh, DATA_CHASE) end
            Chase.list[veh] = nil
        elseif c.auto and isElement(c.target) then
            local tx, ty = getElementPosition(carrier(c.target))
            local x, y = getElementPosition(veh)
            local ag = Agents.byVeh[veh]
            if ag then x, y = ag.x, ag.y end
            local d = sqrt((tx - x) ^ 2 + (ty - y) ^ 2)
            local inWorld = getElementDimension(c.target) == 0 and getElementInterior(c.target) == 0
            -- a physics car without a syncer stands still (nobody drives it): back into the simulation then
            if c.physics and not getElementSyncer(veh) then
                c.noSyncer = c.noSyncer or now
            else
                c.noSyncer = nil
            end
            if not c.physics and d < c.near and inWorld then
                toPhysics(c)
            elseif c.physics and c.noSyncer and now - c.noSyncer > T.CHASE_NO_SYNCER then
                c.noSyncer = nil
                toSim(c)
            elseif c.physics and (d > c.far or not inWorld) and not isElementSeenByPlayers(veh) then
                toSim(c)
            end
            if c.physics and Chase.list[veh] then updatePath(c, now) end
        end
    end
end

function setScriptedChase(veh, target, opts)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return false end
    local c = Chase.list[veh]
    if not target then
        if not c then return false end
        Chase.list[veh] = nil
        removeElementData(veh, DATA_CHASE)
        if c.physics then Scripted.adoptVehicle(veh, c.script) end
        return true
    end
    if not isElement(target) then return false end
    local driver = getVehicleController(veh)
    if not driver or getElementType(driver) ~= "ped" then return false end
    opts = type(opts) == "table" and opts or {}
    if not c then
        local ag = Agents.byVeh[veh]
        c = { veh = veh, physics = not ag, script = ag and ag.script or nil }
        Chase.list[veh] = c
    end
    c.target = target
    c.mode = MODES[opts.mode] and opts.mode or c.mode or "follow"
    c.aggression = math.max(0, math.min(1, tonumber(opts.aggression) or c.aggression or 0.5))
    c.maxSpeed = tonumber(opts.maxSpeed) or c.maxSpeed or 180
    c.fire = opts.fire == true
    c.near = tonumber(opts.near) or T.CHASE_NEAR
    c.far = tonumber(opts.far) or T.CHASE_FAR
    c.auto = opts.auto ~= false
    if c.physics then
        publish(c)
    elseif not c.auto then
        toPhysics(c)
    elseif Agents.byVeh[veh] then
        setScriptedPursuit(veh, carrier(target), { engageDist = 0, closeDist = 0, lostDist = 5000, lostMs = 600000 })
    end
    return true
end

function getScriptedChase(veh)
    local c = Chase.list[veh]
    if not c then return false end
    return { physics = c.physics, mode = c.mode, target = c.target }
end

addEventHandler("onElementDestroy", root, function()
    if Chase.list[source] then Chase.list[source] = nil end
end)
