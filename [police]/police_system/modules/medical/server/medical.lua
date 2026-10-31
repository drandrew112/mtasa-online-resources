-- police_system / modules/medical/server/medical.lua
-- REQUEST_AMBULANCE. With a medic on duty (a signed-in med_erm unit): an ERM task with a short description (source
-- "police"), no AI ambulance. Without one: an AI ambulance (416), spawned unseen like the tow truck, with siren; it
-- stops next to the patient (the nearest injured / dead NPC near the caller), opens the rear doors, the patient
-- gets in, then it drives towards the nearest hospital (med_hospitals) and disappears when nobody sees it.
-- Destroyed before it got there: failed, the caller is told (a new one has to be called).

local MD = POL.module("medical", { jobs = {} })   -- jobs[ambulance] = { patient, caller, state }
local C = POLICE.MEDICAL

local function traffic() return POL.running("ai_land_traffic") and exports.ai_land_traffic or nil end

local function medicsOnDuty()
    if not POL.running("med_erm") then return false end
    local ok, units = pcall(function() return exports.med_erm:getUnits() end)
    return ok and type(units) == "table" and #units > 0
end

-- the patient: an injured / dead NPC near the caller (the stopped / arrested one first)
local function patientNear(player)
    local x, y, z = getElementPosition(player)
    local best, bd
    for _, p in ipairs(getElementsWithinRange(x, y, z, 30, "ped")) do
        if not POL.ai.peds[p] and (isPedDead(p) or getElementHealth(p) < 60) and not getPedOccupiedVehicle(p) then
            local d = POL.dist(player, p)
            if not bd or d < bd then best, bd = p, d end
        end
    end
    return best
end

function MD.request(player)
    local unit = POL.units.of(player)
    local x, y, z = getElementPosition(player)
    if medicsOnDuty() then
        local inc = unit and POL.events.incidentOf(unit)
        local desc = L.forLang("en", "police_system.medical.task_desc", { callsign = unit and unit.callsign or "?",
            zone = getZoneName(x, y, z) })
        local ok, id = pcall(function()
            return exports.med_erm:createTask(L.forLang("en", "police_system.medical.task_title"), desc, x, y, z,
                "Police " .. (unit and unit.callsign or ""), nil, { source = "police" })
        end)
        if ok and id then
            POL.events.logFor(player, "ambulance_requested", { erm = id })
            POL.notify(player, "police_system.medical.erm_task", { id = id })
            return true
        end
    end
    local patient = patientNear(player)
    if not patient then POL.notify(player, "police_system.medical.no_patient") return false end
    local t = traffic()
    if not t then POL.notify(player, "police_system.medical.unavailable") return false end
    local px, py, pz = getElementPosition(patient)
    local sx, sy, sz, rot = t:findHiddenRoadSpawn(px, py, pz, { minDist = C.SPAWN_MIN, maxDist = C.SPAWN_MAX, toward = patient })
    if not sx then POL.notify(player, "police_system.medical.unavailable") return false end
    local amb = t:createScriptedVehicle(C.MODEL, sx, sy, sz, { heading = rot, skin = C.SKIN, profile = "pursuit", speedFactor = 1.2 })
    if not amb then POL.notify(player, "police_system.medical.unavailable") return false end
    if C.PAINTJOB and POL.running("v_paintjobs") then pcall(function() exports.v_paintjobs:setVehicleCustomPaintjob(amb, C.PAINTJOB) end) end
    if POL.running("v_els") then exports.v_els:setElsLights(amb, true); exports.v_els:setElsSiren(amb, true, 1) end
    MD.jobs[amb] = { patient = patient, caller = player, state = "coming" }
    if POL.running("ai_peds") and exports.ai_peds:isAIPed(patient) then
        if not isPedDead(patient) then exports.ai_peds:setAIPedBehaviour(patient, "patient", {}) end
        exports.ai_peds:setAIPedKeep(patient, true)
    end
    t:addScriptedStop(amb, px, py, pz, { tag = "amb_pickup", hold = true, radius = 40 })
    POL.events.logFor(player, "ambulance_requested", { ai = true })
    POL.notify(player, "police_system.medical.ai_coming")
    return true
end

local function fail(amb, job)
    MD.jobs[amb] = nil
    if isElement(job.caller) then POL.notify(job.caller, "police_system.medical.failed") end
end

addEvent("onTrafficVehicleTargetReached")
addEventHandler("onTrafficVehicleTargetReached", root, function(amb, id, kind, tag)
    local job = MD.jobs[amb]
    if not job or tag ~= "amb_pickup" or job.state ~= "coming" then return end
    local t = traffic()
    job.state = "loading"
    setVehicleDoorOpenRatio(amb, 4, 1, 800)
    setVehicleDoorOpenRatio(amb, 5, 1, 800)
    setTimer(function()
        if not isElement(amb) then return end
        local p = job.patient
        if isElement(p) then
            if POL.running("ai_peds") and exports.ai_peds:isAIPed(p) then exports.ai_peds:destroyAIPed(p) end
            if isElement(p) then destroyElement(p) end
        end
        setVehicleDoorOpenRatio(amb, 4, 0, 800)
        setVehicleDoorOpenRatio(amb, 5, 0, 800)
        job.state = "transport"
        local x, y, z = getElementPosition(amb)
        local h = POL.running("med_hospitals") and exports.med_hospitals:getNearestHospital(x, y, z)
        local info = h and exports.med_hospitals:getHospital(h)
        t:continueScriptedVehicle(amb)
        t:clearScriptedTargets(amb)
        if info and info.x then t:addScriptedTurnPoint(amb, info.x, info.y, info.z, { tag = "amb_hospital", radius = 120 }) end
        t:setScriptedDespawnUnseen(amb, { minDist = 80 })
        if isElement(job.caller) then POL.notify(job.caller, "police_system.medical.loaded") end
        POL.db.stat("ambulances", 1)
    end, 3500, 1)
end)

addEvent("onTrafficVehicleRemoved")
addEventHandler("onTrafficVehicleRemoved", root, function(amb, reason)
    local job = MD.jobs[amb]
    if not job then return end
    if job.state == "coming" or job.state == "loading" then fail(amb, job) else MD.jobs[amb] = nil end
end)

addEventHandler("onVehicleExplode", root, function()
    local job = MD.jobs[source]
    if job and job.state ~= "transport" then fail(source, job) end
end)
