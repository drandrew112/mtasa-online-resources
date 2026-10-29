if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
local lobbies, matches, playerState = {}, {}, {}
local nextLobbyId, nextMatchId = 1, 1
local jobMarkers = {}

-- Player-facing messages are ui_core notifications (v_chat hides outputChatBox). The colour
-- arguments of the old call sites are ignored.
local function message(player, text)
    if isElement(player) then triggerClientEvent(player, "jobmanager:notify", resourceRoot, text) end
end
jobMessage = message

local function snapshotPlayer(player)
    local x, y, z = getElementPosition(player)
    return { x = x, y = y, z = z, dimension = getElementDimension(player), interior = getElementInterior(player) }
end

-- [weapon]/wp_manager (soft dependency): a match gives a temporary loadout that hides the
-- player's own weapons; clearing it gives them back.
function weaponManagerRunning()
    local res = getResourceFromName("wp_manager")
    return res and getResourceState(res) == "running"
end

-- keepSave: creator test runs, where v_jobcreator owns "save.position"
local function restorePlayer(player, state, keepSave)
    if not isElement(player) then return end
    if not keepSave then removeElementData(player, "save.position") end
    if weaponManagerRunning() then
        exports.wp_manager:clearPlayerTempLoadout(player)
    else
        takeAllWeapons(player)
    end
    detachElements(player)
    setElementFrozen(player, false)
    setElementAlpha(player, 255)
    setElementCollisionsEnabled(player, true)
    removePedFromVehicle(player)
    setElementInterior(player, state.interior)
    setElementDimension(player, state.dimension)
    if isPedDead(player) then
        spawnPlayer(player, state.x, state.y, state.z, 0, getElementModel(player), state.interior, state.dimension)
    else
        setElementPosition(player, state.x, state.y, state.z)
    end
    setCameraTarget(player, player)
end

local function removeFromList(list, player)
    for index, value in ipairs(list) do
        if value == player then
            table.remove(list, index)
            return true
        end
    end
    return false
end

local function destroyElements(elements)
    for _, element in ipairs(elements) do
        if isElement(element) then destroyElement(element) end
    end
end

-- Lobby invites are delivered to players through the ui_phone resource. We keep
-- that a soft dependency: if the phone is not running, inviting simply fails.
local function phoneReady()
    local res = getResourceFromName("ui_phone")
    return res and getResourceState(res) == "running"
end

-- Pull back any phone invites still pointing at a lobby that is about to vanish
-- (host started the job, or the lobby emptied out).
local function clearLobbyInvites(lobby)
    if not lobby.invited then return end
    for player in pairs(lobby.invited) do
        if isElement(player) and phoneReady() then
            exports.ui_phone:phoneRemoveInvite(player, tostring(lobby.id))
        end
    end
    lobby.invited = nil
end

local function createLobby(job)
    local lobby = { id = nextLobbyId, job = job, players = {}, host = nil, locked = false }
    nextLobbyId = nextLobbyId + 1
    lobbies[lobby.id] = lobby
    return lobby
end

-- Display name for UI/messages only (never stored); falls back to the nick
local function displayNameOf(player)
    return getElementData(player, "displayName") or getPlayerName(player)
end
jobDisplayName = displayNameOf

local function syncLobby(lobby)
    if not lobby then return end
    local names = {}
    for _, player in ipairs(lobby.players) do
        table.insert(names, {
            name = displayNameOf(player),
            host = player == lobby.host,
            crewTag = getElementData(player, "crewTag") or "",
            crewColor = getElementData(player, "crewColor"),
        })
    end
    -- invited players who have not answered yet: listed under the players ("INVITED" card);
    -- hidden while they are busy in another lobby or match
    local invited = {}
    if lobby.invited then
        for player in pairs(lobby.invited) do
            local state = isElement(player) and playerState[player]
            if not isElement(player) or (state and state.lobbyId == lobby.id) then
                lobby.invited[player] = nil
            elseif not state then
                table.insert(invited, {
                    name = displayNameOf(player),
                    crewTag = getElementData(player, "crewTag") or "",
                    crewColor = getElementData(player, "crewColor"),
                })
            end
        end
    end
    for _, player in ipairs(lobby.players) do
        triggerClientEvent(player, "jobmanager:lobby", resourceRoot, {
            id = lobby.id, name = lobby.job.name, type = lobby.job.type,
            players = names, invited = invited, min = lobby.job.minPlayers, max = lobby.job.maxPlayers,
            isHost = player == lobby.host,
            image = lobby.job.image, description = lobby.job.description, createdBy = lobby.job.createdBy,
        })
    end
