if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
JobModes = JobModes or {}

local RACE = JOBS_CONFIG.RACE

-- player -> { match, vehicle, model, pos = {x, y, z, rot}, prev = {x, y, z}, locked,
--             lastRecover, lastManual, recovering, offSince }
-- Tracks enough state per racer to lock them in their vehicle and to put them back on the
-- road at their last checkpoint (death, explosion, water, off the route, under the map).
local raceState = {}

-- setPedCanBeKnockedOffBike is client-side only, so we ask the player's own
-- client to flip it instead of calling it (nonexistent) from the server.
local function setKnockOffBike(player, canBeKnockedOff)
    triggerClientEvent(player, "jobmanager:setKnockOffBike", resourceRoot, canBeKnockedOff)
end

local function releasePlayer(player)
    local state = raceState[player]
    if not state then return end
    raceState[player] = nil
    if isElement(player) then
        setKnockOffBike(player, true)
        triggerClientEvent(player, "jobmanager:raceRacing", resourceRoot, false)
        triggerClientEvent(player, "jobmanager:raceCp", resourceRoot, false)
    end
end

-- GTA heading (0 = north, counter-clockwise) from a towards b
local function headingTo(a, b)
    if not b then return 0 end
    return (math.deg(math.atan2(-(b[1] - a[1]), b[2] - a[2]))) % 360
end

local function routePoint(route, index)
    local cp = route.checkpoints[index]
    if cp then return cp, false end
    if index == #route.checkpoints + 1 then return route.finish, true end
end

-- 3D distance of a point from the segment a-b
local function segmentDistance(px, py, pz, a, b)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local len2 = dx * dx + dy * dy + dz * dz
    local t = 0
    if len2 > 0 then
        t = math.max(0, math.min(1, ((px - a[1]) * dx + (py - a[2]) * dy + (pz - a[3]) * dz) / len2))
    end
    local cx, cy, cz = a[1] + dx * t, a[2] + dy * t, a[3] + dz * t
    return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2 + (pz - cz) ^ 2)
end

--------------------------------------------------------------------------------
-- putting a racer back on the route
--------------------------------------------------------------------------------

local function setGhost(match, vehicle)
    setElementData(vehicle, "jobs.ghost", true)
    table.insert(match.timers, setTimer(function()
        if isElement(vehicle) then setElementData(vehicle, "jobs.ghost", false) end
    end, RACE.ghostMs, 1))
end

-- Last checkpoint reached (or the start line), facing the next checkpoint. A blown up or burning
-- vehicle is replaced by a fresh one, otherwise the same vehicle is repaired.
local function putBack(player)
    local state = raceState[player]
    if not state or not isElement(player) then return end
    local match, pos = state.match, state.pos
    if match.ended or match.finished[player] then return end
    local x, y, z, rot = pos[1], pos[2], pos[3] + 0.5, pos[4] or 0

    local vehicle = state.vehicle
    if not isElement(vehicle) or isVehicleBlown(vehicle) or getElementHealth(vehicle) <= 300 then
        if isElement(vehicle) then destroyElement(vehicle) end
        vehicle = createVehicle(state.model, x, y, z, 0, 0, rot)
        if not vehicle then return end
        setElementDimension(vehicle, match.dimension)
        table.insert(match.vehicles, vehicle)
        state.vehicle = vehicle
    else
        fixVehicle(vehicle)
        setElementPosition(vehicle, x, y, z)
        setElementRotation(vehicle, 0, 0, rot)
        setElementVelocity(vehicle, 0, 0, 0)
        setElementAngularVelocity(vehicle, 0, 0, 0)
    end

    if isPedDead(player) then
        spawnPlayer(player, x, y, z, rot, getElementModel(player), 0, match.dimension)
    end
    setElementInterior(player, 0)
    setElementDimension(player, match.dimension)
    if getPedOccupiedVehicle(player) ~= vehicle then warpPedIntoVehicle(player, vehicle) end
    setKnockOffBike(player, false)

    setElementFrozen(vehicle, true)
    table.insert(match.timers, setTimer(function()
        if isElement(vehicle) then setElementFrozen(vehicle, false) end
    end, 1000, 1))
    setGhost(match, vehicle)

    if state.offSince then
        state.offSince = nil
        triggerClientEvent(player, "jobmanager:raceOffRoute", resourceRoot, false)
    end
    if next(match.spectators) then Spectate.refresh(match) end
