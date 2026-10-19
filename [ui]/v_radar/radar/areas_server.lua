-- Circle areas, server side (see radar/areas.lua). The server keeps every area and who sees it, so a player
-- whose v_radar (re)starts gets them again.
--
-- Server exports:
--   addCircleArea(visibleTo, x, y, radius [, r, g, b, a [, flashing]])        -> id ("a1", ...)
--   updateCircleArea(id, x, y, radius [, r, g, b, a [, flashing]])            -> bool (nil arguments keep the old value)
--   setCircleAreaVisibleTo(id, visibleTo)                                     -> bool
--   removeCircleArea(id)                                                      -> bool
--   clearCircleAreas()                                                        -> removes the calling resource's areas
--   getCircleAreas()                                                          -> { [id] = {x, y, radius, r, g, b, a, flashing, owner}, ... }
--
-- visibleTo: a player, a table of players, a team (its players at the time of the call) or root / nil for
-- everyone (players joining later too). A team's members are not followed: call setCircleAreaVisibleTo again
-- when they change.

local areas = {} -- [id] = { x, y, radius, r, g, b, a, flashing, owner, everyone, players = { [player] = true } }
local readyPlayers = {}
local areaNextId = 0

local function callerName()
	return sourceResource and getResourceName(sourceResource) or getResourceName(getThisResource())
end

-- visibleTo -> everyone (bool), players ({ [player] = true })
local function resolveVisibleTo(visibleTo)
	if visibleTo == nil or visibleTo == root then
		return true, {}
	end

	local players = {}
	local function add(e)
		if isElement(e) then
			local t = getElementType(e)
			if t == "player" then
				players[e] = true
			elseif t == "team" then
				for _, p in ipairs(getPlayersInTeam(e)) do
					players[p] = true
				end
			end
		end
	end

	if type(visibleTo) == "table" then
		for _, e in pairs(visibleTo) do
			add(e)
		end
	else
		add(visibleTo)
	end
	return false, players
end

local function sees(area, player)
	return area.everyone or area.players[player] == true
end

local function sendArea(player, id, area)
	if readyPlayers[player] then
		triggerClientEvent(player, "v_radar:areaSet", resourceRoot, id, area.x, area.y, area.radius,
			area.r, area.g, area.b, area.a, area.flashing, area.owner)
	end
end

local function sendRemove(player, id)
	if readyPlayers[player] then
		triggerClientEvent(player, "v_radar:areaRemove", resourceRoot, id)
	end
end

local function forEachViewer(area, fn)
	if area.everyone then
		for player in pairs(readyPlayers) do
			fn(player)
		end
	else
		for player in pairs(area.players) do
			fn(player)
		end
	end
end

local function color(v, default)
	v = tonumber(v)
	if not v then return default end
	return math.max(0, math.min(255, math.floor(v)))
end

-- Exported
function addCircleArea(visibleTo, x, y, radius, r, g, b, a, flashing)
	x, y, radius = tonumber(x), tonumber(y), tonumber(radius)
	if not x or not y or not radius or radius <= 0 then
		return false
	end

	areaNextId = areaNextId + 1
	local id = "a" .. areaNextId
	local everyone, players = resolveVisibleTo(visibleTo)
	local area = {
		x = x, y = y, radius = radius,
		r = color(r, 230), g = color(g, 50), b = color(b, 50), a = color(a, 90),
		flashing = flashing and true or false,
		owner = callerName(), everyone = everyone, players = players,
	}
	areas[id] = area

	forEachViewer(area, function (player)
		sendArea(player, id, area)
	end)
	return id
end

-- Exported
function updateCircleArea(id, x, y, radius, r, g, b, a, flashing)
	local area = areas[id]
	if not area then
		return false
	end

	area.x = tonumber(x) or area.x
	area.y = tonumber(y) or area.y
	if tonumber(radius) and tonumber(radius) > 0 then
		area.radius = tonumber(radius)
	end
	area.r, area.g, area.b, area.a = color(r, area.r), color(g, area.g), color(b, area.b), color(a, area.a)
	if flashing ~= nil then
		area.flashing = flashing and true or false
	end

	forEachViewer(area, function (player)
		sendArea(player, id, area)
	end)
	return true
end

-- Exported
function setCircleAreaVisibleTo(id, visibleTo)
	local area = areas[id]
	if not area then
		return false
	end

	local old = {}
	forEachViewer(area, function (player)
		old[player] = true
	end)

	area.everyone, area.players = resolveVisibleTo(visibleTo)

	for player in pairs(old) do
		if not sees(area, player) then
			sendRemove(player, id)
		end
	end
	forEachViewer(area, function (player)
		if not old[player] then
			sendArea(player, id, area)
		end
	end)
	return true
end

-- Exported
function removeCircleArea(id)
	local area = areas[id]
	if not area then
		return false
	end

	areas[id] = nil
	forEachViewer(area, function (player)
		sendRemove(player, id)
	end)
	return true
end

local function removeAreasOwnedBy(owner)
	for id, area in pairs(areas) do
		if area.owner == owner then
			removeCircleArea(id)
		end
	end
end

-- Exported: removes every area the calling resource created.
function clearCircleAreas()
	removeAreasOwnedBy(callerName())
	return true
end

-- Exported
function getCircleAreas()
	local list = {}
	for id, area in pairs(areas) do
		list[id] = {x = area.x, y = area.y, radius = area.radius, r = area.r, g = area.g, b = area.b, a = area.a,
			flashing = area.flashing, owner = area.owner}
	end
	return list
end

addEvent("v_radar:requestCircleAreas", true)
addEventHandler("v_radar:requestCircleAreas", resourceRoot, function()
	readyPlayers[client] = true
	for id, area in pairs(areas) do
		if sees(area, client) then
			sendArea(client, id, area)
		end
	end
end)

addEventHandler("onPlayerQuit", root, function()
	readyPlayers[source] = nil
	for _, area in pairs(areas) do
		area.players[source] = nil
	end
end)

addEventHandler("onResourceStop", root, function(stoppedResource)
	if stoppedResource ~= getThisResource() then
		removeAreasOwnedBy(getResourceName(stoppedResource))
	end
end)
