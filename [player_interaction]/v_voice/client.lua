-- Proximity voice, client side: the server only sends us the voice of nearby players
-- (server.lua); here every speaker's volume fades with distance, drops behind buildings and
-- is panned left / right by where they stand relative to the camera.

local speaking = {}  -- [player] = true, remote players we currently hear
local localTalking = false

local function isMuted()
	if not VOICE.BLOCK_MUTED then return false end
	local until_ = tonumber(getElementData(localPlayer, "mute_until"))
	return until_ ~= nil and until_ > getRealTime().timestamp
end

local function headPosition(player)
	local x, y, z = getPedBonePosition(player, 8)
	if not x then
		x, y, z = getElementPosition(player)
		z = z + 0.6
	end
	return x, y, z
end

local function distanceVolume(dist)
	if dist <= VOICE.FULL_VOLUME_RANGE then return 1 end
	if dist >= VOICE.RANGE then return 0 end
	local t = (dist - VOICE.FULL_VOLUME_RANGE) / (VOICE.RANGE - VOICE.FULL_VOLUME_RANGE)
	return (1 - t) * (1 - t)
end

local function updateSpeaker(player, myVeh, mx, my, mz, rx, ry)
	if getElementDimension(player) ~= getElementDimension(localPlayer)
		or getElementInterior(player) ~= getElementInterior(localPlayer) then
		setSoundVolume(player, 0)
		return
	end

	if VOICE.VEHICLE_SHARED and myVeh and getPedOccupiedVehicle(player) == myVeh then
		setSoundVolume(player, 1)
		setSoundPan(player, 0)
		return
	end

	local px, py, pz = headPosition(player)
	local dx, dy, dz = px - mx, py - my, pz - mz
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	local volume = distanceVolume(dist)

	if volume > 0 and not isLineOfSightClear(mx, my, mz, px, py, pz, true, false, false, true, false, true, false) then
		volume = volume * VOICE.OCCLUDED_VOLUME
	end
	setSoundVolume(player, volume)

	-- pan: how far to the right of the camera's view direction the speaker is
	local flat = math.sqrt(dx * dx + dy * dy)
	local pan = 0
	if flat > 0.5 then
		pan = (dx * rx + dy * ry) / flat * VOICE.PAN_STRENGTH
	end
	setSoundPan(player, math.max(-1, math.min(1, pan)))
end

local function updateAll()
	if not next(speaking) then return end

	local mx, my, mz = headPosition(localPlayer)
	local cx, cy, _, lx, ly = getCameraMatrix()
	local fx, fy = lx - cx, ly - cy
	local fl = math.sqrt(fx * fx + fy * fy)
	local rx, ry = 0, 0
	if fl > 0 then
		rx, ry = fy / fl, -fx / fl
	end
	local myVeh = getPedOccupiedVehicle(localPlayer)

	for player in pairs(speaking) do
		if isElement(player) then
			updateSpeaker(player, myVeh, mx, my, mz, rx, ry)
		else
			speaking[player] = nil
		end
	end
end
setTimer(updateAll, VOICE.CLIENT_UPDATE_MS, 0)

addEventHandler("onClientPlayerVoiceStart", root, function()
	if source == localPlayer then
		if isMuted() then
			cancelEvent()
			return
		end
		localTalking = true
		return
	end
	speaking[source] = true
	-- set the volume before the first packet plays, no full-volume blip from far away
	updateAll()
end)

addEventHandler("onClientPlayerVoiceStop", root, function()
	if source == localPlayer then
		localTalking = false
		return
	end
	speaking[source] = nil
end)

addEventHandler("onClientPlayerQuit", root, function()
	speaking[source] = nil
end)

-- Exported
function isPlayerTalking(player)
	if player == localPlayer then return localTalking end
	return speaking[player] == true
end

-- Exported
function isLocalTalking()
	return localTalking
end
