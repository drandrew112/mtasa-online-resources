-- Interior blips: icons that only exist on the minimap while an interior map (radar/interiors.lua) is shown;
-- the normal world blips are hidden then. Every blip belongs to one interior map id.
--
-- Fixed ones: interiors/blips.json. Other resources add theirs through client exports:
--   addInteriorBlip(mapId, x, y, z, icon [, label])  -> id   (icon: "door" | "computer" | "elevator" | "jail")
--   removeInteriorBlip(id)                           -> bool
--   clearInteriorBlips()                             -> removes the calling resource's blips
--   getInteriorBlips([mapId])                        -> { {id, map, x, y, z, icon, label}, ... }
-- A blip whose map does not exist (yet) is simply never shown. Removed when the owning resource stops.

local BLIP_FILE = "interiors/blips.json"
local ICONS = { door = "blips/door.png", computer = "blips/computer.png", elevator = "blips/elevator.png", jail = "blips/jail.png" }
local BLIP_SIZE = 20

local blips = {}   -- [id] = {map, x, y, z, icon, label, owner}
local byMap = {}   -- [mapId] = list (rebuilt lazily)
local nextId = 0
local dirty = true

local function add(map, x, y, z, icon, label, owner)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not map or not x or not y or not ICONS[icon] then
		return false
	end
	nextId = nextId + 1
	blips[nextId] = { id = nextId, map = tostring(map), x = x, y = y, z = z or 0, icon = icon, label = label and tostring(label) or nil, owner = owner }
	dirty = true
	return nextId
end

local function callerOwner()
	return sourceResource and getResourceName(sourceResource) or getResourceName(getThisResource())
end

-- Exported
function addInteriorBlip(map, x, y, z, icon, label)
	return add(map, x, y, z, icon, label, callerOwner())
end

-- Exported
function removeInteriorBlip(id)
	if not blips[id] then
		return false
	end
	blips[id] = nil
	dirty = true
	return true
end

-- Exported
function clearInteriorBlips()
	local owner = callerOwner()
	for id, b in pairs(blips) do
		if b.owner == owner then
			blips[id] = nil
			dirty = true
		end
	end
	return true
end

-- Exported
function getInteriorBlips(map)
	local list = {}
	for _, b in pairs(blips) do
		if not map or b.map == map then
			list[#list + 1] = { id = b.id, map = b.map, x = b.x, y = b.y, z = b.z, icon = b.icon, label = b.label }
		end
	end
	return list
end

-- Called by the minimap renderer: draws the blips of `map` (fade b = 0..1).
function drawInteriorBlips(map, b, remapPlayerPosX, remapPlayerPosY, cameraRotation)
	if dirty then
		byMap = {}
		for _, bl in pairs(blips) do
			byMap[bl.map] = byMap[bl.map] or {}
			table.insert(byMap[bl.map], bl)
		end
		dirty = false
	end
	local list = byMap[map.id]
	if not list then
		return
	end
	local color = tocolor(255, 255, 255, math.floor(255 * b))
	for _, bl in ipairs(list) do
		renderBlip(ICONS[bl.icon], bl.x, bl.y, remapPlayerPosX, remapPlayerPosY, BLIP_SIZE, BLIP_SIZE, color, cameraRotation, false, "ib" .. bl.id)
	end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
	if not fileExists(BLIP_FILE) then
		return
	end
	local f = fileOpen(BLIP_FILE, true)
	if not f then
		return
	end
	local raw = fileRead(f, fileGetSize(f))
	fileClose(f)
	local data = raw and fromJSON(raw)
	if type(data) ~= "table" or type(data.blips) ~= "table" then
		outputDebugString("v_radar: interiors/blips.json could not be read", 2)
		return
	end
	for _, b in ipairs(data.blips) do
		add(b.map, b.x, b.y, b.z, b.icon, b.label, "v_radar")
	end
end)

addEventHandler("onClientResourceStop", root, function(res)
	if res == getThisResource() then
		return
	end
	local owner = getResourceName(res)
	for id, b in pairs(blips) do
		if b.owner == owner then
			blips[id] = nil
			dirty = true
		end
	end
end)
