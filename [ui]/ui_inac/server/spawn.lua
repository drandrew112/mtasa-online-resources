if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Spawns vehicles requested from the interaction menu.
-- Each player keeps at most one menu-spawned vehicle: spawning a new one
-- removes the previous.
--
-- Rules:
--   * only in interior 0 / dimension 0
--   * not while riding in a vehicle driven by another player
--   * no rail vehicles (trains, carriages, tram)

local spawnedVehicles = {} -- player -> vehicle

local function notify(player, title, text)
    triggerClientEvent(player, "ui_inac:notify", player, title, text)
end

local function removeSpawnedVehicle(player)
    local vehicle = spawnedVehicles[player]
    if isElement(vehicle) then
        destroyElement(vehicle)
    end
    spawnedVehicles[player] = nil
end

-- true when the player sits in a vehicle whose driver is another player
local function inOtherPlayersVehicle(player)
    local vehicle = getPedOccupiedVehicle(player)
    if not vehicle then return false end
    local driver = getVehicleController(vehicle)
    return isElement(driver) and driver ~= player and getElementType(driver) == "player"
end

addEvent("ui_inac:spawnVehicle", true)
addEventHandler("ui_inac:spawnVehicle", root, function(model)
    local player = client
    model = tonumber(model)
    if not isElement(player) or not model then return end
    if getVehicleType(model) == "Train" then return end

    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
        notify(player, L.msg("ui_inac.main.error"), L.msg("ui_inac.main.spawn_only_outside"))
        return
    end
    if inOtherPlayersVehicle(player) then
        notify(player, L.msg("ui_inac.main.error"), L.msg("ui_inac.main.spawn_not_as_passenger"))
        return
    end

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
