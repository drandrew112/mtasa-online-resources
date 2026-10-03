-- Public API for other resources (see README.md).

local function clamp(value, min, max)
    return math.max(min, math.min(max, value))
end

local function toBoolean(value)
    return value == true or value == 1 or value == "true"
end

-- Returns every medical parameter of a ped / player as a table (a copy), or false.
-- Elements that are not in the registry are healthy (or dead, if they are dead).
function getMedicalState(element)
    if not isValidPatient(element) then return false end
    local state = Patients[element]
    if state then return buildSnapshot(state) end
    return buildDefaultSnapshot(element)
end

local function setNumber(field, min, max)
    return function(state, value)
        value = tonumber(value)
        if not value then return false end
        state[field] = clamp(value, min, max)
        return true
    end
end

-- Steady-state circulation targets of the patient as it is now
local function currentTargets(state)
    local bloodFraction = state.bloodVolume / MEDIC.BLOOD_VOLUME
    local pain = getPatientPain(state)
    local systolic = getCirculationTargets(state, bloodFraction, pain)
    return getCirculationTargets(state, bloodFraction, pain, systolic)
end

-- Resting value: shifts the simulation's target so that the patient settles at this value
-- (with its current injuries / blood loss / pain / medicines) and stays there; later changes
-- (more blood loss, medicines, the pain fading) act on top. Also sets the current value.
-- index: 1 systolic, 2 diastolic, 3 heart rate
local function setResting(field, index, min, max)
    return function(state, value)
        value = tonumber(value)
        if not value then return false end
        value = clamp(value, min, max)
        state.restShift[field] = 0
        local natural = select(index, currentTargets(state))
        state.restShift[field] = value - natural
        if not state.arrestTick then
            state[field] = value
            -- the diastolic and the pulse follow the systolic: jump to their new targets as well
            if field == "systolic" then
                local _, diastolic, heartRate = currentTargets(state)
                state.diastolic, state.heartRate = diastolic, heartRate
            end
        end
        return true
    end
end

-- key -> setter(state, value) -> success
local SETTERS = {
    systolic = setNumber("systolic", 0, 300),
    diastolic = setNumber("diastolic", 0, 200),
    spo2 = setNumber("spo2", 0, 100),
    bloodVolume = setNumber("bloodVolume", 0, MEDIC.BLOOD_VOLUME),
    pain = setNumber("extraPain", 0, 100),
    -- mmHg added to the target systolic pressure until set back to 0 (lasting high blood pressure)
    hypertension = setNumber("hypertension", 0, 120),

    -- lasting values the patient holds (see setResting); set systolic before diastolic / heartRate
    restingSystolic = setResting("systolic", 1, 40, 260),
    restingDiastolic = setResting("diastolic", 2, 20, 160),
    restingHeartRate = setResting("heartRate", 3, 30, 190),
    -- lasting SpO2 cap (chronic hypoxia), the oxygen mask lifts it, intubation removes it
    restingSpo2 = function(state, value)
        value = tonumber(value)
        if not value then return false end
        value = clamp(value, 1, 100)
        state.spo2Limit = value < MEDIC.SPO2 and value or nil
        if not state.arrestTick then state.spo2 = value end
        return true
    end,

    -- 0 stops every bleeding, 1-3 sets a bleeding that is not tied to an injury
    bleeding = function(state, value)
        value = tonumber(value)
        if not value then return false end
        value = clamp(math.floor(value), 0, 3)
        state.baseBleeding = value
        if value == 0 then
            for _, injury in ipairs(state.injuries) do injury.bleeding = 0 end
        end
        return true
    end,

    -- 0 = cardiac arrest, above 0 during clinical death = return of circulation
    heartRate = function(state, value)
        value = tonumber(value)
        if not value then return false end
        if value <= 0 then
            cardiacArrest(state)
            return true
        end
        restoreCirculation(state)
        state.heartRate = clamp(value, 1, 250)
        return true
    end,

    ivAccess = function(state, value)
        state.ivAccess = toBoolean(value)
        state.ivQuality = state.ivAccess and 100 or 0
        return true
    end,

    intubated = function(state, value)
        state.intubated = toBoolean(value)
        if state.intubated then state.oxygenMask = false end
        for _, injury in ipairs(state.injuries) do
            if injury.type == "suffocation" then injury.treated = state.intubated end
        end
        return true
    end,

    oxygenMask = function(state, value)
        state.oxygenMask = toBoolean(value) and not state.intubated
        return true
    end,

    -- monitor / defibrillator attached (true) or taken off (false)
    monitor = function(state, value)
        if toBoolean(value) then attachMonitor(state) else state.monitor = nil end
        return true
    end,

    -- stable: wakes / revives the patient (vitals keep deciding afterwards)
    -- dazed / unconscious: forced for MEDIC.KNOCKOUT_TIME seconds
    -- clinical_death: cardiac arrest, dead: biological death
    consciousness = function(state, value)
        if value == "clinical_death" then
            cardiacArrest(state)
        elseif value == "dead" then
            biologicalDeath(state)
        elseif value == "stable" or value == "dazed" or value == "unconscious" then
            restoreCirculation(state)
            if value == "stable" then
                state.knockoutState, state.knockoutUntil = nil, nil
            else
                state.knockoutState = value
                state.knockoutUntil = getTickCount() + MEDIC.KNOCKOUT_TIME * 1000
            end
            setConsciousness(state, value)
        else
            return false
        end
        return true
    end,
}

