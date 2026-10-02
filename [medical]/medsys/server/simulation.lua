-- Physiology simulation. One global timer steps every patient in the registry; it only
-- runs while there is at least one patient.
--
-- Model per step:
--   blood volume  <- bleeding (per wound level) + burn plasma loss, IV fluids, slow compensation
--   SpO2          <- drifts to the lowest target of the airway causes / shock / restingSpo2, recovers otherwise;
--                    the oxygen mask lifts the targets, the muscle relaxant stops the breathing
--   heart rate/BP <- drift to targets derived from blood loss (shock classes), pain and hypoxia;
--                    the pulse always rises as the pressure falls (baroreflex); the resting
--                    setters (restingSystolic, ...) add lasting shifts to these targets
--   consciousness <- derived from SpO2, systolic pressure, pain and forced knockouts
--   medicines     <- shift the circulation targets, ease the pain, sedate / paralyse (MEDIC_DRUGS);
--                    an awake patient under the muscle relaxant panics (pulse and pressure jump)
--   intubated patient: kept down until stable (and no medicine keeps it asleep), then extubated
--   SpO2 <= ARREST_SPO2, blood <= ARREST_BLOOD or systolic <= ARREST_SYSTOLIC -> cardiac arrest
--   pulse >= ARREST_HEART_RATE for ARREST_TACHY_TIME seconds                  -> cardiac arrest
--   clinical death longer than DEATH_TIME        -> biological death

local simTimer
local lastTick

local BLOOD_REGEN = 0.3         -- ml/s the body compensates while nothing bleeds
local IV_MAX_VOLUME = 0.9       -- IV fluids restore the volume up to this fraction
local ARREST_SPO2_RATE = 1.5    -- %/s the SpO2 falls without circulation
local SHOCK_SPO2 = { 0.65, 85, 0.3 } -- below this blood fraction the SpO2 drifts to 85% at 0.3%/s
local PAIN_FADE = 1             -- external pain points lost per second

local function approach(value, target, step)
    if value < target then
        return math.min(target, value + step)
    end
    return math.max(target, value - step)
end

local function updateBlood(state, dt, arrested)
    local loss = MEDIC.BLEED_RATE[getPatientBleeding(state)]
    for _, injury in ipairs(state.injuries) do
        local def = MEDIC_INJURIES[injury.type]
        if def.loss then
            loss = loss + def.loss[injury.severity] * (injury.treated and def.treatedLoss or 1)
        end
    end
    if arrested then loss = loss * MEDIC.ARREST_BLEED_FACTOR end

    local gain = 0
    local maxVolume = MEDIC.BLOOD_VOLUME
    if state.ivAccess and state.bloodVolume < MEDIC.BLOOD_VOLUME * IV_MAX_VOLUME then
        gain = MEDIC.IV_FLUID_RATE * (0.5 + state.ivQuality / 200)
        maxVolume = MEDIC.BLOOD_VOLUME * IV_MAX_VOLUME
    elseif loss == 0 and not arrested then
        gain = BLOOD_REGEN
    end

    local volume = state.bloodVolume - loss * dt
    if gain > 0 and volume < maxVolume then
        volume = math.min(maxVolume, volume + gain * dt)
    end
    state.bloodVolume = math.max(0, math.min(MEDIC.BLOOD_VOLUME, volume))
end

