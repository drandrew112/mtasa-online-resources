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

	dxDrawRectangle(x, y, box, box, tocolor(0, 0, 0, 165))

	local r = MIC_IDLE[1] + (MIC_TALKING[1] - MIC_IDLE[1]) * blend
	local g = MIC_IDLE[2] + (MIC_TALKING[2] - MIC_IDLE[2]) * blend
	local b = MIC_IDLE[3] + (MIC_TALKING[3] - MIC_IDLE[3]) * blend
	local pad = math.floor(box * 0.22)
	dxDrawImage(x + pad, y + pad, box - pad * 2, box - pad * 2, MIC_IMAGE, 0, 0, 0, tocolor(r, g, b, 255))
end
