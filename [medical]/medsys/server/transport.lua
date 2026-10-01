-- Transport requested from the examination panel ("Transport"). Useful when the ambulance
-- crews on the scene cannot take every patient: a hearse comes for a dead body, an ambulance
-- for a living patient whose condition is stable. Only peds (a player cannot be removed, and a
-- dead player respawns on its own).
--
-- Transports[ped] = { medic, kind, arriveTick, spot, timer, vehicle, driver, phase }
--   kind:  "dead" (hearse) | "alive" (ambulance), decided when it is requested
--   phase: "waiting" (on the way) -> "loading" (the vehicle stands at the patient) -> "leaving"
--   spot = { x, y, z, rotation, canDrive } picked by the medic's client, nil = no free spot
--          (then the patient is simply taken away when the time is up)

addEvent("onMedicalTransportRequested", false) -- source = patient, (medic, kind)
addEvent("onMedicalPatientTransported", false) -- source = patient, (medic, kind), right before it is destroyed

local Transports = {}

-- Tutorial patients (setTutorialPatient): transport is refused for them
local TutorialPatients = {}

-- Marks a ped / player as a tutorial patient (e.g. the EMS tutorial): no transport can be requested
function setTutorialPatient(element, enabled)
    if not isValidPatient(element) then return false end
    TutorialPatients[element] = enabled and true or nil
    return true
end

function isTutorialPatient(element)
    return TutorialPatients[element] == true
end

addEventHandler("onElementDestroy", root, function() TutorialPatients[source] = nil end)

local function isBodyDead(target)
    local state = Patients[target]
    return (state and state.dead) or isPedDead(target)
end

-- true | false, reason (also the hover text of the button). state = the patient state or nil
function canRequestTransport(target, state)
    if not isElement(target) or getElementType(target) ~= "ped" then
        return false, "Players cannot be transported"
    end
    if TutorialPatients[target] then return false, "Not available in the tutorial" end
    local transport = Transports[target]
    if transport then
        if transport.phase == "waiting" then return false, "Transport is on the way" end
        return false, "The patient is being loaded"
    end
    if not isBodyDead(target) and state and state.consciousness ~= "stable" then
        return false, "Only a stable patient can be transported"
    end
    return true
end

-- phase ("waiting" | "loading" | "leaving"), seconds until the vehicle arrives (while waiting)
-- nil when no transport was requested
function getTransportStatus(target)
    local transport = Transports[target]
    if not transport then return nil end
    if transport.phase ~= "waiting" then return transport.phase end
    return "waiting", math.max(0, math.ceil((transport.arriveTick - getTickCount()) / 1000))
end

local function cleanup(target)
    local transport = Transports[target]
    if not transport then return end
    Transports[target] = nil
    if isTimer(transport.timer) then killTimer(transport.timer) end
    if isElement(transport.driver) then destroyElement(transport.driver) end
    if isElement(transport.vehicle) then destroyElement(transport.vehicle) end
end

-- The spot comes from the client: only trust it near the body
local function validateSpot(target, spot)
    if type(spot) ~= "table" then return nil end
    local x, y, z, rotation = tonumber(spot[1]), tonumber(spot[2]), tonumber(spot[3]), tonumber(spot[4])
    if not (x and y and z and rotation) then return nil end
    local bx, by, bz = getElementPosition(target)
    if getDistanceBetweenPoints3D(x, y, z, bx, by, bz) > MEDIC.TRANSPORT_SPOT_RANGE then return nil end
    return { x = x, y = y, z = z, rotation = rotation, canDrive = spot[5] == true }
end

local function leave(target)
    local transport = Transports[target]
    if not transport then return end
    transport.phase = "leaving"
    triggerEvent("onMedicalPatientTransported", target, transport.medic, transport.kind)
    if isElement(target) then destroyElement(target) end -- onElementDestroy cleans up the rest

    local vehicle, driver = transport.vehicle, transport.driver
    if not isElement(vehicle) then return end
    setVehicleDoorOpenRatio(vehicle, 1, 0, 1000)
    -- the bookkeeping is gone with the body, the vehicle only has to drive off and disappear
    setTimer(function()
        -- drives off when the client found a clear road ahead (server-side ped controls need MTA 1.5.8+)
        if isElement(vehicle) and isElement(driver) and transport.spot.canDrive and setPedControlState then
            setPedControlState(driver, "accelerate", true)
        end
        setTimer(function()
            if isElement(driver) then destroyElement(driver) end
            if isElement(vehicle) then destroyElement(vehicle) end
        end, MEDIC.TRANSPORT_LEAVE_TIME * 1000, 1)
    end, 1000, 1)
end

local function arrive(target)
    local transport = Transports[target]
    if not transport then return end
    if not isElement(target) then
        cleanup(target)
        return
    end
    transport.phase = "loading"

    local spot = transport.spot
    if spot then
        local vehicle = createVehicle(MEDIC.TRANSPORT_VEHICLE[transport.kind], spot.x, spot.y, spot.z, 0, 0, spot.rotation)
        if vehicle then
            local interior, dimension = getElementInterior(target), getElementDimension(target)
            setElementInterior(vehicle, interior)
            setElementDimension(vehicle, dimension)
            setVehicleDamageProof(vehicle, true)
            setVehicleLocked(vehicle, true)
            setVehicleEngineState(vehicle, true)
            setVehicleOverrideLights(vehicle, 2)
            if transport.kind == "alive" then setVehicleSirensOn(vehicle, true) end
            setVehicleDoorOpenRatio(vehicle, 1, 1, 1000) -- boot

            local driver = createPed(MEDIC.TRANSPORT_DRIVER[transport.kind], spot.x, spot.y, spot.z + 2)
            if driver then
                setElementInterior(driver, interior)
                setElementDimension(driver, dimension)
                warpPedIntoVehicle(driver, vehicle)
            end
            transport.vehicle, transport.driver = vehicle, driver
        end
    end

    transport.timer = setTimer(leave, MEDIC.TRANSPORT_LOAD_TIME * 1000, 1, target)
    refreshExaminations(target)
end

-- Returns true, or false + reason
function requestTransport(medic, target, spot)
    local ok, reason = canRequestTransport(target, Patients[target])
    if not ok then return false, reason end

    local kind = isBodyDead(target) and "dead" or "alive"
    Transports[target] = {
        medic = medic,
        kind = kind,
        arriveTick = getTickCount() + MEDIC.TRANSPORT_DELAY * 1000,
        spot = validateSpot(target, spot),
        phase = "waiting",
        timer = setTimer(arrive, MEDIC.TRANSPORT_DELAY * 1000, 1, target),
    }
    triggerEvent("onMedicalTransportRequested", target, medic, kind)
    return true
end

-- The body is gone before the vehicle arrived (scene cleanup, stretcher handover, ...)
addEventHandler("onElementDestroy", root, function()
    local transport = Transports[source]
    if not transport then return end
    if transport.phase == "leaving" then
        Transports[source] = nil -- loaded: the vehicle drives off on its own timers
    else
        cleanup(source)
    end
end)
