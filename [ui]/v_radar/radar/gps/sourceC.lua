local disallowedNodes = {

}

gpsRoute = false
gpsThread = false
reRouting = false
currentNode = false



local gpsColshapes = false
local colshapeElements = {}

local checkForRerouteTimer = false
local rerouteCheckTime = 500

addEventHandler("onClientResourceStart", getResourceRootElement(),
	function ()
		for _, node in ipairs(disallowedNodes) do
			local area = math.floor(node[1] / 65536)
			local defaultNeighbours = shallowcopy(vehicleNodes[area][node[1]].neighbours)

			vehicleNodes[area][node[1]].neighbours = {}

			for k, v in pairs(defaultNeighbours) do
				if k ~= node[2] then
					vehicleNodes[area][node[1]].neighbours[k] = v
				end
			end
		end

		if occupiedVehicle then
			if getElementData(occupiedVehicle, "gpsDestination") then
				local destination = getElementData(occupiedVehicle, "gpsDestination")
				gpsThread = coroutine.create(makeRoute)
				coroutine.resume(gpsThread, destination[1], destination[2], true)
			end
		end
	end
)

function isEventHandlerAdded( sEventName, pElementAttachedTo, func )
    if type( sEventName ) == 'string' and isElement( pElementAttachedTo ) and type( func ) == 'function' then
        local aAttachedFunctions = getEventHandlers( sEventName, pElementAttachedTo )
        if type( aAttachedFunctions ) == 'table' and #aAttachedFunctions > 0 then
            for i, v in ipairs( aAttachedFunctions ) do
                if v == func then
                    return true
                end
            end
        end
    end
    return false
end

addCommandHandler("tognodes",
	function ()
		if getElementData(localPlayer, "admin_level") >= 7 then
			if isEventHandlerAdded("onClientRender", root, renderTheNodes) then
				removeEventHandler("onClientRender", root, renderTheNodes)
			else
				addEventHandler("onClientRender", root, renderTheNodes)
			end
		end
	end
)

function renderTheNodes()
	local playerPosX, playerPosY, playerPosZ = getElementPosition(localPlayer)
	local areaID = floor((playerPosY + 3000) / 750) * 8 + floor((playerPosX + 3000) / 750)
	local drawn = {}

	for id, node in pairs(vehicleNodes[areaID]) do
		if getDistanceBetweenPoints3D(playerPosX, playerPosY, playerPosZ, node.x, node.y, playerPosZ) < 100 then
			local screenX, screenY = getScreenFromWorldPosition(node.x, node.y, node.z)

			if screenX and screenY then
				dxDrawText(tostring(id), screenX - 10, screenY - 5)
			end

			for neighbour in pairs(node.neighbours) do
				if not drawn[neighbour .. "-" .. id] then
					local nodeNeighbour = vehicleNodes[floor(neighbour / 65536)][neighbour]

					dxDrawLine3D(node.x, node.y, node.z + 1, nodeNeighbour.x, nodeNeighbour.y, nodeNeighbour.z + 1, tocolor(220, 163, 30), 3)
					drawn[id .. "-" .. neighbour] = true
				end
			end
		end
	end
end

function makeRoute(destinationX, destinationY, uTurned)
	if isTimer(checkForRerouteTimer) then
		killTimer(checkForRerouteTimer)
	end

	clearGPSRoute()
	gpsLines = {}
	gpsRoute = false

	if gpsColshapes then
		for k, v in pairs(gpsColshapes) do
			colshapeElements[gpsColshapes[k]] = nil

			if isElement(v) then
				destroyElement(v)
			end

			gpsColshapes[k] = nil
		end
	end

	gpsColshapes = {}
	colshapeElements = {}

	if not occupiedVehicle then
		return
	end

	local vehiclePosX, vehiclePosY = getElementPosition(occupiedVehicle)

	local currentZoneName = getZoneName(vehiclePosX, vehiclePosY, 0)
	local currentCityName = getZoneName(vehiclePosX, vehiclePosY, 0, true)
	local zoneName = getZoneName(destinationX, destinationY, 0)
	local cityName = getZoneName(destinationX, destinationY, 0, true)
	local disallowedZones = {
		Unknown = true,

		--["Los Santos"] = true,
	--	["Red County"] = true,

	--	["San Fierro"] = true,
	--	["San Fierro Bay"] = true,
	--	["Gant Bridge"] = true,
	--	["Flint County"] = true,
		Whetstone = true,

	--	["Las Venturas"] = false,
	--["Bone County"] = false,
	--	["Tierra Robada"] = false
	}

	if disallowedZones[currentZoneName] or disallowedZones[currentCityName] then
		setElementData(occupiedVehicle, "gpsDestination", false)
		return false
	end

	if disallowedZones[zoneName] or disallowedZones[cityName] then
		setElementData(occupiedVehicle, "gpsDestination", false)
		return false
	end

	local routePath = calculateRoute(vehiclePosX, vehiclePosY, destinationX, destinationY)

	if not routePath then
		if not uTurned then
		else
		end

		setElementData(occupiedVehicle, "gpsDestination", false)
		return false
	end

	gpsRoute = routePath
	currentNode = 1
	checkForRerouteTimer = setTimer(checkForReroute, rerouteCheckTime, 1)

	for i, node in ipairs(gpsRoute) do
		gpsColshapes[i] = createColTube(node.x, node.y, node.z - 0.3, 8, 5)
		colshapeElements[gpsColshapes[i]] = i
		addGPSLine(node.x, node.y)
	end

	local vehicleOffsetX, vehicleOffsetY = getPositionFromElementOffset(occupiedVehicle, -1, 0, 0)
	local vehicleAngle = math.deg(getAngle(gpsRoute[2].x - gpsRoute[1].x, gpsRoute[2].y - gpsRoute[1].y, vehicleOffsetX - vehiclePosX, vehicleOffsetY - vehiclePosY))

	if vehicleAngle > 0 then
		turnAroundCheckTick = getTickCount()
	end

	lastDestinationX = destinationX
	lastDestinationY = destinationY
	processGPSLines()
