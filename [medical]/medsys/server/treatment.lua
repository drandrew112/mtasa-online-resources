-- Examination sessions (who has the panel open on whom) and treatments (minigames).
--
-- Examining[medic] = target                      -- open examination panels
-- Watchers[target] = { [medic] = true }          -- reverse index for the per-tick panel updates
-- Treatments[medic] = { target, action, option, sessionId, timer, aborted }
-- Locks[target] = { [action] = medic }           -- one medic per procedure per patient

addEvent("onMedicalStateChange", false)
addEvent("onMedicalCardiacArrest", false)
addEvent("onMedicalRevived", false)
addEvent("onMedicalDeath", false)
addEvent("onMedicalTreatment", false)

addEvent("medic:requestExamine", true)
addEvent("medic:closeExamine", true)
addEvent("medic:requestTreatment", true)
addEvent("medic:requestTransport", true)
addEvent("medic:measureGlucose", true)

local Examining = {}
local Watchers = {}
local Treatments = {}
local Locks = {}

local RANGE_TOLERANCE = 1.0 -- server side distance slack (position sync lag)
local LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function getDisplayName(element)
    if getElementType(element) == "player" then
        return (getPlayerName(element):gsub("#%x%x%x%x%x%x", ""))
    end
    local name = getElementData(element, MEDIC.DATA_NAME)
    return type(name) == "string" and name ~= "" and name or "Unknown patient"
end

-- The registered patient, registering it if it is alive (dead bodies are not simulated)
local function getLivePatient(target)
    local state = Patients[target]
    if state or isPedDead(target) then return state end
    return getPatient(target, true)
end

local function isNear(medic, target, range)
    if getElementDimension(medic) ~= getElementDimension(target)
        or getElementInterior(medic) ~= getElementInterior(target) then
        return false
    end
    local x1, y1, z1 = getElementPosition(medic)
    local x2, y2, z2 = getElementPosition(target)
    return getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2) <= range + RANGE_TOLERANCE
end

-- Medic role. The server table is the authority; the element data copy (MEDIC.DATA_ROLE) only
-- lets clients (e.g. the EMS tablet) know it, and client-side changes to it are reverted.
local Medics = {}

addEvent("onPlayerMedicChange") -- source: player, arg: enabled

-- Is the medic role checked at all (MEDIC.REQUIRE_MEDIC_ROLE). Fixed while the resource runs,
-- so other resources query it once.
function isMedicRoleRequired()
    return MEDIC.REQUIRE_MEDIC_ROLE == true
end

-- Does the player hold the medic role (the bare flag, whether or not the role is required)
function isPlayerMedic(player)
    return Medics[player] == true
end

-- May the player work as a medic: always when the role is not required, otherwise with the role
function hasMedicAccess(player)
    return not MEDIC.REQUIRE_MEDIC_ROLE or Medics[player] == true
end

local function syncMedicData(player)
    if Medics[player] then
        setElementData(player, MEDIC.DATA_ROLE, true)
    else
        removeElementData(player, MEDIC.DATA_ROLE)
    end
end

-- Gives (true) or takes (false) the medic role
function setPlayerMedic(player, enabled)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    enabled = enabled and true or false
    if (Medics[player] == true) == enabled then return true end
    Medics[player] = enabled or nil
    syncMedicData(player)
    if not enabled and MEDIC.REQUIRE_MEDIC_ROLE and Examining[player] then closeExamination(player) end
    updateInteractVisibility()
    triggerEvent("onPlayerMedicChange", player, enabled)
    return true
end