-- Heart rhythm (MEDIC_RHYTHMS key). A pulseless one is a cardiac arrest in that rhythm,
-- VT_WITH_PULSE a lasting VT (only a shock ends it), a sinus one moves the resting pulse into its
-- range (bradycardia < 60, tachycardia > 100) when it is outside. A patient already in cardiac
-- arrest only takes a pulseless rhythm: a rhythm with a pulse sets ASYSTOLE instead.
SETTERS.rhythm = function(state, value)
    local def = MEDIC_RHYTHMS[value]
    if not def then return false end
    if not def.pulse then
        if isInClinicalDeath(state) then setRhythm(state, value) else cardiacArrest(state, nil, value) end
        return true
    end
    -- a patient in cardiac arrest can only get a pulseless rhythm: anything else is asystole
    if isInClinicalDeath(state) then
        setRhythm(state, "ASYSTOLE")
        return true
    end
    if value == "VT_WITH_PULSE" then
        startVT(state)
        state.heartRate = MEDIC.VT_RATE
        return true
    end
    state.vtTick = nil
    local hr = state.heartRate
    if value == "SINUS_BRADY" and hr >= MEDIC.BRADY_RATE then
        SETTERS.restingHeartRate(state, 48)
    elseif value == "SINUS_TACHY" and hr <= MEDIC.TACHY_RATE then
        SETTERS.restingHeartRate(state, 125)
    elseif value == "SINUS" and (hr < MEDIC.BRADY_RATE or hr > MEDIC.TACHY_RATE) then
        SETTERS.restingHeartRate(state, MEDIC.HEART_RATE)
    end
    refreshPulseRhythm(state)
    return true
end

-- Changes one parameter. Keys: consciousness, heartRate, systolic, diastolic, spo2, bleeding,
-- bloodVolume, pain, hypertension, restingSystolic, restingDiastolic, restingHeartRate, restingSpo2,
-- ivAccess, intubated, oxygenMask, monitor, rhythm. The simulation keeps running from the new value.
function setMedicalState(element, key, value)
    local setter = SETTERS[key]
    if not setter or not isValidPatient(element) then return false end
    local state = getPatient(element, true)
    if not state or state.dead then return false end
    local ok = setter(state, value)
    if ok and not state.dead then writeVitalsData(state) end
    return ok
end

-- Adds an injury. injuryType: "gunshot" | "fracture" | "burn" | "suffocation",
-- severity: 1-3 or "minor" | "serious" | "critical". Returns the injury id, or false.
function applyInjury(element, injuryType, severity)
    local def = MEDIC_INJURIES[injuryType]
    severity = medicNormalizeSeverity(severity)
    if not def or not severity or not isValidPatient(element) or isPedDead(element) then return false end

    local state = getPatient(element, true)
    if not state or state.dead then return false end

    local id = state.nextInjuryId
    state.nextInjuryId = id + 1
    state.injuries[#state.injuries + 1] = {
        id = id,
        type = injuryType,
        severity = severity,
        bleeding = def.bleed[severity],
        treated = false,
        tick = getTickCount(),
    }
    -- an airway that is already secured covers a new suffocation cause
    if injuryType == "suffocation" and state.intubated then
        state.injuries[#state.injuries].treated = true
    end
    triggerEvent("onMedicalInjury", element, injuryType, severity, id)
    return id
end

-- Resets every parameter to the baseline and drops the element from the registry.
-- A living ped / player also gets its health back to 100.
function healCompletely(element)
    if not isValidPatient(element) then return false end
    resetPatient(element)
    if not isPedDead(element) then
        setElementHealth(element, 100)
    end
    return true
end

function isPatientPersistent(element)
    return Persistent[element] == true
end

addEvent("onMedicalInjury", false)
