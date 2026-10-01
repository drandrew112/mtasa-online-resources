-- Patient registry and the medical state data structure.
--
-- Only elements that are not perfectly healthy are kept in the registry (Patients).
-- The state is server-only: clients receive the status string as element data and full
-- snapshots only while they examine the patient.
--
-- Patients[element] = {
--     element       = element,              -- the ped / player
--     bloodVolume   = 5000,                 -- ml
--     heartRate     = 72,                   -- BPM, 0 in clinical death
--     systolic      = 120, diastolic = 80,  -- mmHg
--     spo2          = 98,                   -- %
--     baseBleeding  = 0,                    -- 0-3, bleeding not tied to an injury (setMedicalState "bleeding")
--     extraPain     = 0,                    -- pain set from outside, fades over time
--     injuries      = { { id, type, severity, bleeding, treated, tick }, ... },
--     nextInjuryId  = 1,
--     ivAccess      = false, ivQuality = 0, -- cannula in place, quality 0-100 (fluid rate)
--     intubated     = false,                -- airway secured
--     hypertension  = 0,                    -- mmHg added to the target systolic pressure (setMedicalState)
--     drugs         = { { id, untilTick }, ... }, -- active medicine doses (MEDIC_DRUGS)
--     apneaRate     = nil,                  -- %/s SpO2 fall while an intubation attempt runs
--     consciousness = "stable",             -- stable | dazed | unconscious | clinical_death | dead
--     tachyTick     = nil,                  -- getTickCount() since the pulse is at ARREST_HEART_RATE+
--     arrestTick    = nil,                  -- getTickCount() of the cardiac arrest
--     deathTick     = nil,                  -- getTickCount() of biological death (arrestTick + DEATH_TIME)
--     knockoutState = nil, knockoutUntil = nil, -- forced dazed / unconscious state and its end
--     dead          = false,                -- biological death, the simulation stops
--     animated      = false,                -- the down animation was played by us
--     sent          = { spo2, heartRate },  -- last values written to element data
-- }

Patients = {}

local patientCount = 0

function isValidPatient(element)
    if not isElement(element) then return false end
    local elementType = getElementType(element)
    return elementType == "ped" or elementType == "player"
end

local function newState(element)
    return {
        element = element,
        bloodVolume = MEDIC.BLOOD_VOLUME,
        heartRate = MEDIC.HEART_RATE,
        systolic = MEDIC.SYSTOLIC,
        diastolic = MEDIC.DIASTOLIC,
        spo2 = MEDIC.SPO2,
        baseBleeding = 0,
        extraPain = 0,
        injuries = {},
        nextInjuryId = 1,
        ivAccess = false,
        ivQuality = 0,
        intubated = false,
        hypertension = 0,
        drugs = {},
        consciousness = "stable",
        dead = false,
        animated = false,
        sent = {},
    }
end

-- Returns the patient state, creating it when create is true
function getPatient(element, create)
    local state = Patients[element]
    if state or not create or not isValidPatient(element) then return state end

    state = newState(element)
    Patients[element] = state
    patientCount = patientCount + 1
    setElementData(element, MEDIC.DATA_STATUS, state.consciousness)
    writeVitalsData(state)
    startSimulation()
    return state
end

-- Drops the element from the registry and clears everything the system put on it.
-- leaving = true when the element is being destroyed / the player is quitting
function removePatient(element, leaving)
    local state = Patients[element]
    if not state then return false end

    Patients[element] = nil
    patientCount = patientCount - 1
    if patientCount <= 0 then
        patientCount = 0
        stopSimulation()
    end

    if isElement(element) and not leaving then
        removeElementData(element, MEDIC.DATA_STATUS)
        removeElementData(element, MEDIC.DATA_SPO2)
        removeElementData(element, MEDIC.DATA_HEART_RATE)
        if state.animated and not state.dead then setPedAnimation(element) end
        if getElementType(element) == "player" then
            triggerClientEvent(element, "medic:selfStatus", resourceRoot, false)
        end
    end
    return true
end

-- Vitals as element data in "subscribe" mode, only written when they change
function writeVitalsData(state)
    local spo2 = math.floor(state.spo2 * 10 + 0.5) / 10
    local heartRate = math.floor(state.heartRate + 0.5)
    if state.sent.spo2 ~= spo2 then
        state.sent.spo2 = spo2
        setElementData(state.element, MEDIC.DATA_SPO2, spo2, "subscribe")
    end
    if state.sent.heartRate ~= heartRate then
        state.sent.heartRate = heartRate
        setElementData(state.element, MEDIC.DATA_HEART_RATE, heartRate, "subscribe")
    end
