-- Traffic vehicles on the client ("puppets"). The server owns the simulation; every client places the
-- vehicles itself each frame from the last state record (segment, s, v, a, lateral, next segment),
-- extrapolated with the same rule as Sync.predict on the server. Corrections are blended out.
--
-- state = { code, s, v, a, t0, next, prev, lat (at s), latTarget, latSlope, err, errT, zfix, zfixTarget, groundAt }
-- The lateral offset is a function of the distance driven since s (Geo.latAfter), so lane offset
-- changes are steered: the heading below is taken from positions that include the offset.

Puppets = { list = {}, debug = false }

local P = Puppets.list
local T = TRAFFIC
local abs, exp, sqrt, min = math.abs, math.exp, math.sqrt, math.min
local getTickCount = getTickCount
local ERR_BLEND = 300      -- ms time constant of correction blending
local SNAP_ERR = 10        -- larger corrections snap
local HEAD_SPAN = 1.8      -- heading is taken over +-this many metres (smooth across lane kinks)
local FAR_UPDATE = 500     -- streamed-out vehicles are moved this often (keeps streaming right)
local STALE = 10000

local function predict(s, v, a, dt)
    local ta = dt < 1 and dt or 1
    local v1 = v + a * ta
    if v1 < 0 then
        local tStop = a < 0 and -v / a or 0
        return s + v * tStop * 0.5, 0
    end
    return s + (v + v1) * 0.5 * ta + v1 * (dt - ta), v1
end

-- chain (prev, code, next) and the position on it
local chainBuf = {}
local function chainOf(st)
    local n, base = 0, 0
    if st.prev and st.prev ~= 0 then
        n = 1; chainBuf[1] = st.prev
        base = Geo.length(st.prev)
    end
    n = n + 1; chainBuf[n] = st.code
    if st.next and st.next ~= 0 then n = n + 1; chainBuf[n] = st.next end
    for i = n + 1, #chainBuf do chainBuf[i] = nil end
    return chainBuf, n, base
end

-- displayed s (in the frame of st.code, may run past its end) and speed
local function current(st, now)
    local s, v = predict(st.s, st.v, st.a, (now - st.t0) / 1000)
    if st.err ~= 0 then
        s = s + st.err * exp(-(now - st.errT) / ERR_BLEND)
    end
    return s, v
end

------------------------------------------------------------------------ incoming states

local function apply(veh, code, s, v, a, lat, latTarget, latSlope, nxt, flags, latRate, t0)
    local st = P[veh]
    local now = getTickCount()
    if st then
        -- where the vehicle is drawn now, expressed in the new record's frame
        local sd = current(st, now)
        local sNew = predict(s, v, a, (now - t0) / 1000)
        local err
        if code == st.code then
            err = sd - sNew
        elseif code == st.next then
            err = (sd - Geo.length(st.code)) - sNew
        elseif st.code == nxt then
            err = (sd + Geo.length(code)) - sNew
        end
        if code ~= st.code then
            if code == st.next then st.prev = st.code
            elseif code ~= st.prev then st.prev = nil end
        end
        st.code, st.s, st.v, st.a, st.t0, st.next = code, s, v, a, t0, nxt
        st.lat, st.latTarget, st.latSlope, st.latRate = lat, latTarget, latSlope, latRate
        if err and abs(err) < SNAP_ERR then st.err, st.errT = err, now else st.err = 0 end
    else
        st = { code = code, s = s, v = v, a = a, t0 = t0, next = nxt, lat = lat, latTarget = latTarget,
               latSlope = latSlope, latRate = latRate, err = 0, errT = now, zfix = 0, zfixTarget = 0, groundAt = 0, farAt = 0,
               ctrlAt = 0 }
        P[veh] = st
    end
    st.seen = now
    if flags % 2 == 1 then
        local ped = getVehicleOccupant(veh, 0)
        if ped then
            setPedControlState(ped, "horn", true)
            setTimer(function() if isElement(ped) then setPedControlState(ped, "horn", false) end end, 700, 1)
        end
    end
end

-- the per-frame placement is attached while there are puppets and removes itself when the last
-- one is gone (released, destroyed or stale)
local placing = false
local placePuppets
local function startPlacing()
    if placing or not next(P) then return end
    placing = true
    addEventHandler("onClientPreRender", root, placePuppets)
end

addEvent(EV_STATE, true)
addEventHandler(EV_STATE, resourceRoot, function(data)
    local t0 = getTickCount() - getPlayerPing(localPlayer) / 2
    for i = 1, #data, 11 do
        local veh = data[i]
        if isElement(veh) then
            apply(veh, data[i + 1], data[i + 2], data[i + 3], data[i + 4], data[i + 5], data[i + 6], data[i + 7],
                data[i + 8], data[i + 9], data[i + 10], t0)
        end
    end
    startPlacing()
end)

