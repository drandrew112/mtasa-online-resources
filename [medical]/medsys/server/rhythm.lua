if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Heart rhythm (ECG) and the monitor / defibrillator (Lifepak 15).
--
-- With a pulse the rhythm is named from the heart rate (sinus / bradycardia / tachycardia, VT at
-- MEDIC.VT_HEART_RATE and above), except a lasting VT with pulse (state.vtTick) that only a shock
-- ends and that turns pulseless after MEDIC.VT_DEGRADE_TIME, and a lasting SVT (state.svtTick, after
-- a ROSC) that only adenosine ends and that turns into VT with pulse after MEDIC.SVT_DEGRADE_TIME.
-- Adenosine stops the heart for MEDIC.ADENOSINE_PAUSE_TIME seconds (state.pauseUntil, the monitor
-- shows ADENOSINE_PAUSE); then an SVT may restart in a sinus rhythm, anything else comes back.
-- A cardiac arrest starts with a rhythm picked by its cause (MEDIC_ARREST_RHYTHMS). Untreated it
-- worsens (pVT -> VF -> asystole, PEA -> asystole); CPR pauses that.
-- CPR: after MEDIC.CPR_CHANGE_MIN seconds of good compressions the rhythm can change at any
-- moment (pulse back, or another arrest rhythm, a shockable one too). The change stops the CPR
-- minigame. VF / pulseless VT mostly needs a shock, and a successful shock is not always a pulse:
-- PEA or asystole can follow.
--
-- state.monitor = {
--     energy      = 200,     -- joules (MEDIC.DEFIB_ENERGY, fixed: ENERGY SELECT is inactive)
--     sync        = false,   -- synchronised shock (cardioversion of VT with pulse)
--     sound       = true,    -- ECG beep + alarm at the panel (SOUND button; a new patient starts with it on)
--     chargeTick  = nil,     -- charging since (charged after DEFIB_CHARGE_TIME, dumped after DEFIB_DISARM_TIME)
--     analyzeTick = nil,     -- ANALYZE running since
--     advice      = nil,     -- "shock" | "noshock", the last analysis (adviceTick)
--     message     = nil,     -- short line on the monitor screen (messageTick)
--     shocks      = 0,
-- }

-- rhythm.lua loads before treatment.lua: its events are added here
addEvent("onMedicalDefibrillation", false)
addEvent("medic:defib", true)

---------------------------------------------------------------------------
-- Rhythm
---------------------------------------------------------------------------

-- Sets the rhythm. The electrical rate of a pulseless VT / PEA is picked when it starts.
function setRhythm(state, rhythm, now)
    if state.rhythm == rhythm then return end
    state.rhythm = rhythm
    state.rhythmTick = now or getTickCount()
    if rhythm == "PULSELESS_VT" then
        state.ecgRate = math.random(170, 210)
    elseif rhythm == "PEA" then
        state.ecgRate = math.random(35, 60)
    else
        state.ecgRate = 0
    end
end

-- Weighted random rhythm for a cardiac arrest of this cause
function pickArrestRhythm(cause)
    local weights = MEDIC_ARREST_RHYTHMS[cause] or MEDIC_ARREST_RHYTHMS.default
    local total = 0
    for _, weight in pairs(weights) do total = total + weight end
    local roll = math.random() * total
    local last
    for rhythm, weight in pairs(weights) do
        roll = roll - weight
        last = rhythm
        if roll <= 0 then return rhythm end
    end
    return last
end

-- the rhythm an untreated condition forces (MEDIC_INJURIES[type].rhythm), or nil
function conditionRhythm(state)
    for _, injury in ipairs(state.injuries) do
        local def = MEDIC_INJURIES[injury.type]
        if def and def.rhythm and not injury.treated then return def.rhythm end
    end
end

-- Names the rhythm of a beating heart from its rate (half a beat of hysteresis around the limits)
function refreshPulseRhythm(state, now)
    local hr, current = state.heartRate, state.rhythm
    local rhythm = "SINUS"
    if state.vtTick then
        rhythm = "VT_WITH_PULSE"
    elseif state.svtTick then
        rhythm = "SVT"
    elseif hr >= MEDIC.VT_HEART_RATE then
        rhythm = "VT_WITH_PULSE"
    elseif conditionRhythm(state) then
        -- an untreated condition with its own rhythm (atrial fibrillation, complete AV block)
        rhythm = conditionRhythm(state)
    elseif hr < MEDIC.BRADY_RATE + (current == "SINUS_BRADY" and 0.5 or -0.5) then
        rhythm = "SINUS_BRADY"
    elseif hr > MEDIC.TACHY_RATE + (current == "SINUS_TACHY" and -0.5 or 0.5) then
        rhythm = "SINUS_TACHY"
    end
    setRhythm(state, rhythm, now)
