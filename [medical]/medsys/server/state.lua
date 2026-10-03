-- Patient registry and the medical state data structure.
--
-- Only elements that are not perfectly healthy are kept in the registry (Patients), except the
-- persistent ones (setPatientPersistent, e.g. every player via medsys_events): they always stay in
-- it, so they always carry the status element data and can always be examined.
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
--     oxygenMask    = false,                -- oxygen mask on
--     hypertension  = 0,                    -- mmHg added to the target systolic pressure (setMedicalState)
--     restShift     = { systolic, diastolic, heartRate }, -- lasting target shifts (setMedicalState resting*)
--     spo2Limit     = nil,                  -- lasting SpO2 target cap (setMedicalState restingSpo2)
--     jitter        = { systolic, heartRate }, -- current random target offsets (natural variation)
--     drugs         = { { id, tick, untilTick }, ... }, -- active medicine doses (MEDIC_DRUGS)
--     aware         = true,                 -- awake apart from the medicines (their sedation / paralysis)
--     panic         = false,                -- awake under the muscle relaxant
--     apneaRate     = nil,                  -- %/s SpO2 fall while an intubation attempt runs
--     consciousness = "stable",             -- stable | dazed | unconscious | clinical_death | dead
--     rhythm        = "SINUS",              -- heart rhythm (MEDIC_RHYTHMS), server/rhythm.lua
--     rhythmTick    = 0,                    -- getTickCount() since the current rhythm (arrest rhythms worsen)
--     ecgRate       = 0,                    -- electrical rate of a pulseless VT / PEA (the others: heartRate / 0)
--     vtTick        = nil,                  -- lasting VT with pulse since (turns pulseless after VT_DEGRADE_TIME)
--     monitor       = nil,                  -- monitor / defibrillator attached: { energy, sync, chargeTick, ... }
--     tachyTick     = nil,                  -- getTickCount() since the pulse is at ARREST_HEART_RATE+
--     arrestTick    = nil,                  -- getTickCount() of the cardiac arrest
--     deathTick     = nil,                  -- getTickCount() of biological death (arrestTick + DEATH_TIME)
--     knockoutState = nil, knockoutUntil = nil, -- forced dazed / unconscious state and its end
--     dead          = false,                -- biological death, the simulation stops
--     sent          = { spo2, heartRate },  -- last values written to element data
-- }

Patients = {}
Persistent = {} -- [element] = true: never discharged, re-registered after a reset / respawn

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
        oxygenMask = false,
        hypertension = 0,
        restShift = { systolic = 0, diastolic = 0, heartRate = 0 },
        spo2Limit = nil,
        jitter = { systolic = 0, heartRate = 0 },
        drugs = {},
        consciousness = "stable",
        rhythm = "SINUS",
        rhythmTick = getTickCount(),
        ecgRate = 0,
        vtTick = nil,
        monitor = nil,
        aware = true,
        panic = false,
        dead = false,
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
        -- a persistent patient starts over with a fresh (healthy) state (a dead one at its spawn)
        if Persistent[element] and not isPedDead(element) then getPatient(element, true) end
    end
    if leaving then Persistent[element] = nil end
    return true
end

-- Nothing is wrong with the patient (back to the baseline), see canDischarge in simulation.lua
function isPatientHealthy(state)
    return #state.injuries == 0 and state.baseBleeding == 0 and state.extraPain == 0
        and not state.knockoutUntil and not state.arrestTick and not state.dead
        and state.hypertension == 0 and #state.drugs == 0
        and state.restShift.systolic == 0 and state.restShift.diastolic == 0
        and state.restShift.heartRate == 0 and not state.spo2Limit and not state.vtTick
        and state.consciousness == "stable"
        and state.bloodVolume >= MEDIC.BLOOD_VOLUME
        and state.spo2 >= MEDIC.DISCHARGE_SPO2
        and math.abs(state.heartRate - MEDIC.HEART_RATE) < MEDIC.HR_JITTER + 2
        and math.abs(state.systolic - MEDIC.SYSTOLIC) < MEDIC.BP_JITTER + 2
end

-- persistent = true keeps the element in the registry even while healthy (registers it now)
function setPatientPersistent(element, persistent)
    if not isValidPatient(element) then return false end
    if persistent then
        Persistent[element] = true
        if not isPedDead(element) then getPatient(element, true) end -- a dead one: at its spawn
    else
        Persistent[element] = nil
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

-- Pain 0-100 from the injuries (treated ones hurt less) plus the external pain, minus the painkillers
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
    return math.min(100, pain) * (1 - math.min(1, getDrugEffect(state, "analgesia")))
end

