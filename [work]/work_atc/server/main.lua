-- Air traffic controller work on top of work_core. Going on duty gives ATC rights (avi_core);
-- which of TWR / APP / RADAR depends on the work level (ATC.LEVELS). Off duty removes them.
-- Work XP is given by the aviation system (work_core:giveWorkXp), not here.

local Granted = {}                 -- players this resource handed rights to

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function clampLevel(level)
    return math.min(math.max(1, math.floor(tonumber(level) or 1)), ATC.MAX_LEVEL)
end

local function rightsForLevel(level)
    local set = {}
    for _, r in ipairs(ATC.LEVELS[clampLevel(level)].rights) do set[r] = true end
    return set
end

-- apply (or remove) the rights of a player according to duty and level
local function refresh(player)
    if not isElement(player) or not isRunning("avi_core") then return end
    if Granted[player] then
        local level = isRunning("work_core") and exports.work_core:getPlayerWorkLevel(player, ATC.WORK_ID) or 1
        exports.avi_core:setPlayerATCRights(player, rightsForLevel(level))
    else
        exports.avi_core:setPlayerATCRights(player, false)
    end
end

local function setDuty(player, enabled)
    Granted[player] = enabled and true or nil
    refresh(player)
end

---------------------------------------------------------------- registration

local function setup()
    if not isRunning("work_core") then return end
    local wc = exports.work_core
    local names = {}
    for lv, def in ipairs(ATC.LEVELS) do names[lv] = def.name end
    wc:registerWork(ATC.WORK_ID, {
        name = ATC.NAME,
        description = ATC.DESCRIPTION,
        color = ATC.COLOR,
        skins = ATC.SKINS,
        maxLevel = ATC.MAX_LEVEL,
        levelXp = ATC.LEVEL_BASE_XP,
        levelStep = ATC.LEVEL_STEP_XP,
        levelNames = names,
    })

    for _, st in ipairs(ATC.STATIONS) do
        local d = st.duty
        wc:createDutyMarker(ATC.WORK_ID, d[1], d[2], d[3], { blip = st.blip })
    end

    -- players already on duty (this resource restarted while work_core kept them)
    for _, player in ipairs(wc:getWorkPlayers(ATC.WORK_ID) or {}) do setDuty(player, true) end
end

addEventHandler("onResourceStart", resourceRoot, setup)
addEvent("onWorkCoreStart")
addEventHandler("onWorkCoreStart", root, setup)

-- avi_core does not persist the rights: give them back after an avi_core restart
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "avi_core" then return end
    for player in pairs(Granted) do refresh(player) end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Granted) do setDuty(player, false) end
end)

---------------------------------------------------------------- work_core events

for _, name in ipairs({ "onPlayerWorkDutyStart", "onPlayerWorkDutyEnd", "onPlayerWorkLevelChange" }) do addEvent(name) end

addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    if workId == ATC.WORK_ID then setDuty(source, true) end
end)

addEventHandler("onPlayerWorkDutyEnd", root, function(workId)
    if workId == ATC.WORK_ID then setDuty(source, false) end
end)

-- promotion / demotion while on duty changes the rights at once
addEventHandler("onPlayerWorkLevelChange", root, function(workId)
    if workId == ATC.WORK_ID and Granted[source] then refresh(source) end
end)

addEventHandler("onPlayerQuit", root, function() Granted[source] = nil end)

---------------------------------------------------------------- exports

function isPlayerATC(player)
    return isRunning("work_core") and exports.work_core:isPlayerOnDuty(player, ATC.WORK_ID) == true
end

function getATCPlayers()
    if not isRunning("work_core") then return {} end
    return exports.work_core:getWorkPlayers(ATC.WORK_ID) or {}
end

function getATCWorkId()
    return ATC.WORK_ID
end

-- -> { "TWR", "APP", ... } the rights a work level gives
function getATCLevelRights(level)
    local out = {}
    for _, r in ipairs(ATC.LEVELS[clampLevel(level)].rights) do out[#out + 1] = r end
    return out
end
