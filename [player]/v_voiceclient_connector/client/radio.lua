-- v_voiceclient_connector / client/radio.lua
-- Radio state of the local player for v_radar and other client resources (replaces the v_voice radio
-- client exports with the same names and return shapes), and the in-game listener: an MTA CEF browser
-- that plays the radio of the player's frequency from the FreeV VoiceServer (listen only, never asks
-- for the microphone, never transmits).
--
-- Client exports:
--   getRadioFrequency() -> freq | false
--   getRadioUnit() -> own unit label | false
--   getRadioState() -> "off" | "keying" | "live"   (own transmission through the external voice client)
--   isRadioTalking() -> own transmission live
--   getRadioSpeaker() -> { player | false, name, unit | false, live } | false   (kept SPEAKER_HOLD_MS after the end)
--   isVoiceListenerActive() -> the in-game CEF listener runs
-- Client events (from the server): v_voiceclient_connector:radioState (freq, unit, external, cef),
--   v_voiceclient_connector:radioSpeaker (speaker), v_voiceclient_connector:radioSelf (state)

local SPEAKER_HOLD_MS = 2500

local myFreq, myUnit, external = false, false, false
local selfState = "off"
local lastSpeaker = nil         -- { player, name, unit, live, frequency, endedAt }

------------------------------------------------------------------------ in-game listener (CEF)

local listener = { browser = nil, url = nil, username = nil, allowed = nil, volume = 1 }

local function hostOf(url)
    return url and url:match("^https?://([^/:]+)")
end

local function destroyListener()
    if isElement(listener.browser) then destroyElement(listener.browser) end
    listener.browser = nil
end

local function listenerUrl()
    return listener.url .. "/?embed=1&client=mta_cef&username=" .. listener.username
end

local function startListener()
    if isElement(listener.browser) or not listener.url or not listener.username then return end
    local browser = createBrowser(1, 1, false, false)   -- remote page, never drawn: audio only
    if not browser then
        outputDebugString("[voice] createBrowser failed: the in-game radio listener is off (CEF disabled?)", 2)
        return
    end
    listener.browser = browser
    addEventHandler("onClientBrowserCreated", browser, function()
        setBrowserVolume(browser, listener.volume)
        local host = hostOf(listener.url)
        requestBrowserDomains({ host }, true, function(accepted)
            listener.allowed = accepted
            if not accepted then
                outputDebugString("[voice] the VoiceServer domain was not allowed: no in-game radio audio", 2)
                return
            end
            if isElement(browser) then loadBrowserURL(browser, listenerUrl()) end
        end)
    end)
end

------------------------------------------------------------------------ server events

addEvent("v_voiceclient_connector:radioState", true)
addEventHandler("v_voiceclient_connector:radioState", resourceRoot, function(freq, unit, ext, cef)
    if freq ~= myFreq and lastSpeaker and lastSpeaker.frequency ~= freq then lastSpeaker = nil end
    myFreq, myUnit, external = freq or false, unit or false, ext or false
    if type(cef) == "table" and cef.url and cef.username then
        local changed = listener.url ~= cef.url or listener.username ~= cef.username
        listener.url, listener.username = cef.url, cef.username
        listener.volume = tonumber(cef.volume) or 1
        if changed then destroyListener() end
        -- the listener only matters while the player is on a frequency; the VoiceServer gets the
        -- frequency from MTA, so the page itself never chooses one
        if myFreq then startListener() end
    else
        destroyListener()
    end
end)

addEvent("v_voiceclient_connector:radioSpeaker", true)
addEventHandler("v_voiceclient_connector:radioSpeaker", resourceRoot, function(s)
    if type(s) ~= "table" then return end
    if s.live == false and lastSpeaker and lastSpeaker.username == s.username then
        lastSpeaker.live = false
        lastSpeaker.endedAt = getTickCount()
        return
    end
    lastSpeaker = { player = s.player, name = s.name, unit = s.unit, live = s.live == true, frequency = s.frequency,
        username = s.username, endedAt = (s.live == false) and getTickCount() or nil }
end)

addEvent("v_voiceclient_connector:radioSelf", true)
addEventHandler("v_voiceclient_connector:radioSelf", resourceRoot, function(state)
    selfState = (state == "keying" or state == "live") and state or "off"
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("v_voiceclient_connector:radioRequest", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, destroyListener)

------------------------------------------------------------------------ exports

function getRadioFrequency()
    return myFreq
end

function getRadioUnit()
    return myUnit
end

function getRadioState()
    return myFreq and selfState or "off"
end

function isRadioTalking()
    return selfState == "live"
end

function getRadioSpeaker()
    local s = lastSpeaker
    if not s or s.frequency ~= myFreq then return false end
    if not s.live and s.endedAt and getTickCount() - s.endedAt > SPEAKER_HOLD_MS then return false end
    return { player = isElement(s.player) and s.player or false, name = s.name, unit = s.unit or false, live = s.live }
end

function isVoiceListenerActive()
    return isElement(listener.browser) and listener.allowed == true
end

function isVoiceClientExternal()
    return external
end
