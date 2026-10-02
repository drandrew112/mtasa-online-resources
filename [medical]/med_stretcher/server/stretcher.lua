-- Server-owned stretcher state. Every Ambulance gets one stretcher object. States:
--   "stowed"  hidden inside the vehicle (attached, alpha 0, no collisions)
--   "moving"  sliding in / out of the vehicle (moveObject), menu disabled
--   "ground"  standing on the ground
--   "pushing" attached in front of a medic (the medic's client drives the movement)
-- A patient can lie on it; loading warps them onto a rear seat, taking out lays them back on it.
-- The menu lives in server/interaction.lua, which is told about every change via onStretcherChanged.

addEvent("stretcher:snapResult", true)
addEvent("onMedicalStateChange") -- fired by medical_system (if running)

local D = STRETCHER_DATA

Stretchers = {}            -- object -> { object, vehicle, state, pusher, patient, seated, menuId, anim }
local byVehicle = {}       -- vehicle -> object
local patientOf = {}       -- ped -> object (lying on it)
local pusherOf = {}        -- player -> object
local lockedIn = {}        -- ped -> vehicle (patient on a rear seat, cannot get out)
local blown = {}           -- vehicle -> true between explode and respawn

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

function notify(player, text)
    if isElement(player) and getElementType(player) == "player" then
        outputChatBox("#e0474c[Stretcher] #ffffff" .. text, player, 255, 255, 255, true)
    end
end

-- Local offset of an element -> world position
local function offsetOf(element, ox, oy, oz)
    local m = getElementMatrix(element)
    return ox * m[1][1] + oy * m[2][1] + oz * m[3][1] + m[4][1],
           ox * m[1][2] + oy * m[2][2] + oz * m[3][2] + m[4][2],
           ox * m[1][3] + oy * m[2][3] + oz * m[3][3] + m[4][3]
end

local function sameWorld(a, b)
    return getElementDimension(a) == getElementDimension(b) and getElementInterior(a) == getElementInterior(b)
end

-- Shortest signed angle difference in degrees (-180..180)
local function angleDelta(from, to)
    return (to - from + 180) % 360 - 180
end

-- Where the stretcher really is. While pushed it is computed from the pusher, because the
-- server-side position of an attached element is not reliable.
local function stretcherPosition(s)
    if s.state == "pushing" and isElement(s.pusher) then
        local o = STRETCHER.PUSH_OFFSET
        return offsetOf(s.pusher, o[1], o[2], o[3])
    end
    return getElementPosition(s.object)
end

-- Is the element standing behind the ambulance (next to the rear doors)?
function isAtVehicleRear(element, vehicle)
    if not isElement(element) or not isElement(vehicle) or not sameWorld(element, vehicle) then return false end
    local rx, ry, rz = offsetOf(vehicle, unpack(STRETCHER.REAR_POINT))
    local ex, ey, ez = getElementPosition(element)
    return getDistanceBetweenPoints3D(rx, ry, rz, ex, ey, ez) <= STRETCHER.REAR_RANGE
end

-- Is the stretcher close enough to the rear of its ambulance to be loaded?
function isStretcherAtRear(s)
    if not sameWorld(s.object, s.vehicle) then return false end
    local ox, oy, oz = offsetOf(s.vehicle, unpack(STRETCHER.OUT_OFFSET))
    local x, y, z = stretcherPosition(s)
    return getDistanceBetweenPoints3D(ox, oy, oz, x, y, z) <= STRETCHER.LOAD_RANGE
end

local function isDown(ped)
    local status = getElementData(ped, "medic.status")
    return status == "unconscious" or status == "clinical_death" or status == "dead"
end

local function setRearDoors(vehicle, open)
    if not isElement(vehicle) or not STRETCHER.REAR_DOORS then return end
    for _, door in ipairs(STRETCHER.REAR_DOORS) do
        setVehicleDoorOpenRatio(vehicle, door, open and 1 or 0, STRETCHER.DOOR_TIME)
    end
end

-- The ambulance stays put while the stretcher slides in / out.
local function holdVehicle(s, hold)
    if not STRETCHER.FREEZE_VEHICLE or not isElement(s.vehicle) then return end
    if hold then
        if s.heldVehicle then return end
        s.heldVehicle = true
        s.vehicleWasFrozen = isElementFrozen(s.vehicle)
        setElementFrozen(s.vehicle, true)
    elseif s.heldVehicle then
        s.heldVehicle = nil
        setElementFrozen(s.vehicle, s.vehicleWasFrozen or false)
    end
end

local function setState(s, state)
    s.state = state
    setElementData(s.object, D.STATE, state)
    onStretcherChanged(s)
end

-- ---------------------------------------------------------------------------------------------
-- Animation paths (moveObject)
-- ---------------------------------------------------------------------------------------------

-- Runs the steps one after the other: { time, x, y, z, rz } moves (rz = relative yaw),
-- { time } only waits. `done` runs after the last one unless the stretcher is gone.
local function runPath(s, steps, done)
    local index = 0
    local function nextStep()
        s.anim = nil
        if not Stretchers[s.object] then return end
        index = index + 1
        local step = steps[index]
        if not step then return done() end
        if step.x then
            moveObject(s.object, step.time, step.x, step.y, step.z, 0, 0, step.rz or 0, "InOutQuad")
        end
        s.anim = setTimer(nextStep, math.max(50, step.time), 1)
    end
    nextStep()
end

local function stopPath(s)
    if isTimer(s.anim) then killTimer(s.anim) end
    s.anim = nil
    if isElement(s.object) then stopObject(s.object) end
end

-- ---------------------------------------------------------------------------------------------
-- Pusher
-- ---------------------------------------------------------------------------------------------

local function clearPusher(s)
    local pusher = s.pusher
    if not pusher then return end
    s.pusher = nil
    pusherOf[pusher] = nil
    if isElement(pusher) then
        removeElementData(pusher, D.PUSHING)
        if not isPedDead(pusher) then setPedAnimation(pusher) end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Patient
-- ---------------------------------------------------------------------------------------------

local function playPatientAnim(ped)
    local a = STRETCHER.PATIENT_ANIM
    local loop = a[3] == true
    setPedAnimation(ped, a[1], a[2], -1, loop, false, false, not loop)
end

local function unlockSeated(s)
    local ped = s.seated
    if not ped then return end
    s.seated = nil
    lockedIn[ped] = nil
    if isElement(ped) then removeElementData(ped, D.LOCKED) end
end

-- Lays the ped on the stretcher (takes them out of a vehicle first).
function putPatient(s, ped)
    if getPedOccupiedVehicle(ped) then removePedFromVehicle(ped) end
    setElementDimension(ped, getElementDimension(s.object))
    setElementInterior(ped, getElementInterior(s.object))

    local o = STRETCHER.PATIENT_OFFSET
    attachElements(ped, s.object, o[1], o[2], o[3], o[4], o[5], o[6])
    playPatientAnim(ped)

    s.patient = ped
    patientOf[ped] = s.object
    setElementData(s.object, D.PATIENT, ped)
    setElementData(ped, D.ON, s.object)
    onStretcherChanged(s)
end

-- Takes the patient off. place = true puts them next to the stretcher.
function removePatient(s, place)
    local ped = s.patient
    if not ped then return end
    s.patient = nil
    patientOf[ped] = nil
    if isElement(s.object) then removeElementData(s.object, D.PATIENT) end
    if isElement(ped) then
        removeElementData(ped, D.ON)
        if isElementAttached(ped) then detachElements(ped) end
        if place and isElement(s.object) then
            local x, y, z = getElementPosition(s.object)
            local _, _, rz = getElementRotation(s.object)
            local rad = math.rad(rz)
            -- one metre to the side of the stretcher, standing height
            setElementPosition(ped, x + math.cos(rad) * 1.0, y + math.sin(rad) * 1.0, z + 0.6)
        end
        if not isPedDead(ped) then
            if isDown(ped) then
                local a = STRETCHER.DOWN_ANIM
                setPedAnimation(ped, a[1], a[2], -1, false, false, false, true)
            else
                setPedAnimation(ped)
            end
        end
    end
    if Stretchers[s.object] then onStretcherChanged(s) end
end

-- Can this ped be laid on the stretcher? (same rules as the client's selector in client/select.lua)
function isPatientCandidate(s, ped, medic)
    if not isElement(ped) or ped == medic then return false end
    local elementType = getElementType(ped)
    if elementType ~= "player" and elementType ~= "ped" then return false end
    if isPedDead(ped) or getPedOccupiedVehicle(ped) or isElementAttached(ped)
        or patientOf[ped] or pusherOf[ped] or not sameWorld(ped, s.object) then return false end
    local x, y, z = getElementPosition(s.object)
    local px, py, pz = getElementPosition(ped)
    -- small tolerance for latency
    return getDistanceBetweenPoints3D(x, y, z, px, py, pz) <= STRETCHER.PATIENT_RANGE + 1.0
end

-- Is there anybody the medic could select?
function hasPatientCandidate(s, medic)
    local x, y, z = getElementPosition(s.object)
    local dim, int = getElementDimension(s.object), getElementInterior(s.object)
    for _, elementType in ipairs({ "player", "ped" }) do
        for _, ped in ipairs(getElementsWithinRange(x, y, z, STRETCHER.PATIENT_RANGE, elementType, int, dim)) do
            if isPatientCandidate(s, ped, medic) then return true end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Stretcher positions
-- ---------------------------------------------------------------------------------------------

-- Hidden inside the ambulance
local function stow(s)
    clearPusher(s)
    local obj, vehicle = s.object, s.vehicle
    if isElementAttached(obj) then detachElements(obj) end
    setElementDimension(obj, getElementDimension(vehicle))
    setElementInterior(obj, getElementInterior(vehicle))
    setElementFrozen(obj, false)
    setElementCollisionsEnabled(obj, false)
    setElementAlpha(obj, 0)
    local o = STRETCHER.STOW_OFFSET
    attachElements(obj, vehicle, o[1], o[2], o[3], o[4], o[5], o[6])
    setState(s, "stowed")
end

-- Stands on the ground where it is now; `snapper`'s client corrects the height to the real
-- ground (the server has no ground data).
local function settle(s, snapper)
    local obj = s.object
    setElementAlpha(obj, 255)
    setElementCollisionsEnabled(obj, true)
    setElementFrozen(obj, true)
    setState(s, "ground")
    if isElement(snapper) then triggerClientEvent(snapper, "stretcher:snap", resourceRoot, obj) end
end

addEventHandler("stretcher:snapResult", resourceRoot, function(obj, z)
    local s = Stretchers[obj]
    if not s or s.state ~= "ground" or type(z) ~= "number" then return end
    local cx, cy, cz = getElementPosition(client)
    local x, y, oldZ = getElementPosition(obj)
    if getDistanceBetweenPoints3D(cx, cy, cz, x, y, oldZ) > 10 or math.abs(z - oldZ) > 2 then return end
    setElementPosition(obj, x, y, z)
end)

-- ---------------------------------------------------------------------------------------------
-- Actions (called from server/interaction.lua after its checks)
-- ---------------------------------------------------------------------------------------------

-- "Take out": the rear doors open, the stretcher slides out to the rear edge and is lowered
-- to the ground behind the ambulance; the doors close. A loaded patient comes out on it.
function takeOutStretcher(s, player)
    if s.state ~= "stowed" then return false end
    local obj, vehicle = s.object, s.vehicle
    holdVehicle(s, true)

    local st, ed, out = STRETCHER.STOW_OFFSET, STRETCHER.EDGE_OFFSET, STRETCHER.OUT_OFFSET
    local sx, sy, sz = offsetOf(vehicle, st[1], st[2], st[3])
    local ex, ey, ez = offsetOf(vehicle, ed[1], ed[2], ed[3])
    local ox, oy, oz = offsetOf(vehicle, out[1], out[2], out[3])
    local _, _, vrz = getElementRotation(vehicle)

    -- visible at the stowed position, then the path runs in world space
    detachElements(obj)
    setElementPosition(obj, sx, sy, sz)
    setElementRotation(obj, 0, 0, (vrz + st[6]) % 360)
    setElementCollisionsEnabled(obj, false)
    setElementAlpha(obj, 255)
    setState(s, "moving")

    local ped = s.seated
    unlockSeated(s)
    if isElement(ped) and not isPedDead(ped) and getPedOccupiedVehicle(ped) == vehicle then
        putPatient(s, ped)
    end

    setRearDoors(vehicle, true)
    runPath(s, {
        { time = STRETCHER.DOOR_TIME },
        { time = STRETCHER.SLIDE_TIME, x = ex, y = ey, z = ez },
        { time = STRETCHER.LOWER_TIME, x = ox, y = oy, z = oz },
    }, function()
        setRearDoors(vehicle, false)
        holdVehicle(s, false)
        settle(s, isElement(player) and player or nil)
    end)
    return true
end

-- "Load": the stretcher lines up behind the ambulance, is lifted to the rear edge and slides
-- in; the patient goes onto a free rear seat; the doors close.
function loadStretcher(s, player)
    if s.state ~= "ground" and s.state ~= "pushing" then return false end
    local obj, vehicle = s.object, s.vehicle
    if blown[vehicle] then return false, "The ambulance is wrecked." end
    if not isStretcherAtRear(s) then
        return false, "Bring the stretcher to the rear doors of the ambulance."
    end

    local seat
    if s.patient then
        for _, candidate in ipairs(STRETCHER.REAR_SEATS) do
            if not getVehicleOccupant(vehicle, candidate) then seat = candidate break end
        end
        if not seat then return false, "There is no free rear seat for the patient." end
    end

    -- let go of the pusher, keep the current world position
    local x, y, z = stretcherPosition(s)
    local _, _, rz = getElementRotation(s.state == "pushing" and s.pusher or obj)
    if s.state == "pushing" then rz = rz + STRETCHER.PUSH_OFFSET[6] end
    clearPusher(s)
    if isElementAttached(obj) then detachElements(obj) end
    setElementFrozen(obj, false)
    setElementPosition(obj, x, y, z)
    setElementRotation(obj, 0, 0, rz % 360)
    setElementCollisionsEnabled(obj, false)
    holdVehicle(s, true)
    setState(s, "moving")

    local st, ed, out = STRETCHER.STOW_OFFSET, STRETCHER.EDGE_OFFSET, STRETCHER.OUT_OFFSET
    local sx, sy, sz = offsetOf(vehicle, st[1], st[2], st[3])
    local ex, ey, ez = offsetOf(vehicle, ed[1], ed[2], ed[3])
    local ox, oy, oz = offsetOf(vehicle, out[1], out[2], out[3])
    local _, _, vrz = getElementRotation(vehicle)
    local turn = angleDelta(rz, vrz + st[6])

    setRearDoors(vehicle, true)
    runPath(s, {
        { time = math.max(STRETCHER.ALIGN_TIME, STRETCHER.DOOR_TIME), x = ox, y = oy, z = oz, rz = turn },
        { time = STRETCHER.LOWER_TIME, x = ex, y = ey, z = ez },
        { time = STRETCHER.SLIDE_TIME, x = sx, y = sy, z = sz },
    }, function()
        local ped = s.patient
        if ped then
            removePatient(s, false)
            if isElement(ped) and isElement(vehicle) then
                setElementDimension(ped, getElementDimension(vehicle))
                setElementInterior(ped, getElementInterior(vehicle))
                -- the seat may have been taken during the animation
                if getVehicleOccupant(vehicle, seat) then seat = nil end
                for _, candidate in ipairs(STRETCHER.REAR_SEATS) do
                    if seat then break end
                    if not getVehicleOccupant(vehicle, candidate) then seat = candidate end
                end
                if seat and warpPedIntoVehicle(ped, vehicle, seat) then
                    s.seated = ped
                    lockedIn[ped] = vehicle
                    setElementData(ped, D.LOCKED, vehicle)
                end
            end
        end
        stow(s)
        setRearDoors(vehicle, false)
        holdVehicle(s, false)
    end)
    return true
end

-- "Push": the stretcher hangs in front of the medic with collisions off. The medic's client
-- moves the medic and plays the push animations (client/push.lua).
function startPushing(s, player)
    if s.state ~= "ground" or pusherOf[player] then return false end
    local obj = s.object
    setElementFrozen(obj, false)
    setElementCollisionsEnabled(obj, false)
    local o = STRETCHER.PUSH_OFFSET
    attachElements(obj, player, o[1], o[2], o[3], o[4], o[5], o[6])

    s.pusher = player
    pusherOf[player] = obj
    setElementData(player, D.PUSHING, obj)
    setState(s, "pushing")
    return true
end

-- "Release": back on the ground in front of the medic.
function releaseStretcher(s)
    if s.state ~= "pushing" then return false end
    local obj, pusher = s.object, s.pusher
    local x, y, z = stretcherPosition(s)
    local _, _, rz = getElementRotation(isElement(pusher) and pusher or obj)
    clearPusher(s)
    if isElementAttached(obj) then detachElements(obj) end
    setElementPosition(obj, x, y, z - STRETCHER.PUSH_OFFSET[3] - STRETCHER.PED_HEIGHT + STRETCHER.GROUND_Z)
    setElementRotation(obj, 0, 0, (rz + STRETCHER.GROUND_ROT_Z) % 360)
    settle(s, pusher)
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Creation / destruction
-- ---------------------------------------------------------------------------------------------

local function createStretcher(vehicle)
    if byVehicle[vehicle] or blown[vehicle] then return end
    local x, y, z = getElementPosition(vehicle)
    local obj = createObject(STRETCHER.OBJECT_MODEL, x, y, z)
    if not obj then return end

    local s = { object = obj, vehicle = vehicle, state = "stowed" }
    Stretchers[obj] = s
    byVehicle[vehicle] = obj
    setElementData(obj, D.VEHICLE, vehicle)
    onStretcherCreated(s)
    stow(s)
end

-- Releases everyone involved, then destroys the object (unless it is being destroyed already).
local function destroyStretcher(obj, destroying)
    local s = Stretchers[obj]
    if not s then return end
    Stretchers[obj] = nil
    if byVehicle[s.vehicle] == obj then byVehicle[s.vehicle] = nil end
    if isTimer(s.anim) then killTimer(s.anim) end
    holdVehicle(s, false)
    clearPusher(s)
    removePatient(s, true)
    unlockSeated(s)
    onStretcherDestroyed(s)
    if not destroying and isElement(obj) then destroyElement(obj) end
end

local function isAmbulance(vehicle)
    return getElementType(vehicle) == "vehicle" and STRETCHER.VEHICLE_MODELS[getElementModel(vehicle)] == true
end

-- Every ambulance gets a stretcher; vehicles that are no longer ambulances lose theirs.
function scanVehicles()
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        if isAmbulance(vehicle) then
            if not byVehicle[vehicle] and not blown[vehicle] then createStretcher(vehicle) end
        elseif byVehicle[vehicle] then
            destroyStretcher(byVehicle[vehicle])
        end
    end
end

-- Coalesces a burst of vehicle creations into one scan
local scanPending = false
local function requestScan()
    if scanPending then return end
    scanPending = true
    setTimer(function()
        scanPending = false
        scanVehicles()
    end, 50, 1)
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- Elements created while the resource is still starting reach the clients only after the start,
    -- later than the menus / data that refer to them. Scan once the start has finished.
    setTimer(scanVehicles, 500, 1)
    -- MTA has no server-side "vehicle created" event. The debug hook catches every createVehicle
    -- call of every resource (needs the addDebugHook ACL right); the timer catches the rest.
    if addDebugHook then
        addDebugHook("postFunction", requestScan, { "createVehicle", "setElementModel" })
    end
    setTimer(scanVehicles, STRETCHER.SCAN_INTERVAL, 0)
end)

addEventHandler("onElementModelChange", root, function()
    if getElementType(source) == "vehicle" then requestScan() end
end)

addEventHandler("onVehicleExplode", root, function()
    blown[source] = true
    if byVehicle[source] then destroyStretcher(byVehicle[source]) end
end)

addEventHandler("onVehicleRespawn", root, function()
    blown[source] = nil
    if isAmbulance(source) then createStretcher(source) end
end)

-- A player / ped leaving the game or being destroyed, from any role.
local function dropPed(ped)
    local obj = pusherOf[ped]
    if obj and Stretchers[obj] then releaseStretcher(Stretchers[obj]) end
    obj = patientOf[ped]
    if obj and Stretchers[obj] then removePatient(Stretchers[obj], false) end
    local vehicle = lockedIn[ped]
    if vehicle and byVehicle[vehicle] then unlockSeated(Stretchers[byVehicle[vehicle]]) end
    pusherOf[ped], patientOf[ped], lockedIn[ped] = nil, nil, nil
end

addEventHandler("onElementDestroy", root, function()
    local elementType = getElementType(source)
    if Stretchers[source] then
        destroyStretcher(source, true)
    elseif elementType == "vehicle" then
        blown[source] = nil
        if byVehicle[source] then destroyStretcher(byVehicle[source]) end
    elseif elementType == "ped" or elementType == "player" then
        dropPed(source)
    end
end)

addEventHandler("onPlayerQuit", root, function() dropPed(source) end)

-- A dying pusher lets go. A dead patient stays on the stretcher (body transport) until respawn.
addEventHandler("onPlayerWasted", root, function()
    local obj = pusherOf[source]
    if obj and Stretchers[obj] then releaseStretcher(Stretchers[obj]) end
end)

addEventHandler("onPlayerSpawn", root, function() dropPed(source) end)

-- Somebody else's script took the patient out of the ambulance
addEventHandler("onPlayerVehicleExit", root, function(vehicle)
    if lockedIn[source] == vehicle and byVehicle[vehicle] then unlockSeated(Stretchers[byVehicle[vehicle]]) end
end)

-- A patient on a rear seat cannot get out on their own, and nobody can jack them.
addEventHandler("onVehicleStartExit", root, function(player)
    if lockedIn[player] == source then
        cancelEvent()
        notify(player, "You can only leave the ambulance on the stretcher.")
    end
end)

addEventHandler("onVehicleStartEnter", root, function(player, seat, jacked)
    if jacked and lockedIn[jacked] == source then cancelEvent() end
end)

-- medical_system plays its own down / get-up animations; keep the patient lying on the stretcher.
addEventHandler("onMedicalStateChange", root, function()
    local ped = source
    if not patientOf[ped] then return end
    setTimer(function()
        if isElement(ped) and patientOf[ped] and not isPedDead(ped) then playPatientAnim(ped) end
    end, 200, 1)
end)

-- Nobody keeps a stretcher animation, a frozen ambulance or a locked seat after this resource stops.
addEventHandler("onResourceStop", resourceRoot, function()
    for obj, s in pairs(Stretchers) do
        stopPath(s)
        destroyStretcher(obj)
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------------------------

function getVehicleStretcher(vehicle) return byVehicle[vehicle] or false end
function getStretcherVehicle(obj) return Stretchers[obj] and Stretchers[obj].vehicle or false end
function getStretcherState(obj) return Stretchers[obj] and Stretchers[obj].state or false end
function getStretcherPatient(obj)
    local s = Stretchers[obj]
    return s and (s.patient or s.seated) or false
end
function getPatientStretcher(ped) return patientOf[ped] or false end

-- Takes the patient lying on the stretcher off (detached, lying / standing anim reset).
-- Returns the ped, or false. The caller decides where they go (e.g. a hospital handover).
function takePatientOff(obj)
    local s = Stretchers[obj]
    if not s or not s.patient then return false end
    local ped = s.patient
    removePatient(s, false)
    return ped
end

function getPusherStretcher(player) return pusherOf[player] end
