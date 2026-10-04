-- Trains on the network (server). Every train is simulated here; the cars are derailed + frozen
-- vehicles ("puppets") that every client places each frame from the snapshots (client/trains.lua).
--
-- train = { id, cars = { { el, type, def, offset, flip } }, length, mass,
--           path (TrainPath), u (head), v (m/s along increasing u), a,
--           ctrl (-1 full brake .. +1 full power), rev (+1 / -1), emergency, input = { w, s },
--           driver, riders = { [player] = { car, spot } }, auto (controlled by an export) }
--
-- Driving: the driver sits in the lead's driver seat (warped), W / S move the controller, X is the
-- emergency brake, R flips the reverser while standing. Passengers are attached to a car.

Trains = {}

local SIM, STOCK = NET.SIM, NET.STOCK
local trains = {}          -- [id] = train
local byElement = {}       -- [car element] = train
-- ids are never reused, not even across restarts (other resources may still know old ones)
local nextId = (getRealTime().timestamp % 100000) * 100 + 1
local lastTick = getTickCount()
local lastSnap, lastPos = 0, 0
local dirtySnap = false
local log = NetServer.log

local function tell(p, fmt, ...)
    if isElement(p) then outputChatBox("[SLR] " .. string.format(fmt, ...), p, 120, 200, 255) end
end

local function sign(x) return x > 0 and 1 or (x < 0 and -1 or 0) end

-- ------------------------------------------------------------------ geometry helpers

-- world pose of car k -> x, y, z (centre, includes the model height), fx, fy, fz (model forward)
local function carPose(t, car)
    local x, y, z, fx, fy, fz = t.path:carPose(t.u - car.offset, car.def.bogie)
    if car.flip then fx, fy, fz = -fx, -fy, -fz end
    return x, y, z + car.def.base + NET.RAIL_Z, fx, fy, fz
end

local function rotationOf(fx, fy, fz)
    local rz = (math.deg(math.atan2(fy, fx)) - 90) % 360
    local rx = math.deg(math.atan2(fz, math.sqrt(fx * fx + fy * fy)))
    return rx, 0, rz
end

local function spansOf(t, margin)
    margin = margin or 0
    return t.path:spans(t.u - t.length - margin, t.u + margin)
end

local function overlaps(sa, sb)
    for _, a in ipairs(sa) do
        for _, b in ipairs(sb) do
            if a[1] == b[1] and a[2] < b[3] and b[2] < a[3] then return true end
        end
    end
    return false
end

-- ------------------------------------------------------------------ snapshots

local function snapshotOf(t)
    local cars = {}
    for k, c in ipairs(t.cars) do cars[k] = { c.el, c.type, c.offset, c.flip } end
    return { id = t.id, cars = cars, length = t.length, path = t.path:serialise(), u = t.u, v = t.v, a = t.a,
        T = t.T, ctrl = t.ctrl, rev = t.rev, emergency = t.emergency, driver = t.driver, number = t.number,
        dim = t.dim, atp = t.atp, auth = t.authority and { t.authority.u, t.authority.sign, t.authority.reason } or false,
        dest = t.dest and t.dest.seg or false }
end