addEvent(EV_RELEASE, true)
addEventHandler(EV_RELEASE, resourceRoot, function(veh, reason, vx, vy, vz)
    if not P[veh] then return end
    P[veh] = nil
    -- the driver's tiny throttle (DRIVER_THROTTLE) must not stay on: it gets out / sits still now
    local driver = isElement(veh) and getVehicleOccupant(veh, 0)
    if driver and getElementType(driver) == "ped" then setPedAnalogControlState(driver, "accelerate", 0) end
    if isElement(veh) and isElementStreamedIn(veh) then
        setElementVelocity(veh, vx / 50, vy / 50, vz / 50)
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if P[source] then P[source] = nil end
end)

------------------------------------------------------------------------ placing

local baseCache = {}

local function baseOf(veh)
    local m = getElementModel(veh)
    local b = baseCache[m]
    if not b then
        b = getElementDistanceFromCentreOfMassToBaseOfModel(veh)
        if not b or b <= 0 then return 0.8 end
        baseCache[m] = b
    end
    return b
end

local function place(veh, st, now, dt, full)
    local s, v = current(st, now)
    local dx = s - st.s     -- distance driven since the record
    local chain, n, base = chainOf(st)
    s = s + base
    local latAfter, lat0, rate0, latT, slope = Geo.latAfter, st.lat, st.latRate, st.latTarget, st.latSlope
    local lat, rate = latAfter(lat0, rate0, latT, slope, dx)

    local x, y, z = Geo.poseOnChain(chain, n, s, lat)
    if not x then return end
    if not full then
        setElementPosition(veh, x, y, z + 1, false)
        return
    end
    -- heading from the lateral rate reached so far (not from the curve ahead): a standing car whose
    -- target just changed must not yaw on the spot, it only turns once it rolls
    local ax, ay, az = Geo.poseOnChain(chain, n, s - HEAD_SPAN, lat - rate * HEAD_SPAN)
    local bx, by, bz = Geo.poseOnChain(chain, n, s + HEAD_SPAN, lat + rate * HEAD_SPAN)
    local fx, fy, fz = bx - ax, by - ay, bz - az
    local l = sqrt(fx * fx + fy * fy + fz * fz)
    if l < 0.05 then
        local _, _, _, tx, ty, tz = Geo.poseOnChain(chain, n, s, 0)
        fx, fy, fz = tx, ty, tz
    else
        fx, fy, fz = fx / l, fy / l, fz / l
    end

    -- ground correction: the lane z comes from the path nodes
    if now >= st.groundAt then
        st.groundAt = now + 300 + math.random(100)
        local gz = getGroundPosition(x, y, z + 2.5)
        if gz and gz ~= 0 and abs(gz - z) < 2 then st.zfixTarget = gz - z end
    end
    local dz = st.zfixTarget - st.zfix
    local zr = 2 * dt
    st.zfix = abs(dz) <= zr and st.zfixTarget or st.zfix + (dz > 0 and zr or -zr)

    local rx, ry, rz = Geo.rotation(fx, fy, fz)
    setElementPosition(veh, x, y, z + st.zfix + baseOf(veh), false)
    setElementRotation(veh, rx, ry, rz)
    setElementVelocity(veh, fx * v / 50, fy * v / 50, fz * v / 50)
    setElementAngularVelocity(veh, 0, 0, 0)

    -- without any input GTA brakes a ped-driven car (locked wheels, skid marks): a touch of throttle
    if now >= st.ctrlAt then
        st.ctrlAt = now + 100
        local ped = getVehicleOccupant(veh, 0)
        if ped then
            setPedControlState(ped, "brake_reverse", false)
            setPedControlState(ped, "handbrake", false)
            setPedAnalogControlState(ped, "accelerate", v > 0.3 and T.DRIVER_THROTTLE or 0)
        end
    end
end

local lastFrame
placePuppets = function()
    local now = getTickCount()
    local dt = (now - (lastFrame or now)) / 1000
    lastFrame = now
    if dt > 0.2 then dt = 0.2 end
    for veh, st in pairs(P) do
        if not isElement(veh) or now - st.seen > STALE then
            P[veh] = nil
        elseif isElementStreamedIn(veh) then
            place(veh, st, now, dt, true)
        elseif now >= st.farAt then
            st.farAt = now + FAR_UPDATE
            place(veh, st, now, FAR_UPDATE / 1000, false)
        end
    end
    if not next(P) then
        placing, lastFrame = false, nil
        removeEventHandler("onClientPreRender", root, placePuppets)
    end
end

-- headlights at night
setTimer(function()
    local h = getTime()
    local on = h >= 20 or h < 6
    for veh in pairs(P) do
        if isElement(veh) and isElementStreamedIn(veh) then setVehicleOverrideLights(veh, on and 2 or 1) end
    end
end, 3000, 0)

function Puppets.state(veh) return P[veh] end
