local roles = {
    [0] = "PLAYER",
    [1] = "TRIAL MOD",
    [2] = "MOD",
    [3] = "ADMIN",
    [4] = "SUPERADMIN",
    [5] = "DEV",
    [6] = "OWNER",
}

local APP_ID          = "998373153950670999"
local UPDATE_INTERVAL = 20000 -- Discord rate limits updates, don't go much lower
local DEBOUNCE        = 1500

-- Used when no button override is set through setDiscordButton
local DEFAULT_BUTTONS = {
    [1] = { "Join", "mtasa://212.73.137.3:22203" },
}

-- Runtime state. `override.*` values set through the exports win over the
-- automatic templates until cleared (nil / empty string).
local override = {}
local settings = {
    showLocation = true,
    showParty    = true,
}
local server = { players = nil, max = nil }
local updateTimer, debounceTimer

local function ed(key, default)
    local v = getElementData(localPlayer, key)
    if v == nil or v == false or v == "" then return default end
    return v
end

local function stripColors(s)
    return (tostring(s):gsub("#%x%x%x%x%x%x", ""))
end

local function playerName()
    -- the account name is applied as the native player name by acc_auth
    return stripColors(getPlayerName(localPlayer))
end

local function locationText()
    local x, y, z = getElementPosition(localPlayer)
    local zone = getZoneName(x, y, z, false)
    local city = getZoneName(x, y, z, true)
    if zone == city or city == "Unknown" then return zone end
    return zone .. ", " .. city
end

local function buildDetails()
    if override.details then return override.details end
    local lvl  = ed("level", "?")
    local role = roles[tonumber(ed("admin_level", 0)) or 0]
    local name = playerName()
    -- role only next to the name, and only for staff
    if role and role ~= roles[0] then name = name .. " [" .. role .. "]" end
    return name .. " | lvl " .. tostring(lvl)
end

local function buildState()
    if override.state then return override.state end
    if settings.showLocation then return locationText() end
    return "San Andreas"
end

local function applyAll()
    if not isDiscordRichPresenceConnected() then return end
    setDiscordRichPresenceDetails(buildDetails())
    setDiscordRichPresenceState(buildState())

    local a = override.asset or { "freev", "MTA:SA" }
    setDiscordRichPresenceAsset(a[1], a[2] or "")
    if override.smallAsset then
        setDiscordRichPresenceSmallAsset(override.smallAsset[1], override.smallAsset[2] or "")
    end
    for i = 1, 2 do
        local b = (override.buttons and override.buttons[i]) or DEFAULT_BUTTONS[i]
        if b then setDiscordRichPresenceButton(i, b[1], b[2]) end
    end
    -- no elapsed timer by default, only when set through setDiscordStartTime
    if override.startTime then setDiscordRichPresenceStartTime(override.startTime) end

    if override.party then
        setDiscordRichPresencePartySize(override.party[1], override.party[2])
    elseif settings.showParty and server.players and server.max then
        setDiscordRichPresencePartySize(server.players, server.max)
    end
end

-- Coalesces bursts of changes (level up, element data spam) into one update
local function requestUpdate()
    if isTimer(debounceTimer) then return end
    debounceTimer = setTimer(applyAll, DEBOUNCE, 1)
end

local function connect()
    setDiscordApplicationID(APP_ID)
    if not isDiscordRichPresenceConnected() then
        outputConsole("RPC: Discord RPC failed to connect")
        return
    end
    outputConsole("RPC: Discord RPC is now connected")
    if isTimer(updateTimer) then killTimer(updateTimer) end
    updateTimer = setTimer(applyAll, UPDATE_INTERVAL, 0)
    triggerServerEvent("discord:requestServerInfo", resourceRoot)
    applyAll()
end
addEventHandler("onClientResourceStart", resourceRoot, connect)

--// Reset the rpc details so the status will not be bugged
addEventHandler("onClientResourceStop", resourceRoot, function()
    if isTimer(updateTimer) then killTimer(updateTimer) end
    resetDiscordRichPresenceData()
end)

addEvent("discord:serverInfo", true)
addEventHandler("discord:serverInfo", resourceRoot, function(players, max)
    server.players, server.max = players, max
    requestUpdate()
end)

-- Refresh when relevant data of the local player changes
local watched = { level = true, admin_level = true }
addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if watched[key] then requestUpdate() end
end)

---------------------------------------------------------------------
-- Exports: change presence elements from other resources.
-- Pass nil / "" to clear a single override and fall back to the template.
---------------------------------------------------------------------
local function str(v)
    if v == nil or v == "" then return nil end
    return tostring(v)
end

function setDiscordDetails(text)
    override.details = str(text); requestUpdate(); return true
end

function setDiscordState(text)
    override.state = str(text); requestUpdate(); return true
end

function setDiscordAsset(name, hover)
    override.asset = str(name) and { tostring(name), tostring(hover or "") } or nil
    requestUpdate(); return true
end

function setDiscordSmallAsset(name, hover)
    override.smallAsset = str(name) and { tostring(name), tostring(hover or "") } or nil
    requestUpdate(); return true
end

function setDiscordButton(index, label, url)
    index = tonumber(index)
    if index ~= 1 and index ~= 2 then return false end
    override.buttons = override.buttons or {}
    override.buttons[index] = (str(label) and str(url)) and { label, url } or nil
    requestUpdate(); return true
end

-- current/max; call with no arguments to return to the server player count
function setDiscordPartySize(current, max)
    current, max = tonumber(current), tonumber(max)
    override.party = (current and max) and { current, max } or nil
    requestUpdate(); return true
end

-- seconds ago the "elapsed" timer started
function setDiscordStartTime(secondsAgo)
    override.startTime = tonumber(secondsAgo)
    requestUpdate(); return true
end

function setDiscordShowLocation(state)
    settings.showLocation = state and true or false
    requestUpdate(); return true
end

function setDiscordShowParty(state)
    settings.showParty = state and true or false
    requestUpdate(); return true
end

function resetDiscordOverrides()
    override = {}
    requestUpdate(); return true
end

function forceDiscordUpdate()
    applyAll(); return true
end

function getDiscordPresence()
    return buildDetails(), buildState()
end


addEvent("v_discordmanager:copyInvite", true)
addEventHandler("v_discordmanager:copyInvite", resourceRoot, function(url)
    if setClipboard(url) then
        exports.ui_core:setAlert("Discord invite copied to the clipboard: " .. url, 114, 137, 218, 4000)
    end
end)
