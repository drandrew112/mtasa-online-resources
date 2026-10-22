-- Motor (client): drives the AI peds this client syncs. The server sends a command per ped (EV_CMD) to its syncer;
-- every frame the ped is turned and moved with control states: walk the points, stand / face, fight (aim + fire,
-- melee, pull an unarmed ped's target out of its vehicle), get out of a vehicle (exit animation). Only peds that are streamed in and synced here are driven; the
-- per-frame handler is attached only while there are commands.
--
-- st = { cmd, i (next point), yaw, ctl = { [control] = state }, ... runtime timers }

Motor = { list = {} }

local S = Motor.list
local T = AIPEDS
local sqrt, atan2, deg, rad, sin, cos, abs, random = math.sqrt, math.atan2, math.deg, math.rad, math.sin, math.cos, math.abs, math.random
local getTickCount = getTickCount
local CONTROLS = { "forwards", "walk", "sprint", "fire", "aim_weapon", "jump" }
local ARRIVE = { walk = 0.9, run = 1.3, sprint = 1.8 }
local TURN = { walk = 300, run = 420, sprint = 540 }   -- deg / s
local attached = false
local camSign = 1          -- setPedCameraRotation sign, calibrated from how the peds actually move
local calib = { bad = 0, good = 0 }

------------------------------------------------------------------------ controls

local function ctl(ped, st, name, on)
    if st.ctl[name] == on then return end
    st.ctl[name] = on
    setPedControlState(ped, name, on)
end

local function releaseAll(ped, st)
    if not isElement(ped) then return end
    for _, c in ipairs(CONTROLS) do setPedControlState(ped, c, false) end
    if st then st.ctl = {} end
end

local function setMove(ped, st, on, speed)
    ctl(ped, st, "forwards", on)
    ctl(ped, st, "walk", on and speed == "walk")
    ctl(ped, st, "sprint", on and speed == "sprint")
end

local function stopCombat(ped, st)
    ctl(ped, st, "fire", false)
    ctl(ped, st, "aim_weapon", false)
end

-- GTA rotZ of the direction to (tx, ty)
local function yawTo(x, y, tx, ty)
    return deg(atan2(-(tx - x), ty - y))
end

local function setYaw(ped, st, yaw)
    st.yaw = yaw
    setElementRotation(ped, 0, 0, yaw, "default", true)
    setPedCameraRotation(ped, camSign * yaw)
end

local function turnTo(ped, st, yaw, rate, dt)
    local cur = st.yaw
    if not cur then
        local _, _, rz = getElementRotation(ped)
        cur = rz
    end
    local diff = (yaw - cur + 540) % 360 - 180
    local step = rate * dt
    if abs(diff) <= step then cur = yaw else cur = cur + (diff > 0 and step or -step) end
    setYaw(ped, st, cur)
    return abs(diff)
end

local function report(ped, kind, data)
    triggerServerEvent(EV_REPORT, resourceRoot, ped, kind, data)
end

-- the camera rotation sign: a ped walking straight (facing its way) must move along its facing
local function calibrate(ped, st, now)
    if now < (st.calibAt or 0) then return end
    st.calibAt = now + 500
    local vx, vy = getElementVelocity(ped)
    local v = sqrt(vx * vx + vy * vy)
    if v < 0.02 or not st.yaw then return end
    local fx, fy = -sin(rad(st.yaw)), cos(rad(st.yaw))
    local dot = (vx * fx + vy * fy) / v
    if dot < 0.2 then calib.bad = calib.bad + 1 else calib.good = calib.good + 1 end
    if calib.bad >= 6 and calib.bad > calib.good * 2 then
        camSign = -camSign
        calib.bad, calib.good = 0, 0
        outputDebugString("[ai_peds] ped camera rotation sign flipped to " .. camSign)
    elseif calib.good > 40 then
        calib.bad, calib.good = 0, 0
    end
end

------------------------------------------------------------------------ moving

-- forward probe: something right in front -> step around it for a moment
local function avoid(ped, st, now, x, y, z, ignore)
    if now >= (st.probeAt or 0) then
        st.probeAt = now + 250
        local fx, fy = -sin(rad(st.yaw or 0)), cos(rad(st.yaw or 0))
        local hit, _, _, _, el = processLineOfSight(x, y, z, x + fx * 1.3, y + fy * 1.3, z, false, true, true, true,
            false, false, false, false, ped)
        if hit and el ~= ignore then
            st.avoidUntil = now + 700
            st.avoidDir = st.avoidDir == 1 and -1 or 1
        end
    end
    if now < (st.avoidUntil or 0) then return 55 * (st.avoidDir or 1) end
    return 0
end

-- not getting anywhere while trying to move: jump once, then tell the server
local function stuckCheck(ped, st, now, x, y)
    if now < (st.stuckAt or 0) then return end
    st.stuckAt = now + 1000
    if st.lx and (x - st.lx) ^ 2 + (y - st.ly) ^ 2 < 0.09 then
        st.stuckN = (st.stuckN or 0) + 1
        if st.stuckN == 2 then
            ctl(ped, st, "jump", true)
            st.jumpOff = now + 150
        elseif st.stuckN >= 4 then
            st.stuckN = 0
            if now - (st.stuckReported or 0) > 3000 then
                st.stuckReported = now
                report(ped, "stuck")
            end
        end
    else
        st.stuckN = 0
    end
    st.lx, st.ly = x, y
end

-- follow cmd.pts from st.i; returns true while there are points left
local function follow(ped, st, now, dt, x, y, z, speed, ignore)
    local pts = st.cmd.pts
    if not pts or st.i > #pts then return false end
    local pt = pts[st.i]
    local dx, dy = pt[1] - x, pt[2] - y
    if dx * dx + dy * dy < (ARRIVE[speed] or 1.3) ^ 2 then
        st.i = st.i + 1
        report(ped, "wp", st.i)
        if st.i > #pts then
            setMove(ped, st, false)
            report(ped, "arrived", st.i)
            return false
        end
        pt = pts[st.i]
    end
    local off = avoid(ped, st, now, x, y, z, ignore)
    local diff = turnTo(ped, st, yawTo(x, y, pt[1], pt[2]) + off, TURN[speed] or 420, dt)
    -- a sharp turn: turn on the spot first (no wide arcs into walls / roads)
    setMove(ped, st, diff < 70, speed)
    stuckCheck(ped, st, now, x, y)
    if diff < 15 then calibrate(ped, st, now) end
    return true
end

------------------------------------------------------------------------ fighting

local function aimPoint(st, t, tx, ty, tz, d, now)
    if now >= (st.jitterAt or 0) then
        st.jitterAt = now + 150
        local spread = (1 - (st.cmd.acc or T.ACCURACY)) * (0.5 + d * 0.06)
        st.jx, st.jy, st.jz = (random() - 0.5) * 2 * spread, (random() - 0.5) * 2 * spread, (random() - 0.5) * spread
    end
    local up = getElementType(t) == "vehicle" and 0.4 or 0.5
    return tx + st.jx, ty + st.jy, tz + up + st.jz
end

local function fireBursts(ped, st, now)
    local c = st.cmd
    if not st.burstEnd then
        st.burstEnd = 0
        st.nextBurst = now + random(300, 700)   -- reaction time
    end
    if now < st.burstEnd then
        ctl(ped, st, "fire", true)
    else
        ctl(ped, st, "fire", false)
        if now >= st.nextBurst then
            local b, p = c.burst or { 200, 500 }, c.pause or { 600, 1200 }
            st.burstEnd = now + random(b[1], b[2])
            st.nextBurst = st.burstEnd + random(p[1], p[2])
        end
    end
end

-- unarmed, target in a slow vehicle: GTA jack (the enter task walks the ped to the door and pulls the target out;
-- the ped ends up in the seat and gets out again in drive()). Returns true while the jack runs.
local JACK_TYPES = { Automobile = true, Bike = true, BMX = true, Quad = true, ["Monster Truck"] = true }

local function jackTarget(ped, st, now, t, tveh, d)
    if st.jackV then
        if not tveh then
            -- target out: give the animation a moment, then fight (inside the seat drive() gets the ped out)
            st.jackEnd = math.min(st.jackEnd, now + 1500)
            if now < st.jackEnd then return true end
        elseif tveh == st.jackV and now < st.jackEnd then
            return true
        end
        st.jackV, st.jackRetry = nil, now + T.JACK_RETRY
        return false
    end
    if not tveh or now < (st.jackRetry or 0) or d > T.JACK_DIST or not JACK_TYPES[getVehicleType(tveh)] then return false end
    local vx, vy, vz = getElementVelocity(tveh)
    if (vx * vx + vy * vy + vz * vz) * 2500 > T.JACK_MAX_SPEED ^ 2 then return false end
    setMove(ped, st, false)
    stopCombat(ped, st)
    -- passenger = false: the driver seat, the only one GTA jacks (the target in another seat is not pulled out)
    if getPedOccupiedVehicleSeat(t) == 0 and setPedEnterVehicle(ped, tveh, false) then
        st.jackV, st.jackEnd = tveh, now + T.JACK_TIMEOUT
        st.jackLeave = now + T.JACK_TIMEOUT + 5000   -- a late finished jack still gets out
        return true
    end
    st.jackRetry = now + T.JACK_RETRY
    return false
end

local function combat(ped, st, now, dt, x, y, z)
    local c = st.cmd
    local t = c.t
    if not isElement(t) or ((getElementType(t) == "ped" or getElementType(t) == "player") and isPedDead(t)) then
        setMove(ped, st, false)
        stopCombat(ped, st)
        return
    end
    local tx, ty, tz = getElementPosition(t)
    local tveh = getElementType(t) ~= "vehicle" and getPedOccupiedVehicle(t)
    local d = sqrt((tx - x) ^ 2 + (ty - y) ^ 2 + (tz - z) ^ 2)
    if now >= (st.losAt or 0) then
        st.losAt = now + 200
        st.los = isLineOfSightClear(x, y, z + 0.6, tx, ty, tz + 0.4, true, not tveh, false, true, false, false, false, ped)
    end
    local yaw = yawTo(x, y, tx, ty)

    if c.me then
        if jackTarget(ped, st, now, t, tveh, d) then return end
        if d > (c.r or T.MELEE_RANGE) + 0.2 then
            ctl(ped, st, "fire", false)
            if not (d > 6 and follow(ped, st, now, dt, x, y, z, "run", t)) then
                local off = avoid(ped, st, now, x, y, z, tveh or t)
                local diff = turnTo(ped, st, yaw + off, 540, dt)
                setMove(ped, st, diff < 70, d > 5 and "sprint" or "run")
                stuckCheck(ped, st, now, x, y)
            end
        else
            setMove(ped, st, false)
            turnTo(ped, st, yaw, 720, dt)
            local phase = (now - (st.meleeT0 or now)) % 700
            if not st.meleeT0 then st.meleeT0 = now end
            ctl(ped, st, "fire", phase < 150)
        end
        return
    end

    if st.los and d <= (c.r or 30) then
        setMove(ped, st, false)
        turnTo(ped, st, yaw, 720, dt)
        local ax, ay, az = aimPoint(st, t, tx, ty, tz, d, now)
        setPedAimTarget(ped, ax, ay, az)
        ctl(ped, st, "aim_weapon", true)
        fireBursts(ped, st, now)
        return
    end
    -- no line of sight / out of range: move (route, else straight at it); a hold point (cover) is not left
    stopCombat(ped, st)
    st.burstEnd = nil
    if follow(ped, st, now, dt, x, y, z, c.sp or "run", t) then return end
    if c.hold and c.pts then
        setMove(ped, st, false)
        turnTo(ped, st, yaw, 540, dt)
        return
    end
    local off = avoid(ped, st, now, x, y, z, tveh or t)
    local diff = turnTo(ped, st, yaw + off, 540, dt)
    setMove(ped, st, diff < 70, c.sp or "run")
    stuckCheck(ped, st, now, x, y)
end

------------------------------------------------------------------------ getting out

-- only setPedExitVehicle: it asks the server, so every client and the server see the ped get out. The enter_exit
-- control state would get it out on this client alone (server and the other clients keep it seated: a ped floating
-- above the vehicle, immune to damage, that cannot be jacked). Refused (1500 ms after the last enter / exit, being
-- jacked): tried again a moment later.
local function exitVehicle(ped, st, now)
    if now < (st.exitAt or 0) then return end
    st.exitAt = now + (setPedExitVehicle(ped) and 3000 or 500)
end

-- sat down in the target's seat after a jack: straight out again (retried while the door / animation blocks it)
local function leaveJacked(ped, st, now)
    if now < (st.jackOutAt or 0) then return end
    st.jackOutAt = now + (setPedExitVehicle(ped) and 1500 or 500)
end

------------------------------------------------------------------------ frame

local function drive(ped, st, now, dt)
    if st.jumpOff and now >= st.jumpOff then st.jumpOff = nil; ctl(ped, st, "jump", false) end
    local c = st.cmd
    if getPedOccupiedVehicle(ped) then
        if c.m == "exit" then exitVehicle(ped, st, now)
        elseif now < (st.jackLeave or 0) then leaveJacked(ped, st, now) end
        return
    end
    if st.jackOutAt then st.jackV, st.jackOutAt, st.jackLeave = nil, nil, nil end
    local x, y, z = getElementPosition(ped)
    -- out here but the server still sends "exit" a second later (exit not confirmed there): tell it where
    if c.m == "exit" then
        if not st.exitedAt then st.exitedAt = now + 1000
        elseif now >= st.exitedAt then
            st.exitedAt = now + 1000
            report(ped, "exited", { x, y, z })
        end
    end
    local m = c.m
    if m == "move" then
        stopCombat(ped, st)
        if not follow(ped, st, now, dt, x, y, z, c.sp or "walk") then setMove(ped, st, false) end
    elseif m == "combat" then
        combat(ped, st, now, dt, x, y, z)
    else
        setMove(ped, st, false)
        stopCombat(ped, st)
        if c.fx then turnTo(ped, st, yawTo(x, y, c.fx, c.fy), 240, dt) end
    end
end

local function frame(slice)
    local now = getTickCount()
    local dt = math.min((slice or 16) / 1000, 0.1)
    for ped, st in pairs(S) do
        if not isElement(ped) then
            S[ped] = nil
        elseif isElementStreamedIn(ped) and isElementSyncer(ped) and not isPedDead(ped) then
            if not st.active then
                st.active = true
                st.ctl, st.yaw = {}, nil
            end
            drive(ped, st, now, dt)
        elseif st.active then
            st.active = false
            releaseAll(ped, st)
        end
    end
    if not next(S) and attached then
        attached = false
        removeEventHandler("onClientPreRender", root, frame)
    end
end

local function attach()
    if attached then return end
    attached = true
    addEventHandler("onClientPreRender", root, frame)
end

------------------------------------------------------------------------ server commands

addEvent(EV_CMD, true)
addEventHandler(EV_CMD, resourceRoot, function(ped, cmd)
    if not isElement(ped) or type(cmd) ~= "table" then return end
    local st = S[ped]
    if not st then
        st = { ctl = {} }
        S[ped] = st
    end
    if st.cmd and st.cmd.v == cmd.v then return end
    local old = st.cmd
    st.cmd = cmd
    st.i = cmd.i or 1
    st.stuckN, st.lx, st.exitedAt = 0, nil, nil
    if old and old.m == "combat" and (cmd.m ~= "combat" or old.t ~= cmd.t) then
        stopCombat(ped, st)
        st.burstEnd, st.meleeT0 = nil, nil
        st.jackV, st.jackRetry = nil, nil
    end
    attach()
end)

addEvent(EV_DROP, true)
addEventHandler(EV_DROP, resourceRoot, function(ped)
    local st = S[ped]
    if not st then return end
    S[ped] = nil
    if st.active then releaseAll(ped, st) end
end)

addEventHandler("onClientElementDestroy", root, function()
    if S[source] then S[source] = nil end
end)

function Motor.debugInfo(ped)
    return S[ped]
end