local function broadcast(to)
    local list = {}
    for _, t in pairs(trains) do list[#list + 1] = snapshotOf(t) end
    triggerClientEvent(to or NetServer.readyPlayers(), "rw:net:trains", resourceRoot, list)
end

addEvent("rw:net:hello", true)
addEventHandler("rw:net:hello", resourceRoot, function()
    -- the network data goes first (latent), the trains right after
    local p = client
    setTimer(function() if isElement(p) then broadcast({ p }) end end, 1500, 1)
end)

-- ------------------------------------------------------------------ path upkeep

local function ensurePath(t)
    local ok, passed = t.path:extendFront(t.u + SIM.LOOKAHEAD)
    t.path:extendBack(t.u - t.length - 20)
    t.path:trim(t.u - t.length - 40, t.u + SIM.LOOKAHEAD + 40)
    if passed then
        dirtySnap = true
        t.pending = t.pending or {}
        for _, p in ipairs(passed) do t.pending[#t.pending + 1] = p end
    end
end

-- nodes the head actually passed this step (the route is planned LOOKAHEAD metres early)
local function passNodes(t)
    local pend = t.pending
    if not pend then return end
    local i = 1
    while pend[i] do
        local p = pend[i]
        if t.u >= p.u then
            table.remove(pend, i)
            if p.trailed then
                Switches.onTrailed(t.id, p.node, p.from)
                triggerEvent("onNetTrainTrailedSwitch", resourceRoot, t.id, p.node)
            end
        else
            i = i + 1
        end
    end
end

-- drops the route ahead of the head (and behind the rear) and builds it again with the current
-- switch states; the part under the train is kept
local function repath(t)
    local ps = t.path.pieces
    for i = #ps, 2, -1 do
        if ps[i].u0 > t.u then table.remove(ps, i) end
    end
    if t.pending then
        for i = #t.pending, 1, -1 do if t.pending[i].u > t.u then table.remove(t.pending, i) end end
    end
    local rear = t.u - t.length
    while #ps > 1 and ps[1].u0 + ps[1].len < rear do table.remove(ps, 1) end
    t.path.frontEnd, t.path.backEnd = nil, nil
    ensurePath(t)
    dirtySnap = true
end

function Trains.onSwitchChanged()
    for _, t in pairs(trains) do repath(t) end
end

-- edited network: rebuild every route from the head position
function Trains.onNetworkRebuilt()
    for _, t in pairs(trains) do
        local seg, s, dir = t.path:at(t.u)
        if Net.segment(seg) then
            local path, u = TrainPath.new(seg, math.min(s, Net.length(seg)), dir)
            t.path, t.u, t.pending = path, u, nil
            ensurePath(t)
        end
    end
    dirtySnap = true
end

-- ------------------------------------------------------------------ spawn / destroy

local function placeServer(t, all)
    for _, car in ipairs(t.cars) do
        if isElement(car.el) and (all or not getVehicleController(car.el)) then
            local x, y, z, fx, fy, fz = carPose(t, car)
            setElementPosition(car.el, x, y, z)
            setElementRotation(car.el, rotationOf(fx, fy, fz))
        end
    end
end

-- types = { "br232", "passenger", ... } or a preset name; head at (seg, s), facing dir.
-- Returns the train id or false, error.
function Trains.spawn(types, seg, s, dir, opts)
    opts = opts or {}
    if type(types) == "string" then types = NET.PRESETS[types] end
    if type(types) ~= "table" or #types == 0 then return false, "unknown composition" end
    if not Net.segment(seg) then return false, "unknown segment" end
    dir = dir == -1 and -1 or 1

    local t = { id = nextId, cars = {}, length = 0, mass = 0, power = 0, maxForce = 0, v = 0, a = 0, ctrl = -0.5,
        rev = 1, emergency = false, input = {}, riders = {}, T = getTickCount(), idle = getTickCount(), auto = opts.auto,
        locks = {}, data = opts.data or {},
        dim = tonumber(opts.dimension) or 0 }
    for k, name in ipairs(types) do
        local def = STOCK[name]
        if not def then return false, "unknown vehicle type " .. tostring(name) end
        t.cars[k] = { type = name, def = def, offset = t.length + def.length / 2, flip = false }
        t.length = t.length + def.length
        t.mass = t.mass + def.mass * 1000
        t.power = t.power + (def.power or 0) * 1000
        t.maxForce = t.maxForce + (def.maxForce or 0) * 1000
    end

    t.path, t.u = TrainPath.new(seg, s, dir)
    ensurePath(t)
    local rear = t.u - t.length
    if t.path.backEnd and rear < t.path.backEnd then
        return false, string.format("not enough track behind (%.0f m short)", t.path.backEnd - rear)
    end
    if t.path.frontEnd and t.u > t.path.frontEnd then return false, "head beyond the end of the track" end
    local mine = spansOf(t, SIM.SPAWN_CLEAR)
    for _, o in pairs(trains) do
        if o.dim == t.dim and overlaps(mine, spansOf(o)) then return false, "track occupied by train " .. o.id end
    end

    nextId = nextId + 1
    for k, car in ipairs(t.cars) do
        local x, y, z, fx, fy, fz = carPose(t, car)
        local rx, ry, rz = rotationOf(fx, fy, fz)
        local el = createVehicle(car.def.model, x, y, z, rx, ry, rz)
        if not el then
            for _, c in ipairs(t.cars) do if isElement(c.el) then destroyElement(c.el) end end
            return false, "createVehicle failed"
        end
        setTrainDerailed(el, true)
        setElementFrozen(el, true)
        setElementSyncer(el, false)
        setVehicleEngineState(el, false)
        setVehicleDamageProof(el, true)
        setVehicleLocked(el, true)
        setElementData(el, "rwn.train", t.id)
        setElementData(el, "rwn.car", k)
        setElementDimension(el, t.dim)
        car.el = el
        byElement[el] = t
    end
    trains[t.id] = t
    dirtySnap = true
    log("train %d spawned: %d cars, %.1f m, %.0f t at %s %.1f dir %d", t.id, #t.cars, t.length, t.mass / 1000, seg, s, dir)
    return t.id
end

local function dropPlayer(t, p, quiet)
    if not isElement(p) then t.riders[p] = nil return end
    local veh = getPedOccupiedVehicle(p)
    local car
    if t.driver == p then
        car = t.cars[1]
        t.driver = nil
        t.input = {}
        if veh then removePedFromVehicle(p) end
    elseif t.riders[p] then
        car = t.cars[t.riders[p].car]
        t.riders[p] = nil
        detachElements(p)
        removeElementData(p, "rwn.ride")
    else
        return
    end
    -- beside the car, right hand side
    if car and isElement(car.el) then
        local x, y, z, fx, fy = carPose(t, car)
        local l = math.sqrt(fx * fx + fy * fy)
        local rx, ry = fy / l, -fx / l
        local _, _, railZ = t.path:point(t.u - car.offset)
        setElementPosition(p, x + rx * 2.8, y + ry * 2.8, railZ + 1.2)
    end
    dirtySnap = true
    if not quiet then triggerClientEvent(p, "rw:net:left", resourceRoot) end
end

function Trains.destroy(id, reason)
    local t = trains[id]
    if not t then return false end
    if t.driver then dropPlayer(t, t.driver, true) end
    for p in pairs(t.riders) do dropPlayer(t, p, true) end
    for _, c in ipairs(t.cars) do
        byElement[c.el] = nil
        if isElement(c.el) then destroyElement(c.el) end
    end
    trains[id] = nil
    Switches.onTrainRemoved(t)
    dirtySnap = true
    log("train %d removed: %s", id, reason or "?")
    return true
end

function Trains.get(id) return trains[id] end
function Trains.all() return trains end
function Trains.ofElement(el) return byElement[el] end

function Trains.ofPlayer(p)
    for _, t in pairs(trains) do
        if t.driver == p or t.riders[p] then return t end
    end
end

-- ------------------------------------------------------------------ driver / riders

function Trains.setDriver(p, id)
    local t = trains[id]
    if not t or not isElement(t.cars[1].el) then return false, "no such train" end
    if t.driver and t.driver ~= p then return false, "the train already has a driver" end
    local old = Trains.ofPlayer(p)
    if old then dropPlayer(old, p, true) end
    if not warpPedIntoVehicle(p, t.cars[1].el, 0) then return false, "warp failed" end
    t.driver = p
    t.input = {}
    t.auto = nil            -- a driver takes over from scripted control
    t.idle = getTickCount()
    dirtySnap = true
    return true
end

function Trains.addRider(p, id, k)
    local t = trains[id]
    if not t then return false, "no such train" end
    local car = t.cars[k]
    if not car or not car.def.ride then return false, "no room in that car" end
    local used = {}
    for _, r in pairs(t.riders) do if r.car == k then used[r.spot] = true end end
    local spot
    for i = 1, #car.def.ride.spots do if not used[i] then spot = i break end end
    if not spot then return false, "the car is full" end
    local old = Trains.ofPlayer(p)
    if old then dropPlayer(old, p, true) end
    if getPedOccupiedVehicle(p) then removePedFromVehicle(p) end
    local sp = car.def.ride.spots[spot]
    local ox, oy = sp[1], sp[2]
    if car.flip then ox, oy = -ox, -oy end
    attachElements(p, car.el, ox, oy, car.def.ride.z)
    t.riders[p] = { car = k, spot = spot }
    setElementData(p, "rwn.ride", { t.id, k })
    t.idle = getTickCount()
    dirtySnap = true
    return true
end

function Trains.removePlayer(p)
    local t = Trains.ofPlayer(p)
    if not t then return false end
    dropPlayer(t, p)
    return true
end

addEvent("rw:net:input", true)
addEventHandler("rw:net:input", resourceRoot, function(input)
    local t = Trains.ofPlayer(client)
    if not t or t.driver ~= client or type(input) ~= "table" then return end
    if NET.SIM.LOG_INPUT then
        log("train %d input from %s: w=%s s=%s x=%s rev=%s", t.id, getPlayerName(client), tostring(input.w), tostring(input.s),
            tostring(input.x), tostring(input.rev))
    end
    t.input = { w = input.w == true, s = input.s == true }
    if input.x then
        t.emergency = true
        t.ctrl = -1
    end
    if input.rev and math.abs(t.v) < 0.1 then t.rev = -t.rev end
    dirtySnap = true
end)

addEvent("rw:net:leave", true)
addEventHandler("rw:net:leave", resourceRoot, function()
    local t = Trains.ofPlayer(client)
    if not t then return end
    if t.driver == client and math.abs(t.v) > 1 then
        return tell(client, "Menet közben nem szállhatsz ki a vezetőállásból.")
    end
    dropPlayer(t, client)
end)

addEventHandler("onVehicleStartExit", resourceRoot, function(p)
    local t = byElement[source]
    -- rw_core trains: rw_loco puts the driver down beside the cab itself
    if t and not getElementData(source, "rw.consist") then
        cancelEvent()
        if t.driver == p and math.abs(t.v) <= 1 then dropPlayer(t, p) end
    end
end)

-- somebody else took the driver out (rw_loco's cab exit)
addEventHandler("onVehicleExit", resourceRoot, function(p)
    local t = byElement[source]
    if t and t.driver == p then
        t.driver, t.input = nil, {}
        dirtySnap = true
    end
end)

addEventHandler("onPlayerWasted", root, function()
    local t = Trains.ofPlayer(source)
    if t then dropPlayer(t, source, true) end
end)

addEventHandler("onPlayerQuit", root, function()
    for _, t in pairs(trains) do
        if t.driver == source then t.driver = nil t.input = {} dirtySnap = true end
        if t.riders[source] then t.riders[source] = nil dirtySnap = true end
    end
end)

-- ------------------------------------------------------------------ simulation

local function step(t, dt)
    -- controller
    if t.driver then
        if t.input.w then
            if t.ctrl < 0 then t.ctrl = math.min(0, t.ctrl + SIM.CONTROL_RATE * 2 * dt) else t.ctrl = t.ctrl + SIM.CONTROL_RATE * dt end
            t.emergency = false
        elseif t.input.s then
            t.ctrl = t.ctrl - SIM.CONTROL_RATE * dt
        end
        t.ctrl = math.max(-1, math.min(1, t.ctrl))
    elseif not t.auto then
        t.ctrl = math.min(t.ctrl, -0.5)     -- nobody in the cab: brakes on
    end

    local mid = t.u - t.length / 2
    local grade = t.path:grade(mid) * SIM.GRADE_FACTOR
    grade = math.max(-SIM.GRADE_CAP, math.min(SIM.GRADE_CAP, grade))

    -- ATP: brake in time for the end of the authority (first switch not reserved / destination)
    local A = t.authority
    t.atp = false
    if A then
        local lead = A.sign > 0 and t.u or t.u - t.length
        local remaining = (A.u - lead) * A.sign
        local toward = t.v * A.sign
        local starting = t.ctrl > 0 and t.rev == A.sign
        if toward > 0.05 or starting then
            -- what the slope and the running resistance do on their own (+ = helps braking)
            local natural = SIM.R0 + 9.81 * grade * A.sign
            local decel = math.max(0.2, (SIM.BRAKE + natural) * 0.9)
            local v2 = math.max(0, toward) ^ 2
            if remaining <= 2 then
                -- at the end of the authority: no traction towards it, hold the brakes
                t.atp = true
                t.ctrl = math.min(t.ctrl, toward > 0.05 and -1 or -0.5)
            elseif remaining <= v2 / (2 * decel) + 3 then
                -- on the braking curve: just the deceleration needed to stop at the end
                local need = v2 / (2 * math.max(0.5, remaining - 1))
                local frac = math.max(0.15, math.min(1, (need - natural) / SIM.BRAKE))
                t.atp = true
                t.ctrl = math.min(t.ctrl, -frac)
            end
        end
    end

    local speed = math.abs(t.v)
    local force = 0
    if t.ctrl > 0 and not next(t.locks) then force = t.ctrl * math.min(t.maxForce, t.power / math.max(speed, 1)) * t.rev end
    local drive = force / t.mass - 9.81 * grade
    local resist = SIM.R0 + SIM.R1 * speed + SIM.R2 * speed * speed
    local brake = t.emergency and SIM.EMERGENCY or (t.ctrl < 0 and -t.ctrl * SIM.BRAKE or 0)
    local fric = resist + brake

    local v = t.v
    local a
    if speed < 0.05 then
        if math.abs(drive) <= fric then a, v = 0, 0
        else a = drive - sign(drive) * fric v = v + a * dt end
    else
        a = drive - sign(v) * fric
        v = v + a * dt
        if sign(v) ~= sign(t.v) and math.abs(drive) <= fric then v = 0 a = 0 end
    end
    if v > SIM.VMAX then v = SIM.VMAX elseif v < -SIM.VMAX then v = -SIM.VMAX end

    local oldU = t.u
    local newU = t.u + (t.v + v) / 2 * dt
    t.u = newU
    ensurePath(t)

    passNodes(t)

    -- end of authority: never run past it
    if A then
        local lead = A.sign > 0 and t.u or t.u - t.length
        if (A.u - lead) * A.sign < 0 and v * A.sign > 0 then
            t.u = A.sign > 0 and A.u or A.u + t.length
            if math.abs(v) > SIM.CRASH_SPEED then
                log("train %d overran its authority (%s) at %.1f km/h", t.id, tostring(A.reason), math.abs(v) * 3.6)
                triggerEvent("onNetTrainOverrun", resourceRoot, t.id, A.reason, math.abs(v))
            end
            v, a = 0, 0
            dirtySnap = true
        end
    end

    -- dead ends (buffer stops / open track)
    local hit
    if t.path.frontEnd and t.u > t.path.frontEnd - 0.3 then t.u = t.path.frontEnd - 0.3 hit = "end" end
    if t.path.backEnd and t.u - t.length < t.path.backEnd + 0.3 then t.u = t.path.backEnd + 0.3 + t.length hit = "end" end

    -- other trains
    local mine = spansOf(t)
    for _, o in pairs(trains) do
        if o ~= t and o.dim == t.dim and overlaps(mine, spansOf(o)) then
            t.u = oldU
            hit = o.id
            o.v, o.a = 0, 0
            break
        end
    end
    if hit then
        if math.abs(v) > SIM.CRASH_SPEED then
            log("train %d crashed into %s at %.1f km/h", t.id, tostring(hit), math.abs(v) * 3.6)
            triggerEvent("onNetTrainCrash", resourceRoot, t.id, hit, math.abs(v))
        end
        v, a = 0, 0
        dirtySnap = true
    end

    if math.abs(a - t.a) > 0.05 or (t.v ~= 0) ~= (v ~= 0) or t.atp ~= t.atpSent then
        dirtySnap = true
        t.atpSent = t.atp
    end
    t.v, t.a = v, a
    t.T = getTickCount()

    if t.driver or next(t.riders) or math.abs(v) > 0.1 then t.idle = t.T end
end

setTimer(function()
    local now = getTickCount()
    local dt = math.min(0.5, (now - lastTick) / 1000)
    lastTick = now
    for id, t in pairs(trains) do
        if not isElement(t.cars[1].el) then
            Trains.destroy(id, "vehicle gone")
        else
            step(t, dt)
            if not t.auto and now - t.idle > SIM.IDLE_DESPAWN * 1000 then Trains.destroy(id, "idle") end
        end
    end
    Trains.publish()
    if dirtySnap or now - lastSnap >= SIM.SNAPSHOT then
        dirtySnap = false
        lastSnap = now
        if next(trains) then broadcast() end
    end
    if now - lastPos >= SIM.SERVER_POS then
        lastPos = now
        for _, t in pairs(trains) do placeServer(t) end
    end
end, SIM.TICK, 0)

-- ------------------------------------------------------------------ other resources

-- Every simulation tick: triggerEvent("onNetTrainStates", root, list) with one entry per train
--   { id, cars = { elements }, types, length, speed (m/s, +u), accel, ctrl, rev, emergency, driver,
--     auto, dim, atp, authority = { reason, remaining } | false, dest, arrived,
--     lines = { { line, tp, dir } } where the lead car centre is (dir = +1: the train faces +tp),
--     moveSign = +1 / -1 / 0 along the train's own forward direction, data }
addEvent("onNetTrainStates", false)
function Trains.publish()
    local list = {}
    for _, t in pairs(trains) do
        local lead = t.cars[1]
        local seg, s, pdir = t.path:at(t.u - lead.offset)
        local ls = {}
        for _, e in ipairs(Lines.fromNet(seg, s)) do ls[#ls + 1] = { line = e.line, tp = e.tp, dir = pdir * e.dir } end
        local cars, types = {}, {}
        for k, c in ipairs(t.cars) do cars[k] = c.el types[k] = c.type end
        local A = t.authority
        local lead2 = t.rev >= 0 and t.u or t.u - t.length
        list[#list + 1] = { id = t.id, cars = cars, types = types, length = t.length, speed = t.v, accel = t.a,
            ctrl = t.ctrl, rev = t.rev, emergency = t.emergency, driver = t.driver, auto = t.auto or false, dim = t.dim,
            atp = t.atp or false, authority = A and { reason = A.reason, remaining = (A.u - lead2) * A.sign } or false,
            dest = t.dest and true or false, arrived = t.arrived or false, lines = ls,
            moveSign = math.abs(t.v) < 0.1 and 0 or (t.v > 0 and 1 or -1), data = t.data }
    end
    triggerEvent("onNetTrainStates", root, list)
end

-- replaces the cars of a standing train (coupling / uncoupling); the head stays where it is
function Trains.setComposition(id, types)
    local t = trains[id]
    if not t then return false, "no such train" end
    if math.abs(t.v) > 0.3 then return false, "the train must stand still" end
    local defs, length = {}, 0
    for k, name in ipairs(types) do
        local def = STOCK[name]
        if not def then return false, "unknown vehicle type " .. tostring(name) end
        defs[k] = def
        length = length + def.length
    end
    t.path:extendBack(t.u - length - 20)
    if t.path.backEnd and t.u - length < t.path.backEnd then return false, "the track behind the train is too short" end
    local probe = { path = t.path, u = t.u, length = length }
    local mine = probe.path:spans(t.u - length, t.u)
    for _, o in pairs(trains) do
        if o ~= t and o.dim == t.dim and overlaps(mine, spansOf(o)) then return false, "the track behind the train is occupied" end
    end
    -- keep the lead (and its driver) when it stays the same type
    local keep = t.cars[1].type == types[1]
    for k, c in ipairs(t.cars) do
        if not (keep and k == 1) then
            for p, r in pairs(t.riders) do if r.car == k then dropPlayer(t, p) end end
            byElement[c.el] = nil
            if isElement(c.el) then destroyElement(c.el) end
        end
    end
    local old1 = t.cars[1]
    t.cars, t.length, t.mass, t.power, t.maxForce = {}, 0, 0, 0, 0
    for k, name in ipairs(types) do
        local def = defs[k]
        local car = { type = name, def = def, offset = t.length + def.length / 2, flip = false }
        t.length = t.length + def.length
        t.mass = t.mass + def.mass * 1000
        t.power = t.power + (def.power or 0) * 1000
        t.maxForce = t.maxForce + (def.maxForce or 0) * 1000
        if k == 1 and keep then
            car.el = old1.el
        else
            local x, y, z, fx, fy, fz = carPose(t, car)
            local el = createVehicle(def.model, x, y, z, rotationOf(fx, fy, fz))
            setTrainDerailed(el, true)
            setElementFrozen(el, true)
            setElementSyncer(el, false)
            setVehicleEngineState(el, false)
            setVehicleDamageProof(el, true)
            setVehicleLocked(el, true)
            setElementDimension(el, t.dim)
            car.el = el
        end
        setElementData(car.el, "rwn.train", t.id)
        setElementData(car.el, "rwn.car", k)
        byElement[car.el] = t
        t.cars[k] = car
    end
    dirtySnap = true
    triggerEvent("onNetTrainCompositionChange", resourceRoot, t.id)
    return true
end
addEvent("onNetTrainCompositionChange", false)

-- ------------------------------------------------------------------ exports

function spawnNetTrain(types, seg, s, dir, opts) return Trains.spawn(types, seg, s, dir, opts) end

-- the lead car's centre at line position tp, facing dir (+1 = increasing tp)
function spawnNetTrainOnLine(types, line, tp, dir, opts)
    if type(types) == "string" then types = NET.PRESETS[types] end
    local def = type(types) == "table" and STOCK[types[1]]
    if not def then return false, "unknown composition" end
    dir = dir == -1 and -1 or 1
    local seg, s, ldir = Lines.toNet(line, tp + dir * def.length / 2)
    if not seg then return false, "unknown line" end
    return Trains.spawn(types, seg, s, ldir * dir, opts)
end

function setNetTrainComposition(id, types) return Trains.setComposition(id, types) end

-- traction lock (no tractive force while any reason is set)
function setNetTrainLock(id, reason, on)
    local t = trains[id]
    if not t then return false end
    t.locks[reason] = on and true or nil
    return true
end

function setNetTrainEmergency(id, on)
    local t = trains[id]
    if not t then return false end
    t.emergency = on and true or false
    if on then t.ctrl = -1 end
    dirtySnap = true
    return true
end

-- free data travelling with the train (service, running number, ...)
function setNetTrainData(id, key, value)
    local t = trains[id]
    if not t then return false end
    t.data[key] = value
    return true
end

function getNetTrainByElement(el) local t = byElement[el] return t and t.id or false end
function getNetTrainByPlayer(p) local t = Trains.ofPlayer(p) return t and t.id or false end
function destroyNetTrain(id) return Trains.destroy(id, "export") end

-- auto / scripted control: ctrl -1..1, rev +1/-1, emergency
function setNetTrainControl(id, ctrl, rev, emergency)
    local t = trains[id]
    if not t then return false end
    t.auto = true
    t.ctrl = math.max(-1, math.min(1, tonumber(ctrl) or t.ctrl))
    if rev == 1 or rev == -1 then t.rev = rev end
    t.emergency = emergency and true or false
    dirtySnap = true
    return true
end

function getNetTrain(id)
    local t = trains[id]
    if not t then return false end
    local seg, s, dir = t.path:at(t.u)
    local riders = {}
    for p, r in pairs(t.riders) do riders[#riders + 1] = { player = p, car = r.car } end
    local cars = {}
    for k, c in ipairs(t.cars) do cars[k] = { element = c.el, type = c.type } end
    return { id = t.id, seg = seg, s = s, dir = dir, u = t.u, speed = t.v, accel = t.a, ctrl = t.ctrl, rev = t.rev,
        emergency = t.emergency, length = t.length, mass = t.mass / 1000, driver = t.driver, riders = riders, cars = cars,
        route = t.path:serialise(), frontEnd = t.path.frontEnd, backEnd = t.path.backEnd, dimension = t.dim,
        dest = t.dest or false, atp = t.atp or false, arrived = t.arrived or false,
        authority = t.authority and { reason = t.authority.reason, remaining = t.authority.remaining, u = t.authority.u } or false }
end

function getNetTrains()
    local t = {}
    for id in pairs(trains) do t[#t + 1] = getNetTrain(id) end
    return t
end

function setNetTrainDriver(p, id) return Trains.setDriver(p, id) end
function addNetTrainRider(p, id, car) return Trains.addRider(p, id, car) end
function removeNetTrainPlayer(p) return Trains.removePlayer(p) end

addEvent("onNetTrainCrash", false)            -- (trainId, hit = train id | "end", speed m/s)
addEvent("onNetTrainTrailedSwitch", false)    -- (trainId, nodeId)
addEvent("onNetTrainOverrun", false)          -- (trainId, authority reason, speed m/s)

addEventHandler("onResourceStop", resourceRoot, function()
    for id in pairs(trains) do Trains.destroy(id, "resource stopped") end
end)

-- ------------------------------------------------------------------ commands

local function nearestTrain(p, maxDist)
    local px, py, pz = getElementPosition(p)
    local best, bestD, bestK
    for _, t in pairs(trains) do
        for k, c in ipairs(t.cars) do
            if isElement(c.el) then
                local x, y, z = getElementPosition(c.el)
                local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
                if d < (maxDist or 40) and (not bestD or d < bestD) then best, bestD, bestK = t, d, k end
            end
        end
    end
    return best, bestK
end

-- /rwtrain spawn [preset] | drive [id] | ride [car] | leave | remove [id|all] | list | tp <seg> <s>
addCommandHandler("rwtrain", function(p, _, cmd, a1, a2)
    if not NetServer.isAdmin(p) then return tell(p, "Nincs jogod ehhez.") end
    if cmd == "spawn" then
        local x, y, z = getElementPosition(p)
        local seg, s = Net.project(x, y, z, 30)
        if not seg then return tell(p, "Nincs vágány 30 m-en belül.") end
        local _, _, _, tx, ty = Net.pointAt(seg, s)
        local _, _, rz = getElementRotation(p)
        local hx, hy = -math.sin(math.rad(rz)), math.cos(math.rad(rz))
        local dir = (hx * tx + hy * ty) >= 0 and 1 or -1
        local id, err = Trains.spawn(a1 or "re2", seg, s, dir, { dimension = getElementDimension(p) })
        if id then tell(p, "Vonat #%d létrehozva (%s, %s %.0f m).", id, a1 or "re2", seg, s)
        else tell(p, "Nem sikerült: %s", err) end
    elseif cmd == "drive" then
        local t = tonumber(a1) and trains[tonumber(a1)] or nearestTrain(p)
        if not t then return tell(p, "Nincs vonat a közelben.") end
        local ok, err = Trains.setDriver(p, t.id)
        if ok then tell(p, "W / S = kontroller, X = vészfék, R = irányváltó (állva), F = kiszállás.")
        else tell(p, "Nem sikerült: %s", err) end
    elseif cmd == "ride" then
        local t, k = nearestTrain(p)
        if not t then return tell(p, "Nincs vonat a közelben.") end
        k = tonumber(a1) or k
        if k == 1 and #t.cars > 1 then k = 2 end
        local ok, err = Trains.addRider(p, t.id, k)
        if ok then tell(p, "Felszálltál (%d. kocsi). F = leszállás.", k) else tell(p, "Nem sikerült: %s", err) end
    elseif cmd == "leave" then
        Trains.removePlayer(p)
    elseif cmd == "remove" then
        if a1 == "all" then
            for id in pairs(trains) do Trains.destroy(id, "command") end
        else
            local t = tonumber(a1) and trains[tonumber(a1)] or nearestTrain(p, 100)
            if t then Trains.destroy(t.id, "command") end
        end
    elseif cmd == "list" then
        for _, t in pairs(trains) do
            local seg, s = t.path:at(t.u)
            tell(p, "#%d  %d kocsi  %s %.0f m  %.0f km/h  vezető: %s", t.id, #t.cars, seg, s, math.abs(t.v) * 3.6,
                t.driver and getPlayerName(t.driver) or "-")
        end
    elseif cmd == "dest" then
        local t = Trains.ofPlayer(p) or nearestTrain(p)
        if not t then return tell(p, "Nincs vonat a közelben.") end
        if not a1 or a1 == "clear" then
            Switches.setDestination(t, nil)
            return tell(p, "Cél törölve (#%d).", t.id)
        end
        if not Net.segment(a1) then return tell(p, "Ismeretlen szakasz.") end
        Switches.setDestination(t, a1, tonumber(a2) or 0)
        local A = t.authority
        tell(p, "Cél: %s %.0f m (#%d) - engedély: %s, %.0f m", a1, tonumber(a2) or 0, t.id, A and A.reason or "-", A and A.remaining or 0)
    elseif cmd == "tp" then
        local seg, s = a1, tonumber(a2) or 0
        if not Net.segment(seg) then return tell(p, "Ismeretlen szakasz.") end
        local x, y, z, tx, ty = Net.pointAt(seg, s)
        setElementPosition(p, x + ty * 3, y - tx * 3, z + 1.2)
    else
        tell(p, "/rwtrain spawn [light|re2|re3|re4] | drive [id] | ride [kocsi] | leave | remove [id|all] | list | dest <szakasz> <s> | dest clear | tp <szakasz> <s>")
    end
end)