function getMedicPlayers()
    local list = {}
    for player in pairs(Medics) do list[#list + 1] = player end
    return list
end

addEventHandler("onElementDataChange", root, function(key)
    if key == MEDIC.DATA_ROLE and client then syncMedicData(source) end
end)

-- Can this player work on the patient at all (not a check of a specific procedure)
local function canAttend(medic, target, range)
    if not isElement(medic) or getElementType(medic) ~= "player" then return false end
    if not isValidPatient(target) or target == medic then return false end
    if isPedDead(medic) or isPedInVehicle(medic) or isPedInVehicle(target) then return false end
    local own = Patients[medic]
    if own and medicIsDown(own.consciousness) then return false end
    if not hasMedicAccess(medic) then return false end
    return isNear(medic, target, range)
end

-- Global wrapper for the other server files (rhythm.lua: the defibrillator buttons)
function canMedicAttend(medic, target, range)
    return canAttend(medic, target, range)
end

-- True while anyone has the panel open on / is treating this element (it must not be discharged)
function isPatientAttended(element)
    return Watchers[element] ~= nil or Locks[element] ~= nil
end

-- The medic receives the patient's vitals element data while examining or treating it
local function refreshSubscription(medic, target)
    if not isElement(medic) or not isElement(target) then return end
    local treatment = Treatments[medic]
    local wanted = Examining[medic] == target or (treatment and treatment.target == target)
    local fn = wanted and addElementDataSubscriber or removeElementDataSubscriber
    fn(target, MEDIC.DATA_SPO2, medic)
    fn(target, MEDIC.DATA_HEART_RATE, medic)
end

---------------------------------------------------------------------------
-- Procedures
---------------------------------------------------------------------------

-- The wound a bandage goes on: the worst bleeder first, then the worst untreated injury
local function findBandageTarget(state)
    local best, bestScore
    for _, injury in ipairs(state.injuries) do
        if not injury.treated and MEDIC_INJURIES[injury.type].treat == "bandage" then
            local score = injury.bleeding * 10 + injury.severity
            if not bestScore or score > bestScore then best, bestScore = injury, score end
        end
    end
    return best
end

-- The fracture a splint goes on: the worst untreated one
local function findSplintTarget(state)
    local best
    for _, injury in ipairs(state.injuries) do
        if not injury.treated and MEDIC_INJURIES[injury.type].treat == "splint" then
            if not best or injury.severity > best.severity then best = injury end
        end
    end
    return best
end

local function worstSeverity(state, injuryType)
    local worst = 0
    for _, injury in ipairs(state.injuries) do
        if injury.type == injuryType and not injury.treated and injury.severity > worst then
            worst = injury.severity
        end
    end
    return worst
end

local function isResourceRunning(name)
    local resource = getResourceFromName(name)
    return resource and getResourceState(resource) == "running"
end

-- resource     minigame resource that has to be running (none for a timed procedure)
-- can(state)   -> true | false, reason
-- validate(state, option) optional, checks the option sent by the panel (e.g. the medicine)
-- start(medic, target, state) -> session id or false
-- duration     timed procedure without a minigame: it succeeds after this many seconds
-- progress(option, state) text of the progress bar of a timed procedure
-- stop(medic)  aborts the minigame (it fires its finish event)
-- cleanup(state) optional, runs when the procedure ends in any way
-- finishEvent  the minigame's result event, sessionArg = position of the session id in it
-- apply(state, success, ...) applies the result, returns the line shown on the panel
-- animated     the minigame has no animation of its own, the medic kneels by the patient
local PROCEDURES = {}

PROCEDURES.bandage = {
    resource = "mg_arrows",
    can = function(state)
        if findBandageTarget(state) or state.baseBleeding > 0 then return true end
        return false, "Nothing to bandage"
    end,
    start = function(medic, target, state)
        local injury = findBandageTarget(state)
        local severity = injury and injury.severity or state.baseBleeding
        return exports.mg_arrows:startArrowsGame(medic, 8 + severity * 4, { speed = 0.85 + severity * 0.15 })
    end,
    stop = function(medic) exports.mg_arrows:stopArrowsGame(medic) end,
    finishEvent = "onArrowsGameFinish",
    sessionArg = 6, -- success, hits, total, percent, reason, sessionId
    animated = true,
    apply = function(state, success)
        if not success then return "The bandage did not hold" end
        local injury = findBandageTarget(state)
        if injury then
            local def = MEDIC_INJURIES[injury.type]
            injury.treated = true
            -- a critical wound keeps oozing until surgery
            injury.bleeding = injury.bleeding >= 3 and 1 or 0
            return ("%s: %s"):format(def.label, def.treatedLabel:lower())
        end
        state.baseBleeding = math.max(0, state.baseBleeding - 2)
        return "Bleeding controlled"
    end,
}

PROCEDURES.splint = {
    resource = "mg_splinting",
    can = function(state)
        if findSplintTarget(state) then return true end
        return false, "No fracture to splint"
    end,
    start = function(medic, target, state)
        local injury = findSplintTarget(state)
        local severity = injury.severity
        return exports.mg_splinting:startSplintGame(medic, target, 6 + severity * 2, { speed = 0.85 + severity * 0.15 })
    end,
    stop = function(medic) exports.mg_splinting:stopSplintGame(medic) end,
    finishEvent = "onSplintGameFinish",
    sessionArg = 6, -- success, hits, total, percent, reason, sessionId
    apply = function(state, success)
        if not success then return "The splint did not hold" end
        local injury = findSplintTarget(state)
        if injury then
            local def = MEDIC_INJURIES[injury.type]
            injury.treated = true
            return ("%s: %s"):format(def.label, def.treatedLabel:lower())
        end
        return "Fracture splinted"
    end,
}

PROCEDURES.cpr = {
    resource = "mg_cpr",
    can = function(state)
        if isInClinicalDeath(state) then return true end
        return false, "The patient has a pulse"
    end,
    start = function(medic, target)
        return exports.mg_cpr:startCPRGame(medic, MEDIC.CPR_DURATION, target)
    end,
    -- reason "interrupted": a rhythm change / a shock stops it (interruptProcedure)
    stop = function(medic, reason) exports.mg_cpr:stopCPRGame(medic, reason) end,
    finishEvent = "onCPRGameFinish",
    sessionArg = 6, -- success, good, total, percent, reason, sessionId, avgBPM
    -- The heart restarts (or the rhythm changes) during the compressions, see checkCPRChange in
    -- rhythm.lua: a round that reaches its end saw no change.
    apply = function(state, success)
        if not isInClinicalDeath(state) then return nil end
        if not success then return "Ineffective compressions" end
        -- good compressions keep the brain perfused: the death timer is pushed back
        extendDeathTimer(state, MEDIC.CPR_TIME_BONUS)
        if not canRestartHeart(state) then return "No pulse - too much blood lost, give fluids" end
        if state.monitor and MEDIC_RHYTHMS[state.rhythm].shockable then
            return "Shockable rhythm - charge and shock!"
        end
        return "No pulse yet - continue CPR"
    end,
}

PROCEDURES.iv = {
    resource = "mg_intravenous",
    can = function(state)
        if not state.ivAccess then return true end
        return false, "IV access already in place"
    end,
    start = function(medic, target, state)
        local bloodFraction = state.bloodVolume / MEDIC.BLOOD_VOLUME
        -- collapsed veins in shock / arrest make it harder
        local difficulty = 1
        if isInClinicalDeath(state) or bloodFraction < 0.7 then
            difficulty = 3
        elseif bloodFraction < 0.85 then
            difficulty = 2
        end
        return exports.mg_intravenous:startIVGame(medic, target, { difficulty = difficulty })
    end,
    stop = function(medic) exports.mg_intravenous:stopIVGame(medic) end,
    finishEvent = "onIVGameFinish",
    sessionArg = 5, -- success, attempts, quality, reason, sessionId
    apply = function(state, success, _, quality)
        if not success then return "Cannulation failed" end
        state.ivAccess = true
        state.ivQuality = quality
        return ("IV access secured (quality %d%%) - fluids running"):format(quality)
    end,
}

PROCEDURES.airway = {
    resource = "mg_airway",
    -- Only with RSI (also in cardiac arrest): the anaesthetic (sedation) and the muscle relaxant
    -- (after its onset) both have to work. Given in the wrong order the patient panics while the
    -- breathing stops (simulation.lua).
    can = function(state)
        if state.intubated then return false, "Airway already secured" end
        if not isSedated(state) then
            if state.consciousness == "stable" or state.consciousness == "confused" or state.consciousness == "dazed" then
                return false, "Patient is conscious - give Ketamine first"
            end
            return false, "Give Ketamine first (induction)"
        end
        if not hasDrugEffect(state, "paralysis") then return false, "Give Rocuronium (muscle relaxant)" end
        if not isParalyzed(state) then return false, "Waiting for the muscle relaxant to work" end
        return true
    end,
    start = function(medic, target, state)
        local difficulty = "normal"
        if worstSeverity(state, "burn") >= 3 then
            difficulty = "nightmare"
        elseif worstSeverity(state, "suffocation") >= 3 then
            difficulty = "hard"
        end
        -- bag-valve mask first, then the SpO2 falls while the tube goes in (the minigame reads it)
        state.spo2 = math.max(state.spo2, MEDIC.PREOX_SPO2)
        state.apneaRate = MEDIC.APNEA_RATE[difficulty]
        writeVitalsData(state)
        return exports.mg_airway:startAirwayGame(medic, target, { difficulty = difficulty })
    end,
    cleanup = function(state)
        state.apneaRate = nil
    end,
    stop = function(medic) exports.mg_airway:stopAirwayGame(medic) end,
    finishEvent = "onAirwayGameFinish",
    sessionArg = 6, -- success, score, time, mistakes, reason, sessionId, details
    apply = function(state, success, _, _, _, reason)
        if not success then
            return reason == "desaturated" and "Intubation failed - patient desaturated" or "Intubation failed"
        end
        state.intubated = true
        state.noOxygen = nil
        state.oxygenMask = false
        for _, injury in ipairs(state.injuries) do
            if injury.type == "suffocation" then injury.treated = true end
        end
        return "Airway secured - patient ventilated"
    end,
}

-- Puts the oxygen mask on / takes it off (the button label follows it)
PROCEDURES.oxygen = {
    duration = MEDIC.OXYGEN_TIME,
    animated = true,
    can = function(state)
        if state.intubated then return false, "Ventilated through the tube" end
        return true
    end,
    progress = function(_, state)
        return state.oxygenMask and "Removing the oxygen mask..." or "Putting on the oxygen mask..."
    end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success)
        if not success then return "The oxygen mask was not changed" end
        if state.intubated then return "Ventilated through the tube" end
        state.oxygenMask = not state.oxygenMask
        return state.oxygenMask and "Oxygen mask on" or "Oxygen mask removed"
    end,
}