end

-- reason: wasted | explode | water | route | fall | manual. A death always respawns (even inside
-- the cooldown), the other reasons wait RACE.recoverCooldown between two recoveries.
local function recoverRacer(player, reason)
    local state = raceState[player]
    if not state or state.recovering or state.match.ended or state.match.finished[player] then return false end
    local now = getTickCount()
    if reason ~= "wasted" and now - (state.lastRecover or -RACE.recoverCooldown) < RACE.recoverCooldown then return false end
    state.recovering, state.lastRecover = true, now
    fadeCamera(player, false, 0.4)
    table.insert(state.match.timers, setTimer(function()
        state.recovering = nil
        if raceState[player] == state then putBack(player) end
        if isElement(player) then fadeCamera(player, true, 0.6) end
    end, 450, 1))
    return true
end

--------------------------------------------------------------------------------
-- checkpoints, finish, time limit
--------------------------------------------------------------------------------

local function sendCheckpoint(player, route, index)
    local cp, isFinish = routePoint(route, index)
    local nextCp, nextFinish = routePoint(route, index + 1)
    local after = not nextFinish and nextCp and routePoint(route, index + 2) or nil
    triggerClientEvent(player, "jobmanager:raceCp", resourceRoot, {
        cp = cp, isFinish = isFinish, next = (not isFinish) and nextCp or false, nextFinish = nextFinish or false,
        after = after or false, index = index, total = #route.checkpoints + 1,
    })
end

local function startFinishLimit(match, endMatch)
    if match.finishLimitStarted then return end
    match.finishLimitStarted = true
    local ms = RACE.finishLimit * 1000
    for _, player in ipairs(match.players) do
        if isElement(player) and not match.left[player] then
            triggerClientEvent(player, "jobmanager:raceFinishLimit", resourceRoot, ms)
        end
    end
    table.insert(match.timers, setTimer(function()
        if not match.ended then endMatch(match, L.msg("v_jobmanager.mode_race.time_up")) end
    end, ms, 1))
end

local function allFinished(match)
    for _, participant in ipairs(match.players) do
        if not match.finished[participant] then return false end
    end
    return true
end

local createCheckpoint
local CP_HIT_BELOW, CP_HIT_HEIGHT = 6, 18      -- hit tube around a checkpoint point (m)

local function finishRace(match, player, endMatch)
    match.finished[player] = true
    table.insert(match.finishOrder, player)
    match.finishTime[player] = getTickCount() - (match.raceStartTick or getTickCount())
    local state = raceState[player]
    releasePlayer(player)
    if allFinished(match) then
        endMatch(match, L.msg("v_jobmanager.core.everyone_finished_race"))
        return
    end
    startFinishLimit(match, endMatch)
    -- watch the others; the vehicle leaves the track once the camera moved away
    Spectate.start(match, player, 1500)
    local vehicle = state and state.vehicle
    table.insert(match.timers, setTimer(function()
        if isElement(vehicle) then destroyElement(vehicle) end
    end, 1700, 1))
    Spectate.refresh(match)
end

