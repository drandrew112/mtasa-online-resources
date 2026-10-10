-- EMS work on top of work_core. Being on duty = holding the medsys medic role; the medical
-- logic itself (examination, stretcher, ERM tablet, hospitals) lives in the [medical] resources.

local Granted = {}                 -- players this resource gave the medic role to

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function setMedic(player, enabled)
    if enabled then Granted[player] = true else Granted[player] = nil end
    if isElement(player) and isRunning("medsys") then
        exports.medsys:setPlayerMedic(player, enabled)
    end
end

local function notify(player, text)
    if isElement(player) then
        triggerClientEvent(player, "ems:notify", resourceRoot, EMS.NAME, text)
    end
end

---------------------------------------------------------------- registration

local function setup()
    if not isRunning("work_core") then return end
    local wc = exports.work_core
    wc:registerWork(EMS.WORK_ID, {
        name = EMS.NAME,
        description = EMS.DESCRIPTION,
        color = EMS.COLOR,
        skins = EMS.SKINS,
        maxLevel = EMS.MAX_LEVEL,
        levelXp = EMS.LEVEL_XP,
        levelStep = EMS.LEVEL_STEP,
        levelNames = EMS.LEVEL_NAMES,
    })

    local vehicles = {}
    for i, v in ipairs(EMS.VEHICLES) do
        vehicles[i] = { model = v.model, name = v.name, color = v.color, data = v.data,
                        platePrefix = EMS.PLATE_PREFIX, plateDigits = EMS.PLATE_DIGITS }
    end

    for _, st in ipairs(EMS.STATIONS) do
        local d = st.duty
        wc:createDutyMarker(EMS.WORK_ID, d[1], d[2], d[3], { blip = st.blip })
        if st.vehicle then
            local m = st.vehicle.marker
            wc:createDutyVehicleMarker(EMS.WORK_ID, m[1], m[2], m[3], vehicles,
                { spawns = st.vehicle.spawns })
        end
    end

    -- players already on duty (work_ems restarted while work_core kept them)
    for _, player in ipairs(wc:getWorkPlayers(EMS.WORK_ID) or {}) do setMedic(player, true) end
end

addEventHandler("onResourceStart", resourceRoot, setup)
addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, setup)

-- medsys does not persist the role: give it back after a medsys restart
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "medsys" then return end
    for player in pairs(Granted) do
        if isElement(player) then exports.medsys:setPlayerMedic(player, true) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Granted) do setMedic(player, false) end
end)

---------------------------------------------------------------- work_core events

for _, name in ipairs({ "onPlayerWorkDutyRequest", "onPlayerWorkDutyStart", "onPlayerWorkDutyEnd",
                        "onWorkVehicleSpawn" }) do
    addEvent(name)
end

addEventHandler("onPlayerWorkDutyRequest", root, function(workId)
    if workId ~= EMS.WORK_ID then return end
    local ok, reason = EmsModules.canGoOnDuty(source)
    if not ok then cancelEvent(true, reason or "You cannot go on duty right now.") end
end)

addEventHandler("onPlayerWorkDutyStart", root, function(workId, skin)
    if workId ~= EMS.WORK_ID then return end
    setMedic(source, true)
    if isRunning("v_achievements") then
        exports.v_achievements:unlockAchievement(source, "ems_duty")
    end
    --notify(source, "You are on duty. Take an ambulance at the vehicle point.")
    EmsModules.fire("onDutyStart", source, skin)
end)

addEventHandler("onPlayerWorkDutyEnd", root, function(workId, reason)
    if workId ~= EMS.WORK_ID then return end
    setMedic(source, false)
    -- off duty = out of the ERM unit (the unit signs out when nobody is left)
    if isRunning("med_erm") then
        exports.med_erm:removePlayerFromUnit(source, "You went off duty.")
    end
    EmsModules.fire("onDutyEnd", source, reason)
end)

addEventHandler("onWorkVehicleSpawn", root, function(player, workId)
    if workId ~= EMS.WORK_ID then return end
    notify(player, "Press J to open the EMS tablet and sign in as a unit.")
    EmsModules.fire("onVehicleSpawn", source, player)
end)

addEventHandler("onPlayerQuit", root, function() Granted[source] = nil end)

-- A completed hospital handover of a real ERM task = one treated patient for every
-- crew member of the unit (v_achievements "ems_patients" stat).
addEvent("onErmUnitHandoverComplete")
addEventHandler("onErmUnitHandoverComplete", root, function(unitId, taskId)
    if not taskId or not isRunning("v_achievements") or not isRunning("med_erm") then return end
    local unit = exports.med_erm:getUnitData(unitId)
    if not unit then return end
    for _, m in ipairs(unit.members or {}) do
        if isElement(m.player) and isRunning("work_core") then
            exports.work_core:giveWorkXp(m.player, EMS.WORK_ID, EMS.XP_PER_PATIENT)
        end
        if isElement(m.player) then
            exports.v_achievements:addStat(m.player, "ems_patients", 1)
        end
    end
end)

---------------------------------------------------------------- work XP for medical actions

local function giveEmsXp(player, amount)
    if amount and amount > 0 and isElement(player) and isRunning("work_core") and isPlayerEms(player) then
        exports.work_core:giveWorkXp(player, EMS.WORK_ID, amount)
    end
end

-- patient -> { ["medic action option"] = true }: what already paid XP
local Rewarded = setmetatable({}, { __mode = "k" })
addEventHandler("onElementDestroy", root, function() Rewarded[source] = nil end)

addEvent("onMedicalTreatment")
addEventHandler("onMedicalTreatment", root, function(medic, action, success, option)
    if success ~= true or not isElement(medic) or getElementType(medic) ~= "player" then return end
    local xp = EMS.XP_TREATMENT[action]
    if not xp then return end
    local key = tostring(medic) .. " " .. action .. (action == "medication" and (" " .. tostring(option)) or "")
    local done = Rewarded[source]
    if not done then done = {} Rewarded[source] = done end
    if done[key] then return end
    done[key] = true
    giveEmsXp(medic, xp)
end)

addEvent("onMedicalPatientTransported")
addEventHandler("onMedicalPatientTransported", root, function(medic, kind)
    giveEmsXp(medic, EMS.XP_TRANSPORT[kind])
end)

addEvent("onHospitalPatientHandover")
addEventHandler("onHospitalPatientHandover", root, function(hospitalId, unitId, patient, medic)
    giveEmsXp(medic, EMS.XP_HANDOVER)
end)

---------------------------------------------------------------- exports

function isPlayerEms(player)
    return isRunning("work_core") and exports.work_core:isPlayerOnDuty(player, EMS.WORK_ID) == true
end

function getEmsPlayers()
    if not isRunning("work_core") then return {} end
    return exports.work_core:getWorkPlayers(EMS.WORK_ID) or {}
end

function getEmsWorkId()
    return EMS.WORK_ID
end
