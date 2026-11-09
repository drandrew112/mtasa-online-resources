-- Radio, server side. Every player can be on one frequency (set by other resources through the
-- exports below). Holding RADIO.KEY keys the radio: the listeners on the frequency hear the intro
-- sound first, and only when it has finished does the server add them to the speaker's voice
-- broadcast list (server.lua buildListeners -> Radio.addListeners). Releasing the key ends the
-- transmission: listeners hear the outro.
--
-- Timing: the speaker's key press reaches the server, the server sends "intro" to the listeners
-- and starts a RADIO.INTRO_MS timer. Both the intro event and the voice packets travel the same
-- server -> listener path, so the voice arrives right when the intro ends on the listener's side.

Radio = {}

local freqOf = {}     -- [player] = frequency number
local unitOf = {}     -- [player] = unit label ("EMS M-12") or nil
local tx = {}         -- [player] = { freq, live, timer, started } while keyed

local function normFreq(freq)
	freq = tonumber(freq)
	if not freq or freq <= 0 then return nil end
	return math.floor(freq * 100 + 0.5) / 100
end

local function isMuted(player)
	if not VOICE.BLOCK_MUTED then return false end
	local until_ = tonumber(getElementData(player, "mute_until"))
	return until_ ~= nil and until_ > getRealTime().timestamp
end

local function displayName(player)
	local name = getElementData(player, "displayName")
	if type(name) ~= "string" or name == "" then name = getPlayerName(player) end
	return (name:gsub("#%x%x%x%x%x%x", ""))
end

-- players on a frequency, without `except`
local function membersOf(freq, except)
	local list = {}
	for p, f in pairs(freqOf) do
		if f == freq and p ~= except and isElement(p) then list[#list + 1] = p end
	end
	return list
end

local function sendState(player)
	triggerClientEvent(player, "v_voice:radioState", resourceRoot, freqOf[player] or false, unitOf[player] or false)
end

local function speakerInfo(player, freq)
	return { name = displayName(player), unit = unitOf[player] or false, freq = freq }
end

-- server.lua: add the live radio listeners to a speaker's broadcast set
function Radio.addListeners(player, set)
	local t = tx[player]
	if not t or not t.live then return end
	for _, p in ipairs(membersOf(t.freq, player)) do set[p] = true end
end

local function goLive(player)
	local t = tx[player]
	if not t then return end
	t.timer = nil
	t.live = true
	refreshVoiceListeners(player)
	local info = speakerInfo(player, t.freq)
	triggerClientEvent(membersOf(t.freq, player), "v_voice:radioLive", resourceRoot, player, info)
	triggerClientEvent(player, "v_voice:radioSelf", resourceRoot, "live")
end

local function stopTx(player, reason)
	local t = tx[player]
	if not t then return end
	tx[player] = nil
	if t.timer and isTimer(t.timer) then killTimer(t.timer) end
	if isElement(player) then
		refreshVoiceListeners(player)
		triggerClientEvent(player, "v_voice:radioSelf", resourceRoot, "off")
	end
	local listeners = membersOf(t.freq, player)
	if #listeners > 0 then
		triggerClientEvent(listeners, "v_voice:radioEnd", resourceRoot, player, t.live, reason or "release")
	end
end

local function startTx(player)
	local freq = freqOf[player]
	if not freq or tx[player] or isMuted(player) then return end
	tx[player] = { freq = freq, live = false, started = getTickCount() }
	local listeners = membersOf(freq, player)
	if #listeners > 0 then
		triggerClientEvent(listeners, "v_voice:radioIntro", resourceRoot, player, speakerInfo(player, freq))
	end
	triggerClientEvent(player, "v_voice:radioSelf", resourceRoot, "keying")
	tx[player].timer = setTimer(goLive, RADIO.INTRO_MS, 1, player)
end

addEvent("v_voice:radioKey", true)
addEventHandler("v_voice:radioKey", resourceRoot, function(down)
	local player = client
	if not player then return end
	if down then startTx(player) else stopTx(player, "release") end
end)

addEvent("v_voice:radioRequest", true)
addEventHandler("v_voice:radioRequest", resourceRoot, function()
	if client then sendState(client) end
end)

-- a player who joins the frequency mid-transmission starts hearing it at once
local function joinRunning(player, freq)
	for speaker, t in pairs(tx) do
		if t.freq == freq and speaker ~= player and isElement(speaker) then
			if t.live then
				refreshVoiceListeners(speaker)
				triggerClientEvent(player, "v_voice:radioLive", resourceRoot, speaker, speakerInfo(speaker, freq))
			end
		end
	end
end

local function leaveRunning(player, freq)
	for speaker, t in pairs(tx) do
		if t.freq == freq and speaker ~= player and isElement(speaker) then
			refreshVoiceListeners(speaker)
			triggerClientEvent(player, "v_voice:radioEnd", resourceRoot, speaker, false, "left")
		end
	end
end

addEventHandler("onPlayerQuit", root, function()
	stopTx(source, "quit")
	freqOf[source] = nil
	unitOf[source] = nil
end)

addEventHandler("onPlayerWasted", root, function()
	stopTx(source, "wasted")
end)

addEventHandler("onResourceStop", resourceRoot, function()
	for p in pairs(tx) do
		if isElement(p) then stopTx(p, "stop") end
	end
end)

------------------------------------------------------------------------ exports

-- setPlayerRadioFrequency(player, freq | false) -> true | false
function setPlayerRadioFrequency(player, freq)
	if not isElement(player) or getElementType(player) ~= "player" then return false end
	freq = freq and normFreq(freq) or nil
	local old = freqOf[player]
	if old == freq then return true end
	if tx[player] then stopTx(player, "frequency") end
	if old then leaveRunning(player, old) end
	freqOf[player] = freq
	sendState(player)
	if freq then joinRunning(player, freq) end
	return true
end

function getPlayerRadioFrequency(player)
	return freqOf[player] or false
end

-- setPlayerRadioUnit(player, label | false): the unit shown next to the speaker's name on the radar
function setPlayerRadioUnit(player, label)
	if not isElement(player) then return false end
	label = (type(label) == "string" and label ~= "") and label or nil
	if unitOf[player] == label then return true end
	unitOf[player] = label
	sendState(player)
	return true
end

function getPlayerRadioUnit(player)
	return unitOf[player] or false
end

-- getRadioFrequencyPlayers(freq) -> { player, ... }
function getRadioFrequencyPlayers(freq)
	freq = normFreq(freq)
	if not freq then return {} end
	return membersOf(freq)
end

-- true while the player's transmission is live (after the intro)
function isPlayerRadioTalking(player)
	return tx[player] ~= nil and tx[player].live == true
end

-- getRadioSpeakers(freq) -> { player, ... } currently keyed on the frequency
function getRadioSpeakers(freq)
	freq = normFreq(freq)
	local list = {}
	for p, t in pairs(tx) do
		if t.freq == freq and isElement(p) then list[#list + 1] = p end
	end
	return list
end
