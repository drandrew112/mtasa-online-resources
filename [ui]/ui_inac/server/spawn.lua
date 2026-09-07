-- Spawns vehicles requested from the interaction menu.
-- Each player keeps at most one menu-spawned vehicle: spawning a new one
-- removes the previous.

local spawnedVehicles = {} -- player -> vehicle

local function removeSpawnedVehicle(player)
    local vehicle = spawnedVehicles[player]
    if isElement(vehicle) then
        destroyElement(vehicle)
    end
    spawnedVehicles[player] = nil
end

addEvent("ui_inac:spawnVehicle", true)
addEventHandler("ui_inac:spawnVehicle", root, function(model)
    local player = client
    model = tonumber(model)
    if not isElement(player) or not model then return end

    removeSpawnedVehicle(player)

    local x, y, z = getElementPosition(player)
    local rotation = getPedRotation(player)

    local vehicle = createVehicle(model, x, y, z + 1, 0, 0, rotation)
    if not vehicle then return end

    spawnedVehicles[player] = vehicle
    warpPedIntoVehicle(player, vehicle)
end)

addEventHandler("onPlayerQuit", root, function()
    removeSpawnedVehicle(source)
end)
