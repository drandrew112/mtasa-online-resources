if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Spectating: a player who is out of a running match (DM: eliminated, race: finished, mission:
-- waiting for the respawn) watches the players still playing until the match ends.
--
-- The spectator's own ped stays in the match dimension, hidden (alpha 0, frozen, no collisions).
-- The spectator's client moves it above the watched player and runs the camera (GTA follow camera
-- of the target); the server only keeps the target list. A server-side attach made the watched
-- players jump. The client picks the target from a locked ui_inac temp menu
-- (core/client/spectate.lua).
--
-- match.spectators[player] = { target = player | false }
-- A mode may define mode.canBeSpectated(match, player) and mode.spectateInfo(match, player)
-- (the short status line next to the name: place, checkpoint, health ...).

Spectate = {}

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
        camera = not entry.target and jobCamera(match) or nil,
    })
end

-- the camera itself is the client's (sendState / jobmanager:spectateSet)
local function setTarget(match, player, entry, target)
    entry.target = target or false
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
            setTarget(match, client, entry, target)
            return
        end
    end
    -- not watchable any more: the client gets the real list and target back
    sendState(match, client, entry, targetsOf(match))
end)
