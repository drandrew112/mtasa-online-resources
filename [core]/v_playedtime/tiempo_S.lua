------------------------------------------------------------------------------------
--  Played-time tracker.
--  Online.minutes / Online.hours are stored in the shared `accounts` table
--  (exports.v_mysql:getAccData / setAccData), keyed by the player element.
--  "Játékidő" element data is the formatted "Hh Mm" string for the HUD.
------------------------------------------------------------------------------------

local function getData(player, key) return exports.v_mysql:getAccData(player, key) end
local function setData(player, key, value) return exports.v_mysql:setAccData(player, key, value) end

local function isLogged(player)
    return isElement(player) and getElementData(player, "isLogged") == true
end

local function pad2(v)
    v = tostring(tonumber(v) or 0)
    if #v == 1 then return "0" .. v end
    return v
end

-- (Re)starts the minute tick for a player and refreshes their HUD string.
local function beginTracking(player)
    if not isLogged(player) then
        setElementData(player, "Játékidő", "N/A")
        return
    end

    local minutes = getData(player, "Online.minutes")
    if minutes == nil then
        setData(player, "Online.minutes", 0)
        setData(player, "Online.hours", 0)
        minutes = 0
    end
    local hours = getData(player, "Online.hours") or 0

    setElementData(player, "Játékidő", pad2(hours) .. "h " .. pad2(minutes) .. "m")

    local existing = getElementData(player, "Online.timer")
    if isTimer(existing) then killTimer(existing) end
    setElementData(player, "Online.timer", setTimer(actualizarJugadorOn, 60000, 1, player))
end

local function stopTracking(player)
    local timer = getElementData(player, "Online.timer")
    if isTimer(timer) then killTimer(timer) end
end

function actualizarJugadorOn(player)
    if not isElement(player) or not isLogged(player) then return end

    local minutes = (tonumber(getData(player, "Online.minutes")) or 0) + 1
    local hours   = tonumber(getData(player, "Online.hours")) or 0
    if minutes >= 60 then
        hours = hours + 1
        minutes = 0
        call(getResourceFromName("v_levelsys"), "giveXp", player, 800)
    end

    setData(player, "Online.minutes", minutes)
    setData(player, "Online.hours", hours)

    setElementData(player, "Játékidő", pad2(hours) .. "h " .. pad2(minutes) .. "m")
    setElementData(player, "Online.timer", setTimer(actualizarJugadorOn, 60000, 1, player))
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        beginTracking(player)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        stopTracking(player)
    end
end)

-- onPlayerLoaded: source = player, arg 1 = account-name string.
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    beginTracking(source)
end)

addEventHandler("onPlayerJoin", root, function()
    setElementData(source, "Játékidő", "N/A")
end)

addEventHandler("onPlayerQuit", root, function()
    stopTracking(source)
end)
