if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Examination sessions (who has the panel open on whom) and treatments (minigames).
--
-- Examining[medic] = target                      -- open examination panels
-- HostMode[medic] = true                         -- that "panel" is the hospital patient panel (med_hospitals
--                                                   er/): hospital staff never get the medsys panel, the
--                                                   client gets medic:host* events instead of medic:panel*
-- Watchers[target] = { [medic] = true }          -- reverse index for the per-tick panel updates
-- Treatments[medic] = { target, action, option, dose, sessionId, timer, aborted }
-- Locks[target] = { [key] = medic }              -- one medic per procedure per patient; the key is
--                                                   the action, or "action:injuryId" / "action:base"
--                                                   for a procedure on one wound (procedure.pick)

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
local HostMode = {}
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
        return ((getElementData(element, "displayName") or getPlayerName(element)):gsub("#%x%x%x%x%x%x", ""))
    end
    local name = getElementData(element, MEDIC.DATA_NAME)
    return type(name) == "string" and name ~= "" and name or L.msg("medsys.treatment.unknown_patient")
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
-- Medics[player] = kind: "ems" (the medsys examination panel) or "hospital" (hospital staff: they
-- work from the hospital patient panel of med_hospitals, the medsys panel never opens for them)
local Medics = {}

addEvent("onPlayerMedicChange") -- source: player, arg: enabled

-- Is the medic role checked at all (MEDIC.REQUIRE_MEDIC_ROLE). Fixed while the resource runs,
-- so other resources query it once.
function isMedicRoleRequired()
    return MEDIC.REQUIRE_MEDIC_ROLE == true
end

-- Does the player hold the medic role (the bare flag, whether or not the role is required)
function isPlayerMedic(player)
    return Medics[player] ~= nil
end

-- "ems" | "hospital" | false
function getMedicKind(player)
    return Medics[player] or false
end

-- Hospital staff: medsys runs in host mode for them (no medsys panel)
function isHostMedic(player)
    return Medics[player] == "hospital"
end

-- May the player work as a medic: always when the role is not required, otherwise with the role
function hasMedicAccess(player)
    return not MEDIC.REQUIRE_MEDIC_ROLE or Medics[player] ~= nil
end

local function syncMedicData(player)
    if Medics[player] then
        setElementData(player, MEDIC.DATA_ROLE, true)
    else
        removeElementData(player, MEDIC.DATA_ROLE)
    end
end

-- Gives (true) or takes (false) the medic role. kind: "ems" (default) or "hospital"
function setPlayerMedic(player, enabled, kind)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    enabled = enabled and true or false
    kind = enabled and (kind == "hospital" and "hospital" or "ems") or nil
    if Medics[player] == kind then return true end
    -- the role or its kind changes: the open panel (medsys or hospital host) goes
    if Examining[player] then closeExamination(player) end
    Medics[player] = kind
    syncMedicData(player)
    updateInteractVisibility()
    triggerEvent("onPlayerMedicChange", player, enabled)
    return true
end

