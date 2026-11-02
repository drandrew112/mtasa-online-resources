-- FILE: mapEditorScriptingExtension_s.lua
-- PURPOSE: Prevent the map editor feature set being limited by what MTA can load from a map file by adding a script file to maps
-- VERSION: RemoveWorldObjects (v1) AutoLOD (v3)

local usedLODModels = {}
local LOD_MAP = {}

function onResourceStartOrStop(startedResource)
	local startEvent = eventName == "onResourceStart"
	local removeObjects = getElementsByType("removeWorldObject", source)

	for removeID = 1, #removeObjects do
		local objectElement = removeObjects[removeID]
		local objectModel = getElementData(objectElement, "model")
		local objectLODModel = getElementData(objectElement, "lodModel")
		local posX = getElementData(objectElement, "posX")
		local posY = getElementData(objectElement, "posY")
		local posZ = getElementData(objectElement, "posZ")
		local objectInterior = getElementData(objectElement, "interior") or 0
		local objectRadius = getElementData(objectElement, "radius")

		if startEvent then
			removeWorldModel(objectModel, objectRadius, posX, posY, posZ, objectInterior)
			removeWorldModel(objectLODModel, objectRadius, posX, posY, posZ, objectInterior)
		else
			restoreWorldModel(objectModel, objectRadius, posX, posY, posZ, objectInterior)
			restoreWorldModel(objectLODModel, objectRadius, posX, posY, posZ, objectInterior)
		end
	end

	if startEvent then
		local resourceName = getResourceName(startedResource)
		local useLODs = get(resourceName..".useLODs")
		local objectsTable = getElementsByType("object", source)
		if useLODs then

			for objectID = 1, #objectsTable do
				local objectElement = objectsTable[objectID]
				local objectModel = getElementModel(objectElement)
				local lodModel = LOD_MAP[objectModel]

				if lodModel then
					local objectX, objectY, objectZ = getElementPosition(objectElement)
					local objectRX, objectRY, objectRZ = getElementRotation(objectElement)
					local objectInterior = getElementInterior(objectElement)
					local objectDimension = getElementDimension(objectElement)
					local lodObject = createObject(lodModel, objectX, objectY, objectZ, objectRX, objectRY, objectRZ, true)

					setElementInterior(lodObject, objectInterior)
					setElementDimension(lodObject, objectDimension)

					setElementParent(lodObject, objectElement)
					setLowLODElement(objectElement, lodObject)

					usedLODModels[lodModel] = true
				end
			end
		end

		for i = 1, #objectsTable do
			local objectElement = objectsTable[i]
			local x, y, z = getElementPosition(objectElement)
			local offsetX = tonumber(getElementData(objectElement, "moveX"))
			local offsetY = tonumber(getElementData(objectElement, "moveY"))
			local offsetZ = tonumber(getElementData(objectElement, "moveZ"))
			if (offsetX and math.abs(offsetX) > 0) or (offsetY and math.abs(offsetY) > 0) or (offsetZ and math.abs(offsetZ) > 0) then
				if not offsetX then offsetX = 0 end
				if not offsetY then offsetY = 0 end
				if not offsetZ then offsetZ = 0 end

				local speed = tonumber(getElementData(objectElement, "moveSpeed")) or 1
				local delay = tonumber(getElementData(objectElement, "moveDelay")) or 0
				local time = getDistanceBetweenPoints3D(x,y,z,x + offsetX,y + offsetY,z + offsetZ) / speed * 1000

				local currentPosX, currentPosY, currentPosZ = getElementPosition(objectElement)
				local endPosX = currentPosX + offsetX
				local endPosY = currentPosY + offsetY
				local endPosZ = currentPosZ + offsetZ
				local properties = {
					moveTime = time,
					delay = delay,
					initialPosX = currentPosX,
					initialPosY = currentPosY,
					initialPosZ = currentPosZ,
					endPosX = endPosX,
					endPosY = endPosY,
					endPosZ = endPosZ,
				}
				if delay > 0 then
					setTimer(onObjectReachedInitialPosition, delay, 1, objectElement, properties)
				else
					onObjectReachedInitialPosition(objectElement, properties)
				end
			end
		end
	end
end
addEventHandler("onResourceStart", resourceRoot, onResourceStartOrStop)
addEventHandler("onResourceStop", resourceRoot, onResourceStartOrStop)

function onObjectReachedEndPosition(objectElement, properties)
	if not isElement(objectElement) then return end
	stopObject(objectElement)
	local time = properties.moveTime
	local delay = properties.delay
	local initialPosX = properties.initialPosX
	local initialPosY = properties.initialPosY
	local initialPosZ = properties.initialPosZ
	moveObject(objectElement, time, initialPosX, initialPosY, initialPosZ)
	setTimer(onObjectReachedInitialPosition, time + delay, 1, objectElement, properties)
end

function onObjectReachedInitialPosition(objectElement, properties)
	if not isElement(objectElement) then return end
	stopObject(objectElement)
	local time = properties.moveTime
	if not time then return end
	local delay = properties.delay
	local endPosX = properties.endPosX
	local endPosY = properties.endPosY
	local endPosZ = properties.endPosZ
	moveObject(objectElement, time, endPosX, endPosY, endPosZ)
	setTimer(onObjectReachedEndPosition, time + delay, 1, objectElement, properties)
end

local function onPlayerResourceStart(resourceElement)
	local mapResource = resourceElement == resource

	if not mapResource then
		return
	end

	triggerClientEvent(source, "setLODsClient", resourceRoot, usedLODModels)
end
addEventHandler("onPlayerResourceStart", root, onPlayerResourceStart)

-- MTA LOD Table [object] = [lodmodel] trimmed to only include objects used in map

LOD_MAP = {

}
