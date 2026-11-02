-- Proximity voice, server side: every player's voice is only sent to the players near them
-- (same dimension and interior, within VOICE.RANGE + VOICE.BROADCAST_MARGIN). The client then
-- fades the volume with distance (client.lua).

local talking = {}   -- [player] = true while the push-to-talk key is held
local listeners = {} -- [player] = { [listener] = true }, what was last given to setPlayerVoiceBroadcastTo

local function isMuted(player)
	if not VOICE.BLOCK_MUTED then return false end
	local until_ = tonumber(getElementData(player, "mute_until"))
	return until_ ~= nil and until_ > getRealTime().timestamp
end

local function sameSet(a, b)
	for k in pairs(a) do
		if not b[k] then return false end
	end
	for k in pairs(b) do
		if not a[k] then return false end
	end
	return true
end

local function applyListeners(player, set)
	if listeners[player] and sameSet(listeners[player], set) then return end
	listeners[player] = set
	local list = {}
	for p in pairs(set) do
		list[#list + 1] = p
	end
	setPlayerVoiceBroadcastTo(player, list)
end

local function buildListeners(player, players, range)
	local set = {}
	if isMuted(player) then return set end

	local x, y, z = getElementPosition(player)
	local dim, int = getElementDimension(player), getElementInterior(player)
	local veh = getPedOccupiedVehicle(player)
	for _, other in ipairs(players) do
		if other ~= player and getElementDimension(other) == dim and getElementInterior(other) == int then
			if VOICE.VEHICLE_SHARED and veh and getPedOccupiedVehicle(other) == veh then
				set[other] = true
			else
				local ox, oy, oz = getElementPosition(other)
				if getDistanceBetweenPoints3D(x, y, z, ox, oy, oz) <= range then
					set[other] = true
				end
			end
		end
	end
	return set
end

local function updateAll()
	local players = getElementsByType("player")
	local range = VOICE.RANGE + VOICE.BROADCAST_MARGIN
	for _, player in ipairs(players) do
		applyListeners(player, buildListeners(player, players, range))
	end
end

addEventHandler("onResourceStart", resourceRoot, function()
	if not isVoiceEnabled() then
		outputServerLog("[v_voice] voice is disabled in mtaserver.conf (<voice>1</voice>), proximity voice is idle")
	end
	-- nobody hears anybody until the first update
	for _, player in ipairs(getElementsByType("player")) do
		setPlayerVoiceBroadcastTo(player, {})
		listeners[player] = {}
	end
	updateAll()
	setTimer(updateAll, VOICE.SERVER_UPDATE_MS, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
	-- back to the MTA default: everybody hears everybody
	for _, player in ipairs(getElementsByType("player")) do
		setPlayerVoiceBroadcastTo(player, root)
	end
end)

addEventHandler("onPlayerJoin", root, function()
	setPlayerVoiceBroadcastTo(source, {})
	listeners[source] = {}
end)

addEventHandler("onPlayerQuit", root, function()
	talking[source] = nil
	listeners[source] = nil
	for _, set in pairs(listeners) do
		set[source] = nil
	end
end)

addEventHandler("onPlayerVoiceStart", root, function()
	if isMuted(source) then
		cancelEvent()
		return
	end
	talking[source] = true
end)

addEventHandler("onPlayerVoiceStop", root, function()
	talking[source] = nil
end)

-- Exported
function isPlayerTalking(player)
	return talking[player] == true
end

-- Exported: the players currently receiving this player's voice.
function getPlayerVoiceListeners(player)
	local list = {}
	for p in pairs(listeners[player] or {}) do
		list[#list + 1] = p
	end
	return list
end