-- Monitor / defibrillator: ECG electrodes and pads, once per patient (it stays on)
PROCEDURES.monitor = {
    duration = MEDIC.MONITOR_TIME,
    animated = true,
    can = function(state)
        if state.monitor then return false, "Monitor attached" end
        return true
    end,
    progress = function() return "Attaching the monitor / defibrillator pads..." end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success)
        if not success then return "The monitor was not attached" end
        attachMonitor(state)
        return "Monitor attached: " .. MEDIC_RHYTHMS[state.rhythm].label
    end,
}

PROCEDURES.medication = {
    duration = MEDIC.DRUG_TIME,
    animated = true,
    -- the menu always opens (oral medicines), IV medicines are checked one by one
    can = function() return true end,
    validate = function(state, drugId)
        local drug = MEDIC_DRUGS[drugId]
        if not drug then return false, "Unknown medicine" end
        if medicDrugNeedsIV(drug) and not state.ivAccess then return false, "Needs IV access" end
        if drug.awake and state.consciousness ~= "stable" and state.consciousness ~= "confused" then
            return false, "The patient cannot swallow"
        end
        return true
    end,
    progress = function(drugId)
        return "Giving " .. MEDIC_DRUGS[drugId].name .. "..."
    end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success, drugId)
        local drug = MEDIC_DRUGS[drugId]
        if not success or not drug then return "The medicine was not given" end
        local now = getTickCount()
        state.drugs[#state.drugs + 1] = { id = drugId, tick = now, untilTick = now + drug.duration * 1000 }
        if drug.glucose then
            state.glucose = math.min(MEDIC.GLUCOSE_MAX, state.glucose + drug.glucose)
        end
        for _, condition in ipairs(drug.treats or {}) do
            for _, injury in ipairs(state.injuries) do
                if injury.type == condition then injury.treated = true end
            end
        end
        return drug.name .. " given"
    end,
}

