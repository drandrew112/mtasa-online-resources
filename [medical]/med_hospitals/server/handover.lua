-- Hospital handover together with med_erm and med_stretcher.
--
-- 1. An ERM unit with an active case parks its vehicle in an ambulance bay with a patient aboard
--    (on its stretcher) -> the unit's status becomes Handover (no ERM timer: the hospital ends it).
--    Without a patient the ambulance simply drives through. An occupied bay's marker is invisible.
-- 2. Leaving the bay during the handover -> En Route, until the vehicle parks in a bay again.
-- 3. A medic pushes the patient on that ambulance's stretcher into a handover marker of the same
--    hospital -> 5 s -> the ped disappears (a player patient is treated and released), the unit's
--    handover is completed in ERM, which ends the task.
-- The tablet's Handover button is refused (onErmUnitHandoverRequest): only the hospital starts it.

addEvent("onHospitalHandoverStart", false)    -- (unitId, hospitalId)
addEvent("onHospitalHandoverLeft", false)     -- (unitId, hospitalId)
addEvent("onHospitalPatientHandover", false)  -- (hospitalId, unitId, patient, medic, taskId)

local active = {}     -- [unitId] = { bay, vehicle, hospital }
local procs = {}      -- [player] = { point, obj, patient, unitId, ends }   running stretcher handovers
local refused = {}    -- [player] = point   (refusal shown once per stay in the marker)

local function ermRunning() return isResourceRunning("med_erm") end

local function vehicleSpeed(vehicle)
    local vx, vy, vz = getElementVelocity(vehicle)
    return (vx * vx + vy * vy + vz * vz) ^ 0.5 * 180  -- km/h
end