-- Sum of an effect field (e.g. "systolic") over the active medicine doses
function getDrugEffect(state, field)
    local total = 0
    for _, dose in ipairs(state.drugs) do
        total = total + (MEDIC_DRUGS[dose.id][field] or 0)
    end
    return total
end

-- Highest value of an effect field over the active doses (effects that do not add up)
function getDrugMax(state, field)
    local best = 0
    for _, dose in ipairs(state.drugs) do
        local value = MEDIC_DRUGS[dose.id][field]
        if value and value > best then best = value end
    end
    return best
end

-- Is any active dose of a medicine with this flag (e.g. "paralysis") in the body
function hasDrugEffect(state, field)
    for _, dose in ipairs(state.drugs) do
        if MEDIC_DRUGS[dose.id][field] then return true end
    end
    return false
end

-- The anaesthetic keeps the patient asleep
function isSedated(state)
    return hasDrugEffect(state, "sedation")
end

-- The muscle relaxant works (its onset is over): no movement, no own breathing
function isParalyzed(state, now)
    now = now or getTickCount()
    for _, dose in ipairs(state.drugs) do
        if MEDIC_DRUGS[dose.id].paralysis and now - dose.tick >= MEDIC.PARALYSIS_ONSET * 1000 then
            return true
        end
    end
    return false
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

    local rhythm = MEDIC_RHYTHMS[state.rhythm]
    local ecgRate = 0
    if rhythm.pulse then
        ecgRate = round(state.heartRate)
    elseif not state.dead then
        ecgRate = state.ecgRate
    end

    local deathTimeLeft
    if isInClinicalDeath(state) then
        deathTimeLeft = math.max(0, math.ceil((state.deathTick - getTickCount()) / 1000))
    end

    return {
        -- registered and not just a healthy persistent element: it needs care
        isPatient = Patients[state.element] == state
            and not (Persistent[state.element] and isPatientHealthy(state)),
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
        oxygenMask = state.oxygenMask,
        sedated = isSedated(state),
        paralyzed = isParalyzed(state, now),
        drugs = drugs,
        rhythm = state.rhythm,
        rhythmLabel = rhythm.label,
        ecgRate = ecgRate,              -- rate of the ECG complexes (the pulse is heartRate)
        monitor = getMonitorSnapshot(state, now), -- nil while no monitor is attached
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
        state.rhythm = "ASYSTOLE"
    end
    local snapshot = buildSnapshot(state)
    snapshot.isPatient = false
    return snapshot
end

---------------------------------------------------------------------------
-- State transitions
---------------------------------------------------------------------------

-- The animations (down / get up) and what a player patient experiences (screen, control lock)
-- belong to medsys_effects, which follows the status element data and these events.
function setConsciousness(state, status)
    local old = state.consciousness
    if old == status then return end
    state.consciousness = status

    setElementData(state.element, MEDIC.DATA_STATUS, status)
    triggerEvent("onMedicalStateChange", state.element, status, old)
end

-- Pulse 0: clinical death starts, the death timer runs.
-- cause: picks the starting rhythm (MEDIC_ARREST_RHYTHMS), rhythm: forces it (pulseless only)
function cardiacArrest(state, cause, rhythm)
    if state.arrestTick or state.dead then return end
    local now = getTickCount()
    state.arrestTick = now
    state.deathTick = now + MEDIC.DEATH_TIME * 1000
    state.tachyTick, state.vtTick = nil, nil
    setRhythm(state, rhythm or pickArrestRhythm(cause), now)
    state.heartRate, state.systolic, state.diastolic = 0, 0, 0
    state.knockoutState, state.knockoutUntil = nil, nil
    state.panic = false

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
    state.vtTick = nil
    refreshPulseRhythm(state)

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
    state.vtTick = nil
    setRhythm(state, "ASYSTOLE")
    if state.monitor then state.monitor.chargeTick, state.monitor.analyzeTick = nil, nil end

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
    Persistent[source] = nil
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

-- Element data outlives the resource, clean it up
addEventHandler("onResourceStop", resourceRoot, function()
    for element in pairs(Patients) do
        if isElement(element) then
            removeElementData(element, MEDIC.DATA_STATUS)
            removeElementData(element, MEDIC.DATA_SPO2)
            removeElementData(element, MEDIC.DATA_HEART_RATE)
        end
    end
end)

-- A fresh spawn is a fresh body
addEventHandler("onPlayerSpawn", root, function()
    if Patients[source] then
        stopTreatmentsOn(source)
        removePatient(source) -- re-registers a persistent one
    elseif Persistent[source] then
        getPatient(source, true)
    end
end)
