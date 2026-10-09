-- Train driver work on top of work_core. Being on duty = holding the rw_core railway role
-- ("vasutas jog"); trains are spawned and driven through the rw_* resources.

local Granted = {}                 -- players this resource gave the railway role to

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function setRailway(player, enabled)
    if enabled then Granted[player] = true else Granted[player] = nil end
    if isElement(player) and isRunning("rw_core") then
        exports.rw_core:setPlayerRailway(player, enabled)
    end
end

---------------------------------------------------------------- registration

local function setup()
    if not isRunning("work_core") then return end
    local wc = exports.work_core
    wc:registerWork(TRAINDRIVER.WORK_ID, {
        name = TRAINDRIVER.NAME,
        description = TRAINDRIVER.DESCRIPTION,
        color = TRAINDRIVER.COLOR,
        skins = TRAINDRIVER.SKINS,
    })

    for _, st in ipairs(TRAINDRIVER.STATIONS) do
        local d = st.duty
        wc:createDutyMarker(TRAINDRIVER.WORK_ID, d[1], d[2], d[3], { blip = st.blip })
    end

    -- players already on duty (this resource restarted while work_core kept them)
    for _, player in ipairs(wc:getWorkPlayers(TRAINDRIVER.WORK_ID) or {}) do setRailway(player, true) end
end

addEventHandler("onResourceStart", resourceRoot, setup)
addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, setup)

-- rw_core does not persist the role: give it back after an rw_core restart
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "rw_core" then return end
    for player in pairs(Granted) do
        if isElement(player) then exports.rw_core:setPlayerRailway(player, true) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Granted) do setRailway(player, false) end
end)

---------------------------------------------------------------- work_core events

for _, name in ipairs({ "onPlayerWorkDutyStart", "onPlayerWorkDutyEnd" }) do addEvent(name) end

addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId ~= TRAINDRIVER.WORK_ID then return end
    setRailway(source, true)
    if isRunning("v_achievements") then
        exports.v_achievements:unlockAchievement(source, "train_duty")
    end
end)

addEventHandler("onPlayerWorkDutyEnd", root, function(workId)
    if workId == TRAINDRIVER.WORK_ID then setRailway(source, false) end
end)

addEventHandler("onPlayerQuit", root, function() Granted[source] = nil end)

---------------------------------------------------------------- exports

function isPlayerTrainDriver(player)
    return isRunning("work_core") and exports.work_core:isPlayerOnDuty(player, TRAINDRIVER.WORK_ID) == true
end

function getTrainDriverPlayers()
    if not isRunning("work_core") then return {} end
    return exports.work_core:getWorkPlayers(TRAINDRIVER.WORK_ID) or {}
end

function getTrainDriverWorkId()
    return TRAINDRIVER.WORK_ID
end
