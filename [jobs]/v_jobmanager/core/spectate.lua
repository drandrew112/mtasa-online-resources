if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Spectating: a player who is out of a running match (DM: eliminated, race: finished, mission:
-- waiting for the respawn) watches the players still playing until the match ends.
--
-- The spectator's own ped stays in the match dimension, hidden (alpha 0, frozen, no collisions)
-- and attached 25 m above the watched player, so streaming and sounds follow the target. The
-- camera is the GTA follow camera of the target (setCameraTarget). The client picks the target
-- from a ui_inac temp menu (core/client/spectate.lua).
--
-- match.spectators[player] = { target = player | false }
-- A mode may define mode.canBeSpectated(match, player) and mode.spectateInfo(match, player)
-- (the short status line next to the name: place, checkpoint, health ...).

Spectate = {}

local FOLLOW_OFFSET = 25

local function targetsOf(match)
    local mode = JobModes[match.job.type]
    local list = {}
    for _, player in ipairs(match.players) do
        if isElement(player) and not match.left[player] and not match.spectators[player]
            and not isPedDead(player)
            and (not mode.canBeSpectated or mode.canBeSpectated(match, player)) then
            list[#list + 1] = player
        end
    end
    return list
end

local function follow(player, target)
    detachElements(player)
    if not isElement(target) then return end
    local carrier = getPedOccupiedVehicle(target) or target
    local x, y, z = getElementPosition(carrier)
    setElementPosition(player, x, y, z + FOLLOW_OFFSET)
    attachElements(player, carrier, 0, 0, FOLLOW_OFFSET)
end

local function sendState(match, player, entry, targets)
    local mode = JobModes[match.job.type]
    local list = {}
    for i, target in ipairs(targets) do
        list[i] = {
            player = target, name = match.playerNames[target] or jobDisplayName(target),
            info = mode.spectateInfo and mode.spectateInfo(match, target) or false,
        }
    end
    triggerClientEvent(player, "jobmanager:spectate", resourceRoot, {
        active = true, targets = list, current = entry.target or false, jobName = match.job.name,
    })
end

local function setTarget(match, player, entry, target)
    entry.target = target or false
    if target then
        follow(player, target)
        setCameraTarget(player, target)
    else
        detachElements(player)
        local cam = jobCamera(match)
        setCameraMatrix(player, cam.pos[1], cam.pos[2], cam.pos[3], cam.lookAt[1], cam.lookAt[2], cam.lookAt[3], cam.roll or 0, cam.fov or 90)
    end
end

-- Makes `player` a spectator (after `delay` ms, e.g. the DM death camera).
function Spectate.start(match, player, delay)
    if match.ended or match.spectators[player] or not isElement(player) then return end
    match.spectators[player] = { target = false, pending = true }
    local function begin()
        local entry = match.spectators[player]
        if match.ended or not entry or not isElement(player) then return end
        entry.pending = nil
        removePedFromVehicle(player)
        local x, y, z = getElementPosition(player)
        if isPedDead(player) then
            spawnPlayer(player, x, y, z + 2, 0, getElementModel(player), 0, match.dimension)
        end
        setElementDimension(player, match.dimension)
        setElementInterior(player, 0)
        setElementFrozen(player, true)
        setElementAlpha(player, 0)
        setElementCollisionsEnabled(player, false)
        setElementData(player, "jobs.spectating", true)
        local targets = targetsOf(match)
        setTarget(match, player, entry, targets[1])
        sendState(match, player, entry, targets)
    end
    if delay and delay > 0 then
        table.insert(match.timers, setTimer(begin, delay, 1))
    else
        begin()
    end
end

-- Back to playing (mission respawn) or out of the match: the ped is the caller's to place.
function Spectate.stop(match, player)
    local entry = match.spectators[player]
    if not entry then return end
    match.spectators[player] = nil
    if not isElement(player) then return end
    if not entry.pending then
        detachElements(player)
        setElementFrozen(player, false)
        setElementAlpha(player, 255)
        setElementCollisionsEnabled(player, true)
        setCameraTarget(player, player)
    end
    removeElementData(player, "jobs.spectating")
    triggerClientEvent(player, "jobmanager:spectate", resourceRoot, { active = false })
end

function Spectate.stopAll(match)
    local list = {}
    for player in pairs(match.spectators) do list[#list + 1] = player end
    for _, player in ipairs(list) do Spectate.stop(match, player) end
end

-- A player left the match: not a spectator any more, and nobody watches them.
function Spectate.forget(match, player)
    Spectate.stop(match, player)
end

function Spectate.isSpectating(match, player)
    local entry = match.spectators[player]
    return entry ~= nil and not entry.pending
end

-- Targets changed (finished, died, left, info): retarget where needed and resend the lists.
function Spectate.refresh(match)
    if match.ended then return end
    local targets = targetsOf(match)
    local valid = {}
    for _, target in ipairs(targets) do valid[target] = true end
    for player, entry in pairs(match.spectators) do
        if not entry.pending and isElement(player) then
            if not entry.target or not valid[entry.target] then
                setTarget(match, player, entry, targets[1])
            elseif isElement(entry.target) then
                -- the watched racer got a new vehicle (recovery): follow the new carrier
                local carrier = getPedOccupiedVehicle(entry.target) or entry.target
                if getElementAttachedTo(player) ~= carrier then follow(player, entry.target) end
            end
            sendState(match, player, entry, targets)
        end
    end
end

addEvent("jobmanager:spectateSet", true)
addEventHandler("jobmanager:spectateSet", resourceRoot, function(target)
    local match = jobPlayerMatch(client)
    local entry = match and match.spectators[client]
    if not entry or entry.pending or not isElement(target) then return end
    for _, candidate in ipairs(targetsOf(match)) do
        if candidate == target then
            if entry.target ~= target then setTarget(match, client, entry, target) end
            return
        end
    end
end)
