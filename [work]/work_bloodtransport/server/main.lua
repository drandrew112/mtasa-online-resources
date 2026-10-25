if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Blood transporter work on top of work_core. Being on duty gives the transporter right (bt_core)
-- and a BT- ambulance; the blood transport service itself (bt_dispatch) is a separate state.

local Granted = {}

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function setRight(player, enabled)
    if enabled then Granted[player] = true else Granted[player] = nil end
    if isElement(player) and isRunning("bt_core") then exports.bt_core:setRight(player, enabled) end
end

local function setup()
    if not isRunning("work_core") then return end
    local wc = exports.work_core
    wc:registerWork(BTWORK.WORK_ID, {
        name = BTWORK.NAME, description = BTWORK.DESCRIPTION, color = BTWORK.COLOR, skins = BTWORK.SKINS,
        maxLevel = BTWORK.MAX_LEVEL, levelXp = BTWORK.LEVEL_XP, levelStep = BTWORK.LEVEL_STEP,
        levelNames = BTWORK.LEVEL_NAMES,
    })

    local vehicles = {}
    for i, v in ipairs(BTWORK.VEHICLES) do
        vehicles[i] = { model = v.model, name = v.name, color = v.color, data = v.data,
                        tuning = v.tuning, elsExtra = v.elsExtra, sirenType = v.sirenType, paintjob = v.paintjob,
                        platePrefix = BTWORK.PLATE_PREFIX, plateDigits = BTWORK.PLATE_DIGITS }
    end

    for _, st in ipairs(BTWORK.STATIONS) do
        local d = st.duty
        wc:createDutyMarker(BTWORK.WORK_ID, d[1], d[2], d[3], { blip = BTWORK.BLIP })
        if st.vehicle then
            local m = st.vehicle.marker
            wc:createDutyVehicleMarker(BTWORK.WORK_ID, m[1], m[2], m[3], vehicles, { spawns = st.vehicle.spawns })
        end
    end

    -- players already on duty (this resource restarted while work_core kept them)
    for _, player in ipairs(wc:getWorkPlayers(BTWORK.WORK_ID) or {}) do setRight(player, true) end
end

addEventHandler("onResourceStart", resourceRoot, setup)
addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, setup)

-- bt_core does not persist the right: give it back after a bt_core restart
addEvent("onBtCoreStart")
addEventHandler("onBtCoreStart", root, function()
    for player in pairs(Granted) do
        if isElement(player) then exports.bt_core:setRight(player, true) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Granted) do setRight(player, false) end
end)

for _, name in ipairs({ "onPlayerWorkDutyStart", "onPlayerWorkDutyEnd" }) do addEvent(name) end

addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId == BTWORK.WORK_ID then setRight(source, true) end
end)

addEventHandler("onPlayerWorkDutyEnd", root, function(workId)
    if workId == BTWORK.WORK_ID then setRight(source, false) end
end)

addEventHandler("onPlayerQuit", root, function() Granted[source] = nil end)

---------------------------------------------------------------- exports

function isPlayerBloodTransporter(player)
    return isRunning("work_core") and exports.work_core:isPlayerOnDuty(player, BTWORK.WORK_ID) == true
end

function getBloodTransportPlayers()
    if not isRunning("work_core") then return {} end
    return exports.work_core:getWorkPlayers(BTWORK.WORK_ID) or {}
end

function getBloodTransportWorkId()
    return BTWORK.WORK_ID
end