end

-- Effective bleeding level (0-3): the worst of the wounds and the unattributed bleeding
function getPatientBleeding(state)
    local level = state.baseBleeding
    for _, injury in ipairs(state.injuries) do
        if injury.bleeding > level then level = injury.bleeding end
    end
    return level
end

-- Pain 0-100 from the injuries (treated ones hurt less) plus the external pain
function getPatientPain(state)
    local pain = state.extraPain
    for _, injury in ipairs(state.injuries) do
        local def = MEDIC_INJURIES[injury.type]
        local value = def.pain[injury.severity]
        if injury.treated then value = value * def.treatedPain end
        if value > pain then
            pain = value + (pain * 0.25) -- the worst one dominates, the rest adds a little
        else
            pain = pain + value * 0.25
        end
    end
    return math.min(100, pain)
end

-- Sum of an effect field (e.g. "systolic") over the active medicine doses
function getDrugEffect(state, field)
    local total = 0
    for _, dose in ipairs(state.drugs) do
        total = total + (MEDIC_DRUGS[dose.id][field] or 0)
    end
    return total
end

function isInClinicalDeath(state)
    return state.arrestTick ~= nil and not state.dead
end

local function round(value)
    return math.floor(value + 0.5)
end

-- Full medical data as a plain table (safe to hand out, it is a copy)
function buildSnapshot(state)
    local bleeding = getPatientBleeding(state)
    local injuries = {}
    for i, injury in ipairs(state.injuries) do
        local def = MEDIC_INJURIES[injury.type]
        injuries[i] = {
            id = injury.id,
            type = injury.type,
            label = def.label,
            severity = injury.severity,
            severityLabel = MEDIC_SEVERITY[injury.severity],
            bleeding = injury.bleeding,
            treated = injury.treated,
            treatedLabel = injury.treated and def.treatedLabel or nil,
        }
    end

    local systolic, diastolic = round(state.systolic), round(state.diastolic)
    local now = getTickCount()
    local drugs = {}
    for i, dose in ipairs(state.drugs) do
        drugs[i] = { id = dose.id, name = MEDIC_DRUGS[dose.id].name,
            timeLeft = math.max(0, math.ceil((dose.untilTick - now) / 1000)) }
    end

    local deathTimeLeft
    if isInClinicalDeath(state) then
        deathTimeLeft = math.max(0, math.ceil((state.deathTick - getTickCount()) / 1000))
    end

    return {
        isPatient = Patients[state.element] == state,
        consciousness = state.consciousness,
        consciousnessLabel = MEDIC_CONSCIOUSNESS[state.consciousness],
        heartRate = round(state.heartRate),
        systolic = systolic,
        diastolic = diastolic,
        bloodPressure = ("%d/%d"):format(systolic, diastolic),
        spo2 = round(state.spo2),
        bleeding = bleeding,
        bleedingLabel = MEDIC_BLEEDING[bleeding],
        bloodVolume = round(state.bloodVolume),
        bloodPercent = round(state.bloodVolume / MEDIC.BLOOD_VOLUME * 100),
        pain = round(getPatientPain(state)),
        injuries = injuries,
        ivAccess = state.ivAccess,
        intubated = state.intubated,
        drugs = drugs,
        clinicalDeath = isInClinicalDeath(state),
        deathTimeLeft = deathTimeLeft,
        dead = state.dead,
    }
end

-- Snapshot of an element that is not in the registry (healthy, or already dead)
function buildDefaultSnapshot(element)
    local state = newState(element)
    if getElementHealth(element) <= 0 or isPedDead(element) then
        state.dead = true
        state.consciousness = "dead"
        state.heartRate, state.systolic, state.diastolic, state.spo2 = 0, 0, 0, 0
    end
    local snapshot = buildSnapshot(state)
    snapshot.isPatient = false
    return snapshot
end

---------------------------------------------------------------------------
-- State transitions
---------------------------------------------------------------------------

local function playDownAnimation(state)
    local element = state.element
    if isPedInVehicle(element) or isPedDead(element) then return end
    setPedAnimation(element, MEDIC.ANIM_DOWN[1], MEDIC.ANIM_DOWN[2], -1, false, false, false, true)
    state.animated = true
end