end

addEventHandler("onClientColShapeHit", getRootElement(),
	function (element)
		if colshapeElements[source] and element == localPlayer then
			local currentShape = colshapeElements[source]

			clearGPSRoute()

			if currentShape >= 2 then
				if isTimer(checkForRerouteTimer) then
					killTimer(checkForRerouteTimer)
				end

				checkForRerouteTimer = false
			end

			if currentShape == #gpsRoute then
				for i = 1, currentShape do
					if isElement(gpsColshapes[i]) then
						destroyElement(gpsColshapes[i])
					end

					gpsColshapes[i] = nil
				end

				if isTimer(checkForRerouteTimer) then
					killTimer(checkForRerouteTimer)
				end

				checkForRerouteTimer = false
				setElementData(occupiedVehicle, "gpsDestination", false)
				return
			else
				for i = 1, currentShape do
					if isElement(gpsColshapes[i]) then
						destroyElement(gpsColshapes[i])
					end

					gpsColshapes[i] = nil
				end

				for i = currentShape, #gpsRoute do
					addGPSLine(gpsRoute[i].x, gpsRoute[i].y)
				end

				if isTimer(checkForRerouteTimer) then
					killTimer(checkForRerouteTimer)
				end

				currentNode = currentShape + 1
				turnAroundCheckTick = getTickCount()
				checkForRerouteTimer = setTimer(checkForReroute, rerouteCheckTime, 1)
				reRouting = false
				processGPSLines()
			end
		end
	end
)

addEventHandler("onClientVehicleEnter", getRootElement(),
	function (player)
		if player == localPlayer and getElementData(source, "gpsDestination") then
			local destination = getElementData(source, "gpsDestination")
			gpsThread = coroutine.create(makeRoute)
			coroutine.resume(gpsThread, destination[1], destination[2], true)
		end
	end
)

addEventHandler("onClientVehicleExit", getRootElement(),
	function (player)
		if player == localPlayer and gpsRoute then
			endRoute()
		end
	end
)

addEventHandler("onClientElementDestroy", getRootElement(),
	function ()
		if source == occupiedVehicle and getElementData(source, "gpsDestination") then
			setElementData(source, "gpsDestination", false)

			if gpsRoute then
				endRoute()
			end
		end
	end
)

function calculateRoute(x1, y1, x2, y2)
	local startNode = getVehicleNodeClosestToPoint(x1, y1)
	local endNode = getVehicleNodeClosestToPoint(x2, y2)

	if not startNode then
		return false
	end

	if not endNode then
		return false
	end

	return calculatePath(startNode, endNode)
end

function endRoute()
	if gpsRoute then
		if gpsColshapes then
			for k, v in pairs(gpsColshapes) do
				colshapeElements[gpsColshapes[k]] = nil

				if isElement(v) then
					destroyElement(v)
				end

				gpsColshapes[k] = nil
			end
		end

		if isTimer(checkForRerouteTimer) then
			killTimer(checkForRerouteTimer)
		end

		checkForRerouteTimer = false
		clearGPSRoute()
		gpsRoute = false
		gpsThread = false
	end
end

function reRoute(checkShape)
	if not gpsRoute or not occupiedVehicle then
		return
	end

	local vehiclePosX, vehiclePosY = getElementPosition(occupiedVehicle)

	if getDistanceBetweenPoints2D(gpsRoute[checkShape].x, gpsRoute[checkShape].y, vehiclePosX, vehiclePosY) >= 50 then
		if not makeRoute(lastDestinationX, lastDestinationY, true) then
			checkForRerouteTimer = setTimer(checkForReroute, 10000, 1)
			reRouting = true
		end
	else
		checkForRerouteTimer = setTimer(checkForReroute, rerouteCheckTime, 1)
		reRouting = false
	end