-- Neuro exam (D of ABCDE): responsiveness, pupils, FAST. Its findings stay on the panel.
PROCEDURES.neuro = {
    duration = MEDIC.NEURO_TIME,
    animated = true,
    can = function(state)
        if state.neuroChecked then return false, "Neuro exam done - findings below" end
        return true
    end,
    progress = function() return "Checking responsiveness, pupils, face, arms and speech..." end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success)
        if not success then return "The neuro exam was interrupted" end
        state.neuroChecked = true
        return "Neuro exam done"
    end,
}

-- The actions the panel can offer right now: { [action] = true | reason }
-- equipment: getPatientEquipment(target) (server/equipment.lua), nil = not checked
local function getAvailability(state, target, equipment)
    local result = {}
    local dead = not state or state.dead
    for action, procedure in pairs(PROCEDURES) do
        if dead then
            result[action] = "Patient is dead"
        else
            local ok, reason = procedure.can(state)
            result[action] = ok or reason
        end
    end
    local ok, reason = canRequestTransport(target, state)
    result.transport = ok or reason
    result.glucometer = dead and "Patient is dead" or true -- a device, measured from its own window
    if not dead then applyEquipmentAvailability(result, equipment, state) end
    return result
end

-- Snapshot for the examination panel: the medical data + which buttons are usable
local function getPanelSnapshot(target)
    local state = getLivePatient(target)
    local snapshot = state and buildSnapshot(state) or buildDefaultSnapshot(target)
    local equipment = getPatientEquipment(target)
    snapshot.actions = getAvailability(state, target, equipment)
    snapshot.equipment = getEquipmentSnapshot(equipment)
    -- the panel shows what the medic sees: the glucose only comes from the glucometer, the hidden
    -- conditions only through their findings
    snapshot.glucose, snapshot.conditions = nil, nil
    snapshot.transportPhase, snapshot.transportTimeLeft = getTransportStatus(target)
    return snapshot