-- kind: nil = every medic, "ems" / "hospital" = only that kind
function getMedicPlayers(kind)
    local list = {}
    for player, k in pairs(Medics) do
        if not kind or k == kind then list[#list + 1] = player end
    end
    return list
end

addEventHandler("onElementDataChange", root, function(key)
    if key == MEDIC.DATA_ROLE and client then syncMedicData(source) end
end)

-- Competency limits of a medic, set by a work resource (work_ems from the work_core competencies):
-- { [key] = needed competency name } of every DENIED key. Keys: "action.<action>" (MEDIC_ACTIONS and
-- "monitor"), "drug.<id>", "dose.high" (the orange doses), "defib.<op>" (charge, shock, analyze, sync).
-- No table / a key not in it = allowed. Synced as MEDIC.DATA_PERMS so the panel greys them out.
local Denied = {}

-- A name may be a message object (work_core competency names): the element data gets its locale key,
-- the panel translates it in the medic's own language.
local function syncPermissions(player)
    if Denied[player] then
        local t = {}
        for k, v in pairs(Denied[player]) do t[k] = L.isMsg(v) and v.t or v end
        setElementData(player, MEDIC.DATA_PERMS, t)
    elseif getElementData(player, MEDIC.DATA_PERMS) ~= nil then removeElementData(player, MEDIC.DATA_PERMS) end
end

function setMedicPermissions(player, denied)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local t = {}
    for k, v in pairs(type(denied) == "table" and denied or {}) do
        if type(k) == "string" then t[k] = L.isMsg(v) and v or tostring(v) end
    end
    Denied[player] = next(t) and t or nil
    syncPermissions(player)
    return true
end

function getMedicPermissions(player)
    return Denied[player] or {}
end

-- -> true | false, reason
function checkMedicPermission(medic, key)
    local need = Denied[medic] and Denied[medic][key]
    if need then return false, L.msg("medsys.treatment.needs_competency", { name = need }) end
    return true
end

addEventHandler("onElementDataChange", root, function(key)
    if key == MEDIC.DATA_PERMS and client then syncPermissions(source) end
end)
addEventHandler("onPlayerQuit", root, function() Denied[source] = nil end)

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

-- Lock key of a procedure on one wound: picked = an injury or "base" (bleeding without one)
local function pickKey(action, picked)
    return action .. ":" .. (picked == "base" and "base" or tostring(picked.id))
end

-- The live locks on a patient: { [key] = medic }
local function getClaims(target)
    local claims = {}
    for key, medic in pairs(Locks[target] or {}) do
        if isElement(medic) then claims[key] = medic end
    end
    return claims
end

-- A medic working on this kind of procedure (any wound), or nil
local function findClaim(claims, action)
    local prefix = action .. ":"
    for key, medic in pairs(claims or {}) do
        if key == action or key:sub(1, #prefix) == prefix then return medic end
    end
    return nil
end

-- The wound a bandage goes on: the worst bleeder first, then the worst untreated injury.
-- claims: wounds another medic is already working on are skipped
local function findBandageTarget(state, claims)
    local best, bestScore
    for _, injury in ipairs(state.injuries) do
        if not injury.treated and MEDIC_INJURIES[injury.type].treat == "bandage"
            and not (claims and claims[pickKey("bandage", injury)]) then
            local score = injury.bleeding * 10 + injury.severity
            if not bestScore or score > bestScore then best, bestScore = injury, score end
        end
    end
    return best
end

local function pickBandage(state, claims)
    local injury = findBandageTarget(state, claims)
    if injury then return injury end
    if state.baseBleeding > 0 and not (claims and claims["bandage:base"]) then return "base" end
    return nil
end

-- The fracture a splint goes on: the worst untreated one (claims as above)
local function findSplintTarget(state, claims)
    local best
    for _, injury in ipairs(state.injuries) do
        if not injury.treated and MEDIC_INJURIES[injury.type].treat == "splint"
            and not (claims and claims[pickKey("splint", injury)]) then
            if not best or injury.severity > best.severity then best = injury end
        end
    end
    return best
end

-- Is the picked wound still there and untreated (it is applied at the end of the minigame)
local function isPickedOpen(state, picked)
    if picked == "base" then return state.baseBleeding > 0 end
    for _, injury in ipairs(state.injuries) do
        if injury == picked then return not injury.treated end
    end
    return false
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
-- can(state, claims) -> true | false, reason (claims: getClaims of the patient)
-- pick(state, claims) optional: the wound it goes on (injury | "base"), locked per wound, so
--              other medics can work on the other wounds at the same time; nil = none free
-- validate(state, option, dose) optional, checks the option sent by the panel (e.g. the medicine,
--   dose = index of its dose option)
-- start(medic, target, state, picked) -> session id or false
-- duration     timed procedure without a minigame: it succeeds after this many seconds
--              (or a function(option) returning them)
-- progress(option, state, dose) text of the progress bar of a timed procedure
-- stop(medic)  aborts the minigame (it fires its finish event)
-- cleanup(state) optional, runs when the procedure ends in any way
-- finishEvent  the minigame's result event, sessionArg = position of the session id in it
-- apply(state, success, ...) applies the result, returns the line shown on the panel
--              (with pick: apply(state, success, picked), picked = nil when it is gone meanwhile)
-- animated     the minigame has no animation of its own, the medic kneels by the patient
local PROCEDURES = {}

PROCEDURES.bandage = {
    resource = "mg_arrows",
    can = function(state, claims)
        if pickBandage(state, claims) then return true end
        local other = findClaim(claims, "bandage")
        if other then return false, L.msg("medsys.treatment.name_is_already_treating_it", { name = getDisplayName(other) }) end
        return false, L.msg("medsys.treatment.nothing_to_bandage")
    end,
    pick = pickBandage,
    start = function(medic, target, state, picked)
        local severity = picked == "base" and state.baseBleeding or picked.severity
        return exports.mg_arrows:startArrowsGame(medic, 8 + severity * 4, { speed = 0.85 + severity * 0.15 })
    end,
    stop = function(medic) exports.mg_arrows:stopArrowsGame(medic) end,
    finishEvent = "onArrowsGameFinish",
    sessionArg = 6, -- success, hits, total, percent, reason, sessionId
    animated = true,
    apply = function(state, success, picked)
        if not success then return L.msg("medsys.treatment.bandage_did_not_hold") end
        if not picked then return L.msg("medsys.treatment.already_treated") end
        local injury = picked ~= "base" and picked
        if injury then
            local def = MEDIC_INJURIES[injury.type]
            injury.treated = true
            -- a critical wound keeps oozing until surgery
            injury.bleeding = injury.bleeding >= 3 and 1 or 0
            return ("%s: %s"):format(def.label, def.treatedLabel:lower())
        end
        state.baseBleeding = math.max(0, state.baseBleeding - 2)
        return L.msg("medsys.treatment.bleeding_controlled")
    end,
}

PROCEDURES.splint = {
    resource = "mg_splinting",
    can = function(state, claims)
        if findSplintTarget(state, claims) then return true end
        local other = findClaim(claims, "splint")
        if other then return false, L.msg("medsys.treatment.name_is_already_treating_it", { name = getDisplayName(other) }) end
        return false, L.msg("medsys.treatment.no_fracture_to_splint")
    end,
    pick = findSplintTarget,
    start = function(medic, target, state, picked)
        local severity = picked.severity
        return exports.mg_splinting:startSplintGame(medic, target, 6 + severity * 2, { speed = 0.85 + severity * 0.15 })
    end,
    stop = function(medic) exports.mg_splinting:stopSplintGame(medic) end,
    finishEvent = "onSplintGameFinish",
    sessionArg = 6, -- success, hits, total, percent, reason, sessionId
    apply = function(state, success, picked)
        if not success then return L.msg("medsys.treatment.splint_did_not_hold") end
        if not picked then return L.msg("medsys.treatment.already_treated") end
        local def = MEDIC_INJURIES[picked.type]
        picked.treated = true
        return ("%s: %s"):format(def.label, def.treatedLabel:lower())
    end,
}

PROCEDURES.cpr = {
    resource = "mg_cpr",
    can = function(state)
        if isInClinicalDeath(state) then return true end
        return false, L.msg("medsys.treatment.patient_has_pulse")
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
        if not success then return L.msg("medsys.treatment.ineffective_compressions") end
        -- good compressions keep the brain perfused: the death timer is pushed back
        extendDeathTimer(state, MEDIC.CPR_TIME_BONUS)
        if not canRestartHeart(state) then return L.msg("medsys.treatment.no_pulse_too_much_blood_lost") end
        if state.monitor and MEDIC_RHYTHMS[state.rhythm].shockable then
            return L.msg("medsys.treatment.shockable_rhythm_charge_and_shock")
        end
        return L.msg("medsys.treatment.no_pulse_yet_continue_cpr")
    end,
}

PROCEDURES.iv = {
    resource = "mg_intravenous",
    can = function(state)
        if not state.ivAccess then return true end
        return false, L.msg("medsys.treatment.iv_access_already_in_place")
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
        if not success then return L.msg("medsys.treatment.cannulation_failed") end
        state.ivAccess = true
        state.ivQuality = quality
        return L.msg("medsys.treatment.iv_access_secured_hang_infusion", { quality = quality })
    end,
}

-- The infusion bag on the IV access (the IV button turns into this once the cannula is in).
-- option: "hang" (a new MEDIC_DEFAULT_FLUID bag from the medical bag, replaces the one hanging),
-- "rate:<id>" (MEDIC_INFUSION_RATES), "stop" (the bag comes off, what is left in it is lost)
local function infusionOp(option)
    if option == "hang" or option == "stop" then return option end
    local id = type(option) == "string" and option:match("^rate:(%w+)$")
    if id and medicInfusionRate(id) then return "rate", id end
    return nil
end

PROCEDURES.infusion = {
    duration = function(option) return option == "hang" and MEDIC.INFUSION_HANG_TIME or MEDIC.INFUSION_RATE_TIME end,
    animated = true,
    can = function(state)
        if not state.ivAccess then return false, L.msg("medsys.treatment.needs_iv_access") end
        return true
    end,
    validate = function(state, option)
        local op, id = infusionOp(option)
        if not op then return false, L.msg("medsys.treatment.unknown_procedure") end
        if op ~= "hang" and not state.infusion then return false, L.msg("medsys.treatment.no_infusion_bag") end
        if op == "rate" and state.infusion.rate == id then return false, L.msg("medsys.treatment.infusion_already_at_rate") end
        return true
    end,
    progress = function(option)
        local op, id = infusionOp(option)
        if op == "hang" then
            local fluid = MEDIC_FLUIDS[MEDIC_DEFAULT_FLUID]
            return L.msg("medsys.treatment.hanging_infusion", { volume = fluid.volume, name = fluid.name })
        elseif op == "rate" then
            return L.msg("medsys.treatment.setting_drip_rate", { rate = medicInfusionRate(id).label })
        end
        return L.msg("medsys.treatment.removing_infusion_bag")
    end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success, option)
        if not success then return L.msg("medsys.treatment.infusion_was_not_changed") end
        if not state.ivAccess then return L.msg("medsys.treatment.needs_iv_access") end
        local op, id = infusionOp(option)
        if op == "hang" then
            local fluid = MEDIC_FLUIDS[MEDIC_DEFAULT_FLUID]
            local rate = state.infusion and state.infusion.rate or MEDIC_DEFAULT_RATE
            state.infusion = { fluid = MEDIC_DEFAULT_FLUID, left = fluid.volume, rate = rate }
            return L.msg("medsys.treatment.infusion_running", { volume = fluid.volume, name = fluid.name,
                rate = medicInfusionRate(rate).label })
        elseif op == "rate" then
            if not state.infusion then return L.msg("medsys.treatment.no_infusion_bag") end
            state.infusion.rate = id
            return L.msg("medsys.treatment.drip_rate_set", { rate = medicInfusionRate(id).label })
        end
        removeInfusion(state)
        return L.msg("medsys.treatment.infusion_bag_removed")
    end,
}

PROCEDURES.airway = {
    resource = "mg_airway",
    -- Only with RSI (also in cardiac arrest): the anaesthetic (sedation) and the muscle relaxant
    -- (after its onset) both have to work. Given in the wrong order the patient panics while the
    -- breathing stops (simulation.lua).
    can = function(state)
        if state.intubated then return false, L.msg("medsys.treatment.airway_already_secured") end
        if not isSedated(state) then
            if state.consciousness == "stable" or state.consciousness == "confused" or state.consciousness == "dazed" then
                return false, L.msg("medsys.treatment.patient_is_conscious_give_ketamine_first")
            end
            return false, L.msg("medsys.treatment.give_ketamine_first_induction")
        end
        if not hasDrugEffect(state, "paralysis") then return false, L.msg("medsys.treatment.give_rocuronium_muscle_relaxant") end
        if not isParalyzed(state) then return false, L.msg("medsys.treatment.waiting_for_muscle_relaxant_to_work") end
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
            return reason == "desaturated" and L.msg("medsys.treatment.intubation_failed_patient_desaturated") or L.msg("medsys.treatment.intubation_failed")
        end
        state.intubated = true
        state.noOxygen = nil
        state.oxygenMask = false
        for _, injury in ipairs(state.injuries) do
            if injury.type == "suffocation" then injury.treated = true end
        end
        return L.msg("medsys.treatment.airway_secured_patient_ventilated")
    end,
}

-- Puts the oxygen mask on / takes it off (the button label follows it)
PROCEDURES.oxygen = {
    duration = MEDIC.OXYGEN_TIME,
    animated = true,
    can = function(state)
        if state.intubated then return false, L.msg("medsys.treatment.ventilated_through_tube") end
        return true
    end,
    progress = function(_, state)
        return state.oxygenMask and L.msg("medsys.treatment.removing_oxygen_mask") or L.msg("medsys.treatment.putting_on_oxygen_mask")
    end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success)
        if not success then return L.msg("medsys.treatment.oxygen_mask_was_not_changed") end
        if state.intubated then return L.msg("medsys.treatment.ventilated_through_tube") end
        state.oxygenMask = not state.oxygenMask
        return state.oxygenMask and L.msg("medsys.treatment.oxygen_mask_on") or L.msg("medsys.treatment.oxygen_mask_removed")
    end,
}

