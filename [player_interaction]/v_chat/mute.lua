-- ============================================================
--  v_chat / mute.lua  (server)
--  Chat mute. Blocks outgoing chat messages while active; the
--  player is told through an ui_core Alert (chat is disabled for
--  them). Duration is in minutes, there is no /unmute – a mute
--  ends on its own. Mutes survive relog / a resource restart
--  (stored in account data).
--
--  Element data:  mute_until (epoch), mute_reason, mute_admin
--  Account data:  same keys, in the shared `accounts` table
--                 (exports.v_mysql:getAccData / setAccData, keyed by player)
-- ============================================================

local CHECK_INTERVAL = 5000  -- expiry sweep, ms

local function getData(player, key) return exports.v_mysql:getAccData(player, key) end
local function setData(player, key, value) return exports.v_mysql:setAccData(player, key, value) end

local function isLogged(player)
    return isElement(player) and getElementData(player, "isLogged") == true
end

-- Players we have already seen muted, so the "mute expired" alert fires once.
local seenMuted = {}

local function now()
    return getRealTime().timestamp
end

local function formatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then return m .. "m " .. s .. "s" end
    return s .. "s"
end

local function alert(player, text, r, g, b, duration)
    triggerClientEvent(player, "chat:muteAlert", player, text, r, g, b, duration)
end

local function clearMuteData(player)
    for _, key in ipairs({ "mute_until", "mute_reason", "mute_admin" }) do
        setElementData(player, key, false)
        if isLogged(player) then
            setData(player, key, false)
        end
    end
end

-- Seconds left on the player's mute (0 when not muted).
function getMuteRemaining(player)
    if not isElement(player) then return 0 end

    local until_ = tonumber(getElementData(player, "mute_until"))
    if not until_ and isLogged(player) then
        until_ = tonumber(getData(player, "mute_until"))
    end
    if not until_ then return 0 end

    local left = until_ - now()
    return left > 0 and left or 0
end

-- NOTE: named isChatMuted, not isPlayerMuted – the latter is a built-in MTA
-- function and shadowing it resource-wide is asking for trouble.
function isChatMuted(player)
    return getMuteRemaining(player) > 0
end

-- Called by v_chat's send handler when a muted player tries to talk.
function notifyMuteBlocked(player)
    alert(player, "You are muted! Time left: " .. formatDuration(getMuteRemaining(player)), 255, 90, 90, 4000)
end

-- ------------------------------------------------------------
--  mutePlayer(player, minutes, reason, admin_name)  – exported
--  Returns true, or false + an error string.
-- ------------------------------------------------------------
function mutePlayer(player, minutes, reason, adminName)
    if not isElement(player) or getElementType(player) ~= "player" then
        return false, "Invalid player"
    end

    minutes = tonumber(minutes)
    if not minutes or minutes <= 0 then
        return false, "Invalid duration"
    end
    minutes = math.floor(minutes)

    reason    = (type(reason) == "string"    and reason    ~= "") and reason    or "No reason given"
    adminName = (type(adminName) == "string" and adminName ~= "") and adminName or "Console"

    local until_ = now() + minutes * 60
    setElementData(player, "mute_until", until_)
    setElementData(player, "mute_reason", reason)
    setElementData(player, "mute_admin", adminName)

    if isLogged(player) then
        setData(player, "mute_until", until_)
        setData(player, "mute_reason", reason)
        setData(player, "mute_admin", adminName)
    end

    seenMuted[player] = true
    alert(player, ("Muted by %s (%d min) for %s"):format(adminName, minutes, reason), 255, 170, 60, 7000)

    outputServerLog(("[v_chat] %s muted %s for %d min (%s)"):format(adminName, getPlayerName(player), minutes, reason))
    return true
end

-- ------------------------------------------------------------
--  Restore a mute once the player is loaded (or drop it if it
--  lapsed offline). onPlayerLoaded fires after the shared MySQL
--  account-data sync, so mute_until is up to date.
-- ------------------------------------------------------------
addEvent("onPlayerLoaded")
addEventHandler("onPlayerLoaded", root, function()
    if not isLogged(source) then return end

    local until_ = tonumber(getData(source, "mute_until"))
    if not until_ then return end

    if until_ > now() then
        setElementData(source, "mute_until", until_)
        setElementData(source, "mute_reason", getData(source, "mute_reason") or "No reason given")
        setElementData(source, "mute_admin", getData(source, "mute_admin") or "Console")
        seenMuted[source] = true
    else
        for _, key in ipairs({ "mute_until", "mute_reason", "mute_admin" }) do
            setData(source, key, false)
        end
    end
end)

-- ------------------------------------------------------------
--  Expiry sweep – fire the "mute expired" alert once.
-- ------------------------------------------------------------
setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do
        if isChatMuted(player) then
            seenMuted[player] = true
        elseif seenMuted[player] then
            seenMuted[player] = nil
            clearMuteData(player)
            alert(player, "Your mute has expired, you can use the chat again.", 85, 255, 85, 5000)
        end
    end
end, CHECK_INTERVAL, 0)

addEventHandler("onPlayerQuit", root, function()
    seenMuted[source] = nil
end)