end

local function getJoinableLobby(job)
    for _, lobby in pairs(lobbies) do
        if lobby.job.id == job.id and not lobby.locked and #lobby.players < job.maxPlayers then
            return lobby
        end
    end
end

local function leaveLobby(player, quiet)
    local state = playerState[player]
    if not state or state.kind ~= "lobby" then return false end
    local lobby = lobbies[state.lobbyId]
    playerState[player] = nil
    if not lobby then return false end
    local wasHost = lobby.host == player
    removeFromList(lobby.players, player)
    if wasHost then lobby.host = lobby.players[1] end
    if #lobby.players == 0 then
        clearLobbyInvites(lobby)
        lobbies[lobby.id] = nil
    else
        syncLobby(lobby)
    end
    triggerClientEvent(player, "jobmanager:closeUi", resourceRoot)
    if not quiet then message(player, L.msg("v_jobmanager.core.you_left_lobby")) end
    return true
end

-- Players inside v_jobcreator cannot join lobbies (and vice versa: the creator
-- refuses players that have a playerState here).
local function inCreator(player)
    return getElementData(player, "jobCreator") == true
end

local function joinJob(player, job)
    if inCreator(player) or job.scriptOnly then return false end
    if playerState[player] then
        message(player, L.msg("v_jobmanager.core.leave_your_current_lobby_or_match"), 255, 120, 120)
        return false
    end
    local lobby = getJoinableLobby(job) or createLobby(job)
    table.insert(lobby.players, player)
    if not lobby.host then lobby.host = player end
    playerState[player] = { kind = "lobby", lobbyId = lobby.id, returnState = snapshotPlayer(player) }
    syncLobby(lobby)
    message(player, L.msg("v_jobmanager.core.lobby", { id = lobby.id, players = #lobby.players, max_players = job.maxPlayers }))
    return true
end

local function joinLobbyById(player, lobbyId)
    if inCreator(player) then return false end
    if playerState[player] then
        message(player, L.msg("v_jobmanager.core.leave_your_current_lobby_or_match"), 255, 120, 120)
        return false
    end
    local lobby = lobbies[lobbyId]
    if not lobby or lobby.locked or #lobby.players >= lobby.job.maxPlayers then
        message(player, L.msg("v_jobmanager.core.that_lobby_is_no_longer_available"), 255, 120, 120)
        return false
    end
    table.insert(lobby.players, player)
    if not lobby.host then lobby.host = player end
    playerState[player] = { kind = "lobby", lobbyId = lobby.id, returnState = snapshotPlayer(player) }
    syncLobby(lobby)
    message(player, L.msg("v_jobmanager.core.lobby", { id = lobby.id, players = #lobby.players, max_players = lobby.job.maxPlayers }))
    return true
end

-- Random open lobby across ALL jobs, or a brand new lobby for a random job
-- if none are joinable right now.
local function quickJob(player)
    if inCreator(player) then return false end
    if playerState[player] then
        message(player, L.msg("v_jobmanager.core.leave_your_current_lobby_or_match"), 255, 120, 120)
        return false
    end
    local candidates = {}
    for _, lobby in pairs(lobbies) do
        if not lobby.locked and #lobby.players < lobby.job.maxPlayers then table.insert(candidates, lobby) end
    end
    if #candidates > 0 then
        local lobby = candidates[math.random(#candidates)]
        table.insert(lobby.players, player)
        if not lobby.host then lobby.host = player end
        playerState[player] = { kind = "lobby", lobbyId = lobby.id, returnState = snapshotPlayer(player) }
        syncLobby(lobby)
        message(player, L.msg("v_jobmanager.core.quick_joined", { name = lobby.job.name }))
        return true
    end
    if #jobs == 0 then
        message(player, L.msg("v_jobmanager.core.there_are_no_jobs_configured"), 255, 200, 100)
        return false
    end
    return joinJob(player, jobs[math.random(#jobs)])
end

-- Stats shown on the end-of-match scoreboard. `left` = the player left the match.
local function buildStats(match)
    local rows = {}
    local function crew(player)
        return match.crewTags[player] or "", match.crewColors[player]
    end
    if match.job.type == JOB_TYPE_RACE then
        for place, player in ipairs(match.finishOrder) do
            local tag, colour = crew(player)
            table.insert(rows, { name = match.playerNames[player] or "?", place = place, timeMs = match.finishTime[player], crewTag = tag, crewColor = colour })
        end
        for _, player in ipairs(match.players) do
            if not match.finishTime[player] then
                local tag, colour = crew(player)
                table.insert(rows, { name = match.playerNames[player] or "?", place = false, timeMs = false, crewTag = tag, crewColor = colour, left = match.left[player] or nil })
            end
        end
    else
        for _, player in ipairs(match.players) do
            local tag, colour = crew(player)
            table.insert(rows, {
                name = match.playerNames[player] or "?",
                kills = match.kills[player] or 0,
                deaths = match.deaths[player] or 0,
                crewTag = tag,
                crewColor = colour,
                left = match.left[player] or nil,
            })
        end
        table.sort(rows, function(a, b)
            if (a.left or false) ~= (b.left or false) then return not a.left end
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.deaths < b.deaths
        end)
    end
    return rows
end

local function averagePoint(points)
    local sx, sy, sz = 0, 0, 0
    for _, p in ipairs(points) do
        sx, sy, sz = sx + p[1], sy + p[2], sz + p[3]
    end
    local n = #points
    return sx / n, sy / n, sz / n
end

-- Fixed, generic scoreboard camera: reuse the authored race finish camera when
-- there is one, otherwise auto-compute a top-down shot from known job points.
-- Same mechanism for every match; never a specific player's own viewpoint.
-- Also the spectator camera when nobody is left to watch.
function jobCamera(match)
    local job = match.job
    local spawns
    if job.type == JOB_TYPE_RACE then
        local route = job.race
        if route and route.finishCamera then return route.finishCamera end
        spawns = route and route.spawnpoints
    elseif job.type == JOB_TYPE_DM then
        spawns = job.deathmatch and job.deathmatch.spawnpoints
    elseif job.type == JOB_TYPE_MISSION then
        spawns = job.mission and job.mission.spawnpoints
    end
    if spawns and #spawns > 0 then
        local cx, cy, cz = averagePoint(spawns)
        return { pos = { cx, cy, cz + 60 }, lookAt = { cx, cy, cz }, roll = 0, fov = 90 }
    end
    return { pos = { 0, 0, 100 }, lookAt = { 0, 0, 0 }, roll = 0, fov = 90 }
end

-- the running match of a player (modes use it from their own event handlers)
function jobPlayerMatch(player)
    local state = playerState[player]
    return state and state.kind == "match" and matches[state.matchId] or nil
end

function jobMatchById(id)
    return matches[id]
end

-- `aborted` (resource stop, broken job, script abort) skips the payouts (core/rewards.lua).
local function endMatch(match, reason, aborted)
    if not match or match.ended then return end
    match.ended = true
    for _, timer in ipairs(match.timers) do
        if isTimer(timer) then killTimer(timer) end
    end
    Spectate.stopAll(match)
    local mode = JobModes[match.job.type]
    if mode and mode.onEnd then mode.onEnd(match, aborted) end
    local stats = buildStats(match)
    local camera = jobCamera(match)
    local opts = match.opts
    local rewards = (not aborted and not opts.test) and buildRewards(match) or {}
    for _, player in ipairs(match.players) do
        local state = playerState[player]
        if state and state.matchId == match.id then
            restorePlayer(player, state.returnState, opts.test)
            playerState[player] = nil
            local reward = rewards[player]
            if reward then payReward(player, reward) end
            if opts.test or opts.quiet then
                triggerClientEvent(player, "jobmanager:matchQuietEnd", resourceRoot, reason, opts.test or false)
            else
                triggerClientEvent(player, "jobmanager:matchEnded", resourceRoot, {
                    reason = reason, jobId = match.job.id, jobName = match.job.name,
                    type = match.job.type, stats = stats, camera = camera, reward = reward,
                    replay = not match.job.scriptOnly and not opts.test,
                })
            end
        end
    end
    -- spectators who left (finished race, eliminated DM): the same reward as if they had stayed
    for player in pairs(match.rewardOnEnd) do
        local reward = rewards[player]
        if reward and isElement(player) then
            payReward(player, reward)
            message(player, L.msg("v_jobmanager.core.reward_paid_after_leave", {
                name = match.job.name, money = reward.money.total, xp = reward.xp.total,
            }))
        end
    end
    destroyElements(match.vehicles)
    destroyElements(match.markers)
    destroyElements(match.objects)
    matches[match.id] = nil
    if mode and mode.afterEnd then mode.afterEnd(match, reason, aborted) end
end
jobEndMatch = endMatch

-- Starts a match without a lobby (lobby start, script missions, creator test runs).
-- opts: { test, dimension, reward = false | {money, xp}, tag, returnTo = {x, y, z, interior, dimension},
--         startStage, quiet, script }
local function createMatch(job, players, opts)
    opts = opts or {}
    local mode = JobModes[job.type]
    if not mode then return false, L.msg("v_jobmanager.core.unsupported_job_type") end
    local id = nextMatchId
    nextMatchId = nextMatchId + 1
    local match = {
        id = id, job = job, players = players, dimension = opts.dimension or (50000 + id), opts = opts,
        vehicles = {}, markers = {}, objects = {}, progress = {}, finished = {}, eliminated = {},
        playerNames = {}, kills = {}, deaths = {}, finishOrder = {}, finishTime = {},
        crewTags = {}, crewColors = {}, left = {}, spectators = {}, timers = {}, rewardOnEnd = {},
        startPlayers = #players, startTick = getTickCount(),
        ended = false,
    }
    matches[id] = match
    -- the clients raise the LOD distance of these models for the match (core/client/objects.lua)
    local objectModels, seenModel = {}, {}
    for _, def in ipairs(job.objects or {}) do
        if not seenModel[def.model] then seenModel[def.model] = true objectModels[#objectModels + 1] = def.model end
    end
    for _, player in ipairs(players) do
        match.playerNames[player] = displayNameOf(player)
        match.crewTags[player] = getElementData(player, "crewTag") or ""
        match.crewColors[player] = getElementData(player, "crewColor")
        local state = playerState[player]
        if not state then
            state = { returnState = snapshotPlayer(player) }
            playerState[player] = state
        end
        state.kind, state.matchId, state.lobbyId = "match", id, nil
        if type(opts.returnTo) == "table" then state.returnState = opts.returnTo end
        -- while the job runs the account keeps the place the player came from (v_accounts savesys)
        if not opts.test then
            local r = state.returnState
            setElementData(player, "save.position", { r.x, r.y, r.z, r.interior, r.dimension }, false)
        end
        if weaponManagerRunning() then exports.wp_manager:setPlayerTempLoadout(player, {}) end
        triggerClientEvent(player, "jobmanager:matchStarted", resourceRoot, job.name,
            { id = id, type = job.type, name = job.name, test = opts.test or false,
              dimension = match.dimension, objectModels = objectModels })
    end
    for index, def in ipairs(job.objects or {}) do
        local object = createObject(def.model, def.x, def.y, def.z, def.rx or 0, def.ry or 0, def.rz or 0)
        if object then
            setElementDimension(object, match.dimension)
            -- many catalog models are dynamic in GTA: a knocked over cone would only move on one
            -- client. Frozen here, unbreakable + longer LOD on the clients (core/client/objects.lua)
            setElementFrozen(object, true)
            if def.scale then setObjectScale(object, def.scale) end
            if def.alpha then setElementAlpha(object, def.alpha) end
            if def.collisions == false then setElementCollisionsEnabled(object, false) end
            if def.doublesided then setElementDoubleSided(object, true) end
            table.insert(match.objects, object)
        else
            outputDebugString("[v_jobmanager] " .. job.id .. ": objects[" .. index .. "] model " .. tostring(def.model) .. " could not be created", 2)
        end
    end
    -- spectator lists (places, checkpoints, health change)
    table.insert(match.timers, setTimer(function()
        if not match.ended and next(match.spectators) then Spectate.refresh(match) end
    end, 2000, 0))
    mode.start(match, endMatch)
    return match
end

local function startMatch(lobby)
    if lobby.locked or #lobby.players < lobby.job.minPlayers then return false, L.msg("v_jobmanager.core.not_enough_players") end
    if not JobModes[lobby.job.type] then return false, L.msg("v_jobmanager.core.unsupported_job_type") end
    lobby.locked = true
    clearLobbyInvites(lobby)
    lobbies[lobby.id] = nil
    local match, err = createMatch(lobby.job, lobby.players, {})
    return match and true or false, err
end

-- A player drops out of a running match: left it (command / menu) or quit. The mode decides
-- whether that ends the match.
local function dropFromMatch(player, match, quit)
    if match.ended then return end
    match.left[player] = true
    Spectate.forget(match, player)
    local mode = JobModes[match.job.type]
    if mode and mode.onPlayerGone then mode.onPlayerGone(match, player, endMatch, quit) end
    if not match.ended and next(match.spectators) then Spectate.refresh(match) end
end

-- Leaving a running match: no reward and no penalty, back to where the player came from.
-- A spectator who is already out of the race / DM (finished, eliminated) keeps the reward: it is
-- paid when the match ends, computed the same way as for the others (endMatch).
local function leaveMatch(player)
    local state = playerState[player]
    if not state or state.kind ~= "match" then return false end
    local match = matches[state.matchId]
    playerState[player] = nil
    local test = match and match.opts.test
    local keepsReward = match and not test and not match.ended and match.spectators[player] ~= nil
        and match.job.type ~= JOB_TYPE_MISSION
    if keepsReward then match.rewardOnEnd[player] = true end
    if match then dropFromMatch(player, match, false) end
    restorePlayer(player, state.returnState, test)
    triggerClientEvent(player, "jobmanager:matchLeft", resourceRoot, test or false)
    if keepsReward then
        if matches[match.id] then message(player, L.msg("v_jobmanager.core.reward_after_match_end")) end
    elseif not test then
        message(player, L.msg("v_jobmanager.core.you_left_job"))
    end
    return true
end

addCommandHandler("quickjob", function(player)
    quickJob(player)
end)

local function requestStart(player)
    local state = playerState[player]
    local lobby = state and state.kind == "lobby" and lobbies[state.lobbyId]
    if not lobby then message(player, L.msg("v_jobmanager.core.you_are_not_in_lobby"), 255, 120, 120) return end
    if lobby.host ~= player then message(player, L.msg("v_jobmanager.core.only_lobby_host_can_start_job"), 255, 120, 120) return end
    local ok, err = startMatch(lobby)
    if not ok then message(player, err, 255, 120, 120) return end
    -- v_achievements is optional: only called while it runs
    local ach = getResourceFromName("v_achievements")
    if ach and getResourceState(ach) == "running" and isElement(player) then
        exports.v_achievements:unlockAchievement(player, "host_game")
    end
end

addCommandHandler("startjob", function(player)
    requestStart(player)
end)

-- A lobby is left at once; a running match only once confirmed (the client asks first).
local function requestLeave(player, confirmed)
    if leaveLobby(player) then return end
    local state = playerState[player]
    if state and state.kind == "match" then
        if confirmed then
            leaveMatch(player)
        else
            triggerClientEvent(player, "jobmanager:confirmLeave", resourceRoot)
        end
        return
    end
    message(player, L.msg("v_jobmanager.core.you_are_not_in_job"), 255, 200, 100)
end

addCommandHandler("leavejob", function(player, _, arg)
    requestLeave(player, arg == "confirm")
end)

-- UI entry points. They deliberately use `client`, never a player value
-- supplied by the caller, and all identifiers are checked against server config.
addEvent("jobmanager:joinJob", true)
addEventHandler("jobmanager:joinJob", resourceRoot, function(jobId)
    local job = type(jobId) == "string" and jobsById[jobId]
    if not job then return end
    joinJob(client, job)
end)

addEvent("jobmanager:requestJobs", true)
addEventHandler("jobmanager:requestJobs", resourceRoot, function()
    if playerState[client] then return end
    local list = {}
    for _, job in ipairs(jobs) do
        local mMoney, mXp, mLabel = jobmanagerGetMultiplier(job.id)
        table.insert(list, {
            id = job.id, name = job.name, type = job.type,
            min = job.minPlayers, max = job.maxPlayers,
            image = job.image, description = job.description, createdBy = job.createdBy,
            community = job.community or false,
            moneyMult = mMoney, xpMult = mXp, multLabel = mLabel or nil,
        })
    end
    triggerClientEvent(client, "jobmanager:jobs", resourceRoot, list)
end)

addEvent("jobmanager:requestLobbies", true)
addEventHandler("jobmanager:requestLobbies", resourceRoot, function()
    local list = {}
    for _, lobby in pairs(lobbies) do
        if not lobby.locked and #lobby.players < lobby.job.maxPlayers then
            local mMoney, mXp, mLabel = jobmanagerGetMultiplier(lobby.job.id)
            table.insert(list, {
                moneyMult = mMoney, xpMult = mXp, multLabel = mLabel or nil,
                id = lobby.id, jobId = lobby.job.id, jobName = lobby.job.name, type = lobby.job.type,
                hostName = lobby.host and displayNameOf(lobby.host) or "?",
                count = #lobby.players, max = lobby.job.maxPlayers,
                image = lobby.job.image, description = lobby.job.description, createdBy = lobby.job.createdBy,
            })
        end
    end
    triggerClientEvent(client, "jobmanager:lobbies", resourceRoot, list)
end)

addEvent("jobmanager:joinLobby", true)
addEventHandler("jobmanager:joinLobby", resourceRoot, function(lobbyId)
    if type(lobbyId) ~= "number" then return end
    joinLobbyById(client, lobbyId)
end)

addEvent("jobmanager:quickJob", true)
addEventHandler("jobmanager:quickJob", resourceRoot, function()
    quickJob(client)
end)

addEvent("jobmanager:startJob", true)
addEventHandler("jobmanager:startJob", resourceRoot, function()
    requestStart(client)
end)

-- confirmed = true: the job menu's "Yes, leave" (a running match is left without asking again)
addEvent("jobmanager:leaveJob", true)
addEventHandler("jobmanager:leaveJob", resourceRoot, function(confirmed)
    requestLeave(client, confirmed == true)
end)

--------------------------------------------------------------------------------
-- Lobby invites (anyone in a lobby can invite; delivered via ui_phone)
--------------------------------------------------------------------------------

local function currentLobby(player)
    local state = playerState[player]
    if not state or state.kind ~= "lobby" then return nil end
    return lobbies[state.lobbyId]
end

addEvent("jobmanager:requestInvitablePlayers", true)
addEventHandler("jobmanager:requestInvitablePlayers", resourceRoot, function()
    if not currentLobby(client) then return end
    local list = {}
    for _, player in ipairs(getElementsByType("player")) do
        if player ~= client and not playerState[player] then
            list[#list + 1] = { player = player, name = displayNameOf(player) }
        end
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    triggerClientEvent(client, "jobmanager:invitablePlayers", resourceRoot, list)
end)

addEvent("jobmanager:invitePlayer", true)
addEventHandler("jobmanager:invitePlayer", resourceRoot, function(target)
    local lobby = currentLobby(client)
    if not lobby then return end
    if not isElement(target) or getElementType(target) ~= "player" then return end
    if target == client then return end
    if playerState[target] then
        message(client, L.msg("v_jobmanager.core.is_already_in_lobby_or_match", { player = displayNameOf(target) }), 255, 200, 100)
        return
    end
    if lobby.locked or #lobby.players >= lobby.job.maxPlayers then
        message(client, L.msg("v_jobmanager.core.this_lobby_cannot_take_any_more"), 255, 200, 100)
        return
    end
    if not phoneReady() then
        message(client, L.msg("v_jobmanager.core.phone_service_is_unavailable_right_now"), 255, 120, 120)
        return
    end

    local ok = exports.ui_phone:phoneAddInvite(
        target,
        tostring(lobby.id),
        lobby.job.name .. " lobby",
        L.msg("v_jobmanager.core.invited_you_players", { player = displayNameOf(client), players = #lobby.players, max_players = lobby.job.maxPlayers }),
        "v_jobmanager",
        "jobmanagerAcceptInvite",
        "jobmanagerDeclineInvite"
    )
    if not ok then
        message(client, L.msg("v_jobmanager.core.could_not_send_invite"), 255, 120, 120)
        return
    end

    lobby.invited = lobby.invited or {}
    lobby.invited[target] = true
    syncLobby(lobby)
    message(client, L.msg("v_jobmanager.core.invited", { player = displayNameOf(target) }))
    message(target, L.msg("v_jobmanager.core.invited_you_to_lobby_open_your", { player = displayNameOf(client), name = lobby.job.name }), 120, 200, 255)
end)

addEventHandler("onPlayerQuit", root, function()
    for _, lobby in pairs(lobbies) do
        if lobby.invited and lobby.invited[source] then
            lobby.invited[source] = nil
            syncLobby(lobby)
        end
    end
    local state = playerState[source]
    if not state then return end
    if state.kind == "lobby" then
        leaveLobby(source, true)
        return
    end
    -- "save.position" stays on the player: v_accounts' quit save writes the place before the job
    local match = matches[state.matchId]
    playerState[source] = nil
    if match then dropFromMatch(source, match, true) end
end)

-- jobId -> { marker, blip }
local markerElements = {}

local function removeJobMarker(jobId)
    local entry = markerElements[jobId]
    if not entry then return end
    jobMarkers[entry.marker] = nil
    if isElement(entry.blip) then destroyElement(entry.blip) end
    if isElement(entry.marker) then destroyElement(entry.marker) end
    markerElements[jobId] = nil
end

local function createJobMarker(job)
    removeJobMarker(job.id)
    if not job.marker or job.scriptOnly then return end
    local marker = createMarker(job.marker[1], job.marker[2], job.marker[3] - 1, "cylinder", 2, 50, 160, 255, 120)
    jobMarkers[marker] = job
    local blip = createBlipAttachedTo(marker, 9, 2, 50, 160, 255, 255)
    -- v_radar shows this as the blip's name (bigmap hover, bigmap blip menu, 3D blips)
    setElementData(blip, "tooltipText", job.name)
    markerElements[job.id] = { marker = marker, blip = blip }
end

local resourceStarted = false
addEventHandler("onResourceStart", resourceRoot, function()
    resourceStarted = true
    for _, job in ipairs(jobs) do createJobMarker(job) end
end)

-- Only games that have a world marker need to be known by the client (3D labels, E to join).
local function sendMarkers(player)
    local list = {}
    for _, job in ipairs(jobs) do
        if job.marker then
            table.insert(list, { id = job.id, name = job.name, type = job.type,
                minPlayers = job.minPlayers, maxPlayers = job.maxPlayers, marker = job.marker })
        end
    end
    triggerClientEvent(player, "jobmanager:markers", resourceRoot, list)
end

-- Clients get one marker list per burst of (un)registrations (the MySQL load
-- registers every game at once).
local markerTimer
local function markersChanged()
    if isTimer(markerTimer) then return end
    markerTimer = setTimer(function() markerTimer = nil sendMarkers(root) end, 100, 1)
end

-- Live (re)registration from core/games.lua (MySQL load, publish / unpublish, instance sync).
function onJobRegistered(job)
    if not resourceStarted then return end
    createJobMarker(job)
    markersChanged()
end

function onJobUnregistered(job)
    if not resourceStarted then return end
    removeJobMarker(job.id)
    markersChanged()
end

addEvent("jobmanager:requestMarkers", true)
addEventHandler("jobmanager:requestMarkers", resourceRoot, function() sendMarkers(client) end)

addEventHandler("onMarkerHit", root, function(player, matchingDimension)
    local job = jobMarkers[source]
    if job and matchingDimension and getElementType(player) == "player" then
        triggerClientEvent(player, "jobmanager:showJoinHint", resourceRoot, job.id, job.name)
    end
end)

addEventHandler("onMarkerLeave", root, function(player)
    if jobMarkers[source] and getElementType(player) == "player" then
        triggerClientEvent(player, "jobmanager:hideJoinHint", resourceRoot)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    local activeMatches = {}
    for _, match in pairs(matches) do table.insert(activeMatches, match) end
    for _, match in ipairs(activeMatches) do endMatch(match, L.msg("v_jobmanager.core.resource_stopped"), true) end
end)

-- Public server API for other resources. These functions keep the validation and
-- state ownership in the core instead of exposing its tables.
function jobmanagerJoin(player, jobId)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local job = jobsById[jobId]
    return job and joinJob(player, job) or false
end

-- leaves a lobby or a running match (no reward, no penalty)
function jobmanagerLeave(player)
    if not isElement(player) then return false end
    return leaveLobby(player, true) or leaveMatch(player)
end

function jobmanagerGetState(player)
    local state = playerState[player]
    if not state then return false end
    return { kind = state.kind, lobbyId = state.lobbyId, matchId = state.matchId }
end

-- Called by ui_phone when a player accepts a lobby invite. `id` is the lobby id
-- that was passed to phoneAddInvite.
function jobmanagerAcceptInvite(player, id)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local lobbyId = tonumber(id)
    if not lobbyId then return false end
    local lobby = lobbies[lobbyId]
    if lobby and lobby.invited then lobby.invited[player] = nil end
    return joinLobbyById(player, lobbyId)
end

-- Called by ui_phone when a player declines a lobby invite: off the lobby's invited list.
function jobmanagerDeclineInvite(player, id)
    local lobby = lobbies[tonumber(id) or -1]
    if not lobby or not lobby.invited or not lobby.invited[player] then return false end
    lobby.invited[player] = nil
    syncLobby(lobby)
    return true
end

--------------------------------------------------------------------------------
-- missions started by scripts (business setups, heists) and creator test runs
--------------------------------------------------------------------------------

local function freePlayer(player)
    return isElement(player) and getElementType(player) == "player" and not playerState[player]
        and not inCreator(player) and not isPedDead(player) and getElementData(player, "isLogged") == true
end

local function cleanPoint(p)
    if type(p) ~= "table" then return nil end
    local x, y, z = tonumber(p.x or p[1]), tonumber(p.y or p[2]), tonumber(p.z or p[3])
    if not (x and y and z) then return nil end
    return { x = x, y = y, z = z, interior = tonumber(p.interior or p[4]) or 0, dimension = tonumber(p.dimension or p[5]) or 0 }
end

-- missionId: a mission game (public or scriptOnly). players: list of free players.
-- opts: { reward = false | {money = n, xp = n}, tag = string, returnTo = {x, y, z, interior, dimension},
--         startStage = stage id, quiet = bool (no scoreboard) }
-- -> matchId | false, reason. The mission always runs in its own dimension.
function jobmanagerStartMission(missionId, players, opts)
    local job = jobsById[missionId]
    if not job or job.type ~= JOB_TYPE_MISSION then return false, "unknown mission" end
    if type(players) ~= "table" or #players == 0 then return false, "no players" end
    local seen = {}
    for _, player in ipairs(players) do
        if seen[player] or not freePlayer(player) then return false, "player not available" end
        seen[player] = true
    end
    if #players > job.maxPlayers then return false, "too many players" end
    opts = type(opts) == "table" and opts or {}
    local reward = opts.reward
    if reward ~= false then
        reward = type(reward) == "table" and { money = math.max(0, tonumber(reward.money) or 0), xp = math.max(0, tonumber(reward.xp) or 0) } or nil
    end
    local list = {}
    for i, player in ipairs(players) do list[i] = player end
    local match, err = createMatch(job, list, {
        script = true, reward = reward, tag = type(opts.tag) == "string" and opts.tag or nil,
        returnTo = cleanPoint(opts.returnTo), quiet = opts.quiet == true,
        startStage = type(opts.startStage) == "string" and opts.startStage or nil,
    })
    if not match then return false, err end
    return match.id
end

function jobmanagerAbortMission(matchId, reason)
    local match = matches[tonumber(matchId) or -1]
    if not match or match.job.type ~= JOB_TYPE_MISSION then return false end
    endMatch(match, type(reason) == "string" and reason or L.msg("v_jobmanager.mission.aborted"), true)
    return true
end

-- completes the `scriptEvent` objectives named `name` in the current stage
function jobmanagerMissionSignal(matchId, name)
    local match = matches[tonumber(matchId) or -1]
    if not match or match.ended or match.job.type ~= JOB_TYPE_MISSION or type(name) ~= "string" then return false end
    return Mission.signal(match, name)
end

function jobmanagerGetMatch(matchId)
    local match = matches[tonumber(matchId) or -1]
    if not match then return false end
    local players = {}
    for _, player in ipairs(match.players) do
        if not match.left[player] and isElement(player) then players[#players + 1] = player end
    end
    return {
        jobId = match.job.id, type = match.job.type, players = players, dimension = match.dimension,
        stage = match.mission and match.mission.stageId or nil, startedAt = match.startTick,
        test = match.opts.test or false, tag = match.opts.tag,
    }
end

-- v_jobcreator: runs an unsaved mission alone in the editor dimension, without rewards.
-- game = the sanitized creator document. -> matchId | false, reason
function jobmanagerTestMission(player, game, startStage)
    if not isElement(player) or getElementType(player) ~= "player" or playerState[player] then return false, "busy" end
    if type(game) ~= "table" or game.type ~= JOB_TYPE_MISSION then return false, "not a mission" end
    local copy = {}
    for k, v in pairs(game) do copy[k] = v end
    copy.id, copy.createdBy, copy.marker, copy.scriptOnly = "__creator_test", copy.createdBy or "creator", nil, true
    local ok, err = validateGame(copy)
    if not ok then return false, err end
    local match, cerr = createMatch(copy, { player }, {
        test = true, dimension = getElementDimension(player), tag = "__creator_test",
        startStage = type(startStage) == "string" and startStage or nil,
    })
    if not match then return false, cerr end
    return match.id
end

-- ends a creator test run (F6)
function jobmanagerStopTest(player)
    local match = jobPlayerMatch(player)
    if not match or not match.opts.test then return false end
    endMatch(match, L.msg("v_jobmanager.mission.test_stopped"), true)
    return true
end
