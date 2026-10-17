if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Spawns vehicles requested from the interaction menu.
-- Each player keeps at most one menu-spawned vehicle: spawning a new one
-- replaces the previous. Players riding in the old vehicle are moved to the
-- same seat of the new one; who does not fit is left on foot.
--
-- Rules:
--   * not while in admin jail or in a job (v_jobmanager lobby/match)
--   * only in interior 0 / dimension 0
--   * not while riding in a vehicle driven by another player
--   * no rail vehicles (trains, carriages, tram)
--   * admin level 0: one spawn per SPAWN_COOLDOWN

local SPAWN_COOLDOWN = 60000 -- ms

local spawnedVehicles = {} -- player -> vehicle
local lastSpawn = {}       -- serial -> tick of the last spawn (survives reconnects)

local function notify(player, title, text)
    triggerClientEvent(player, "ui_inac:notify", player, title, text)
end

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function accData(player, key)
    if not resourceRunning("v_mysql") then return nil end
    return exports.v_mysql:getAccData(player, key)
end

local function adminLevel(player)
    return tonumber(accData(player, "admin_level")) or 0
end

local function isJailed(player)
    return accData(player, "adminjail") and true or false
end

local function inJob(player)
    if not resourceRunning("v_jobmanager") then return false end
    return exports.v_jobmanager:jobmanagerGetState(player) and true or false
end

-- true when the player sits in a vehicle whose driver is another player
local function inOtherPlayersVehicle(player)
    local vehicle = getPedOccupiedVehicle(player)
    if not vehicle then return false end
    local driver = getVehicleController(vehicle)
    return isElement(driver) and driver ~= player and getElementType(driver) == "player"
end

-- Destroys the player's previous vehicle. Returns the other players that were
-- inside it as { [seat] = player }; they are already taken out of it.
local function removeSpawnedVehicle(player)
    local vehicle = spawnedVehicles[player]
    spawnedVehicles[player] = nil
    local riders = {}
    if not isElement(vehicle) then return riders end

    for seat, occupant in pairs(getVehicleOccupants(vehicle) or {}) do
        if isElement(occupant) and getElementType(occupant) == "player" and occupant ~= player then
            riders[seat] = occupant
        end
        removePedFromVehicle(occupant)
    end
    destroyElement(vehicle)
    return riders
end

-- Seats the previous riders on the same seat of the new vehicle. The
-- spawner already holds seat 0, so a former driver is left on foot too.
local function seatRiders(vehicle, riders)
    local maxSeat = getVehicleMaxPassengers(vehicle) or 0
    for seat, rider in pairs(riders) do
        if isElement(rider) and seat ~= 0 and seat <= maxSeat
            and not getVehicleOccupant(vehicle, seat)
            and getElementInterior(rider) == 0 and getElementDimension(rider) == 0 then
            warpPedIntoVehicle(rider, vehicle, seat)
        end
    end
end

addEvent("ui_inac:spawnVehicle", true)
addEventHandler("ui_inac:spawnVehicle", root, function(model)
    local player = client
    model = tonumber(model)
    if not isElement(player) or not model then return end
    if getVehicleType(model) == "Train" then return end

    local errTitle = L.msg("ui_inac.main.error")

    if isJailed(player) then
        notify(player, errTitle, L.msg("ui_inac.main.spawn_jailed"))
        return
    end
    if inJob(player) then
        notify(player, errTitle, L.msg("ui_inac.main.spawn_in_job"))
        return
    end
    if getElementInterior(player) ~= 0 or getElementDimension(player) ~= 0 then
        notify(player, errTitle, L.msg("ui_inac.main.spawn_only_outside"))
        return
    end
    if inOtherPlayersVehicle(player) then
        notify(player, errTitle, L.msg("ui_inac.main.spawn_not_as_passenger"))
        return
    end

    local serial = getPlayerSerial(player)
    local now = getTickCount()
    if adminLevel(player) <= 0 and lastSpawn[serial] and now - lastSpawn[serial] < SPAWN_COOLDOWN then
        local seconds = math.ceil((SPAWN_COOLDOWN - (now - lastSpawn[serial])) / 1000)
        notify(player, errTitle, L.msg("ui_inac.main.spawn_cooldown", { seconds = seconds }))
        return
    end

    local riders = removeSpawnedVehicle(player)

    local x, y, z = getElementPosition(player)
    local rotation = getPedRotation(player)

    local vehicle = createVehicle(model, x, y, z + 1, 0, 0, rotation)
    if not vehicle then return end

    lastSpawn[serial] = now
    spawnedVehicles[player] = vehicle
    warpPedIntoVehicle(player, vehicle)
    seatRiders(vehicle, riders)
end)

addEventHandler("onPlayerQuit", root, function()
    removeSpawnedVehicle(source)
end)