-- Monitor / defibrillator: ECG electrodes and pads, once per patient (it stays on)
PROCEDURES.monitor = {
    duration = MEDIC.MONITOR_TIME,
    animated = true,
    can = function(state)
        if state.monitor then return false, L.msg("medsys.treatment.monitor_attached") end
        return true
    end,
    progress = function() return L.msg("medsys.treatment.attaching_monitor_defibrillator_pads") end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success)
        if not success then return L.msg("medsys.treatment.monitor_was_not_attached") end
        attachMonitor(state)
        return L.msg("medsys.treatment.monitor_attached_2", { label = MEDIC_RHYTHMS[state.rhythm].label })
    end,
}

PROCEDURES.medication = {
    duration = MEDIC.DRUG_TIME,
    animated = true,
    -- the menu always opens (oral medicines), IV medicines are checked one by one
    can = function() return true end,
    validate = function(state, drugId, dose)
        local drug = MEDIC_DRUGS[drugId]
        if not drug then return false, L.msg("medsys.treatment.unknown_medicine") end
        if dose ~= nil and drug.dosing and not drug.dosing.options[tonumber(dose) or 0] then
            return false, L.msg("medsys.treatment.unknown_dose")
        end
        if medicDrugNeedsIV(drug) and not state.ivAccess then return false, L.msg("medsys.treatment.needs_iv_access") end
        if drug.awake and state.consciousness ~= "stable" and state.consciousness ~= "confused" then
            return false, L.msg("medsys.treatment.patient_cannot_swallow")
        end
        return true
    end,
    progress = function(drugId, state, dose)
        local drug = MEDIC_DRUGS[drugId]
        local option = medicDrugDose(drug, dose)
        local name = option and (drug.name .. " " .. medicDoseText(drug, option, state.weight)) or drug.name
        return L.msg("medsys.treatment.giving", { name = name })
    end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success, drugId, dose)
        local drug = MEDIC_DRUGS[drugId]
        if not success or not drug then return L.msg("medsys.treatment.medicine_was_not_given") end
        local now = getTickCount()
        -- the effects in MEDIC_DRUGS are for the standard dose: the chosen dose scales them
        local option = medicDrugDose(drug, dose)
        local scale = medicDoseScale(drug, option)
        local amount = option and medicDoseText(drug, option, state.weight) or nil
        state.drugs[#state.drugs + 1] = { id = drugId, tick = now, scale = scale, dose = amount,
            untilTick = now + drug.duration * 1000 * getDoseTimeFactor(scale) }
        if drug.glucose then
            state.glucose = math.min(MEDIC.GLUCOSE_MAX, state.glucose + drug.glucose * scale)
        end
        if drug.adenosine then applyAdenosine(state, scale) end
        if scale >= (drug.dosing and drug.dosing.treatMin or 0.5) then
            for _, condition in ipairs(drug.treats or {}) do
                for _, injury in ipairs(state.injuries) do
                    if injury.type == condition then injury.treated = true end
                end
            end
        end
        -- too much of it in the body (e.g. fentanyl -> opioid overdose): a new hidden condition
        local overdose = drug.dosing and drug.dosing.overdose
        if overdose and getDrugLoad(state, drugId) >= overdose.scale then
            local present = false
            for _, injury in ipairs(state.injuries) do
                if injury.type == overdose.condition and not injury.treated then present = true end
            end
            if not present then applyInjury(state.element, overdose.condition, overdose.severity or 2) end
        end
        return (amount and (drug.name .. " " .. amount) or drug.name) .. " given"
    end,
}

