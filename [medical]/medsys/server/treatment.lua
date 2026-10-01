-- Examination sessions (who has the panel open on whom) and treatments (minigames).
--
-- Examining[medic] = target                      -- open examination panels
-- Watchers[target] = { [medic] = true }          -- reverse index for the per-tick panel updates
-- Treatments[medic] = { target, action, sessionId, aborted }
-- Locks[target] = { [action] = medic }           -- one medic per procedure per patient

addEvent("onMedicalStateChange", false)
addEvent("onMedicalCardiacArrest", false)
addEvent("onMedicalRevived", false)
addEvent("onMedicalDeath", false)
addEvent("onMedicalTreatment", false)

addEvent("medic:requestExamine", true)
addEvent("medic:closeExamine", true)
addEvent("medic:requestTreatment", true)

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
    return "Unknown patient"
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

-- Medic role, kept on the server only (element data could be set by the client itself)
local Medics = {}

function isPlayerMedic(player)
    if not MEDIC.REQUIRE_MEDIC_ROLE then return true end
    return Medics[player] == true
end

function setPlayerMedic(player, enabled)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    Medics[player] = enabled and true or nil
    if not enabled and MEDIC.REQUIRE_MEDIC_ROLE and Examining[player] then closeExamination(player) end
    updateInteractVisibility()
    return true
end

function getMedicPlayers()
    local list = {}
    for player in pairs(Medics) do list[#list + 1] = player end
    return list
end

-- Can this player work on the patient at all (not a check of a specific procedure)
local function canAttend(medic, target, range)
    if not isElement(medic) or getElementType(medic) ~= "player" then return false end
    if not isValidPatient(target) or target == medic then return false end
    if isPedDead(medic) or isPedInVehicle(medic) or isPedInVehicle(target) then return false end
    local own = Patients[medic]
    if own and medicIsDown(own.consciousness) then return false end
    if not isPlayerMedic(medic) then return false end
    return isNear(medic, target, range)
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

-- resource     minigame resource that has to be running
-- can(state)   -> true | false, reason
-- start(medic, target, state) -> session id or false
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

PROCEDURES.cpr = {
    resource = "mg_cpr",
    can = function(state)
        if isInClinicalDeath(state) then return true end
        return false, "The patient has a pulse"
    end,
    start = function(medic, target)
        return exports.mg_cpr:startCPRGame(medic, MEDIC.CPR_DURATION, target)
    end,
    stop = function(medic) exports.mg_cpr:stopCPRGame(medic) end,
    finishEvent = "onCPRGameFinish",
    sessionArg = 6, -- success, good, total, percent, reason, sessionId, avgBPM
    apply = function(state, success, _, _, percent)
        if not isInClinicalDeath(state) then return nil end
        if not success then return "Ineffective compressions" end

        local bloodFraction = state.bloodVolume / MEDIC.BLOOD_VOLUME
        local chance = 0
        if bloodFraction > MEDIC.ARREST_BLOOD + 0.02 then
            chance = MEDIC.ROSC_BASE + math.max(0, percent - 70) * MEDIC.ROSC_PER_PERCENT
            if state.ivAccess then chance = chance + MEDIC.ROSC_IV_BONUS end
            if state.intubated then chance = chance + MEDIC.ROSC_AIRWAY_BONUS end
        end

        if math.random() < chance then
            restoreCirculation(state)
            return "Pulse restored (ROSC)"
        end
        -- good compressions keep the brain perfused: the death timer is pushed back
        local now = getTickCount()
        state.deathTick = math.min(now + MEDIC.DEATH_TIME * 1000, state.deathTick + MEDIC.CPR_TIME_BONUS * 1000)
        notifyPatient(state)
        if chance == 0 then return "No pulse - too much blood lost, give fluids" end
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
    can = function(state)
        if state.intubated then return false, "Airway already secured" end
        if state.consciousness ~= "unconscious" and state.consciousness ~= "clinical_death" then
            return false, "Patient is conscious"
        end
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
        for _, injury in ipairs(state.injuries) do
            if injury.type == "suffocation" then injury.treated = true end
        end
        return "Airway secured - patient ventilated"
    end,
}

-- The actions the panel can offer right now: { [action] = true | reason }
local function getAvailability(state)
    local result = {}
    for action, procedure in pairs(PROCEDURES) do
        if not state or state.dead then
            result[action] = "Patient is dead"
        else
            local ok, reason = procedure.can(state)
            result[action] = ok or reason
        end
    end
    return result
end

-- Snapshot for the examination panel: the medical data + which buttons are usable
local function getPanelSnapshot(target)
    local state = getLivePatient(target)
    local snapshot = state and buildSnapshot(state) or buildDefaultSnapshot(target)
    snapshot.actions = getAvailability(state)
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

    local message = PROCEDURES[treatment.action].apply(state, success, ...)
    triggerEvent("onMedicalTreatment", target, medic, treatment.action, success == true)
    if isElement(medic) then
        openExamination(medic, target, message, not success)
    end
end

for action, procedure in pairs(PROCEDURES) do
    addEventHandler(procedure.finishEvent, root, function(success, ...)
        local treatment = Treatments[source]
        if not treatment or treatment.action ~= action then return end
        local sessionId = select(procedure.sessionArg - 1, ...)
        if sessionId ~= treatment.sessionId then return end
        finishTreatment(source, success, ...)
    end)
end

-- Starts a procedure. Returns true, or false + reason.
function startTreatment(medic, target, action)
    local procedure = PROCEDURES[action]
    if not procedure then return false, "Unknown procedure" end
    if Treatments[medic] then return false, "You are busy" end
    if not canAttend(medic, target, MEDIC.INTERACT_RANGE) then return false, "Too far from the patient" end
    if not isResourceRunning(procedure.resource) then return false, "Equipment unavailable" end

    local state = getLivePatient(target)
    if not state or state.dead then return false, "Patient is dead" end
    local ok, reason = procedure.can(state)
    if not ok then return false, reason end

    local locks = Locks[target]
    if locks and isElement(locks[action]) then
        return false, "Someone else is already doing this"
    end

    closeExamination(medic)
    Locks[target] = locks or {}
    Locks[target][action] = medic
    Treatments[medic] = { target = target, action = action }
    refreshSubscription(medic, target)
    triggerClientEvent(medic, "medic:busy", resourceRoot, true)
    if procedure.animated then lockMedic(medic, target, true) end

    local sessionId = procedure.start(medic, target, state)
    if not sessionId then
        releaseTreatment(medic)
        openExamination(medic, target, "Could not start the procedure", true)
        return true
    end
    Treatments[medic].sessionId = sessionId
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

addEventHandler("medic:requestTreatment", resourceRoot, function(target, action)
    local medic = client
    if Examining[medic] ~= target then return end
    local ok, reason = startTreatment(medic, target, action)
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
