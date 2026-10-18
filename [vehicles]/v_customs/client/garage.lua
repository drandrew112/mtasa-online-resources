-- v_customs :: drive-in / drive-out animations (client)
--
-- Runs inside the session's private dimension. The car is frozen and moved by
-- hand every frame (the driver syncs it), the camera sits at a fixed point in
-- the workshop (outside for the drive-out) and follows the car, and a local copy of the garage door is
-- animated - the shared door in dimension 0 belongs to server/workshop.lua.

Garage = Garage or {}

local anim   -- { veh, cam, door, start, update(elapsed) -> finished, done }

local function lerp(a, b, t) return a + (b - a) * t end

local function lerpAngle(a, b, t)
    local d = ((b - a + 180) % 360) - 180
    return a + d * t
end

local function easeOut(t)   return 1 - (1 - t) * (1 - t) end
-- starts at rest, ends moving at distance/duration speed (handed over to the server)
local function easeLaunch(t) return t * t * (2 - t) end

local function restZ(veh, floorZ)
    return floorZ + (getElementDistanceFromCentreOfMassToBaseOfModel(veh) or 0.6)
end

local function doorPos(ws, open)
    local d = ws.door
    if not open then return d.x, d.y, d.z end
    return d.x + d.open[1], d.y + d.open[2], d.z + d.open[3]
end

local function createDoor(ws, dim, open)
    local d = ws.door
    local r = (open and d.openRot) or { 0, 0, 0 }
    local x, y, z = doorPos(ws, open)
    local obj = createObject(d.model, x, y, z, (d.rx or 0) + r[1], (d.ry or 0) + r[2], (d.rz or 0) + r[3])
    if obj then setElementDimension(obj, dim) end
    return obj
end

-- Always a full stroke: the local door is created at one end and never reversed.
local function moveDoor(obj, ws, open)
    if not isElement(obj) then return end
    local x, y, z = doorPos(ws, open)
    local r = ws.door.openRot or { 0, 0, 0 }
    local s = open and 1 or -1
    moveObject(obj, ws.door.time, x, y, z, r[1] * s, r[2] * s, r[3] * s, "InOutQuad")
end

local function render()
    local a = anim
    if not a then return end
    if not isElement(a.veh) then
        Garage.stop()
        return
    end

    local finished = a.update(getTickCount() - a.start)

    local vx, vy, vz = getElementPosition(a.veh)
    local c = a.cam
    setCameraMatrix(c[1], c[2], c[3], vx, vy, vz + 0.3)

    if finished then
        local done = a.done
        local _, _, rz = getElementRotation(a.veh)
        Garage.stop(true)
        if done then done(vx, vy, vz, rz) end
    end
end

local function begin(veh, cam, door, update, done)
    Garage.stop()
    anim = { veh = veh, cam = cam, door = door, start = getTickCount(), update = update, done = done }
    setElementFrozen(veh, true)
    addEventHandler("onClientPreRender", root, render)
end

-- keepDoor: a finished animation leaves its door standing (shut behind the car
-- during the menu, up after the drive-out) until Garage.cleanup().
function Garage.stop(keepDoor)
    if not anim then return end
    removeEventHandler("onClientPreRender", root, render)
    if not keepDoor and isElement(anim.door) then destroyElement(anim.door) end
    Garage.door = keepDoor and anim.door or nil
    anim = nil
end

-- Destroys the leftover door of a finished animation.
function Garage.cleanup()
    Garage.stop()
    if isElement(Garage.door) then destroyElement(Garage.door) end
    Garage.door = nil
end

function Garage.isRunning()
    return anim ~= nil
end

-- Car is snapped to the workshop's start pose (however it came in), then rolls
-- to the park spot while the door shuts behind it. done() fires when it stands
-- still.
function Garage.enter(veh, ws, dim, done)
    Garage.cleanup()
    local dur = Customs.ANIM.enter
    local s = ws.enter
    local sx, sy, sz, srz = s[1], s[2], restZ(veh, s[3]), s[4]
    setElementVelocity(veh, 0, 0, 0)
    setElementAngularVelocity(veh, 0, 0, 0)
    setElementPosition(veh, sx, sy, sz)
    setElementRotation(veh, 0, 0, srz)
    local p = ws.park
    local ez = restZ(veh, p[3])

    local door = createDoor(ws, dim, true)
    local doorAt = math.max(0, dur - ws.door.time - 300)
    local doorMoving = false

    begin(veh, ws.cam, door, function(el)
        if not doorMoving and el >= doorAt then
            doorMoving = true
            moveDoor(door, ws, false)
        end
        local t = easeOut(math.min(1, el / dur))
        setElementPosition(veh, lerp(sx, p[1], t), lerp(sy, p[2], t), lerp(sz, ez, t))
        setElementRotation(veh, 0, 0, lerpAngle(srz, p[4], t))
        return el >= dur and el >= doorAt + ws.door.time
    end, done)
end

-- The camera cuts outside, facing the door; behind the shut door the car is
-- turned round at once, then the door goes up and the car drives out.
-- done(x, y, z, rz) fires at the outside point, still in the private dimension.
function Garage.exit(veh, ws, dim, done)
    Garage.cleanup()
    local drive = Customs.ANIM.driveOut
    local e = ws.exit
    setElementRotation(veh, 0, 0, e[4])
    local sx, sy, sz = getElementPosition(veh)
    local ez = restZ(veh, e[3])

    local door = createDoor(ws, dim, false)
    moveDoor(door, ws, true)
    local wait = ws.door.time

    begin(veh, ws.exitCam, door, function(el)
        if el < wait then return false end
        local t = easeLaunch(math.min(1, (el - wait) / drive))
        setElementPosition(veh, lerp(sx, e[1], t), lerp(sy, e[2], t), lerp(sz, ez, t))
        return el >= wait + drive
    end, done)
end