-- Neuro exam (D of ABCDE): responsiveness, pupils, FAST. Its findings stay on the panel.
PROCEDURES.neuro = {
    duration = MEDIC.NEURO_TIME,
    animated = true,
    can = function(state)
        if state.neuroChecked then return false, L.msg("medsys.treatment.neuro_exam_done_findings_below") end
        return true
    end,
    progress = function() return L.msg("medsys.treatment.checking_responsiveness_pupils_face_arms_and") end,
    stop = function() end, -- releaseTreatment kills the timer
    apply = function(state, success)
        if not success then return L.msg("medsys.treatment.neuro_exam_was_interrupted") end
        state.neuroChecked = true
        return L.msg("medsys.treatment.neuro_exam_done")
    end,
}

-- The actions the panel can offer right now: { [action] = true | reason }
-- equipment: getPatientEquipment(target) (server/equipment.lua), nil = not checked
local function getAvailability(state, target, equipment)
    local result = {}
    local dead = not state or state.dead
    local claims = getClaims(target)
    for action, procedure in pairs(PROCEDURES) do
        if dead then
            result[action] = L.msg("medsys.rhythm.patient_is_dead")
        elseif not procedure.pick and claims[action] then
            -- the medic doing it is busy (no panel), so everyone watching sees the same
            result[action] = L.msg("medsys.treatment.name_is_already_doing_this", { name = getDisplayName(claims[action]) })
        else
            local ok, reason = procedure.can(state, claims)
            result[action] = ok or reason
        end
    end
    local ok, reason = canRequestTransport(target, state)
    result.transport = ok or reason
    result.glucometer = dead and L.msg("medsys.rhythm.patient_is_dead") or true -- a device, measured from its own window
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
    -- who is working on which wound (the injury list shows it)
    local claims = getClaims(target)
    for _, injury in ipairs(snapshot.injuries or {}) do
        for action, procedure in pairs(PROCEDURES) do
            local medic = procedure.pick and claims[pickKey(action, injury)]
            if medic then injury.treatingBy = getDisplayName(medic) end
        end
    end
    snapshot.transportPhase, snapshot.transportTimeLeft = getTransportStatus(target)
    return snapshot