end

---------------------------------------------------------------------------
-- Examination panel
---------------------------------------------------------------------------

function closeExamination(medic, notifyClient)
    local target = Examining[medic]
    if not target then return false end
    Examining[medic] = nil

    local watchers = Watchers[target]
    if watchers then
        watchers[medic] = nil
        if not next(watchers) then Watchers[target] = nil end
    end
    refreshSubscription(medic, target)
    if notifyClient ~= false and isElement(medic) then
        triggerClientEvent(medic, "medic:panelClose", resourceRoot)
    end
    return true
end

-- message: optional result line shown on the panel (e.g. after a procedure), isError colours it red
function openExamination(medic, target, message, isError)
    if not canAttend(medic, target, MEDIC.PANEL_RANGE) then return false end
    if Treatments[medic] then return false end
    if Examining[medic] and Examining[medic] ~= target then
        closeExamination(medic, false)
    end

    local snapshot = getPanelSnapshot(target)
    Examining[medic] = target
    Watchers[target] = Watchers[target] or {}
    Watchers[target][medic] = true
    refreshSubscription(medic, target)

    triggerClientEvent(medic, "medic:panelOpen", resourceRoot, target, getDisplayName(target),
        snapshot, message, isError == true)
    return true
end

-- Called by the simulation after every step
function sendPanelUpdates(state)
    local target = state.element
    local watchers = Watchers[target]
    if not watchers then return end

    local list = {}
    for medic in pairs(watchers) do
        if isElement(medic) and isNear(medic, target, MEDIC.PANEL_RANGE) then
            list[#list + 1] = medic
        else
            closeExamination(medic)
        end
    end
    if #list > 0 then
        triggerClientEvent(list, "medic:panelUpdate", resourceRoot, target, getPanelSnapshot(target))
    end
end

-- Re-sends the panel to everyone examining the target (after a reset)
function refreshExaminations(target)
    local watchers = Watchers[target]
    if not watchers then return end
    for medic in pairs(watchers) do
        if not openExamination(medic, target) then closeExamination(medic) end
    end
end

addEventHandler("medic:requestExamine", resourceRoot, function(target)
    if not openExamination(client, target) then
        triggerClientEvent(client, "medic:panelClose", resourceRoot)
    end
end)

addEventHandler("medic:closeExamine", resourceRoot, function()
    closeExamination(client, false)
end)

-- spot = { x, y, z, rotation, canDrive } picked by the client next to the body, or nil
addEventHandler("medic:requestTransport", resourceRoot, function(target, spot)
    local medic = client
    if Examining[medic] ~= target then return end
    local ok, reason
    if not canAttend(medic, target, MEDIC.PANEL_RANGE) then
        ok, reason = false, "Too far from the patient"
    else
        ok, reason = requestTransport(medic, target, spot)
    end
    if ok then
        openExamination(medic, target, ("Transport requested - arrives in %d s"):format(MEDIC.TRANSPORT_DELAY))
    else
        triggerClientEvent(medic, "medic:panelMessage", resourceRoot, reason, true)
    end
end)

-- Glucometer: finger prick, the reading comes after MEDIC.GLUCOMETER_TIME seconds (not continuous).
-- The medic keeps the panel and can move; the reading is taken at the end. Result event:
-- medic:glucoseResult (target, value mg/dL | false, error text)
local Glucometers = {} -- [medic] = timer

addEventHandler("medic:measureGlucose", resourceRoot, function(target)
    local medic = client
    local function fail(reason)
        triggerClientEvent(medic, "medic:glucoseResult", resourceRoot, target, false, reason)
    end
    if Examining[medic] ~= target then return end
    if Glucometers[medic] then return fail("Measuring...") end
    if not canAttend(medic, target, MEDIC.INTERACT_RANGE) then return fail("Too far from the patient") end
    local state = getLivePatient(target)
    if not state or state.dead then return fail("No blood flow - no reading") end
    local hasBag, reason = checkGlucometerEquipment(medic, target)
    if not hasBag then return fail(reason) end

    Glucometers[medic] = setTimer(function()
        Glucometers[medic] = nil
        if not isElement(medic) or not isElement(target) then return end
        if not canAttend(medic, target, MEDIC.PANEL_RANGE) then return fail("Moved away - measure again") end
        local now = Patients[target]
        local value = now and not now.dead and math.floor(now.glucose + 0.5) or MEDIC.GLUCOSE
        triggerClientEvent(medic, "medic:glucoseResult", resourceRoot, target, value)
        triggerEvent("onMedicalTreatment", target, medic, "glucometer", true, value)
    end, MEDIC.GLUCOMETER_TIME * 1000, 1)
end)

addEventHandler("onPlayerQuit", root, function()
    local timer = Glucometers[source]
    if timer and isTimer(timer) then killTimer(timer) end
    Glucometers[source] = nil
end)

---------------------------------------------------------------------------
-- Treatment lifecycle
---------------------------------------------------------------------------

local function lockMedic(medic, target, locked)
    for _, control in ipairs(LOCK_CONTROLS) do
        toggleControl(medic, control, not locked)
    end
    if locked then
        local mx, my = getElementPosition(medic)
        local tx, ty = getElementPosition(target)
        setElementRotation(medic, 0, 0, -math.deg(math.atan2(tx - mx, ty - my)))
        setPedAnimation(medic, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
    else
        setPedAnimation(medic)
    end
end

-- Clears the bookkeeping of a treatment and returns it
local function releaseTreatment(medic)
    local treatment = Treatments[medic]
    if not treatment then return nil end
    Treatments[medic] = nil

    if treatment.timer then
        if isTimer(treatment.timer) then killTimer(treatment.timer) end
        treatment.timer = nil
    end
    local target, action = treatment.target, treatment.action
    local locks = Locks[target]
    if locks and locks[action] == medic then
        locks[action] = nil
        if not next(locks) then Locks[target] = nil end
    end
    local procedure = PROCEDURES[action]
    local state = procedure.cleanup and Patients[target]
    if state then procedure.cleanup(state) end
    if isElement(medic) then
        if procedure.animated then lockMedic(medic, target, false) end
        refreshSubscription(medic, target)
        triggerClientEvent(medic, "medic:busy", resourceRoot, false)
    end
    return treatment
end

local function finishTreatment(medic, success, ...)
    local treatment = releaseTreatment(medic)
    if not treatment or treatment.aborted then return end

    local target = treatment.target
    local state = isElement(target) and Patients[target]
    if not state or state.dead then return end

    local message, isError
    if treatment.interrupt then
        -- stopped by the patient's change (interruptProcedure): it counts as done, nothing to apply
        success, message, isError = true, treatment.interrupt, treatment.interruptError
    else
        message = PROCEDURES[treatment.action].apply(state, success, ...)
        isError = not success
        if success == true then onEquipmentTreatmentDone(medic, target, treatment.action, treatment.option, state) end
    end
    triggerEvent("onMedicalTreatment", target, medic, treatment.action, success == true, treatment.option)
    if isElement(medic) then
        openExamination(medic, target, message, isError)
    end
end

-- The medic running this procedure on the target, or nil
function getProcedureMedic(target, action)
    local locks = Locks[target]
    local medic = locks and locks[action]
    local treatment = medic and Treatments[medic]
    if treatment and treatment.target == target and treatment.action == action then return medic end
    return nil
end

-- Stops a running procedure because the patient changed (e.g. the rhythm during CPR). The
-- medic gets the panel back with the message; no result is applied.
function interruptProcedure(medic, message, isError)
    local treatment = Treatments[medic]
    if not treatment then return false end
    treatment.interrupt, treatment.interruptError = message, isError == true
    PROCEDURES[treatment.action].stop(medic, "interrupted") -- fires the finish event
    if Treatments[medic] == treatment then finishTreatment(medic, false) end -- it did not
    return true
end

-- Shows a line on the panel of everyone examining the target
function notifyExaminers(target, message, isError)
    local watchers = Watchers[target]
    if not watchers then return end
    local list = {}
    for medic in pairs(watchers) do
        if isElement(medic) then list[#list + 1] = medic end
    end
    if #list > 0 then triggerClientEvent(list, "medic:panelMessage", resourceRoot, message, isError == true) end
end

function isExaminingPatient(medic, target)
    return Examining[medic] == target
end

for action, procedure in pairs(PROCEDURES) do
    if procedure.finishEvent then
        addEventHandler(procedure.finishEvent, root, function(success, ...)
            local treatment = Treatments[source]
            if not treatment or treatment.action ~= action then return end
            local sessionId = select(procedure.sessionArg - 1, ...)
            if sessionId ~= treatment.sessionId then return end
            finishTreatment(source, success, ...)
        end)
    end
end

-- Starts a procedure. option: e.g. the medicine id. Returns true, or false + reason.
function startTreatment(medic, target, action, option)
    local procedure = PROCEDURES[action]
    if not procedure then return false, "Unknown procedure" end
    if Treatments[medic] then return false, "You are busy" end
    if not canAttend(medic, target, MEDIC.INTERACT_RANGE) then return false, "Too far from the patient" end
    if procedure.resource and not isResourceRunning(procedure.resource) then return false, "Equipment unavailable" end

    local state = getLivePatient(target)
    if not state or state.dead then return false, "Patient is dead" end
    local ok, reason = procedure.can(state)
    if not ok then return false, reason end
    if procedure.validate then
        ok, reason = procedure.validate(state, option)
        if not ok then return false, reason end
    end
    ok, reason = onEquipmentTreatmentCheck(medic, target, action, option, state)
    if not ok then return false, reason end

    local locks = Locks[target]
    if locks and isElement(locks[action]) then
        return false, "Someone else is already doing this"
    end

    closeExamination(medic)
    Locks[target] = locks or {}
    Locks[target][action] = medic
    Treatments[medic] = { target = target, action = action, option = option }
    refreshSubscription(medic, target)
    triggerClientEvent(medic, "medic:busy", resourceRoot, true)
    if procedure.animated then lockMedic(medic, target, true) end

    if procedure.duration then
        local treatment = Treatments[medic]
        treatment.timer = setTimer(function()
            treatment.timer = nil
            finishTreatment(medic, true, option)
        end, procedure.duration * 1000, 1)
        triggerClientEvent(medic, "medic:progress", resourceRoot, procedure.progress(option, state), procedure.duration * 1000)
        onEquipmentTreatmentStart(medic, target, action)
        return true
    end

    local sessionId = procedure.start(medic, target, state)
    if not sessionId then
        releaseTreatment(medic)
        openExamination(medic, target, "Could not start the procedure", true)
        return true
    end
    Treatments[medic].sessionId = sessionId
    onEquipmentTreatmentStart(medic, target, action)
    return true
end

-- Aborts every procedure running on a patient (death, despawn, reset). No result is applied.
-- reopen = true: the medics get the examination panel back (the patient is still there)
function stopTreatmentsOn(target, reopen)
    local locks = Locks[target]
    if not locks then return end
    for action, medic in pairs(locks) do
        local treatment = Treatments[medic]
        if treatment and treatment.target == target then
            treatment.aborted = true
            if isElement(medic) then PROCEDURES[action].stop(medic) end -- fires the finish event
            releaseTreatment(medic)
            if reopen and isElement(medic) and isElement(target) then openExamination(medic, target) end
        end
    end
    Locks[target] = nil
end

addEventHandler("medic:requestTreatment", resourceRoot, function(target, action, option)
    local medic = client
    if Examining[medic] ~= target then return end
    local ok, reason = startTreatment(medic, target, action, option)
    if not ok then
        triggerClientEvent(medic, "medic:panelMessage", resourceRoot, reason, true)
    end
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

-- The patient disappears: close every panel on it (treatments are stopped by state.lua)
local function onTargetLeave()
    local watchers = Watchers[source]
    if not watchers then return end
    for medic in pairs(watchers) do closeExamination(medic) end
end
addEventHandler("onElementDestroy", root, onTargetLeave)

addEventHandler("onPlayerQuit", root, function()
    Medics[source] = nil
    onTargetLeave()
    if Examining[source] then closeExamination(source, false) end
    local treatment = Treatments[source]
    if treatment then
        treatment.aborted = true
        releaseTreatment(source)
    end
end)

-- Medics must not stay frozen when the resource stops mid-procedure
addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Medics) do
        if isElement(player) then removeElementData(player, MEDIC.DATA_ROLE) end
    end
    for medic, treatment in pairs(Treatments) do
        if isElement(medic) and PROCEDURES[treatment.action].animated then
            lockMedic(medic, treatment.target, false)
        end
    end
end)

-- A dead medic stops working (not every minigame stops on its own)
addEventHandler("onPlayerWasted", root, function()
    if Examining[source] then closeExamination(source) end
    local treatment = Treatments[source]
    if treatment then
        treatment.aborted = true
        PROCEDURES[treatment.action].stop(source)
        releaseTreatment(source)
    end
end)