local function playGetUpAnimation(state)
    if not state.animated then return end
    state.animated = false
    if isPedInVehicle(state.element) then return end
    setPedAnimation(state.element, MEDIC.ANIM_GETUP[1], MEDIC.ANIM_GETUP[2], -1, false, false, true, false)
end

-- Tells a player patient its own condition (overlay + control lock on the client)
function notifyPatient(state)
    local element = state.element
    if getElementType(element) ~= "player" then return end
    local snapshot = state.arrestTick and buildSnapshot(state)
    triggerClientEvent(element, "medic:selfStatus", resourceRoot, state.consciousness,
        snapshot and snapshot.deathTimeLeft or nil)
end

function setConsciousness(state, status)
    local old = state.consciousness
    if old == status then return end
    state.consciousness = status

    setElementData(state.element, MEDIC.DATA_STATUS, status)
    if medicIsDown(status) and not medicIsDown(old) then
        playDownAnimation(state)
    elseif not medicIsDown(status) and medicIsDown(old) then
        playGetUpAnimation(state)
    end

    notifyPatient(state)
    triggerEvent("onMedicalStateChange", state.element, status, old)
end

-- Pulse 0: clinical death starts, the death timer runs
function cardiacArrest(state)
    if state.arrestTick or state.dead then return end
    local now = getTickCount()
    state.arrestTick = now
    state.deathTick = now + MEDIC.DEATH_TIME * 1000
    state.tachyTick = nil
    state.heartRate, state.systolic, state.diastolic = 0, 0, 0
    state.knockoutState, state.knockoutUntil = nil, nil

    setConsciousness(state, "clinical_death")
    writeVitalsData(state)
    triggerEvent("onMedicalCardiacArrest", state.element)
end

-- Return of spontaneous circulation (successful CPR)
function restoreCirculation(state)
    if not isInClinicalDeath(state) then return end
    state.arrestTick, state.deathTick = nil, nil
    state.heartRate = MEDIC.ROSC_HEART_RATE
    state.systolic = MEDIC.ROSC_SYSTOLIC
    state.diastolic = MEDIC.ROSC_SYSTOLIC * (MEDIC.DIASTOLIC / MEDIC.SYSTOLIC)
    state.spo2 = math.max(state.spo2, MEDIC.ROSC_SPO2)

    setConsciousness(state, "unconscious")
    writeVitalsData(state)
    triggerEvent("onMedicalRevived", state.element)
end

-- Biological death. killElement = false when the element is already dead (wasted)
function biologicalDeath(state, killElement)
    if state.dead then return end
    state.dead = true
    state.arrestTick, state.deathTick = nil, nil
    state.heartRate, state.systolic, state.diastolic, state.spo2 = 0, 0, 0, 0
    state.animated = false

    setConsciousness(state, "dead")
    writeVitalsData(state)
    stopTreatmentsOn(state.element, true)

    local element = state.element
    if killElement ~= false and isElement(element) and not isPedDead(element) then
        killPed(element)
    end
    triggerEvent("onMedicalDeath", element)
end

-- Everything back to the baseline, the element leaves the registry
function resetPatient(element)
    local state = Patients[element]
    if not state then return false end
    stopTreatmentsOn(element, true)
    removePatient(element)
    refreshExaminations(element) -- open panels show the healthy state
    return true
end

---------------------------------------------------------------------------
-- Element lifecycle
---------------------------------------------------------------------------

local function onLeave()
    if Patients[source] then
        stopTreatmentsOn(source)
        removePatient(source, true)
    end
end
addEventHandler("onElementDestroy", root, onLeave)
addEventHandler("onPlayerQuit", root, onLeave)

local function onWasted()
    local state = Patients[source]
    if state and not state.dead then
        biologicalDeath(state, false)
    end
end
addEventHandler("onPlayerWasted", root, onWasted)
addEventHandler("onPedWasted", root, onWasted)

-- Element data and animations outlive the resource, clean them up
addEventHandler("onResourceStop", resourceRoot, function()
    for element, state in pairs(Patients) do
        if isElement(element) then
            removeElementData(element, MEDIC.DATA_STATUS)
            removeElementData(element, MEDIC.DATA_SPO2)
            removeElementData(element, MEDIC.DATA_HEART_RATE)
            if state.animated and not state.dead then setPedAnimation(element) end
        end
    end
end)

-- A fresh spawn is a fresh body
addEventHandler("onPlayerSpawn", root, function()
    if Patients[source] then
        stopTreatmentsOn(source)
        removePatient(source)
    end
end)
