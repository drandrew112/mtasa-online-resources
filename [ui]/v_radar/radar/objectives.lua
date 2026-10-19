if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Objectives: mission targets other resources place on the radar through exports.
--
-- Every objective shows as a yellow circle on the minimap, the bigmap, the pause
-- preview and (if enabled) as a 3D blip, at any distance. While exactly one
-- objective exists, a yellow route to it is kept up to date continuously (on
-- foot or in any vehicle). With two or more there is no automatic route. The
-- route is a navmesh road route (radar/gps/sourceC.lua), searched again from
-- the player's position when they leave it or drive against it.
--
-- The objective route is independent of the waypoint route (gpsRoute, purple,
-- radar/gps/sourceC.lua): both can be active at the same time.
--
-- Client exports:
--   addObjective(x, y, z [, label])           -> id
--   updateObjective(id, x, y, z [, label])    -> bool
--   removeObjective(id)                       -> bool
--   clearObjectives()                         -> removes the calling resource's objectives
--   getObjectives()                           -> { {id, x, y, z, label}, ... }
-- Server exports (same names, first argument is the player) live in server.lua.
-- Objectives are removed automatically when the resource that created them stops.

objective_color = tocolor(255, 205, 40)

objectives = {}
-- route points {x, y, z} and the segment the player is on
objectiveRoute = false
objectiveRouteNode = 1
objectiveRouteImage = false
objectiveRouteImageData = {}

local objectiveNextId = 0
local routeTarget = false -- objective the current route leads to
local routeTargetX, routeTargetY = 0, 0
local lastTargetRoute = 0

local ROUTE_UPDATE_INTERVAL = 300
local TARGET_MOVED_DISTANCE = 5
local TARGET_REROUTE_COOLDOWN = 1500 -- a moving objective gets a new route at most this often

local function findObjective(id)
	for i, obj in ipairs(objectives) do
		if obj.id == id then
			return obj, i
		end
	end
	return false
end

-- The route itself is a navmesh route tracker (radar/gps/sourceC.lua): rerouted when the player leaves it.
local objectiveTracker

function rebuildObjectiveRouteImage()
	if isElement(objectiveRouteImage) then
		destroyElement(objectiveRouteImage)
	end
	objectiveRouteImage = false
	objectiveRouteImageData = {}

	if not objectiveRoute or not objectiveTracker then
		return
	end

	local lines = objectiveTracker:getMapLines()
	if #lines >= 2 then
		objectiveRouteImage, objectiveRouteImageData = buildRouteImage(lines)
	end
end

objectiveTracker = createRouteTracker("objective", {
	changed = function (t)
		objectiveRoute = t.points
		objectiveRouteNode = t.index
		rebuildObjectiveRouteImage()
	end,
})

local function clearObjectiveRoute()
	routeTarget = false
	objectiveTracker:stop()
end

local function makeObjectiveRoute(obj)
	routeTarget = obj
	routeTargetX, routeTargetY = obj.x, obj.y
	lastTargetRoute = getTickCount()
	objectiveTracker:setDestination(obj.x, obj.y, obj.z)
end

function updateObjectiveRoute()
	if #objectives ~= 1 or not dimensionHasMap() or getElementInterior(localPlayer) ~= 0 then
		if routeTarget then
			clearObjectiveRoute()
		end
		return
	end

	local obj = objectives[1]
	if routeTarget ~= obj then
		makeObjectiveRoute(obj)
	elseif getDistanceBetweenPoints2D(routeTargetX, routeTargetY, obj.x, obj.y) > TARGET_MOVED_DISTANCE
		and getTickCount() - lastTargetRoute > TARGET_REROUTE_COOLDOWN then
		makeObjectiveRoute(obj)
	end
	-- following the route, leaving it, rerouting: the tracker's own timer
end

-- Waypoint + objective blips, consumed by the renderers in radar/sourceC.lua.
local waypointGroundZ = {}

local function getWaypointZ(x, y)
	local key = floor(x) .. "," .. floor(y)
	if waypointGroundZ[key] then
		return waypointGroundZ[key]
	end

	local z = getGroundPosition(x, y, 1000)
	if z and z ~= 0 then
		waypointGroundZ = {[key] = z}
		return z
	end

	local _, _, playerZ = getElementPosition(localPlayer)
	return playerZ
end

