-- Circle areas: filled, see-through circles on the minimap and the bigmap (gang war zones, search areas...).
-- Drawn by drawCircleAreas in radar/sourceC.lua, under the routes and the blips.
--
-- Client exports (only this player sees them):
--   addCircleArea(x, y, radius [, r, g, b, a [, flashing]])            -> id
--   updateCircleArea(id, x, y, radius [, r, g, b, a [, flashing]])     -> bool (nil arguments keep the old value)
--   removeCircleArea(id)                                               -> bool
--   clearCircleAreas()                                                 -> removes the calling resource's areas
--   getCircleAreas()                                                   -> { {id, x, y, radius, r, g, b, a, flashing}, ... }
-- Server exports (radar/areas_server.lua) take who sees the area first: a player, a table of players, a team or
-- root / nil for everyone. Areas are removed automatically when the resource that created them stops.
--
-- radius in metres; colour 0-255, default red with alpha 90; flashing = the fill pulses.

circleAreas = {}

local DEFAULT_COLOR = {230, 50, 50, 90}
local areaNextId = 0

local function findArea(id)
	for i, area in ipairs(circleAreas) do
		if area.id == id then
			return area, i
		end
	end
	return false
end

local function clampColor(v, default)
	v = tonumber(v)
	if not v then return default end
	return max(0, min(255, floor(v)))
end

-- Internal add/update, shared by the client exports and the server sync.
local function setArea(id, x, y, radius, r, g, b, a, flashing, owner)
	local area = findArea(id)
	x, y, radius = tonumber(x), tonumber(y), tonumber(radius)

	if not area then
		if not x or not y or not radius or radius <= 0 then
			return false
		end
		area = {id = id, owner = owner}
		circleAreas[#circleAreas + 1] = area
		area.r, area.g, area.b, area.a = DEFAULT_COLOR[1], DEFAULT_COLOR[2], DEFAULT_COLOR[3], DEFAULT_COLOR[4]
		area.flashing = false
	end

	if x then area.x = x end
	if y then area.y = y end
	if radius and radius > 0 then area.radius = radius end
	area.r = clampColor(r, area.r)
	area.g = clampColor(g, area.g)
	area.b = clampColor(b, area.b)
	area.a = clampColor(a, area.a)
	if flashing ~= nil then
		area.flashing = flashing and true or false
	end
	return true
end

local function deleteArea(id)
	local _, index = findArea(id)
	if not index then
		return false
	end
	table.remove(circleAreas, index)
	return true
end

local function deleteAreasOwnedBy(owner)
	for i = #circleAreas, 1, -1 do
		if circleAreas[i].owner == owner then
			table.remove(circleAreas, i)
		end
	end
end

local function callerOwner()
	return "c:" .. (sourceResource and getResourceName(sourceResource) or getResourceName(getThisResource()))
end

-- Exported
function addCircleArea(x, y, radius, r, g, b, a, flashing)
	areaNextId = areaNextId + 1
	local id = areaNextId
	if not setArea(id, x, y, radius, r, g, b, a, flashing, callerOwner()) then
		return false
	end
	return id
end

-- Exported
function updateCircleArea(id, x, y, radius, r, g, b, a, flashing)
	if not findArea(id) then
		return false
	end
	return setArea(id, x, y, radius, r, g, b, a, flashing)
end

-- Exported
function removeCircleArea(id)
	return deleteArea(id)
end

-- Exported: removes every area the calling resource created on this client.
function clearCircleAreas()
	deleteAreasOwnedBy(callerOwner())
	return true
end

-- Exported
function getCircleAreas()
	local list = {}
	for _, area in ipairs(circleAreas) do
		list[#list + 1] = {id = area.id, x = area.x, y = area.y, radius = area.radius,
			r = area.r, g = area.g, b = area.b, a = area.a, flashing = area.flashing}
	end
	return list
end

-- Server-side exports arrive here. Server ids are strings ("a1", ...), client ids numbers.
addEvent("v_radar:areaSet", true)
addEventHandler("v_radar:areaSet", resourceRoot,
	function (id, x, y, radius, r, g, b, a, flashing, ownerName)
		setArea(id, x, y, radius, r, g, b, a, flashing, "s:" .. tostring(ownerName))
	end
)

addEvent("v_radar:areaRemove", true)
addEventHandler("v_radar:areaRemove", resourceRoot,
	function (id)
		deleteArea(id)
	end
)

addEventHandler("onClientResourceStop", root,
	function (stoppedResource)
		if stoppedResource ~= getThisResource() then
			deleteAreasOwnedBy("c:" .. getResourceName(stoppedResource))
		end
	end
)

addEventHandler("onClientResourceStart", resourceRoot,
	function ()
		-- the areas the server already shows us (v_radar restart / late start)
		triggerServerEvent("v_radar:requestCircleAreas", resourceRoot)
	end
)