local function updateSpO2(state, dt, arrested, bloodFraction, now)
    if state.apneaRate then
        state.spo2 = math.max(0, state.spo2 - state.apneaRate * dt)
        return
    end
    if arrested then
        state.spo2 = math.max(0, state.spo2 - ARREST_SPO2_RATE * dt)
        return
    end
    -- paralysed without a tube: no breathing at all, the mask only slows the fall
    if not state.intubated and isParalyzed(state, now) then
        local rate = MEDIC.PARALYSIS_SPO2_RATE * (state.oxygenMask and MEDIC.OXYGEN_APNEA_FACTOR or 1)
        state.spo2 = math.max(0, state.spo2 - rate * dt)
        return
    end

    local mask = state.oxygenMask and not state.intubated
    local bonus = mask and MEDIC.OXYGEN_SPO2_BONUS or 0
    local target, rate = mask and MEDIC.OXYGEN_SPO2 or MEDIC.SPO2, MEDIC.SPO2_RECOVERY
    if not state.intubated then
        for _, injury in ipairs(state.injuries) do
            local def = MEDIC_INJURIES[injury.type]
            local value = def.spo2 and def.spo2[injury.severity]
            if value and value + bonus < target then
                target, rate = value + bonus, def.spo2Rate
            end
        end
    end
    -- lasting low SpO2 of the patient (setMedicalState "restingSpo2"), the mask lifts it too
    if state.spo2Limit and not state.intubated and state.spo2Limit + bonus < target then
        target, rate = state.spo2Limit + bonus, MEDIC.SPO2_RECOVERY
    end
    if bloodFraction < SHOCK_SPO2[1] and SHOCK_SPO2[2] + bonus < target then
        target, rate = SHOCK_SPO2[2] + bonus, SHOCK_SPO2[3]
    end

    if state.spo2 > target then
        state.spo2 = math.max(target, state.spo2 - rate * dt)
    else
        local recovery = MEDIC.SPO2_RECOVERY * (mask and MEDIC.OXYGEN_RECOVERY or 1)
        state.spo2 = math.min(target, state.spo2 + recovery * dt)
    end
end

-- Physiological targets of the circulation: systolic, diastolic, heart rate.
-- systolicNow is the pressure the pulse reacts to (baroreflex); the simulation passes the
-- actual one, the resting setters (exports.lua) the steady state (the systolic target).
function getCirculationTargets(state, bloodFraction, pain, systolicNow)
    local shift = state.restShift
    local loss = 1 - bloodFraction
    local spo2 = state.spo2

    -- blood pressure holds until ~15% loss (class I), then falls
    local systolic = MEDIC.SYSTOLIC - math.max(0, loss - 0.15) * 250 + pain * 0.1
        + state.hypertension + shift.systolic + getDrugEffect(state, "systolic")
        + (state.panic and MEDIC.PANIC_SYSTOLIC or 0)
    local diastolic = systolic * (MEDIC.DIASTOLIC / MEDIC.SYSTOLIC) + shift.diastolic
    if spo2 < 50 then -- severe hypoxia: collapse before the arrest
        systolic = systolic * (spo2 / 50)
        diastolic = diastolic * (spo2 / 50)
    end
    systolic = math.max(0, systolic)
    diastolic = math.max(0, math.min(systolic - 10, diastolic))

    -- the pulse follows the actual pressure: the lower it is, the faster the heart beats,
    -- whatever lowered it (blood loss, medicine, ...). On top: early compensation of the
    -- blood loss (the pressure still holds), pain and hypoxia.
    systolicNow = systolicNow or systolic
    local heartRate = MEDIC.HEART_RATE + math.max(0, MEDIC.SYSTOLIC - systolicNow) * MEDIC.BARO_REFLEX
        + math.min(loss, 0.3) * 100 + pain * 0.25 + shift.heartRate
        + getDrugEffect(state, "heartRate") + (state.panic and MEDIC.PANIC_HEART_RATE or 0)
    if spo2 < 85 then heartRate = heartRate + (85 - spo2) end
    -- severe hypoxia: the heart muscle fails, bradycardia before the arrest
    if spo2 < 50 then heartRate = 20 + spo2 end
    return systolic, diastolic, math.max(0, heartRate)
end

-- Natural variation: now and then a new random offset on the pressure / pulse targets
local function updateJitter(state, dt)
    local jitter = state.jitter
    if math.random() < dt / MEDIC.JITTER_TIME then
        jitter.systolic = (math.random() * 2 - 1) * MEDIC.BP_JITTER
        jitter.heartRate = (math.random() * 2 - 1) * MEDIC.HR_JITTER
    end
    return jitter
end

local function updateCirculation(state, dt, bloodFraction, pain)
    local jitter = updateJitter(state, dt)
    local systolic, diastolic = getCirculationTargets(state, bloodFraction, pain, state.systolic)
    if systolic > 0 then
        diastolic = math.max(0, diastolic + jitter.systolic * (MEDIC.DIASTOLIC / MEDIC.SYSTOLIC))
        systolic = math.max(0, systolic + jitter.systolic)
    end
    state.systolic = approach(state.systolic, systolic, MEDIC.BP_RATE * dt)
    state.diastolic = approach(state.diastolic, diastolic, MEDIC.BP_RATE * dt)
    local _, _, heartRate = getCirculationTargets(state, bloodFraction, pain, state.systolic)
    if heartRate > 0 then heartRate = heartRate + jitter.heartRate end
    state.heartRate = approach(state.heartRate, heartRate, MEDIC.HR_RATE * dt)