end

-- Panel line after a rhythm change (without a monitor the medic only knows that something changed)
local function rhythmChangeMessage(state)
    if not state.monitor then return L.msg("medsys.rhythm.patient_s_condition_changed_attach_monitor") end
    local def = MEDIC_RHYTHMS[state.rhythm]
    if def.shockable then return L.msg("medsys.rhythm.rhythm_change_shock", { label = def.label }) end
    return L.msg("medsys.rhythm.rhythm_change", { label = def.label })
end

-- Lasting VT with pulse (ends a lasting SVT)
function startVT(state)
    state.vtTick = getTickCount()
    state.svtTick, state.svtRate = nil, nil
    setRhythm(state, "VT_WITH_PULSE")
end

-- Lasting SVT at a rate picked from MEDIC.SVT_RATE
function startSVT(state)
    if state.vtTick then return end
    state.svtTick = getTickCount()
    state.svtRate = math.random(MEDIC.SVT_RATE[1], MEDIC.SVT_RATE[2])
    setRhythm(state, "SVT")
end

-- Arrest / ROSC / death: no SVT, no adenosine pause, no post-ROSC window
function clearSVT(state)
    state.svtTick, state.svtRate, state.roscTick = nil, nil, nil
    state.pauseUntil, state.pauseConvert = nil, nil
end

-- The adenosine pause is over: the heart restarts
local function resolveAdenosine(state)
    local convert = state.pauseConvert
    state.pauseUntil, state.pauseConvert = nil, nil
    local message
    if convert and state.svtTick then
        state.svtTick, state.svtRate = nil, nil
        state.heartRate = math.min(state.heartRate, math.random(95, 110))
        refreshPulseRhythm(state)
        message = L.msg("medsys.rhythm.adenosine_sinus_restored")
    else
        message = L.msg("medsys.rhythm.adenosine_rhythm_unchanged")
    end
    writeVitalsData(state)
    notifyExaminers(state.element, message, not convert)
end

-- Adenosine given (treatment.lua): the heart stops for a moment, an SVT may convert.
-- scale: dose multiplier (1 = 6 mg, 2 = 12 mg)
function applyAdenosine(state, scale)
    if isInClinicalDeath(state) or state.dead then return false end
    local now = getTickCount()
    state.pauseUntil = now + MEDIC.ADENOSINE_PAUSE_TIME * 1000
    local success = MEDIC.ADENOSINE_SUCCESS[(scale or 1) >= 2 and 2 or 1]
    state.pauseConvert = state.svtTick ~= nil and math.random() < success
    if not medicIsDown(state.consciousness) then
        state.extraPain = math.max(state.extraPain, MEDIC.ADENOSINE_PAIN)
    end
    return true
end

function isAdenosinePause(state)
    return state.pauseUntil ~= nil
end

-- Every step of a patient with a pulse. True when the lasting VT turned pulseless (arrest).
function updatePulseRhythm(state, now, dt)
    if state.pauseUntil then
        if now < state.pauseUntil then return false end
        resolveAdenosine(state)
    end
    if state.vtTick and now - state.vtTick >= MEDIC.VT_DEGRADE_TIME * 1000 then return true end
    if state.svtTick and now - state.svtTick >= MEDIC.SVT_DEGRADE_TIME * 1000 then
        startVT(state)
        notifyExaminers(state.element, rhythmChangeMessage(state), true)
    end
    -- the first minutes after a ROSC: the heart can still slip into SVT
    if state.roscTick then
        if now - state.roscTick >= MEDIC.POST_ROSC_SVT_WINDOW * 1000 then
            state.roscTick = nil
        elseif not state.svtTick and not state.vtTick
            and math.random() < (dt or 0) * MEDIC.POST_ROSC_SVT_CHANCE / MEDIC.POST_ROSC_SVT_WINDOW then
            state.roscTick = nil
            startSVT(state)
            notifyExaminers(state.element, rhythmChangeMessage(state), true)
        end
    end
    refreshPulseRhythm(state, now)
    return false