function createCheckpoint(match, player, endMatch)
    local route = match.job.race
    local index = match.progress[player] or 1
    local point, isFinish = routePoint(route, index)
    if not point then endMatch(match, L.msg("v_jobmanager.mode_race.invalid_race_configuration")) return end

    -- only the hit counts, the player's client draws the checkpoint (mode_race/client). A colshape,
    -- not a GTA "checkpoint" marker: those still draw their arrow and ring at alpha 0.
    local size = point[4] or 5
    local marker = createColTube(point[1], point[2], point[3] - CP_HIT_BELOW, size, CP_HIT_HEIGHT)
    setElementDimension(marker, match.dimension)
    table.insert(match.markers, marker)
    sendCheckpoint(player, route, index)
    addEventHandler("onColShapeHit", marker, function(hitElement, matchingDimension)
        if not matchingDimension or match.ended then return end
        if hitElement ~= player and (getElementType(hitElement) ~= "vehicle" or getVehicleController(hitElement) ~= player) then return end
        if not isElement(marker) then return end
        if isElement(marker) then destroyElement(marker) end
        triggerClientEvent(player, "jobmanager:raceCpHit", resourceRoot, isFinish)
        if isFinish then
            finishRace(match, player, endMatch)
        else
            local state = raceState[player]
            if state then
                state.prev = { point[1], point[2], point[3] }
                state.pos = { point[1], point[2], point[3], headingTo(point, (routePoint(route, index + 1))) }
            end
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
        table.insert(match.timers, setTimer(function() startCountdown(match, endMatch, count - 1) end, 1000, 1))
        return
    end

    for _, player in ipairs(match.players) do
        triggerClientEvent(player, "jobmanager:raceCountdown", resourceRoot, "GO")
    end
    for _, vehicle in ipairs(match.vehicles) do if isElement(vehicle) then setElementFrozen(vehicle, false) end end
    match.raceStartTick = getTickCount()
    for _, player in ipairs(match.players) do
        if raceState[player] then createCheckpoint(match, player, endMatch) end
    end
end

--------------------------------------------------------------------------------
-- off the route / under the map (server, 1 Hz)
--------------------------------------------------------------------------------

local function checkRoute(match)
    local route = match.job.race
    local limit = route.offRoute or RACE.offRoute
    local now = getTickCount()
    for _, player in ipairs(match.players) do
        local state = raceState[player]
        local vehicle = state and state.vehicle
        if state and not state.recovering and not match.finished[player] and isElement(vehicle) and not isPedDead(player) then
            local x, y, z = getElementPosition(vehicle)
            if z < match.raceMinZ - RACE.fallBelow then
                recoverRacer(player, "fall")
            elseif limit > 0 then
                local target = routePoint(route, match.progress[player] or 1)
                local off = target and segmentDistance(x, y, z, state.prev, target) > limit
                if off and not state.offSince then
                    state.offSince = now
                    triggerClientEvent(player, "jobmanager:raceOffRoute", resourceRoot, RACE.offRouteGrace * 1000)
                elseif off and now - state.offSince >= RACE.offRouteGrace * 1000 then
                    recoverRacer(player, "route")
                elseif not off and state.offSince then
                    state.offSince = nil
                    triggerClientEvent(player, "jobmanager:raceOffRoute", resourceRoot, false)
                end
            end
        end
    end
end

-- place 1..n of a racer right now: finished first, then checkpoint progress, then distance
local function livePlace(match, player)
    local route = match.job.race
    local function key(p)
        local state = raceState[p]
        local target = routePoint(route, match.progress[p] or 1)
        local dist = 0
        if state and target and isElement(state.vehicle) then
            local x, y, z = getElementPosition(state.vehicle)
            dist = getDistanceBetweenPoints3D(x, y, z, target[1], target[2], target[3])
        end
        return match.progress[p] or 1, dist
    end
    local place = #match.finishOrder + 1
    local myProgress, myDist = key(player)
    for _, other in ipairs(match.players) do
        if other ~= player and not match.finished[other] and not match.left[other] then
            local progress, dist = key(other)
            if progress > myProgress or (progress == myProgress and dist < myDist) then place = place + 1 end
        end
    end
    return place
end

--------------------------------------------------------------------------------
-- mode
--------------------------------------------------------------------------------

JobModes[JOB_TYPE_RACE] = {
    validate = function(game)
        local race = game.race
        if type(race) ~= "table" then return false, "missing race block" end
        if type(race.vehicles) ~= "table" or type(race.vehicles[1]) ~= "number" then return false, "race.vehicles needs a vehicle model" end
        if not validatePoints(race.spawnpoints, 3, game.maxPlayers) then return false, "race.spawnpoints needs at least maxPlayers {x,y,z,rot}" end
        if not validatePoints(race.checkpoints, 3, 0) then return false, "invalid race.checkpoints" end
        if not validatePoints({ race.finish }, 3, 1) then return false, "invalid race.finish" end
        if race.offRoute ~= nil and (type(race.offRoute) ~= "number" or race.offRoute < 0) then return false, "race.offRoute must be a number >= 0" end
        return true
    end,
    start = function(match, endMatch)
        local route = match.job.race
        if not route or #route.spawnpoints < #match.players then
            endMatch(match, L.msg("v_jobmanager.mode_race.race_configuration_is_incomplete"))
            return
        end
        local minZ = math.huge
        for _, list in ipairs({ route.spawnpoints, route.checkpoints, { route.finish } }) do
            for _, p in ipairs(list) do minZ = math.min(minZ, p[3]) end
        end
        match.raceMinZ = minZ
        local vehicleModel = route.vehicles[1] or 411
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
                prev = { spawn[1], spawn[2], spawn[3] },
                locked = true,
            }
            setKnockOffBike(player, false)
            triggerClientEvent(player, "jobmanager:raceRacing", resourceRoot, true, vehicleModel)
        end
        table.insert(match.timers, setTimer(function() startCountdown(match, endMatch, 3) end, 1000, 1))
        table.insert(match.timers, setTimer(function() if not match.ended then checkRoute(match) end end, 1000, 0))
    end,

    -- Called by the core once the match is over (finish, time limit, resource stop) so we
    -- release everyone still locked in their vehicle and restore their normal bike physics.
    onEnd = function(match)
        for _, player in ipairs(match.players) do
            if raceState[player] and raceState[player].match == match then releasePlayer(player) end
            if isElement(player) then triggerClientEvent(player, "jobmanager:raceFinishLimit", resourceRoot, false) end
        end
    end,

    -- left the match or quit: counts as not finished, the vehicle goes
    onPlayerGone = function(match, player, endMatch)
        local state = raceState[player]
        local vehicle = state and state.match == match and state.vehicle
        releasePlayer(player)
        if isElement(player) then removePedFromVehicle(player) end
        if isElement(vehicle) then destroyElement(vehicle) end
        if isElement(player) then triggerClientEvent(player, "jobmanager:raceFinishLimit", resourceRoot, false) end
        match.finished[player] = true
        if allFinished(match) then endMatch(match, L.msg("v_jobmanager.core.everyone_finished_race")) end
    end,

    canBeSpectated = function(match, player)
        return not match.finished[player] and raceState[player] ~= nil
    end,
    spectateInfo = function(match, player)
        local route = match.job.race
        return L.msg("v_jobmanager.spectate.race_info", {
            place = livePlace(match, player), cp = math.max(0, (match.progress[player] or 1) - 1),
            total = #route.checkpoints + 1,
        })
    end,
}