local function unitCrew(unit)
    local out = {}
    for _, name in ipairs(unit and unit.members or {}) do
        local p = getPlayerFromName(name)
        if p then out[#out + 1] = p end
    end
    return out
end

local function notifyCrew(unit, text)
    for _, p in ipairs(unitCrew(unit)) do notify(p, text) end
end

---------------------------------------------------------------- ambulance bays

-- Is there a patient on the ambulance's stretcher (seated in the back, or still lying on it)?
local function hasPatientAboard(vehicle)
    if not isResourceRunning("med_stretcher") then return false end
    local obj = exports.med_stretcher:getVehicleStretcher(vehicle)
    return obj and isElement(exports.med_stretcher:getStretcherPatient(obj)) or false
end

local function onVehicleParked(bay, vehicle)
    if not ermRunning() then return end
    local unit = exports.med_erm:getVehicleUnit(vehicle)
    if not unit or active[unit.id] then return end
    -- no patient aboard: the ambulance simply drives through the bay (a unit already in
    -- handover after a reload is still taken over, its patient may be out on the stretcher)
    if unit.status ~= "handover" and not hasPatientAboard(vehicle) then return end
    if unit.task == 0 then
        local driver = getVehicleOccupant(vehicle, 0)
        if driver then notify(driver, "Your unit has no active case - no handover started.") end
        return
    end

    -- a unit already in handover (resource restart / reload) is simply taken over
    if unit.status ~= "handover" then
        local ok, err = exports.med_erm:setUnitStatus(unit.id, "handover", false)
        if not ok then
            outputDebugString("[med_hospitals] setUnitStatus handover failed: " .. tostring(err), 2)
            return
        end
    end

    local h = bay.hospital
    active[unit.id] = { bay = bay, vehicle = vehicle, hospital = h }
    notifyCrew(unit, ("Handover started at #f0c040%s#ffffff. Push the patient on the stretcher into the handover marker.")
        :format(h.name))
    triggerEvent("onHospitalHandoverStart", resourceRoot, unit.id, h.id)
end

local function updateBays()
    for bay in eachPoint("bay") do
        local occupant = bay.vehicle
        if occupant and not isInPoint(occupant, bay) then occupant = nil end
        if not occupant then occupant = elementsInPoint(bay, "vehicle")[1] end

        if occupant ~= bay.vehicle then
            bay.vehicle, bay.parked = occupant, false
            setBayOccupied(bay, occupant ~= nil)
        end
        if occupant and not bay.parked and vehicleSpeed(occupant) <= HOSP.BAY_MAX_SPEED then
            bay.parked = true
            onVehicleParked(bay, occupant)
        end
    end
end

local function updateActive()
    if not ermRunning() then
        active = {}
        return
    end
    for unitId, a in pairs(active) do
        local unit = exports.med_erm:getUnitData(unitId)
        if not unit or unit.status ~= "handover" then
            -- ended elsewhere (completed, tablet status change, sign-out)
            active[unitId] = nil
        elseif not isElement(a.vehicle) or a.bay.vehicle ~= a.vehicle then
            active[unitId] = nil
            exports.med_erm:setUnitStatus(unitId, "enroute")
            notifyCrew(unit, "You left the ambulance bay - status is #da3633En Route#ffffff until you park again.")
            triggerEvent("onHospitalHandoverLeft", resourceRoot, unitId, a.hospital.id)
        end
    end
end

-- Only the hospital starts a handover: the tablet's Handover button is refused.
-- (re-attached when med_erm restarts and registers the event again)
local function refuseTabletHandover() cancelEvent() end

local function hookErm()
    if ermRunning() then addEventHandler("onErmUnitHandoverRequest", root, refuseTabletHandover) end
end

addEventHandler("onResourceStart", root, function(res)
    if res == resource then
        hookErm()
    elseif getResourceName(res) == "med_erm" then
        removeEventHandler("onErmUnitHandoverRequest", root, refuseTabletHandover)
        hookErm()
    end
end)

---------------------------------------------------------------- stretcher handover

-- Can the player hand over the patient on the stretcher they push here?
-- -> true, { obj, patient, unitId }  |  false, reason
local function checkHandover(player, point)
    local obj = getElementData(player, "stretcher.pushing")
    if not isElement(obj) or not isResourceRunning("med_stretcher") then
        return false, "Bring the patient here on a stretcher."
    end
    local ms = exports.med_stretcher
    if ms:getStretcherState(obj) ~= "pushing" then return false, "Bring the patient here on a stretcher." end

    local patient = ms:getStretcherPatient(obj)
    if not isElement(patient) or ms:getPatientStretcher(patient) ~= obj then
        return false, "There is no patient on the stretcher."
    end

    if not ermRunning() then return false, "The dispatch system is offline." end
    local vehicle = ms:getStretcherVehicle(obj)
    local unit = isElement(vehicle) and exports.med_erm:getVehicleUnit(vehicle)
    if not unit then return false, "This stretcher's ambulance is not an EMS unit on duty." end

    local a = active[unit.id]
    if not a or unit.status ~= "handover" then
        return false, "Your ambulance is not in handover. Park it in an ambulance bay of this hospital."
    end
    if a.hospital ~= point.hospital then
        return false, "Your ambulance is parked at " .. a.hospital.name .. "."
    end
    return true, { obj = obj, patient = patient, unitId = unit.id }
end

local function cancelProc(player, reason)
    local p = procs[player]
    if not p then return end
    procs[player] = nil
    stopProgress(player)
    if reason then notify(player, "Handover cancelled: " .. reason) end
end

-- Where a handed-over player patient is put
local function releasePosition(h)
    if h.release then return h.release.x, h.release.y, h.release.z, h.release.rot end
    local base = h.heal or h.handover[1] or h
    local o = HOSP.RELEASE_OFFSET
    return base.x + o[1], base.y + o[2], base.z + 1 + o[3], 0
end

local function completeProc(player)
    local p = procs[player]
    procs[player] = nil
    stopProgress(player)

    local h = p.point.hospital
    local patient = p.patient
    local unit = exports.med_erm:getUnitData(p.unitId)
    local taskId = unit and unit.task ~= 0 and unit.task or false

    -- listeners can still read the patient (medsys state etc.)
    triggerEvent("onHospitalPatientHandover", resourceRoot, h.id, p.unitId, patient, player, taskId)

    if isElement(patient) then
        if getElementType(patient) == "player" then
            exports.med_stretcher:takePatientOff(p.obj)
            if isResourceRunning("medsys") then exports.medsys:healCompletely(patient) end
            if not isPedDead(patient) then setElementHealth(patient, 100) end
            local x, y, z, rot = releasePosition(h)
            setElementInterior(patient, h.interior)
            setElementDimension(patient, h.dimension)
            setElementPosition(patient, x, y, z)
            setElementRotation(patient, 0, 0, rot)
            setPedAnimation(patient)
            notify(patient, "You were handed over to " .. h.name .. " and treated.")
        else
            destroyElement(patient) -- med_stretcher clears the stretcher on destroy
        end
    end

    active[p.unitId] = nil
    exports.med_erm:completeHandover(p.unitId)
    if unit then notifyCrew(unit, "Patient handed over to #f0c040" .. h.name .. "#ffffff. Case completed.") end
end

local function updateHandoverMarkers()
    local seen = {}
    local now = getTickCount()

    for point in eachPoint("handover") do
        for _, player in ipairs(elementsInPoint(point, "player")) do
            seen[player] = point
            if not procs[player] and not isPedDead(player) and not getPedOccupiedVehicle(player) then
                local ok, data = checkHandover(player, point)
                if ok then
                    refused[player] = nil
                    procs[player] = {
                        point = point, obj = data.obj, patient = data.patient, unitId = data.unitId,
                        ends = now + HOSP.HANDOVER_TIME,
                    }
                    startProgress(player, point.marker, HOSP.HANDOVER_TIME, "Handing over the patient")
                elseif refused[player] ~= point then
                    refused[player] = point
                    notify(player, data)
                end
            end
        end
    end

    for player in pairs(refused) do
        if seen[player] ~= refused[player] then refused[player] = nil end
    end

    for player, p in pairs(procs) do
        if not isElement(player) then
            procs[player] = nil
        elseif seen[player] ~= p.point then
            cancelProc(player, "you left the handover marker.")
        else
            local ok, data = checkHandover(player, p.point)
            if not ok then
                refused[player] = p.point
                cancelProc(player, data)
            elseif data.obj ~= p.obj or data.patient ~= p.patient then
                cancelProc(player, "the patient changed.")
            elseif now >= p.ends then
                completeProc(player)
            end
        end
    end
end

---------------------------------------------------------------- lifecycle / API helpers

function getActiveHandover(unitId)
    local a = active[tonumber(unitId) or -1]
    return a and a.hospital or false
end

function isHandingOver(player) return procs[player] ~= nil end

UnloadHandlers[#UnloadHandlers + 1] = function()
    for player in pairs(procs) do cancelProc(player, "the hospitals were reloaded.") end
    procs, refused, active = {}, {}, {}  -- parked units are taken over again by the new bays
end

addEventHandler("onPlayerQuit", root, function()
    procs[source], refused[source] = nil, nil
end)

addEventHandler("onPlayerWasted", root, function()
    cancelProc(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        updateBays()
        updateActive()
        updateHandoverMarkers()
    end, HOSP.TICK, 0)
end)