end

-- Return of circulation from CPR or a shock: not always a sinus rhythm
local function returnOfCirculation(state)
    restoreCirculation(state)
    state.roscTick = getTickCount()
    if math.random() < MEDIC.ROSC_VT_CHANCE then
        startVT(state)
    elseif math.random() < MEDIC.ROSC_SVT_CHANCE then
        startSVT(state)
    end
end

-- Too little blood for the heart to restart (give fluids)
function canRestartHeart(state)
    return state.bloodVolume / MEDIC.BLOOD_VOLUME > MEDIC.ARREST_BLOOD + 0.02
end

-- Chance of a returning pulse: base + IV access + airway + adrenaline
local function roscChance(state, base)
    if not canRestartHeart(state) then return 0 end
    local chance = base
    if state.ivAccess then chance = chance + MEDIC.ROSC_IV_BONUS end
    if isVentilated(state) then chance = chance + MEDIC.ROSC_AIRWAY_BONUS end
    return chance + getDrugMax(state, "roscBonus")
end

-- Good compressions keep the brain perfused: the death timer is pushed back
function extendDeathTimer(state, seconds)
    if not isInClinicalDeath(state) then return end
    local now = getTickCount()
    state.deathTick = math.min(now + MEDIC.DEATH_TIME * 1000, state.deathTick + seconds * 1000)
end

-- Outcome of a change during CPR: "ROSC" or the new rhythm (may equal the current one = no change)
local function rollCPRChange(state, percent)
    local shockable = MEDIC_RHYTHMS[state.rhythm].shockable
    local chance = roscChance(state, MEDIC.ROSC_BASE + math.max(0, percent - 70) * MEDIC.ROSC_PER_PERCENT)
    if shockable then chance = chance * MEDIC.CPR_SHOCKABLE_ROSC end
    if math.random() < chance then return "ROSC" end
    if shockable then
        if math.random() < 0.5 then return state.rhythm == "VF" and "PULSELESS_VT" or "VF" end
        return state.rhythm
    end
    if math.random() < MEDIC.CPR_TO_SHOCKABLE then return "VF" end
    return state.rhythm == "PEA" and "ASYSTOLE" or "PEA"
end

local function isResourceRunning(name)
    local resource = getResourceFromName(name)
    return resource and getResourceState(resource) == "running"
end

-- A medic does CPR on the patient: after CPR_CHANGE_MIN seconds of good compressions so far the
-- rhythm can change, and the change stops the minigame
local function checkCPRChange(state, medic, dt)
    if not isResourceRunning("mg_cpr") then return end
    local elapsed, _, _, percent, passing = exports.mg_cpr:getCPRGameProgress(medic)
    if not elapsed or elapsed < MEDIC.CPR_CHANGE_MIN or not passing then return end
    if math.random() >= dt / MEDIC.CPR_CHANGE_TIME then return end

    local outcome = rollCPRChange(state, percent)
    if outcome == state.rhythm then return end
    extendDeathTimer(state, MEDIC.CPR_TIME_BONUS * math.min(1, elapsed / MEDIC.CPR_DURATION))

    local message
    if outcome == "ROSC" then
        returnOfCirculation(state)
        writeVitalsData(state)
        message = L.msg("medsys.rhythm.pulse_restored_rosc_stop_cpr")
    else
        setRhythm(state, outcome)
        message = rhythmChangeMessage(state)
    end
    interruptProcedure(medic, message)
end

-- Every step in clinical death: CPR changes, or the untreated rhythm worsens
function updateArrestRhythm(state, dt, now)
    local medic = getProcedureMedic(state.element, "cpr")
    if medic then
        state.rhythmTick = state.rhythmTick + dt * 1000 -- CPR holds the rhythm
        checkCPRChange(state, medic, dt)
        return
    end
    local age = (now - state.rhythmTick) / 1000
    if state.rhythm == "PULSELESS_VT" and age >= MEDIC.PVT_DEGRADE_TIME then
        setRhythm(state, "VF", now)
    elseif state.rhythm == "VF" and age >= MEDIC.VF_DEGRADE_TIME then
        setRhythm(state, "ASYSTOLE", now)
    elseif state.rhythm == "PEA" and age >= MEDIC.PEA_DEGRADE_TIME then
        setRhythm(state, "ASYSTOLE", now)
    end
