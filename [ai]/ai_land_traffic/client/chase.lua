-- Chase motor (client): the syncer of a chase vehicle (element data DATA_CHASE, server/chase.lua) steers its driver
-- ped with control states every CHASE_STEER ms. Modes:
--   follow  stays behind the target at a distance that shrinks with the aggression
--   box     drives up beside the target (left side) to squeeze it towards the kerb
--   pit     aims at the target's rear quarter; alongside it, turns into it (PIT manoeuvre)
--   ram     straight at where the target will be in half a second, full throttle
--   block   cuts off: aims at where the target will be in a few seconds
-- The mode's aim point is only used with the target in plain sight close by; otherwise the car follows the road path
-- the server sends (EV_CHASE_PATH: navmesh route to the target, pure pursuit, slowing down before corners). Rays
-- ahead steer it around walls; when it hardly moves for 1.5 s it reverses out (repeated stucks: longer, alternating
-- sides), and with its nose against a wall it backs off at once.
-- The timer only runs while a streamed-in chase vehicle is synced here.

local list = {}        -- [vehicle] = state { path, pathAt, pathI, lastX, lastY, lastAt, stuckN, stuckAt, reverseUntil,
                       --                     reverseSide, commitUntil, fireAt, driving }
local timer
local sqrt, atan2, abs, min, max = math.sqrt, math.atan2, math.abs, math.min, math.max
local CONTROLS = { "accelerate", "brake_reverse", "handbrake", "vehicle_fire", "horn" }
local COS30, SIN30 = 0.866, 0.5

local function carrier(t)
    if isElement(t) and (getElementType(t) == "player" or getElementType(t) == "ped") then
        return getPedOccupiedVehicle(t) or t
    end
    return t
end

local function releaseControls(ped)
    if not isElement(ped) then return end
    for _, c in ipairs(CONTROLS) do setPedControlState(ped, c, false) end
    setPedAnalogControlState(ped, "vehicle_left", 0)
    setPedAnalogControlState(ped, "vehicle_right", 0)
end

-- the point the vehicle drives at for this mode
local function aimPoint(o, vx, vy, tx, ty, tvx, tvy, tfx, tfy, dist)
    local m = o.m
    if m == "ram" then
        return tx + tvx * 25, ty + tvy * 25
    elseif m == "block" then
        local lead = min(4, dist / 15)
        return tx + tvx * 50 * lead, ty + tvy * 50 * lead
    elseif m == "box" then
        -- beside the target, on its left (rx, ry = its right)
        local rx, ry = tfy, -tfx
        return tx + tvx * 30 - rx * 2.6, ty + tvy * 30 - ry * 2.6
    elseif m == "pit" then
        -- the rear quarter (right side), then into it once alongside
        local rx, ry = tfy, -tfx
        local relx, rely = vx - tx, vy - ty
        local along = relx * tfx + rely * tfy
        if dist < 7 and along > -3.5 and along < 1.5 then
            return tx + tfx * 1.5 - rx * 0.5, ty + tfy * 1.5 - ry * 0.5
        end
        return tx - tfx * 2.2 + rx * 1.4 + tvx * 20, ty - tfy * 2.2 + ry * 1.4 + tvy * 20
    end
    -- follow: about a second ahead of the target
    return tx + tvx * 50, ty + tvy * 50
end

------------------------------------------------------------------------ road path (server/chase.lua updatePath)

addEvent(EV_CHASE_PATH, true)
addEventHandler(EV_CHASE_PATH, resourceRoot, function(veh, pts)
    local st = list[veh]
    if st and type(pts) == "table" then st.path, st.pathAt, st.pathI = pts, getTickCount(), 1 end
end)

-- the point `look` metres along the path ahead of the car (pure pursuit) and the sharpest turn (radians) within the
-- next `scan` metres; nil when the path is old or the car is off it
local function pathAim(st, vx, vy, look, scan, now)
    local p = st.path
    if not p or now - st.pathAt > 4000 then return nil end
    local n = #p / 3
    local best, bd = nil, math.huge
    for i = max(1, (st.pathI or 1) - 2), n do
        local d = (p[i * 3 - 2] - vx) ^ 2 + (p[i * 3 - 1] - vy) ^ 2
        if d < bd then best, bd = i, d end
    end
    if not best or bd > 22 * 22 then return nil end
    st.pathI = best
    -- distances and turns along the path from its nearest point (the car may be just past it)
    local ax, ay, turn, acc = nil, nil, 0, 0
    local px, py, hx, hy = p[best * 3 - 2], p[best * 3 - 1], nil, nil
    for i = best + 1, n do
        local x, y = p[i * 3 - 2], p[i * 3 - 1]
        local sl = sqrt((x - px) ^ 2 + (y - py) ^ 2)
        if sl > 0.5 then
            local ux, uy = (x - px) / sl, (y - py) / sl
            if hx and acc < scan then
                local a = abs(atan2(hx * uy - hy * ux, hx * ux + hy * uy))
                if a > turn then turn = a end
            end
            hx, hy = ux, uy
        end
        acc = acc + sl
        if not ax and acc >= look then ax, ay = x, y end
        if ax and acc >= scan then break end
        px, py = x, y
    end
    if not ax then ax, ay = p[n * 3 - 2], p[n * 3 - 1] end
    return ax, ay, turn