end

-- True when the pulse has been at the extreme limit for long enough to stop the heart
local function updateTachycardia(state, now)
    if state.heartRate < MEDIC.ARREST_HEART_RATE then
        state.tachyTick = nil
        return false
    end
    state.tachyTick = state.tachyTick or now
    return now - state.tachyTick >= MEDIC.ARREST_TACHY_TIME * 1000
end

-- Expired medicine doses wear off
local function updateDrugs(state, now)
    for i = #state.drugs, 1, -1 do
        if now >= state.drugs[i].untilTick then table.remove(state.drugs, i) end
    end
end

local CONSCIOUSNESS_RANK = { stable = 1, dazed = 2, unconscious = 3 }

local function deriveConsciousness(state, pain, now)
    local status = "stable"
    if state.spo2 < MEDIC.UNCONSCIOUS_SPO2 or state.systolic < MEDIC.UNCONSCIOUS_SYSTOLIC then
        status = "unconscious"
    elseif state.spo2 < MEDIC.DAZED_SPO2 or state.systolic < MEDIC.DAZED_SYSTOLIC or pain >= MEDIC.DAZED_PAIN then
        status = "dazed"
    end
    state.aware = status ~= "unconscious"
    -- the anaesthetic and the muscle relaxant keep the patient down
    if isSedated(state) or isParalyzed(state, now) then status = "unconscious" end

    if state.knockoutUntil then
        if now >= state.knockoutUntil then
            state.knockoutState, state.knockoutUntil = nil, nil
        elseif CONSCIOUSNESS_RANK[state.knockoutState] > CONSCIOUSNESS_RANK[status] then
            status = state.knockoutState
        end
    end
    return status
end

-- True when there is nothing left to simulate or show for this patient
local function canDischarge(state)
    return not Persistent[state.element] and isPatientHealthy(state)
        and not isPatientAttended(state.element)
end

local function stepPatient(state, dt, now)
    if state.dead then return end

    local arrested = state.arrestTick ~= nil
    updateBlood(state, dt, arrested)
    local bloodFraction = state.bloodVolume / MEDIC.BLOOD_VOLUME
    updateSpO2(state, dt, arrested, bloodFraction, now)
    state.extraPain = math.max(0, state.extraPain - PAIN_FADE * dt)
    updateDrugs(state, now)
    -- awake under the muscle relaxant (no anaesthetic): panic
    state.panic = state.aware and hasDrugEffect(state, "paralysis") and not isSedated(state)

    if arrested then
        if now >= state.deathTick then
            biologicalDeath(state)
        end
        return
    end

    local pain = getPatientPain(state)
    updateCirculation(state, dt, bloodFraction, pain)

    if state.spo2 <= MEDIC.ARREST_SPO2 or bloodFraction <= MEDIC.ARREST_BLOOD
        or state.systolic <= MEDIC.ARREST_SYSTOLIC or updateTachycardia(state, now) then
        cardiacArrest(state)
        return
    end

    local status = deriveConsciousness(state, pain, now)
    -- an intubated patient never wakes up with the tube in: it stays down until it has fully
    -- recovered (and no medicine keeps it asleep), then the tube comes out
    if state.intubated and status ~= "unconscious" then
        if status == "stable" then
            state.intubated = false
        else
            status = "unconscious"
        end
    end
    setConsciousness(state, status)
end

local function simulate()
    local now = getTickCount()
    local dt = math.min(5, (now - lastTick) / 1000)
    lastTick = now

    for element, state in pairs(Patients) do
        if isElement(element) then
            stepPatient(state, dt, now)
            if Patients[element] == state then
                writeVitalsData(state)
                sendPanelUpdates(state)
                if canDischarge(state) then removePatient(element) end
            end
        else
            removePatient(element, true)
        end
    end
end

function startSimulation()
    if simTimer then return end
    lastTick = getTickCount()
    simTimer = setTimer(simulate, MEDIC.TICK, 0)
end

function stopSimulation()
    if not simTimer then return end
    if isTimer(simTimer) then killTimer(simTimer) end
    simTimer = nil
end