end

function checkForReroute()
	if not gpsRoute or not occupiedVehicle then
		return
	end

	local vehiclePosX, vehiclePosY = getElementPosition(occupiedVehicle)
	local nextColshapeDistance = getDistanceBetweenPoints2D(gpsRoute[currentNode].x, gpsRoute[currentNode].y, vehiclePosX, vehiclePosY)

	if nextColshapeDistance >= 30 and nextColshapeDistance < 80 and gpsRoute[currentNode + 1] and turnAroundCheckTick and getTickCount() - turnAroundCheckTick > 5000 then
		local vehicleOffsetX, vehicleOffsetY = getPositionFromElementOffset(occupiedVehicle, -1, 0, 0)
		local vehicleAngle = math.deg(getAngle(gpsRoute[currentNode + 1].x - gpsRoute[currentNode].x, gpsRoute[currentNode + 1].y - gpsRoute[currentNode].y, vehicleOffsetX - vehiclePosX, vehicleOffsetY - vehiclePosY))

		if vehicleAngle > 0 then
			turnAroundCheckTick = getTickCount()
			checkForRerouteTimer = setTimer(checkForReroute, rerouteCheckTime, 1)
			reRouting = false
			return
		else
			reRouting = false
		end
	end

	if isTimer(checkForRerouteTimer) then
		killTimer(checkForRerouteTimer)
	end

	if nextColshapeDistance > 100 then
		checkForRerouteTimer = setTimer(reRoute, 10, 1, currentNode)
		reRouting = getTickCount()
	else
		checkForRerouteTimer = setTimer(checkForReroute, rerouteCheckTime, 1)
	end
end

function getPositionFromElementOffset(element, x, y, z)
	local elementMatrix = getElementMatrix(element)

	local offsetX = x * elementMatrix[1][1] + y * elementMatrix[2][1] + z * elementMatrix[3][1] + elementMatrix[4][1]
	local offsetY = x * elementMatrix[1][2] + y * elementMatrix[2][2] + z * elementMatrix[3][2] + elementMatrix[4][2]
	local offsetZ = x * elementMatrix[1][3] + y * elementMatrix[2][3] + z * elementMatrix[3][3] + elementMatrix[4][3]

	return offsetX, offsetY, offsetZ
end

function getAngle(x1, y1, x2, y2)
	local angle = math.atan2(x2, y2) - math.atan2(x1, y1)

	if angle <= -math.pi then
		angle = angle + math.pi * 2
	elseif angle > math.pi then
		angle = angle - math.pi * 2
	end

	return angle
end

function shallowcopy(t)
	if type(t) ~= "table" then
		return t
	end

	local target = {}
	for k, v in pairs(t) do
		target[k] = v
	end
	return target
end

function calculatePath(startNode, endNode)
	local usedNodes = {[startNode.id] = true}
	local currentNodes = {}
	local ways = {}

	for id, distance in pairs(startNode.neighbours) do
		usedNodes[id] = true
		currentNodes[id] = distance
		ways[id] = {startNode.id}
	end

	while true do
		local currentNode = -1
		local maxDistance = 10000

		for id, distance in pairs(currentNodes) do
			if distance < maxDistance then
				currentNode = id
				maxDistance = distance
			end
		end

		if currentNode == -1 then
			return false
		end

		if endNode.id == currentNode then
			local lastNode = currentNode
			local foundedNodes = {}

			while (tonumber(lastNode) ~= nil) do
				local node = getVehicleNodeByID(lastNode)
				table.insert(foundedNodes, 1, node)
				lastNode = ways[lastNode]
			end

			return foundedNodes
		end

		for id, distance in pairs(getVehicleNodeByID(currentNode).neighbours) do
			if not usedNodes[id] then
				ways[id] = currentNode
				currentNodes[id] = maxDistance + distance
				usedNodes[id] = true
			end
		end

		currentNodes[currentNode] = nil
	end
end

function getVehicleNodeByID(nodeID)
	local areaID = floor(nodeID / 65536)
	if areaID >= 0 and areaID <= 63 then
		return vehicleNodes[areaID][nodeID]
	end
end

function getVehicleNodeClosestToPoint(x, y)
	local foundedNode = -1
	local lastNodeDistance = 10000
	local areaID = floor((y + 3000) / 750) * 8 + floor((x + 3000) / 750)

	if not vehicleNodes[areaID] then
		return false
	end

	for _, node in pairs(vehicleNodes[areaID]) do
		local nodeDistance = getDistanceBetweenPoints2D(x, y, node.x, node.y)

		if lastNodeDistance > nodeDistance then
			lastNodeDistance = nodeDistance
			foundedNode = node
		end
	end

	return foundedNode
end