end

---------------------------------------------------------------------------
-- Monitor / defibrillator
---------------------------------------------------------------------------

function attachMonitor(state)
    state.monitor = state.monitor or { energy = MEDIC.DEFIB_ENERGY, sync = false, sound = true, shocks = 0 }
end

local function setMonitorMessage(monitor, text, now)
    monitor.message, monitor.messageTick = text, now or getTickCount()
end

local function isCharged(monitor, now)
    return monitor.chargeTick ~= nil and now - monitor.chargeTick >= MEDIC.DEFIB_CHARGE_TIME * 1000
end

-- Time based parts of the monitor: the analysis result (and its auto charge), the dumped charge
function updateMonitor(state, now)
    local monitor = state.monitor
    if not monitor then return end

    if monitor.analyzeTick and now - monitor.analyzeTick >= MEDIC.DEFIB_ANALYZE_TIME * 1000 then
        monitor.analyzeTick = nil
        local shock = MEDIC_RHYTHMS[state.rhythm].shockable == true
        monitor.advice, monitor.adviceTick = shock and "shock" or "noshock", now
        if shock then
            monitor.sync = false
            monitor.chargeTick = now -- AED mode: charges on its own
            notifyExaminers(state.element, L.msg("medsys.rhythm.shock_advised_charging_stand_clear"), true)
        else
            notifyExaminers(state.element, L.msg("medsys.rhythm.no_shock_advised_continue_cpr_if"))
        end
    end

    if monitor.chargeTick and now - monitor.chargeTick >= (MEDIC.DEFIB_CHARGE_TIME + MEDIC.DEFIB_DISARM_TIME) * 1000 then
        monitor.chargeTick = nil
        setMonitorMessage(monitor, "CHARGE REMOVED", now)
    end
end

-- Copy for the panel snapshot, times as milliseconds left / age
function getMonitorSnapshot(state, now)
    local monitor = state.monitor
    if not monitor then return nil end
    local snapshot = { energy = monitor.energy, sync = monitor.sync, sound = monitor.sound, shocks = monitor.shocks }
    if monitor.chargeTick then
        local left = MEDIC.DEFIB_CHARGE_TIME * 1000 - (now - monitor.chargeTick)
        if left > 0 then snapshot.chargeLeft = left else snapshot.charged = true end
    end
    if monitor.analyzeTick then
        snapshot.analyzeLeft = math.max(0, MEDIC.DEFIB_ANALYZE_TIME * 1000 - (now - monitor.analyzeTick))
    end
    if monitor.advice then
        snapshot.advice, snapshot.adviceAge = monitor.advice, now - monitor.adviceTick
    end
    if monitor.message then
        snapshot.message, snapshot.messageAge = monitor.message, now - monitor.messageTick
    end
    return snapshot
end

