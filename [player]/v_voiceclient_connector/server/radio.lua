-- v_voiceclient_connector / server/radio.lua
-- Radio frequency of the players (moved here from v_voice radio/agencies.lua). The audio itself goes
-- through the FreeV VoiceServer (Cloudflare Realtime): this module only decides who is on which
-- frequency, with which unit callsign, and tells the clients (v_radar, in-game listener).
--
--   on duty (work_core) in a radio work -> VC.VOICESERVER.FREQ[work] (ems 140, police 170)
--   unit callsign: EMS med_erm getUnitData(player).callsign, police police_system getOfficerUnit(player)
--   off duty / quit -> no frequency
--   setPlayerRadioFrequency(player, freq) from other resources overrides the work frequency until
--   cleared (false) or the duty ends.
--
-- Server exports (same names / shapes as the old v_voice radio, see meta.xml):
--   getPlayerRadioFrequency(player) -> freq | false
--   setPlayerRadioFrequency(player, freq | false) -> true | false, error
--   getPlayerRadioUnit(player) -> label | false
--   getRadioFrequencyPlayers(freq) -> { player, ... }
-- Events: onVoiceRadioFrequencyChange (source = player; newFreq | false, oldFreq | false)

Radio = {
    freqOf = {},     -- [player] = effective frequency
    unitOf = {},     -- [player] = unit label ("EMS M-12") | nil
    workOf = {},     -- [player] = work id the frequency came from
    manual = {},     -- [player] = frequency set through setPlayerRadioFrequency
}

addEvent("onVoiceRadioFrequencyChange", false)

local CFG = VC.VOICESERVER

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

function Radio.validFreq(freq)
    freq = tonumber(freq)
    if not freq or freq ~= math.floor(freq) or freq < CFG.FREQ_MIN or freq > CFG.FREQ_MAX then return nil end
    return freq
end

function Radio.account(player)
    if not isElement(player) or not running("v_accounts") then return nil end
    local ok, acc = pcall(function() return exports.v_accounts:getName(player) end)
    return ok and type(acc) == "string" and acc ~= "" and acc or nil
end

local function onDutyWork(player)
    if not running("work_core") then return nil end
    local ok, work = pcall(function() return exports.work_core:getPlayerWork(player) end)
    if not ok or not work then return nil end
    local ok2, duty = pcall(function() return exports.work_core:isPlayerOnDuty(player, work) end)
    if ok2 and duty then return work end
    return nil
end

local function unitCallsign(work, player)
    local ok, cs = false, nil
    if work == "ems" and running("med_erm") then
        ok, cs = pcall(function()
            local u = exports.med_erm:getUnitData(player)
            return u and u.callsign
        end)
    elseif work == "police" and running("police_system") then
        ok, cs = pcall(function() return exports.police_system:getOfficerUnit(player) end)
    end
    if ok and cs and cs ~= "" then return tostring(cs) end
    return nil
end

-- recomputes one player's frequency / unit; tells the client and fires the change event
function Radio.update(player)
    if not isElement(player) then return end
    local work = onDutyWork(player)
    local workFreq = work and CFG.FREQ[work] or nil

    -- a duty change drops the manual override
    if Radio.workOf[player] ~= work then Radio.manual[player] = nil end
    Radio.workOf[player] = work

    local freq = Radio.manual[player] or workFreq or nil
    local unit = nil
    if work and CFG.FREQ[work] then
        local cs = unitCallsign(work, player)
        local tag = CFG.UNIT_TAG[work]
        unit = cs and (tag and (tag .. " " .. cs) or cs) or tag
    end

    local old = Radio.freqOf[player]
    local unitChanged = Radio.unitOf[player] ~= unit
    Radio.freqOf[player] = freq
    Radio.unitOf[player] = unit
    if old ~= freq then
        triggerEvent("onVoiceRadioFrequencyChange", player, freq or false, old or false)
    end
    if old ~= freq or unitChanged then
        Radio.sendState(player)
        if VoiceServer then VoiceServer.dirty = true end
    end
end

-- client state: frequency, unit, external client, CEF listener settings
function Radio.sendState(player)
    if not isElement(player) then return end
    local acc = Radio.account(player)
    local cef = false
    if acc and CFG.CEF.ENABLED then
        cef = { url = CFG.URL, username = acc, volume = CFG.CEF.VOLUME }
    end
    triggerClientEvent(player, "v_voiceclient_connector:radioState", resourceRoot,
        Radio.freqOf[player] or false, Radio.unitOf[player] or false,
        VoiceServer and VoiceServer.externalOf(player) or false, cef)
end

local pending = {}
function Radio.updateSoon(player)
    if pending[player] then return end
    pending[player] = true
    setTimer(function()
        pending[player] = nil
        Radio.update(player)
    end, 100, 1)
end

local function updateAll()
    for _, p in ipairs(getElementsByType("player")) do Radio.update(p) end
end

addEventHandler("onResourceStart", resourceRoot, function()
    updateAll()
    setTimer(updateAll, CFG.ASSIGN_MS, 0)
end)

addEventHandler("onPlayerQuit", root, function()
    local old = Radio.freqOf[source]
    Radio.freqOf[source], Radio.unitOf[source], Radio.workOf[source], Radio.manual[source] = nil, nil, nil, nil
    pending[source] = nil
    if old then triggerEvent("onVoiceRadioFrequencyChange", source, false, old) end
    if VoiceServer then VoiceServer.dirty = true end
end)

addEventHandler("onElementDataChange", root, function(key)
    if key == "work.id" and getElementType(source) == "player" then Radio.updateSoon(source) end
end)

-- work_core / med_erm events (fine when those resources are not running: the handlers never fire)
addEvent("onPlayerWorkDutyStart")
addEvent("onPlayerWorkDutyEnd")
addEventHandler("onPlayerWorkDutyStart", root, function() Radio.updateSoon(source) end)
addEventHandler("onPlayerWorkDutyEnd", root, function() Radio.updateSoon(source) end)
addEvent("onErmUnitSignIn")
addEvent("onErmUnitSignOut")
local function refreshEms()
    for _, p in ipairs(getElementsByType("player")) do
        if Radio.workOf[p] == "ems" then Radio.updateSoon(p) end
    end
end
addEventHandler("onErmUnitSignIn", root, refreshEms)
addEventHandler("onErmUnitSignOut", root, refreshEms)

-- the client asks for its state after its scripts loaded
addEvent("v_voiceclient_connector:radioRequest", true)
addEventHandler("v_voiceclient_connector:radioRequest", resourceRoot, function()
    if client then Radio.sendState(client) end
end)

------------------------------------------------------------------------ exports

function getPlayerRadioFrequency(player)
    return Radio.freqOf[player] or false
end

-- setPlayerRadioFrequency(player, freq | false) -> true | false, "out_of_range" / "bad_player"
function setPlayerRadioFrequency(player, freq)
    if not isElement(player) or getElementType(player) ~= "player" then return false, "bad_player" end
    if freq == false or freq == nil then
        Radio.manual[player] = nil
    else
        local f = Radio.validFreq(freq)
        if not f then return false, "out_of_range" end
        Radio.manual[player] = f
    end
    Radio.update(player)
    return true
end

function getPlayerRadioUnit(player)
    return Radio.unitOf[player] or false
end

function getRadioFrequencyPlayers(freq)
    freq = Radio.validFreq(freq)
    local list = {}
    if not freq then return list end
    for p, f in pairs(Radio.freqOf) do
        if f == freq and isElement(p) then list[#list + 1] = p end
    end
    return list
end
