------------------------------------------------------------------------------------
--  Played-time tracker.
--
--  Storage : `Online.hours` / `Online.minutes` in the shared `accounts` table
--            (exports.v_mysql:getAccData / setAccData). These keys are also read
--            by v_socialpanel for offline players - do not rename them.
--  HUD     : "Játékidő" element data is the formatted "HHh MMm" string read by
--            ui_inac, ui_pause, v_socialpanel and v_admin - do not rename it.
--
--  One global timer ticks every minute and walks the tracked players. Nothing
--  is kept in element data, so clients never see (or overwrite) timer handles.
------------------------------------------------------------------------------------

local TICK_MS        = 60000
local XP_PER_HOUR    = 800
local KEY_HOURS      = "Online.hours"
local KEY_MINUTES    = "Online.minutes"
local KEY_HUD        = "Játékidő"
local HUD_UNKNOWN    = "N/A"

local tracked   = {}    -- tracked[player] = true while logged in
local tickTimer         -- the single global timer, only alive while someone is tracked

local function isLogged(player)
    return isElement(player) and getElementData(player, "isLogged") == true
end

local function formatPlaytime(hours, minutes)
    return ("%02dh %02dm"):format(hours, minutes)
end

local function readPlaytime(player)
    local hours   = tonumber(exports.v_mysql:getAccData(player, KEY_HOURS)) or 0
    local minutes = tonumber(exports.v_mysql:getAccData(player, KEY_MINUTES)) or 0
    return hours, minutes
end

local function updateHud(player, hours, minutes)
    setElementData(player, KEY_HUD, formatPlaytime(hours, minutes))
end

-- Adds one minute to a player, rolls minutes into hours, saves both in one write.
local function addMinute(player)
    local hours, minutes = readPlaytime(player)
    minutes = minutes + 1

    local hourCompleted = minutes >= 60
    if hourCompleted then
        hours   = hours + 1
        minutes = 0
    end

    exports.v_mysql:setAccData(player, { [KEY_HOURS] = hours, [KEY_MINUTES] = minutes })
    updateHud(player, hours, minutes)

    if hourCompleted then
        exports.v_levelsys:giveXp(player, XP_PER_HOUR)
    end
end

local function onTick()
    for player in pairs(tracked) do
        if isLogged(player) then
            addMinute(player)
        else
            tracked[player] = nil
        end
    end
end

local function ensureTimer()
    if not isTimer(tickTimer) then
        tickTimer = setTimer(onTick, TICK_MS, 0)
    end
end

local function stopTracking(player)
    tracked[player] = nil
    if isTimer(tickTimer) and next(tracked) == nil then
        killTimer(tickTimer)
        tickTimer = nil
    end
end

local function beginTracking(player)
    if not isLogged(player) then
        setElementData(player, KEY_HUD, HUD_UNKNOWN)
        return
    end

    -- First login ever: create both values together so they are never half-set.
    if exports.v_mysql:getAccData(player, KEY_MINUTES) == nil then
        exports.v_mysql:setAccData(player, { [KEY_HOURS] = 0, [KEY_MINUTES] = 0 })
    end

    updateHud(player, readPlaytime(player))
    tracked[player] = true
    ensureTimer()
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        beginTracking(player)
    end
end)

-- onPlayerLoaded: source = player, arg 1 = account-name string.
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    beginTracking(source)
end)

addEventHandler("onPlayerJoin", root, function()
    setElementData(source, KEY_HUD, HUD_UNKNOWN)
end)

addEventHandler("onPlayerQuit", root, function()
    stopTracking(source)
end)
