-- Radio, client side.
--
-- Push to talk: RADIO.KEY is bound to MTA's own "voiceptt" command (that starts / stops the
-- microphone) and to our handler (push / release sound + tell the server). The bind only exists
-- while we are on a frequency and not typing (RADIO.BLOCK_DATA, chat box, console).
--
-- Listeners: intro sound when someone keys the frequency, then the voice (full volume, no pan,
-- see Radio.isLive in client.lua) with a quiet static loop under it, outro at the end.

Radio = {}

local myFreq = false
local myUnit = false
local selfState = "off"        -- "off" | "keying" | "live"
local bound = false
local keyHeld = false

local live = {}                -- [speaker] = info, transmissions we hear now
local intros = {}              -- [speaker] = sound, intro playing
local lastSpeaker = nil        -- { player, name, unit, freq, live, endedAt }
local staticSound = nil

local function sfx(name)
	local s = playSound("sounds/" .. name .. ".wav")
	if s then setSoundVolume(s, RADIO.SFX_VOLUME) end
	return s
end

------------------------------------------------------------------------ static loop

local function updateStatic()
	if next(live) then
		if not isElement(staticSound) then
			staticSound = playSound("sounds/static.wav", true)
			if staticSound then setSoundVolume(staticSound, RADIO.STATIC_VOLUME) end
		end
	elseif isElement(staticSound) then
		destroyElement(staticSound)
		staticSound = nil
	end
end

------------------------------------------------------------------------ push to talk

local function blocked()
	if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return true end
	for _, key in ipairs(RADIO.BLOCK_DATA) do
		if getElementData(localPlayer, key) then return true end
	end
	return false
end

local function onKey(_, state)
	if state == "down" then
		if keyHeld or not myFreq then return end
		keyHeld = true
		sfx("push")
		triggerServerEvent("v_voice:radioKey", resourceRoot, true)
	else
		if not keyHeld then return end
		keyHeld = false
		sfx("release")
		triggerServerEvent("v_voice:radioKey", resourceRoot, false)
	end
end

local function setBound(on)
	if on == bound then return end
	bound = on
	if on then
		bindKey(RADIO.KEY, "both", onKey)
		bindKey(RADIO.KEY, "down", "voiceptt", "1")
		bindKey(RADIO.KEY, "up", "voiceptt", "0")
	else
		unbindKey(RADIO.KEY, "both", onKey)
		unbindKey(RADIO.KEY, "down", "voiceptt")
		unbindKey(RADIO.KEY, "up", "voiceptt")
	end
end

-- keep the bind in line with the frequency / typing state (never unbind while the key is held,
-- the "up" bind has to stop the microphone)
setTimer(function()
	if keyHeld then
		if not getKeyState(RADIO.KEY) then onKey(RADIO.KEY, "up") end
		return
	end
	setBound(myFreq ~= false and isVoiceEnabled() and not blocked())
end, 200, 0)

------------------------------------------------------------------------ server events

addEvent("v_voice:radioState", true)
addEventHandler("v_voice:radioState", resourceRoot, function(freq, unit)
	if freq ~= myFreq then
		-- channel changed: whatever we heard belongs to the old one
		for speaker, s in pairs(intros) do
			if isElement(s) then destroyElement(s) end
			intros[speaker] = nil
		end
		live = {}
		updateStatic()
		if lastSpeaker and lastSpeaker.freq ~= freq then lastSpeaker = nil end
	end
	myFreq = freq or false
	myUnit = unit or false
	if not myFreq and keyHeld then onKey(RADIO.KEY, "up") end
end)

addEvent("v_voice:radioSelf", true)
addEventHandler("v_voice:radioSelf", resourceRoot, function(state)
	selfState = state
end)

addEvent("v_voice:radioIntro", true)
addEventHandler("v_voice:radioIntro", resourceRoot, function(speaker, info)
	if not isElement(speaker) then return end
	if isElement(intros[speaker]) then destroyElement(intros[speaker]) end
	intros[speaker] = sfx("intro")
	lastSpeaker = { player = speaker, name = info.name, unit = info.unit, freq = info.freq, live = false }
end)

addEvent("v_voice:radioLive", true)
addEventHandler("v_voice:radioLive", resourceRoot, function(speaker, info)
	if not isElement(speaker) then return end
	intros[speaker] = nil   -- the intro has just finished (or we joined mid-transmission)
	live[speaker] = info
	lastSpeaker = { player = speaker, name = info.name, unit = info.unit, freq = info.freq, live = true }
	if Voice and Voice.radioSpeakerStart then Voice.radioSpeakerStart(speaker) end
	updateStatic()
end)

addEvent("v_voice:radioEnd", true)
addEventHandler("v_voice:radioEnd", resourceRoot, function(speaker, wasLive, reason)
	if isElement(intros[speaker]) then destroyElement(intros[speaker]) end
	local heard = live[speaker] ~= nil or intros[speaker] ~= nil
	intros[speaker] = nil
	live[speaker] = nil
	updateStatic()
	if heard and reason ~= "left" then sfx("outro") end
	if lastSpeaker and lastSpeaker.player == speaker then
		lastSpeaker.live = false
		lastSpeaker.endedAt = getTickCount()
	end
end)

addEventHandler("onClientPlayerQuit", root, function()
	if isElement(intros[source]) then destroyElement(intros[source]) end
	intros[source] = nil
	if live[source] then
		live[source] = nil
		updateStatic()
	end
	if lastSpeaker and lastSpeaker.player == source then lastSpeaker = nil end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
	triggerServerEvent("v_voice:radioRequest", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
	setBound(false)
end)

------------------------------------------------------------------------ used by client.lua

-- true when we hear this player through the radio right now
function Radio.isLive(player)
	return live[player] ~= nil
end

------------------------------------------------------------------------ exports

-- getRadioFrequency() -> number | false
function getRadioFrequency()
	return myFreq
end

-- getRadioUnit() -> own unit label | false
function getRadioUnit()
	return myUnit
end

-- isRadioTalking() -> true while our own transmission is live (after the intro)
function isRadioTalking()
	return selfState == "live"
end

-- getRadioState() -> "off" | "keying" (intro playing for the listeners) | "live"
function getRadioState()
	return selfState
end

-- getRadioSpeaker() -> { player, name, unit, live } | false
-- The other player talking on our frequency, kept RADIO.SPEAKER_HOLD_MS after the end.
function getRadioSpeaker()
	local s = lastSpeaker
	if not s or s.freq ~= myFreq then return false end
	if not s.live and s.endedAt and getTickCount() - s.endedAt > RADIO.SPEAKER_HOLD_MS then return false end
	return { player = isElement(s.player) and s.player or false, name = s.name, unit = s.unit or false, live = s.live }
end