end

---------------------------------------------------------------------------
-- Examination panel
---------------------------------------------------------------------------

function closeExamination(medic, notifyClient)
    local target = Examining[medic]
    if not target then return false end
    local host = HostMode[medic]
    Examining[medic] = nil
    HostMode[medic] = nil

    local watchers = Watchers[target]
    if watchers then
        watchers[medic] = nil
        if not next(watchers) then Watchers[target] = nil end
    end
    refreshSubscription(medic, target)
    if notifyClient ~= false and isElement(medic) then
        triggerClientEvent(medic, host and "medic:hostClose" or "medic:panelClose", resourceRoot)
    end
    return true
end

-- A line for the medic's panel (the medsys panel, or the hospital panel in host mode)
function sendPanelMessage(medic, message, isError)
    if not isElement(medic) then return end
    triggerClientEvent(medic, isHostMedic(medic) and "medic:hostMessage" or "medic:panelMessage", resourceRoot, message, isError == true)
end

-- message: optional result line shown on the panel (e.g. after a procedure), isError colours it red.
-- Hospital staff (isHostMedic) get the host mode: the snapshot goes to the hospital patient panel.
function openExamination(medic, target, message, isError)
    if not canAttend(medic, target, MEDIC.PANEL_RANGE) then return false end
    if Treatments[medic] then return false end
    if Examining[medic] and Examining[medic] ~= target then
        closeExamination(medic, false)
    end

    local host = isHostMedic(medic)
    if Examining[medic] == target and (HostMode[medic] == true) ~= host then
        closeExamination(medic, false)
    end
    local snapshot = getPanelSnapshot(target)
    Examining[medic] = target
    HostMode[medic] = host or nil
    Watchers[target] = Watchers[target] or {}
    Watchers[target][medic] = true
    refreshSubscription(medic, target)

    triggerClientEvent(medic, host and "medic:hostOpen" or "medic:panelOpen", resourceRoot, target, getDisplayName(target),
        snapshot, message, isError == true)
    return true
