if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- work_police: the police work on work_core. Being on duty = holding the police right of police_system
-- (setPoliceRight); everything else (units, MDC, stops, pursuits...) is police_system's. Ranks = work levels
-- (rankBadges: v_nametags shows the rank image next to the work card). Pay and XP come from police_system at the
-- end of a unit (by the submitted reports).

local W = POLICE_WORK
local Granted = {}   -- players this resource gave the right to

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function setRight(player, on)
    if on then Granted[player] = true else Granted[player] = nil end
    if isElement(player) and isRunning("police_system") then
        exports.police_system:setPoliceRight(player, on)
    end
end

local function setup()
    if not isRunning("work_core") then return end
    local wc = exports.work_core
    wc:registerWork(W.WORK_ID, {
        name = W.NAME, description = W.DESCRIPTION, color = W.COLOR, skins = W.SKINS,
        maxLevel = W.MAX_LEVEL, levelXp = W.LEVEL_XP, levelStep = W.LEVEL_STEP, levelNames = W.LEVEL_NAMES,
        rankBadges = true,
    })
    local vehicles = {}
    for i, v in ipairs(W.VEHICLES) do
        vehicles[i] = { model = v.model, name = v.name, tuning = v.tuning, elsExtra = v.elsExtra, sirenType = v.sirenType,
                        paintjob = v.paintjob, level = v.level, platePrefix = W.PLATE_PREFIX, plateDigits = W.PLATE_DIGITS }
    end
    for _, st in ipairs(W.STATIONS) do
        local d = st.duty
        wc:createDutyMarker(W.WORK_ID, d[1], d[2], d[3], { blip = st.blip })
        if st.vehicle then
            local m = st.vehicle.marker
            wc:createDutyVehicleMarker(W.WORK_ID, m[1], m[2], m[3], vehicles, { spawns = st.vehicle.spawns })
        end
    end
    for _, player in ipairs(wc:getWorkPlayers(W.WORK_ID) or {}) do setRight(player, true) end
end

addEventHandler("onResourceStart", resourceRoot, setup)
addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, setup)

-- police_system restarted: the rights are given back
addEvent("onPoliceSystemStart")
addEventHandler("onPoliceSystemStart", root, function()
    for player in pairs(Granted) do
        if isElement(player) then exports.police_system:setPoliceRight(player, true) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Granted) do setRight(player, false) end
end)

for _, name in ipairs({ "onPlayerWorkDutyRequest", "onPlayerWorkDutyStart", "onPlayerWorkDutyEnd" }) do addEvent(name) end

addEventHandler("onPlayerWorkDutyRequest", root, function(workId)
    if workId ~= W.WORK_ID then return end
    local ok, reason = PoliceWorkModules.canGoOnDuty(source)
    if not ok then cancelEvent(true, reason or L.msg("work_police.main.cannot_go_on_duty")) end
end)

addEventHandler("onPlayerWorkDutyStart", root, function(workId, skin)
    if workId ~= W.WORK_ID then return end
    setRight(source, true)
    PoliceWorkModules.fire("onDutyStart", source, skin)
end)

addEventHandler("onPlayerWorkDutyEnd", root, function(workId, reason)
    if workId ~= W.WORK_ID then return end
    setRight(source, false)
    PoliceWorkModules.fire("onDutyEnd", source, reason)
end)

addEventHandler("onPlayerQuit", root, function() Granted[source] = nil end)

-- exports
function isPlayerPolice(player)
    return isRunning("work_core") and exports.work_core:isPlayerOnDuty(player, W.WORK_ID) == true
end

function getPolicePlayers()
    if not isRunning("work_core") then return {} end
    return exports.work_core:getWorkPlayers(W.WORK_ID) or {}
end