end

-- a wall (building / object, not a vehicle) in direction (dx, dy) within len m from (x, y, z); the target never
-- counts, nor a surface facing up (the road rising ahead, a kerb)
local function blocked(veh, x, y, z, dx, dy, len, target)
    local hit, _, _, _, el, _, _, nz = processLineOfSight(x, y, z, x + dx * len, y + dy * len, z, true, false, false,
        true, false, false, false, false, veh)
    return hit and el ~= target and (nz or 0) < 0.55
end

local function startReverse(st, now, ms, side)
    st.reverseUntil = now + ms
    st.reverseSide = side
end

local function steer(veh, ped, o, st, now)
    local tgt = carrier(o.t)
    if not isElement(tgt) then releaseControls(ped); return end
    local vx, vy, vz = getElementPosition(veh)
    local tx, ty, tz = getElementPosition(tgt)
    local tvx, tvy = getElementVelocity(tgt)
    local tm = getElementMatrix(tgt)
    local tfx, tfy = tm[2][1], tm[2][2]
    local dist = sqrt((tx - vx) ^ 2 + (ty - vy) ^ 2)
    local m = getElementMatrix(veh)
    local fx, fy = m[2][1], m[2][2]
    local fl = sqrt(fx * fx + fy * fy)
    if fl > 0.01 then fx, fy = fx / fl, fy / fl end
    local svx, svy, svz = getElementVelocity(veh)
    local speed = sqrt(svx * svx + svy * svy + svz * svz) * 180          -- km/h
    local fwdSpeed = (svx * fx + svy * fy) * 180                        -- km/h, < 0 = rolling backwards
    local tspeed = sqrt(tvx * tvx + tvy * tvy) * 180

    -- aim: the mode's point with the target in plain sight close by, else the road path to it
    local direct = dist < 45 and not processLineOfSight(vx, vy, vz + 0.8, tx, ty, tz + 0.8, true, false, false, true,
        false, false, false, false, veh)
    local ax, ay, turn
    if not direct then
        ax, ay, turn = pathAim(st, vx, vy, 7 + speed / 3.6 * 0.7, 30 + speed / 3.6 * 1.5, now)
    end
    if not ax then
        ax, ay = aimPoint(o, vx, vy, tx, ty, tvx, tvy, tfx, tfy, dist)
        turn = 0
    end
    local dx, dy = ax - vx, ay - vy
    local angle = atan2(fx * dy - fy * dx, fx * dx + fy * dy)   -- > 0: aim point on the left

    ---------------------------------------------------------------- reversing out
    if st.reverseUntil then
        if now < st.reverseUntil then
            setPedControlState(ped, "accelerate", false)
            setPedControlState(ped, "brake_reverse", true)
            setPedControlState(ped, "handbrake", false)
            -- backwards the nose swings the other way: steering right turns it left (towards an aim on the left)
            local side = st.reverseSide or (angle > 0 and 1 or -1)
            setPedAnalogControlState(ped, "vehicle_left", side < 0 and 1 or 0)
            setPedAnalogControlState(ped, "vehicle_right", side > 0 and 1 or 0)
            return
        end
        st.reverseUntil, st.reverseSide = nil, nil
        st.commitUntil = now + 1200           -- forward for a moment before the next stuck check
        st.lastX, st.lastY, st.lastAt = vx, vy, now
    end

    ---------------------------------------------------------------- stuck: wants to move, hardly moved in 1.5 s
    local wantMove = dist > 7 or not direct
    if not st.lastAt or not wantMove then
        st.lastX, st.lastY, st.lastAt = vx, vy, now
    elseif now - st.lastAt > 1500 then
        local moved = sqrt((vx - st.lastX) ^ 2 + (vy - st.lastY) ^ 2)
        st.lastX, st.lastY, st.lastAt = vx, vy, now
        if moved < 2 and now > (st.commitUntil or 0) then
            -- stuck again soon after: reverse longer, alternating the escape side
            st.stuckN = now - (st.stuckAt or 0) < 12000 and (st.stuckN or 0) + 1 or 1
            st.stuckAt = now
            startReverse(st, now, 1300 + min(3, st.stuckN) * 500,
                st.stuckN >= 2 and ((st.stuckN % 2 == 0) and 1 or -1) or nil)
            return
        end
    end

    ---------------------------------------------------------------- walls ahead: around them, slower, back off
    local probe = 3.5 + max(0, fwdSpeed) / 3.6 * 0.9
    local bx, by, bz = vx + fx * 2.2, vy + fy * 2.2, vz + 0.4
    local lx, ly = fx * COS30 - fy * SIN30, fy * COS30 + fx * SIN30     -- 30 degrees left
    local rx, ry = fx * COS30 + fy * SIN30, fy * COS30 - fx * SIN30     -- 30 degrees right
    local front = blocked(veh, bx, by, bz, fx, fy, probe, tgt)
    local leftHit = blocked(veh, bx, by, bz, lx, ly, probe * 0.75, tgt)
    local rightHit = blocked(veh, bx, by, bz, rx, ry, probe * 0.75, tgt)
    local avoid = 0
    if front or leftHit or rightHit then
        if rightHit and not leftHit then avoid = 0.6
        elseif leftHit and not rightHit then avoid = -0.6
        elseif front then avoid = angle >= 0 and 0.9 or -0.9 end
        -- nose almost against the wall at a crawl: straight back off, nose swinging to the free side
        if front and fwdSpeed < 8 and now > (st.commitUntil or 0) and blocked(veh, bx, by, bz, fx, fy, 1.6, tgt) then
            startReverse(st, now, 1400, avoid >= 0 and 1 or -1)
            return
        end
    end
    angle = angle + avoid

    local amount = min(1, abs(angle) / 0.5)
    setPedAnalogControlState(ped, "vehicle_left", angle > 0 and amount or 0)
    setPedAnalogControlState(ped, "vehicle_right", angle < 0 and amount or 0)

    ---------------------------------------------------------------- speed: corners ahead, steering angle, walls
    local aggr = tonumber(o.a) or 0.5
    local cap = tonumber(o.s) or 180
    if turn > 1.2 then cap = min(cap, 35) elseif turn > 0.7 then cap = min(cap, 55) elseif turn > 0.35 then cap = min(cap, 85) end
    if abs(angle) > 0.9 then cap = min(cap, 30) elseif abs(angle) > 0.5 then cap = min(cap, 55) end
    if front then cap = min(cap, 25) end
    local throttle, brake = speed < cap, speed > cap + 12
    if o.m == "follow" and direct then
        -- keep a gap behind the target (shorter when more aggressive)
        local gap = 26 - aggr * 18
        if dist < gap and speed > tspeed then throttle = false end
        if dist < gap * 0.5 and speed > tspeed + 10 then brake = true end
    elseif o.m == "box" and direct and dist < 9 and speed > tspeed + 8 then
        throttle = false
    end
    if brake then throttle = false end
    setPedControlState(ped, "accelerate", throttle)
    setPedControlState(ped, "brake_reverse", brake and fwdSpeed > 2)
    setPedControlState(ped, "handbrake", abs(angle) > 1.2 and speed > 45)

    -- tank cannon: target in front, close, in sight
    if o.f then
        local fire = direct and dist < 60 and abs(angle) < 0.12 and now >= (st.fireAt or 0)
        if fire then st.fireAt = now + 4000 end
        setPedControlState(ped, "vehicle_fire", fire)
    end
end

local function tick()
    local now = getTickCount()
    for veh, st in pairs(list) do
        local o = isElement(veh) and getElementData(veh, DATA_CHASE)
        local ped = isElement(veh) and getVehicleController(veh)
        if type(o) ~= "table" or not isElementStreamedIn(veh) then
            if st.driving then releaseControls(ped) end
            list[veh] = nil
        elseif ped and getElementType(ped) == "ped" and isElementSyncer(veh) and not isPedDead(ped) then
            st.driving = true
            steer(veh, ped, o, st, now)
        elseif st.driving then
            st.driving = false
            releaseControls(ped)
        end
    end
    if not next(list) and timer then
        killTimer(timer)
        timer = nil
    end
end

local function track(veh)
    if list[veh] or getElementType(veh) ~= "vehicle" or not isElementStreamedIn(veh) then return end
    if type(getElementData(veh, DATA_CHASE)) ~= "table" then return end
    list[veh] = {}
    if not timer then timer = setTimer(tick, TRAFFIC.CHASE_STEER, 0) end
end

addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key == DATA_CHASE then track(source) end
end)
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do track(veh) end
end)