end

-- Called by the simulation after every step
function sendPanelUpdates(state)
    local target = state.element
    local watchers = Watchers[target]
    if not watchers then return end

    local list, hosts = {}, {}
    for medic in pairs(watchers) do
        if isElement(medic) and isNear(medic, target, MEDIC.PANEL_RANGE) then
            if HostMode[medic] then hosts[#hosts + 1] = medic else list[#list + 1] = medic end
        else
            closeExamination(medic)
        end
    end
    if #list > 0 or #hosts > 0 then
        local snapshot = getPanelSnapshot(target)
        if #list > 0 then triggerClientEvent(list, "medic:panelUpdate", resourceRoot, target, snapshot) end
        if #hosts > 0 then triggerClientEvent(hosts, "medic:hostUpdate", resourceRoot, target, snapshot) end
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
        triggerClientEvent(client, isHostMedic(client) and "medic:hostClose" or "medic:panelClose", resourceRoot)
    end
end)

addEventHandler("medic:closeExamine", resourceRoot, function()
    closeExamination(client, false)
end)

-- spot = { x, y, z, rotation, canDrive } picked by the client next to the body, or nil
addEventHandler("medic:requestTransport", resourceRoot, function(target, spot)
    local medic = client
    if Examining[medic] ~= target or HostMode[medic] then return end -- no transport from the hospital
    local ok, reason
    if not canAttend(medic, target, MEDIC.PANEL_RANGE) then
        ok, reason = false, L.msg("medsys.rhythm.too_far_from_patient")
    else
        ok, reason = requestTransport(medic, target, spot)
    end
    if ok then
        openExamination(medic, target, L.msg("medsys.treatment.transport_requested_arrives_in_s", { transport_delay = MEDIC.TRANSPORT_DELAY }))
    else
        sendPanelMessage(medic, reason, true)
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
    local allowed, why = checkMedicPermission(medic, "action.glucometer")
    if not allowed then return fail(why) end
    if Glucometers[medic] then return fail(L.msg("medsys.treatment.measuring")) end
    if not canAttend(medic, target, MEDIC.INTERACT_RANGE) then return fail(L.msg("medsys.rhythm.too_far_from_patient")) end
    local state = getLivePatient(target)
    if not state or state.dead then return fail(L.msg("medsys.treatment.no_blood_flow_no_reading")) end
    local hasBag, reason = checkGlucometerEquipment(medic, target)
    if not hasBag then return fail(reason) end

    Glucometers[medic] = setTimer(function()
        Glucometers[medic] = nil
        if not isElement(medic) or not isElement(target) then return end
        if not canAttend(medic, target, MEDIC.PANEL_RANGE) then return fail(L.msg("medsys.treatment.moved_away_measure_again")) end
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
    if locks and locks[treatment.lockKey] == medic then
        locks[treatment.lockKey] = nil
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
    -- the other medics' panels show the freed procedure / wound at once
    if isElement(target) and Patients[target] then sendPanelUpdates(Patients[target]) end
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
        local procedure = PROCEDURES[treatment.action]
        if procedure.pick then
            local picked = isPickedOpen(state, treatment.picked) and treatment.picked or nil
            message = procedure.apply(state, success, picked)
        else
            message = procedure.apply(state, success, ...)
        end
        isError = not success
        if success == true then onEquipmentTreatmentDone(medic, target, treatment.action, treatment.option, state) end
    end
    triggerEvent("onMedicalTreatment", target, medic, treatment.action, success == true, treatment.option, treatment.dose)
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
    local list, hosts = {}, {}
    for medic in pairs(watchers) do
        if isElement(medic) then
            if HostMode[medic] then hosts[#hosts + 1] = medic else list[#list + 1] = medic end
        end
    end
    if #list > 0 then triggerClientEvent(list, "medic:panelMessage", resourceRoot, message, isError == true) end
    if #hosts > 0 then triggerClientEvent(hosts, "medic:hostMessage", resourceRoot, message, isError == true) end
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

-- Starts a procedure. option: e.g. the medicine id, dose: index of its dose option (MEDIC_DRUGS
-- dosing.options, nil = the default dose). Returns true, or false + reason.
function startTreatment(medic, target, action, option, dose)
    local procedure = PROCEDURES[action]
    if not procedure then return false, L.msg("medsys.treatment.unknown_procedure") end
    local allowed, why = checkMedicPermission(medic, "action." .. action)
    if allowed and action == "medication" then
        allowed, why = checkMedicPermission(medic, "drug." .. tostring(option))
        -- a drug ordered by a doctor may be given by a nurse too (med_hospitals ER orders, K8)
        if not allowed and hostAllowsAction(medic, target, "drug." .. tostring(option)) then allowed, why = true, nil end
        local drug = MEDIC_DRUGS[option]
        local chosen = allowed and drug and drug.dosing and medicDrugDose(drug, dose)
        if chosen and chosen.high then allowed, why = checkMedicPermission(medic, "dose.high") end
    elseif allowed and action == "infusion" then
        local id = type(option) == "string" and option:match("^rate:(%w+)$")
        local rate = id and medicInfusionRate(id)
        if rate and rate.perm then allowed, why = checkMedicPermission(medic, rate.perm) end
    end
    if not allowed then return false, why end
    -- a patient handed over to the ER (med_hospitals er.case) is the hospital staff's, not the EMS crew's
    if not isHostMedic(medic) and isElement(target) and getElementData(target, "er.case") then
        return false, L.msg("medsys.treatment.in_hospital_care")
    end
    if Treatments[medic] then return false, L.msg("medsys.treatment.you_are_busy") end
    if not canAttend(medic, target, MEDIC.INTERACT_RANGE) then return false, L.msg("medsys.rhythm.too_far_from_patient") end
    if procedure.resource and not isResourceRunning(procedure.resource) then return false, L.msg("medsys.treatment.equipment_unavailable") end

    local state = getLivePatient(target)
    if not state or state.dead then return false, L.msg("medsys.rhythm.patient_is_dead") end
    local claims = getClaims(target)
    if not procedure.pick and claims[action] then
        return false, L.msg("medsys.treatment.name_is_already_doing_this", { name = getDisplayName(claims[action]) })
    end
    local ok, reason = procedure.can(state, claims)
    if not ok then return false, reason end
    if procedure.validate then
        ok, reason = procedure.validate(state, option, dose)
        if not ok then return false, reason end
    end
    ok, reason = onEquipmentTreatmentCheck(medic, target, action, option, state)
    if not ok then return false, reason end
    ok, reason = onHostTreatmentCheck(medic, target, action, option, state)
    if not ok then return false, reason end

    -- one medic per wound (pick) or per procedure
    local picked = procedure.pick and procedure.pick(state, claims)
    if procedure.pick and not picked then return false, L.msg("medsys.treatment.someone_else_is_already_doing_this") end
    local lockKey = picked and pickKey(action, picked) or action

    closeExamination(medic)
    Locks[target] = Locks[target] or {}
    Locks[target][lockKey] = medic
    Treatments[medic] = { target = target, action = action, option = option, dose = dose, picked = picked, lockKey = lockKey }
    sendPanelUpdates(state) -- the others see at once who took it
    refreshSubscription(medic, target)
    triggerClientEvent(medic, "medic:busy", resourceRoot, true)
    if procedure.animated then lockMedic(medic, target, true) end

    local duration = procedure.duration
    if type(duration) == "function" then duration = duration(option) end
    if duration then
        local treatment = Treatments[medic]
        treatment.timer = setTimer(function()
            treatment.timer = nil
            finishTreatment(medic, true, option, dose)
        end, duration * 1000, 1)
        triggerClientEvent(medic, "medic:progress", resourceRoot, procedure.progress(option, state, dose), duration * 1000)
        onEquipmentTreatmentStart(medic, target, action)
        return true
    end

    local sessionId = procedure.start(medic, target, state, picked)
    if not sessionId then
        releaseTreatment(medic)
        openExamination(medic, target, L.msg("medsys.treatment.could_not_start_procedure"), true)
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
    for _, medic in pairs(locks) do
        local treatment = Treatments[medic]
        if treatment and treatment.target == target then
            treatment.aborted = true
            if isElement(medic) then PROCEDURES[treatment.action].stop(medic) end -- fires the finish event
            releaseTreatment(medic)
            if reopen and isElement(medic) and isElement(target) then openExamination(medic, target) end
        end
    end
    Locks[target] = nil
end

addEventHandler("medic:requestTreatment", resourceRoot, function(target, action, option, dose)
    local medic = client
    if Examining[medic] ~= target then return end
    local ok, reason = startTreatment(medic, target, action, option, dose)
    if not ok then
        sendPanelMessage(medic, reason, true)
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
