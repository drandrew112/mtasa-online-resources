-- Heart rhythm (ECG) and the monitor / defibrillator (Lifepak 15).
--
-- With a pulse the rhythm is named from the heart rate (sinus / bradycardia / tachycardia, VT at
-- MEDIC.VT_HEART_RATE and above), except a lasting VT with pulse (state.vtTick) that only a shock
-- ends and that turns pulseless after MEDIC.VT_DEGRADE_TIME.
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

-- Names the rhythm of a beating heart from its rate (half a beat of hysteresis around the limits)
function refreshPulseRhythm(state, now)
    local hr, current = state.heartRate, state.rhythm
    local rhythm = "SINUS"
    if state.vtTick or hr >= MEDIC.VT_HEART_RATE then
        rhythm = "VT_WITH_PULSE"
    elseif hr < MEDIC.BRADY_RATE + (current == "SINUS_BRADY" and 0.5 or -0.5) then
        rhythm = "SINUS_BRADY"
    elseif hr > MEDIC.TACHY_RATE + (current == "SINUS_TACHY" and -0.5 or 0.5) then
        rhythm = "SINUS_TACHY"
    end
    setRhythm(state, rhythm, now)
end

-- Every step of a patient with a pulse. True when the lasting VT turned pulseless (arrest).
function updatePulseRhythm(state, now)
    if state.vtTick and now - state.vtTick >= MEDIC.VT_DEGRADE_TIME * 1000 then return true end
    refreshPulseRhythm(state, now)
    return false
end

-- Lasting VT with pulse
function startVT(state)
    state.vtTick = getTickCount()
    setRhythm(state, "VT_WITH_PULSE")
end

-- Return of circulation from CPR or a shock: not always a sinus rhythm
local function returnOfCirculation(state)
    restoreCirculation(state)
    if math.random() < MEDIC.ROSC_VT_CHANCE then startVT(state) end
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

-- Panel line after a rhythm change (without a monitor the medic only knows that something changed)
local function rhythmChangeMessage(state)
    if not state.monitor then return "The patient's condition changed - attach the monitor" end
    local def = MEDIC_RHYTHMS[state.rhythm]
    if def.shockable then return "Rhythm change: " .. def.label .. " - shock!" end
    return "Rhythm change: " .. def.label
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
        message = "Pulse restored (ROSC) - stop CPR"
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
            notifyExaminers(state.element, "Shock advised - charging, stand clear!", true)
        else
            notifyExaminers(state.element, "No shock advised - continue CPR if there is no pulse")
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
    if cprMedic then interruptProcedure(cprMedic, "Stand clear - shock delivered") end

    local before = state.rhythm
    local def = MEDIC_RHYTHMS[before]
    local message, bad

    if isInClinicalDeath(state) then
        if not def.shockable then
            message, bad = "No effect - not a shockable rhythm, continue CPR", true
        elseif math.random() < MEDIC.SHOCK_SUCCESS then
            if math.random() < roscChance(state, MEDIC.SHOCK_ROSC) then
                returnOfCirculation(state)
                message = "Shock delivered - pulse restored (ROSC)"
            else
                setRhythm(state, math.random() < MEDIC.SHOCK_ROSC_PEA and "PEA" or "ASYSTOLE")
                message = "Shock delivered - continue CPR, check the rhythm"
            end
        else
            if before == "PULSELESS_VT" and math.random() < 0.5 then setRhythm(state, "VF") end
            message = "Shock delivered - continue CPR, check the rhythm"
        end
    else
        -- a beating heart
        if not medicIsDown(state.consciousness) then
            state.extraPain = math.max(state.extraPain, MEDIC.SHOCK_PAIN)
        end
        local unsyncVF = not monitor.sync and math.random() < MEDIC.SHOCK_PULSE_VF
        if before == "VT_WITH_PULSE" then
            local base = monitor.sync and MEDIC.CARDIOVERSION_SYNC or MEDIC.CARDIOVERSION_UNSYNC
            if math.random() < base then
                state.vtTick = nil
                state.heartRate = math.min(state.heartRate, 110)
                refreshPulseRhythm(state)
                message = "Cardioversion successful"
            elseif unsyncVF then
                cardiacArrest(state, "shock")
                message, bad = "Unsynchronised shock - the heart went into VF!", true
            else
                message, bad = "Shock delivered - still ventricular tachycardia", true
            end
        else
            -- a shock on a normally beating (sinus) heart stops it, synchronised or not
            cardiacArrest(state, "shock")
            message, bad = "Shock on a beating heart - cardiac arrest!", true
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
    if monitor.analyzeTick then return "Analysing - wait", true end
    if monitor.chargeTick then return nil end
    monitor.chargeTick = now
    monitor.message = nil
end

DEFIB_OPS.shock = function(state, monitor, medic, _, now)
    if not isCharged(monitor, now) then return "Charge the defibrillator first", true end
    return deliverShock(state, medic)
end

DEFIB_OPS.analyze = function(state, monitor, _, _, now)
    if monitor.analyzeTick then return nil end
    if state.consciousness ~= "clinical_death" and state.consciousness ~= "unconscious" then
        return "Analyse only an unresponsive patient", true
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
        message, isError = "Patient is dead", true
    elseif not canMedicAttend(medic, target, MEDIC.PANEL_RANGE) then
        message, isError = "Too far from the patient", true
    else
        local charged = isCharged(state.monitor, getTickCount())
        message, isError = handler(state, state.monitor, medic, value, getTickCount())
        everyone = op == "shock" and charged -- everyone around sees what the shock did
    end
    if message and everyone then
        notifyExaminers(target, message, isError)
    elseif message then
        triggerClientEvent(medic, "medic:panelMessage", resourceRoot, message, isError == true)
    end
    if Patients[target] == state then sendPanelUpdates(state) end
end)
