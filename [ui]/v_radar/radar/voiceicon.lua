-- Voice indicator: small mic panel on the right of the minimap, just above the speedometer slot.
-- Grey while silent, blue while the local player's microphone is transmitting (v_voice).
-- renderVoiceIcon() is called from renderMinimap (radar/sourceC.lua) right after renderSpeedo,
-- so it follows the minimap's position, visibility and size.

local MIC_IMAGE = "radar/files/mic.png"
local MIC_IDLE = { 150, 150, 150 }
local MIC_TALKING = { 64, 156, 255 }
local MIC_FADE_MS = 150

local talking = false
local blend = 0       -- 0 = idle colour, 1 = talking colour
local lastTick = getTickCount()

addEventHandler("onClientPlayerVoiceStart", localPlayer, function()
	-- v_voice cancels the event for muted players
	if not wasEventCancelled() then talking = true end
end)

addEventHandler("onClientPlayerVoiceStop", localPlayer, function()
	talking = false
end)

function renderVoiceIcon(mx, my, mw, mh)
	local now = getTickCount()
	local step = (now - lastTick) / MIC_FADE_MS
	lastTick = now
	if not isVoiceEnabled() then return end

	blend = talking and math.min(1, blend + step) or math.max(0, blend - step)

	-- same size formula as the speedometer panel (radar/speedo.lua)
	local speedoSize = math.floor(math.min(mw * 0.375, mh * 0.5333))
	local box = math.floor(speedoSize * 0.4)
	local x = mx + mw
	local y = my + mh - speedoSize - box - 2

	local r = MIC_IDLE[1] + (MIC_TALKING[1] - MIC_IDLE[1]) * blend
	local g = MIC_IDLE[2] + (MIC_TALKING[2] - MIC_IDLE[2]) * blend
	local b = MIC_IDLE[3] + (MIC_TALKING[3] - MIC_IDLE[3]) * blend
	local pad = math.floor(box * 0.22)
	dxDrawImage(x + pad, y + pad, box - pad * 2, box - pad * 2, MIC_IMAGE, 0, 0, 0, tocolor(r, g, b, 255))

	renderRadioInfo(x + box, y, box)
end

------------------------------------------------------------------------ radio (v_voice radio module)
-- Right of the mic: the radio channel while we are on a frequency ("CH 104"), blue while anybody
-- talks on it (us or someone else). Further right: the other speaker's name and unit
-- (police / EMS unit from the v_voice agency watcher), kept a moment after the transmission.

local RADIO_POLL_MS = 100
local RADIO_IDLE = { 220, 220, 220 }
local RADIO_UNIT = { 170, 170, 170 }

local radio = { freq = false, state = "off", speaker = false }
local radioNext = 0
local radioFont, radioFontSize = nil, 0
local radioBlend = 0
local radioLast = getTickCount()

local function pollRadio(now)
	if now < radioNext then return end
	radioNext = now + RADIO_POLL_MS
	local res = getResourceFromName("v_voice")
	if not res or getResourceState(res) ~= "running" then
		radio.freq, radio.state, radio.speaker = false, "off", false
		return
	end
	local ok = pcall(function()
		radio.freq = exports.v_voice:getRadioFrequency()
		radio.state = radio.freq and exports.v_voice:getRadioState() or "off"
		radio.speaker = radio.freq and exports.v_voice:getRadioSpeaker() or false
	end)
	if not ok then radio.freq, radio.state, radio.speaker = false, "off", false end
end

local function freqText(freq)
	if freq == math.floor(freq) then return string.format("CH %d", freq) end
	return (string.format("CH %.2f", freq):gsub("0+$", ""))
end

local function shadowText(text, x, y, color, font)
	dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 180), 1, font, "left", "center")
	dxDrawText(text, x, y, x, y, color, 1, font, "left", "center")
end

function renderRadioInfo(x, y, box)
	local now = getTickCount()
	pollRadio(now)
	if not radio.freq then return end

	local size = math.max(8, math.floor(box * 0.3))
	if size ~= radioFontSize then
		if isElement(radioFont) then destroyElement(radioFont) end
		radioFont = dxCreateFont("files/RobotoB.ttf", size, false, "antialiased") or "default-bold"
		radioFontSize = size
	end

	local sp = radio.speaker
	local talking = radio.state == "live" or radio.state == "keying" or (sp and sp.live)
	local step = (now - radioLast) / MIC_FADE_MS
	radioLast = now
	radioBlend = talking and math.min(1, radioBlend + step) or math.max(0, radioBlend - step)

	local cy = y + box / 2
	local r = RADIO_IDLE[1] + (MIC_TALKING[1] - RADIO_IDLE[1]) * radioBlend
	local g = RADIO_IDLE[2] + (MIC_TALKING[2] - RADIO_IDLE[2]) * radioBlend
	local b = RADIO_IDLE[3] + (MIC_TALKING[3] - RADIO_IDLE[3]) * radioBlend
	local label = freqText(radio.freq)
	local tx = x + 2
	shadowText(label, tx, cy, tocolor(r, g, b, 255), radioFont)

	if sp then
		tx = tx + dxGetTextWidth(label, 1, radioFont) + math.floor(box * 0.35)
		local nameColor = sp.live and tocolor(MIC_TALKING[1], MIC_TALKING[2], MIC_TALKING[3], 255) or tocolor(255, 255, 255, 200)
		shadowText(sp.name, tx, cy, nameColor, radioFont)
		if sp.unit then
			tx = tx + dxGetTextWidth(sp.name, 1, radioFont) + math.floor(box * 0.2)
			shadowText(sp.unit, tx, cy, tocolor(RADIO_UNIT[1], RADIO_UNIT[2], RADIO_UNIT[3], 230), radioFont)
		end
	end
end