-- A player who dies mid-race (fall, explosion, drowning, ...) is revived at the last checkpoint.
addEventHandler("onPlayerWasted", root, function()
    if raceState[source] then recoverRacer(source, "wasted") end
end)

-- A blown up race vehicle: a fresh one at the last checkpoint after a moment.
addEventHandler("onVehicleExplode", root, function()
    local vehicle = source
    for player, state in pairs(raceState) do
        if state.vehicle == vehicle then
            table.insert(state.match.timers, setTimer(function()
                if raceState[player] == state and state.vehicle == vehicle then recoverRacer(player, "explode") end
            end, 1500, 1))
            return
        end
    end
end)

-- reason: "water" (the client saw the vehicle in the water) | "manual" (job menu)
addEvent("jobmanager:raceRecover", true)
addEventHandler("jobmanager:raceRecover", resourceRoot, function(reason)
    local state = raceState[client]
    if not state or (reason ~= "water" and reason ~= "manual") then return end
    if reason == "manual" then
        local now = getTickCount()
        local wait = RACE.manualCooldown - (now - (state.lastManual or -RACE.manualCooldown))
        if wait > 0 then
            jobMessage(client, L.msg("v_jobmanager.mode_race.reset_wait", { seconds = math.ceil(wait / 1000) }))
            return
        end
        if recoverRacer(client, reason) then state.lastManual = now end
        return
    end
    recoverRacer(client, reason)
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