-- Delivers the charge. Returns the panel line and whether it is bad news.
local function deliverShock(state, medic)
    local monitor = state.monitor
    local energy = monitor.energy
    local target = state.element
    monitor.chargeTick, monitor.advice = nil, nil
    monitor.shocks = monitor.shocks + 1
    setMonitorMessage(monitor, ("ENERGY DELIVERED %dJ"):format(energy))

    -- stand clear: whoever does the compressions lets go
    local cprMedic = getProcedureMedic(target, "cpr")
    if cprMedic then interruptProcedure(cprMedic, L.msg("medsys.rhythm.stand_clear_shock_delivered")) end

    local before = state.rhythm
    local def = MEDIC_RHYTHMS[before]
    local message, bad

    if isInClinicalDeath(state) then
        if not def.shockable then
            message, bad = L.msg("medsys.rhythm.no_effect_not_shockable_rhythm_continue"), true
        elseif math.random() < MEDIC.SHOCK_SUCCESS then
            if math.random() < roscChance(state, MEDIC.SHOCK_ROSC) then
                returnOfCirculation(state)
                message = L.msg("medsys.rhythm.shock_delivered_pulse_restored_rosc")
            else
                setRhythm(state, math.random() < MEDIC.SHOCK_ROSC_PEA and "PEA" or "ASYSTOLE")
                message = L.msg("medsys.rhythm.shock_delivered_continue_cpr_check_rhythm")
            end
        else
            if before == "PULSELESS_VT" and math.random() < 0.5 then setRhythm(state, "VF") end
            message = L.msg("medsys.rhythm.shock_delivered_continue_cpr_check_rhythm")
        end
    else
        -- a beating heart
        if not medicIsDown(state.consciousness) then
            state.extraPain = math.max(state.extraPain, MEDIC.SHOCK_PAIN)
        end
        local unsyncVF = not monitor.sync and math.random() < MEDIC.SHOCK_PULSE_VF
        if before == "VT_WITH_PULSE" or before == "SVT" then
            local base = monitor.sync and MEDIC.CARDIOVERSION_SYNC or MEDIC.CARDIOVERSION_UNSYNC
            if math.random() < base then
                state.vtTick, state.svtTick, state.svtRate = nil, nil, nil
                state.heartRate = math.min(state.heartRate, 110)
                refreshPulseRhythm(state)
                message = L.msg("medsys.rhythm.cardioversion_successful")
            elseif unsyncVF then
                cardiacArrest(state, "shock")
                message, bad = L.msg("medsys.rhythm.unsynchronised_shock_heart_went_into_vf"), true
            else
                message = before == "SVT" and L.msg("medsys.rhythm.shock_delivered_still_svt")
                    or L.msg("medsys.rhythm.shock_delivered_still_ventricular_tachycardia")
                bad = true
            end
        else
            -- a shock on a normally beating (sinus) heart stops it, synchronised or not
            cardiacArrest(state, "shock")
            message, bad = L.msg("medsys.rhythm.shock_on_beating_heart_cardiac_arrest"), true
        end
    end

    writeVitalsData(state)
    triggerEvent("onMedicalDefibrillation", target, medic, energy, before, state.rhythm)
    return message, bad
end

-- Buttons of the monitor window: op(state, monitor, medic, value, now) -> panel line, isError
local DEFIB_OPS = {}

DEFIB_OPS.sync = function(_, monitor, _, _, now)
    monitor.sync = not monitor.sync
    setMonitorMessage(monitor, monitor.sync and "SYNC MODE" or "SYNC OFF", now)
end

DEFIB_OPS.sound = function(_, monitor)
    monitor.sound = not monitor.sound
end

DEFIB_OPS.charge = function(_, monitor, _, _, now)
    if monitor.analyzeTick then return L.msg("medsys.rhythm.analysing_wait"), true end
    if monitor.chargeTick then return nil end
    monitor.chargeTick = now
    monitor.message = nil
end

DEFIB_OPS.shock = function(state, monitor, medic, _, now)
    if not isCharged(monitor, now) then return L.msg("medsys.rhythm.charge_defibrillator_first"), true end
    return deliverShock(state, medic)
end

DEFIB_OPS.analyze = function(state, monitor, _, _, now)
    if monitor.analyzeTick then return nil end
    if state.consciousness ~= "clinical_death" and state.consciousness ~= "unconscious" then
        return L.msg("medsys.rhythm.analyse_only_unresponsive_patient"), true
    end
    monitor.analyzeTick = now
    monitor.chargeTick, monitor.advice, monitor.message = nil, nil, nil
end

-- op: "sync", "sound", "charge", "shock", "analyze"
addEventHandler("medic:defib", resourceRoot, function(target, op, value)
    local medic = client
    local handler = DEFIB_OPS[op]
    if not handler or not isExaminingPatient(medic, target) then return end
    local state = Patients[target]
    if not state or not state.monitor then return end

    local message, isError, everyone
    if state.dead then
        message, isError = L.msg("medsys.rhythm.patient_is_dead"), true
    elseif not canMedicAttend(medic, target, MEDIC.PANEL_RANGE) then
        message, isError = L.msg("medsys.rhythm.too_far_from_patient"), true
    else
        local allowed, why = checkMedicPermission(medic, "defib." .. op)
        if not allowed then
            message, isError = why, true
        else
            local charged = isCharged(state.monitor, getTickCount())
            message, isError = handler(state, state.monitor, medic, value, getTickCount())
            everyone = op == "shock" and charged -- everyone around sees what the shock did
        end
    end
    if message and everyone then
        notifyExaminers(target, message, isError)
    elseif message then
        triggerClientEvent(medic, "medic:panelMessage", resourceRoot, message, isError == true)
    end
    if Patients[target] == state then sendPanelUpdates(state) end
end)