function getSpecialBlips()
	local list = {}

	for _, obj in ipairs(objectives) do
		list[#list + 1] = {
			key = "objective:" .. tostring(obj.id),
			icon = "blips/objective.png",
			x = obj.x, y = obj.y, z = obj.z,
			label = obj.label or L("v_radar.objectives.objective"),
		}
	end

	if occupiedVehicle and isElement(occupiedVehicle) then
		local destination = getElementData(occupiedVehicle, "gpsDestination")
		if type(destination) == "table" and destination[1] and destination[2] then
			list[#list + 1] = {
				key = "waypoint",
				icon = "blips/waypoint.png",
				x = destination[1], y = destination[2], z = getWaypointZ(destination[1], destination[2]),
				label = L("v_radar.objectives.waypoint"),
			}
		end
	end

	return list
end

-- Internal add/update/remove, shared by the client exports and the server sync.
local function setObjective(id, x, y, z, label, owner)
	x, y, z = tonumber(x), tonumber(y), tonumber(z)
	if not x or not y then
		return false
	end
	if not z then
		z = getGroundPosition(x, y, 1000)
		if not z or z == 0 then
			local _, _, playerZ = getElementPosition(localPlayer)
			z = playerZ
		end
	end

	local obj = findObjective(id)
	if obj then
		obj.x, obj.y, obj.z = x, y, z
		if label ~= nil then
			obj.label = label and tostring(label) or nil
		end
	else
		objectives[#objectives + 1] = {
			id = id,
			x = x, y = y, z = z,
			label = label and tostring(label) or nil,
			owner = owner,
		}
	end

	updateObjectiveRoute()
	return true
end

local function deleteObjective(id)
	local obj, index = findObjective(id)
	if not obj then
		return false
	end

	table.remove(objectives, index)
	updateObjectiveRoute()
	return true
end

local function deleteObjectivesOwnedBy(owner)
	for i = #objectives, 1, -1 do
		if objectives[i].owner == owner then
			table.remove(objectives, i)
		end
	end
	updateObjectiveRoute()
end

local function callerOwner()
	return "c:" .. (sourceResource and getResourceName(sourceResource) or getResourceName(getThisResource()))
end

-- Exported
function addObjective(x, y, z, label)
	objectiveNextId = objectiveNextId + 1
	local id = objectiveNextId

	if not setObjective(id, x, y, z, label, callerOwner()) then
		return false
	end
	return id
end

-- Exported
function updateObjective(id, x, y, z, label)
	if not findObjective(id) then
		return false
	end
	return setObjective(id, x, y, z, label)
end

-- Exported
function removeObjective(id)
	return deleteObjective(id)
end

-- Exported: removes every objective the calling resource created.
function clearObjectives()
	deleteObjectivesOwnedBy(callerOwner())
	return true
end

-- Exported
function getObjectives()
	local list = {}
	for _, obj in ipairs(objectives) do
		list[#list + 1] = {id = obj.id, x = obj.x, y = obj.y, z = obj.z, label = obj.label}
	end
	return list
end

-- Server-side exports (server.lua) arrive here. Server ids are strings ("s1", ...)
-- so they never collide with the numeric client ids.
addEvent("v_radar:objectiveSet", true)
addEventHandler("v_radar:objectiveSet", resourceRoot,
	function (id, x, y, z, label, ownerName)
		setObjective(id, x, y, z, label, "s:" .. tostring(ownerName))
	end
)

addEvent("v_radar:objectiveRemove", true)
addEventHandler("v_radar:objectiveRemove", resourceRoot,
	function (id)
		deleteObjective(id)
	end
)

addEvent("v_radar:objectiveClearOwner", true)
addEventHandler("v_radar:objectiveClearOwner", resourceRoot,
	function (ownerName)
		deleteObjectivesOwnedBy("s:" .. tostring(ownerName))
	end
)

addEventHandler("onClientResourceStop", root,
	function (stoppedResource)
		if stoppedResource ~= getThisResource() then
			deleteObjectivesOwnedBy("c:" .. getResourceName(stoppedResource))
		end
	end
)

addEventHandler("onClientResourceStart", resourceRoot,
	function ()
		setTimer(updateObjectiveRoute, ROUTE_UPDATE_INTERVAL, 0)
		-- Pull the objectives the server already set for us (v_radar restart / late start).
		triggerServerEvent("v_radar:requestObjectives", resourceRoot)
	end
)
