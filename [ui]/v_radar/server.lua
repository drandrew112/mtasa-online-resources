addEvent("executeCommand", true)
addEventHandler("executeCommand", getRootElement(), function(cmd, ...)
	executeCommandHandler(cmd, client, ...)
end)

-- Objectives (see radar/objectives.lua). The server keeps every player's
-- objectives so they can be re-sent when the player's v_radar (re)starts.
local playerObjectives = {} -- [player] = { [id] = {x, y, z, label, owner} }
local readyPlayers = {}
local objectiveNextId = 0

local function callerName()
	return sourceResource and getResourceName(sourceResource) or getResourceName(getThisResource())
end

local function sendObjective(player, id, obj)
	if readyPlayers[player] then
		triggerClientEvent(player, "v_radar:objectiveSet", resourceRoot, id, obj.x, obj.y, obj.z, obj.label, obj.owner)
	end
end

-- Exported: addObjective(player, x, y, z [, label]) -> id
function addObjective(player, x, y, z, label)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not isElement(player) or getElementType(player) ~= "player" or not x or not y then
		return false
	end

	objectiveNextId = objectiveNextId + 1
	local id = "s" .. objectiveNextId
	local obj = {x = x, y = y, z = z, label = label and tostring(label) or nil, owner = callerName()}

	playerObjectives[player] = playerObjectives[player] or {}
	playerObjectives[player][id] = obj
	sendObjective(player, id, obj)
	return id
end

-- Exported: updateObjective(player, id, x, y, z [, label]) -> bool
function updateObjective(player, id, x, y, z, label)
	local obj = playerObjectives[player] and playerObjectives[player][id]
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not obj or not x or not y then
		return false
	end

	obj.x, obj.y, obj.z = x, y, z
	if label ~= nil then
		obj.label = label and tostring(label) or nil
	end
	sendObjective(player, id, obj)
	return true
end

-- Exported: removeObjective(player, id) -> bool
function removeObjective(player, id)
	if not (playerObjectives[player] and playerObjectives[player][id]) then
		return false
	end

	playerObjectives[player][id] = nil
	if readyPlayers[player] then
		triggerClientEvent(player, "v_radar:objectiveRemove", resourceRoot, id)
	end
	return true
end

-- Exported: clearObjectives(player) removes the calling resource's objectives of that player.
function clearObjectives(player)
	local list = playerObjectives[player]
	if not list then
		return false
	end

	local owner = callerName()
	for id, obj in pairs(list) do
		if obj.owner == owner then
			removeObjective(player, id)
		end
	end
	return true
end

addEvent("v_radar:requestObjectives", true)
addEventHandler("v_radar:requestObjectives", resourceRoot, function()
	readyPlayers[client] = true
	for id, obj in pairs(playerObjectives[client] or {}) do
		sendObjective(client, id, obj)
	end
end)

addEventHandler("onPlayerQuit", root, function()
	playerObjectives[source] = nil
	readyPlayers[source] = nil
end)

addEventHandler("onResourceStop", root, function(stoppedResource)
	if stoppedResource == getThisResource() then
		return
	end

	local owner = getResourceName(stoppedResource)
	for player, list in pairs(playerObjectives) do
		local removed = false
		for id, obj in pairs(list) do
			if obj.owner == owner then
				list[id] = nil
				removed = true
			end
		end
		if removed and readyPlayers[player] then
			triggerClientEvent(player, "v_radar:objectiveClearOwner", resourceRoot, owner)
		end
	end
end)
