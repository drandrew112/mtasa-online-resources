JobModes = JobModes or {}

-- player -> { match, vehicle, model, pos = {x, y, z, rot}, locked }
-- Tracks enough state per racer to lock them in their vehicle and to put
-- them back on the road at their last checkpoint if they die mid-race.
local raceState = {}

-- setPedCanBeKnockedOffBike is client-side only, so we ask the player's own
-- client to flip it instead of calling it (nonexistent) from the server.
local function setKnockOffBike(player, canBeKnockedOff)
    triggerClientEvent(player, "jobmanager:setKnockOffBike", resourceRoot, canBeKnockedOff)
end

local function releasePlayer(player)
    local state = raceState[player]
    if not state then return end
    if isElement(player) then setKnockOffBike(player, true) end
    raceState[player] = nil
end

-- Revives the player at the last checkpoint they reached (or the start
-- line) and puts them back in a vehicle. If their vehicle blew up, a fresh
-- one is created in its place instead of reusing the wreck.
local function respawnAtCheckpoint(player)
    local state = raceState[player]
    if not state or not isElement(player) then return end
    local match, pos = state.match, state.pos

    local vehicle = state.vehicle
    if not isElement(vehicle) or isVehicleBlown(vehicle) then
        if isElement(vehicle) then destroyElement(vehicle) end
        vehicle = createVehicle(state.model, pos[1], pos[2], pos[3], 0, 0, pos[4] or 0)
        setElementDimension(vehicle, match.dimension)
        table.insert(match.vehicles, vehicle)
        state.vehicle = vehicle
    else
        setElementPosition(vehicle, pos[1], pos[2], pos[3])
        setElementRotation(vehicle, 0, 0, pos[4] or 0)
        setElementVelocity(vehicle, 0, 0, 0)
        setElementAngularVelocity(vehicle, 0, 0, 0)
    end

    spawnPlayer(player, pos[1], pos[2], pos[3], pos[4] or 0, getElementModel(player), 0, match.dimension)
    setElementInterior(player, 0)
    setElementDimension(player, match.dimension)
    warpPedIntoVehicle(player, vehicle)
    setKnockOffBike(player, false)
end

local function createCheckpoint(match, player, endMatch)
    local route = races[match.job.raceId]
    local index = match.progress[player] or 1
    local point, isFinish = route.checkpoints[index], false
    if not point then point, isFinish = route.finish, true end
    if not point then endMatch(match, "Invalid race configuration.") return end

    local marker = createMarker(point[1], point[2], point[3], "checkpoint", point[4] or 5, isFinish and 0 or 255, isFinish and 180 or 255, 0, 140, player)
    setElementDimension(marker, match.dimension)
    table.insert(match.markers, marker)
    addEventHandler("onMarkerHit", marker, function(hitElement, matchingDimension)
        if hitElement ~= player or not matchingDimension or match.ended then return end
        if isElement(marker) then destroyElement(marker) end
        if isFinish then
            match.finished[player] = true
            table.insert(match.finishOrder, player)
            match.finishTime[player] = getTickCount() - (match.raceStartTick or getTickCount())
            releasePlayer(player)
            for _, participant in ipairs(match.players) do if not match.finished[participant] then return end end
            endMatch(match, "Everyone finished the race.")
        else
            local state = raceState[player]
            if state then state.pos = { point[1], point[2], point[3], 0 } end
            match.progress[player] = index + 1
            createCheckpoint(match, player, endMatch)
        end
    end)
end

-- 3-2-1-GO countdown, ~1s per tick, sent to every player in the match.
-- Vehicles stay frozen until "GO".
local function startCountdown(match, endMatch, count)
    if match.ended then return end
    if count > 0 then
        for _, player in ipairs(match.players) do
            triggerClientEvent(player, "jobmanager:raceCountdown", resourceRoot, count)
        end
        -- match/endMatch must travel as upvalues, not setTimer arguments:
        -- setTimer clones table arguments and drops function arguments
        -- entirely, which silently detaches match from the real one in
        -- core and turns endMatch into a nil call a few hops down the line.
        setTimer(function() startCountdown(match, endMatch, count - 1) end, 1000, 1)
        return
    end

    for _, player in ipairs(match.players) do
        triggerClientEvent(player, "jobmanager:raceCountdown", resourceRoot, "GO")
    end
    for _, vehicle in ipairs(match.vehicles) do if isElement(vehicle) then setElementFrozen(vehicle, false) end end
    match.raceStartTick = getTickCount()
    for _, player in ipairs(match.players) do createCheckpoint(match, player, endMatch) end
end

JobModes[JOB_TYPE_RACE] = {
    start = function(match, endMatch)
        local route = races[match.job.raceId]
        if not route or not route.settings or not route.spawnpoints or #route.spawnpoints < #match.players then
            endMatch(match, "Race configuration is incomplete.")
            return
        end
        local vehicleModel = route.settings.vehicles[1] or 411
        for index, player in ipairs(match.players) do
            local spawn = route.spawnpoints[index]
            local vehicle = createVehicle(vehicleModel, spawn[1], spawn[2], spawn[3], 0, 0, spawn[4] or 0)
            setElementInterior(player, 0)
            setElementDimension(player, match.dimension)
            setElementDimension(vehicle, match.dimension)
            warpPedIntoVehicle(player, vehicle)
            setElementFrozen(vehicle, true)
            table.insert(match.vehicles, vehicle)
            match.progress[player], match.finished[player] = 1, false
            raceState[player] = {
                match = match, vehicle = vehicle, model = vehicleModel,
                pos = { spawn[1], spawn[2], spawn[3], spawn[4] or 0 },
                locked = true,
            }
            setKnockOffBike(player, false)
        end
        setTimer(function() startCountdown(match, endMatch, 3) end, 1000, 1)
    end,

    -- Called by the core once the match is over (finish, resource stop, or
    -- every remaining player disconnected) so we release everyone still
    -- locked in their vehicle and restore their normal bike physics.
    onEnd = function(match)
        for _, player in ipairs(match.players) do releasePlayer(player) end
    end,
}

-- A player who dies mid-race (fall, explosion, drowning, ...) is revived on
-- the spot instead of being left dead waiting for a checkpoint hit that can
-- never come.
addEventHandler("onPlayerWasted", root, function()
    local state = raceState[source]
    if not state or state.match.ended or state.match.finished[source] then return end
    respawnAtCheckpoint(source)
end)

-- Keep racers in their vehicle for the length of the race: no bailing out,
-- no getting jacked. Forced removals (vehicle blown up, scripted teleport)
-- are left alone since cancelling those has no effect anyway.
addEventHandler("onVehicleStartExit", root, function(player, seat, forced)
    if forced then return end
    local state = raceState[player]
    if state and state.locked and not state.match.ended and not state.match.finished[player] then
        cancelEvent()
    end
end)
