local lobbies, matches, playerState = {}, {}, {}
local nextLobbyId, nextMatchId = 1, 1
local jobMarkers = {}

local function message(player, text, r, g, b)
    outputChatBox("[Jobs] " .. text, player, r or 255, g or 255, b or 255)
end

local function snapshotPlayer(player)
    local x, y, z = getElementPosition(player)
    return { x = x, y = y, z = z, dimension = getElementDimension(player), interior = getElementInterior(player) }
end

local function restorePlayer(player, state)
    if not isElement(player) then return end
    takeAllWeapons(player)
    setElementFrozen(player, false)
    removePedFromVehicle(player)
    setElementInterior(player, state.interior)
    setElementDimension(player, state.dimension)
    if isPedDead(player) then
        spawnPlayer(player, state.x, state.y, state.z, 0, getElementModel(player), state.interior, state.dimension)
    else
        setElementPosition(player, state.x, state.y, state.z)
    end
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

-- Lobby invites are delivered to players through the v_phone resource. We keep
-- that a soft dependency: if the phone is not running, inviting simply fails.
local function phoneReady()
    local res = getResourceFromName("v_phone")
    return res and getResourceState(res) == "running"
end

-- Pull back any phone invites still pointing at a lobby that is about to vanish
-- (host started the job, or the lobby emptied out).
local function clearLobbyInvites(lobby)
    if not lobby.invited then return end
    for player in pairs(lobby.invited) do
        if isElement(player) and phoneReady() then
            exports.v_phone:phoneRemoveInvite(player, tostring(lobby.id))
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

local function syncLobby(lobby)
    if not lobby then return end
    local names = {}
    for _, player in ipairs(lobby.players) do
        table.insert(names, {
            name = getPlayerName(player),
            host = player == lobby.host,
            crewTag = getElementData(player, "crewTag") or "",
            crewColor = getElementData(player, "crewColor"),
        })
    end
    for _, player in ipairs(lobby.players) do
        triggerClientEvent(player, "jobmanager:lobby", resourceRoot, {
            id = lobby.id, name = lobby.job.name, type = lobby.job.type,
            players = names, min = lobby.job.minPlayers, max = lobby.job.maxPlayers,
            isHost = player == lobby.host,
            image = lobby.job.image, description = lobby.job.description,
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
    if not quiet then message(player, "You left the lobby.") end
    return true
end

local function joinJob(player, job)
    if playerState[player] then
        message(player, "Leave your current lobby or match first.", 255, 120, 120)
        return false
    end
    local lobby = getJoinableLobby(job) or createLobby(job)
    table.insert(lobby.players, player)
    if not lobby.host then lobby.host = player end
    playerState[player] = { kind = "lobby", lobbyId = lobby.id, returnState = snapshotPlayer(player) }
    syncLobby(lobby)
    message(player, "Lobby " .. lobby.id .. " (" .. #lobby.players .. "/" .. job.maxPlayers .. ").")
    return true
end

local function joinLobbyById(player, lobbyId)
    if playerState[player] then
        message(player, "Leave your current lobby or match first.", 255, 120, 120)
        return false
    end
    local lobby = lobbies[lobbyId]
    if not lobby or lobby.locked or #lobby.players >= lobby.job.maxPlayers then
        message(player, "That lobby is no longer available.", 255, 120, 120)
        return false
    end
    table.insert(lobby.players, player)
    if not lobby.host then lobby.host = player end
    playerState[player] = { kind = "lobby", lobbyId = lobby.id, returnState = snapshotPlayer(player) }
    syncLobby(lobby)
    message(player, "Lobby " .. lobby.id .. " (" .. #lobby.players .. "/" .. lobby.job.maxPlayers .. ").")
    return true
end

-- Random open lobby across ALL jobs, or a brand new lobby for a random job
-- if none are joinable right now.
local function quickJob(player)
    if playerState[player] then
        message(player, "Leave your current lobby or match first.", 255, 120, 120)
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
        message(player, "Quick-joined " .. lobby.job.name .. ".")
        return true
    end
    if #jobs == 0 then
        message(player, "There are no jobs configured.", 255, 200, 100)
        return false
    end
    return joinJob(player, jobs[math.random(#jobs)])
end

-- Stats shown on the end-of-match scoreboard.
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
                table.insert(rows, { name = match.playerNames[player] or "?", place = false, timeMs = false, crewTag = tag, crewColor = colour })
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
            })
        end
        table.sort(rows, function(a, b)
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
local function computeCamera(match)
    if match.job.type == JOB_TYPE_RACE then
        local route = races and races[match.job.raceId]
        if route and route.finishCamera then return route.finishCamera end
        if route and route.spawnpoints and #route.spawnpoints > 0 then
            local cx, cy, cz = averagePoint(route.spawnpoints)
            return { pos = { cx, cy, cz + 60 }, lookAt = { cx, cy, cz }, roll = 0, fov = 90 }
        end
    elseif match.job.spawns and #match.job.spawns > 0 then
        local cx, cy, cz = averagePoint(match.job.spawns)
        return { pos = { cx, cy, cz + 60 }, lookAt = { cx, cy, cz }, roll = 0, fov = 90 }
    end
    return { pos = { 0, 0, 100 }, lookAt = { 0, 0, 0 }, roll = 0, fov = 90 }
end

local function endMatch(match, reason)
    if not match or match.ended then return end
    match.ended = true
    local mode = JobModes[match.job.type]
    if mode and mode.onEnd then mode.onEnd(match) end
    local stats = buildStats(match)
    local camera = computeCamera(match)
    for _, player in ipairs(match.players) do
        local state = playerState[player]
        if state and state.matchId == match.id then
            restorePlayer(player, state.returnState)
            playerState[player] = nil
            triggerClientEvent(player, "jobmanager:matchEnded", resourceRoot, {
                reason = reason, jobId = match.job.id, jobName = match.job.name,
                type = match.job.type, stats = stats, camera = camera,
            })
        end
    end
    destroyElements(match.vehicles)
    destroyElements(match.markers)
    matches[match.id] = nil
end

local function startMatch(lobby)
    if lobby.locked or #lobby.players < lobby.job.minPlayers then return false, "Not enough players." end
    lobby.locked = true
    local match = {
        id = nextMatchId, job = lobby.job, players = lobby.players, dimension = 50000 + nextMatchId,
        vehicles = {}, markers = {}, progress = {}, finished = {}, eliminated = {},
        playerNames = {}, kills = {}, deaths = {}, finishOrder = {}, finishTime = {},
        crewTags = {}, crewColors = {},
        ended = false,
    }
    nextMatchId = nextMatchId + 1
    matches[match.id] = match
    clearLobbyInvites(lobby)
    lobbies[lobby.id] = nil
    for _, player in ipairs(match.players) do
        match.playerNames[player] = getPlayerName(player)
        match.crewTags[player] = getElementData(player, "crewTag") or ""
        match.crewColors[player] = getElementData(player, "crewColor")
        local state = playerState[player]
        if state then state.kind, state.matchId, state.lobbyId = "match", match.id, nil end
        triggerClientEvent(player, "jobmanager:matchStarted", resourceRoot, match.job.name)
    end
    local mode = JobModes[match.job.type]
    if not mode then endMatch(match, "Unsupported job type.") return false, "Unsupported job type." end
    mode.start(match, endMatch)
    return true
end

addCommandHandler("quickjob", function(player)
    quickJob(player)
end)

local function requestStart(player)
    local state = playerState[player]
    local lobby = state and state.kind == "lobby" and lobbies[state.lobbyId]
    if not lobby then message(player, "You are not in a lobby.", 255, 120, 120) return end
    if lobby.host ~= player then message(player, "Only the lobby host can start the job.", 255, 120, 120) return end
    local ok, err = startMatch(lobby)
    if not ok then message(player, err, 255, 120, 120) end
end

addCommandHandler("startjob", function(player)
    requestStart(player)
end)

local function requestLeave(player)
    if leaveLobby(player) then return end
    message(player, "You can only leave before the job starts.", 255, 200, 100)
end

addCommandHandler("leavejob", function(player)
    requestLeave(player)
end)

-- Future UI entry points. They deliberately use `client`, never a player value
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
        table.insert(list, {
            id = job.id, name = job.name, type = job.type,
            min = job.minPlayers, max = job.maxPlayers,
            image = job.image, description = job.description,
        })
    end
    triggerClientEvent(client, "jobmanager:jobs", resourceRoot, list)
end)

addEvent("jobmanager:requestLobbies", true)
addEventHandler("jobmanager:requestLobbies", resourceRoot, function()
    local list = {}
    for _, lobby in pairs(lobbies) do
        if not lobby.locked and #lobby.players < lobby.job.maxPlayers then
            table.insert(list, {
                id = lobby.id, jobId = lobby.job.id, jobName = lobby.job.name, type = lobby.job.type,
                hostName = lobby.host and getPlayerName(lobby.host) or "?",
                count = #lobby.players, max = lobby.job.maxPlayers,
                image = lobby.job.image, description = lobby.job.description,
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

addEvent("jobmanager:leaveJob", true)
addEventHandler("jobmanager:leaveJob", resourceRoot, function()
    requestLeave(client)
end)

--------------------------------------------------------------------------------
-- Lobby invites (anyone in a lobby can invite; delivered via v_phone)
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
            list[#list + 1] = { player = player, name = getPlayerName(player) }
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
        message(client, getPlayerName(target) .. " is already in a lobby or match.", 255, 200, 100)
        return
    end
    if lobby.locked or #lobby.players >= lobby.job.maxPlayers then
        message(client, "This lobby cannot take any more players.", 255, 200, 100)
        return
    end
    if not phoneReady() then
        message(client, "The phone service is unavailable right now.", 255, 120, 120)
        return
    end

    local ok = exports.v_phone:phoneAddInvite(
        target,
        tostring(lobby.id),
        lobby.job.name .. " lobby",
        getPlayerName(client) .. " invited you  -  " .. #lobby.players .. "/" .. lobby.job.maxPlayers .. " players",
        "v_jobmanager",
        "jobmanagerAcceptInvite"
    )
    if not ok then
        message(client, "Could not send the invite.", 255, 120, 120)
        return
    end

    lobby.invited = lobby.invited or {}
    lobby.invited[target] = true
    message(client, "Invited " .. getPlayerName(target) .. ".")
    message(target, getPlayerName(client) .. " invited you to a " .. lobby.job.name ..
        " lobby. Open your phone to respond.", 120, 200, 255)
end)

addEventHandler("onPlayerWasted", root, function(totalAmmo, killer)
    local state = playerState[source]
    local match = state and state.kind == "match" and matches[state.matchId]
    if not match or match.job.type ~= JOB_TYPE_DM or match.eliminated[source] then return end

    match.deaths[source] = (match.deaths[source] or 0) + 1
    if isElement(killer) and getElementType(killer) == "player" and killer ~= source then
        local killerState = playerState[killer]
        if killerState and killerState.kind == "match" and killerState.matchId == match.id then
            match.kills[killer] = (match.kills[killer] or 0) + 1
        end
    end

    match.eliminated[source] = true
    local count, winner = JobModes[JOB_TYPE_DM].remaining(match)
    if count <= 1 then endMatch(match, winner and (getPlayerName(winner) .. " won the deathmatch.") or "Deathmatch ended.") end
end)

addEventHandler("onPlayerQuit", root, function()
    local state = playerState[source]
    if not state then return end
    if state.kind == "lobby" then
        leaveLobby(source, true)
    else
        local match = matches[state.matchId]
        if match then
            if match.job.type == JOB_TYPE_DM then
                match.eliminated[source] = true
                local count, winner = JobModes[JOB_TYPE_DM].remaining(match)
                if count <= 1 then endMatch(match, winner and (getPlayerName(winner) .. " won the deathmatch.") or "Deathmatch ended.") end
            elseif match.job.type == JOB_TYPE_RACE then
                -- A player who disconnects mid-race must still count as "finished"
                -- (with no time), otherwise the race waits forever for them.
                match.finished[source] = true
                local allDone = true
                for _, participant in ipairs(match.players) do
                    if not match.finished[participant] then allDone = false break end
                end
                if allDone then endMatch(match, "Everyone finished the race.") end
            end
        end
        playerState[source] = nil
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, job in ipairs(jobs) do
        local marker = createMarker(job.marker[1], job.marker[2], job.marker[3] - 1, "cylinder", 2, 50, 160, 255, 120)
        jobMarkers[marker] = job
        createBlipAttachedTo(marker, 9, 2, 50, 160, 255, 255)
    end
end)

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
    for _, match in ipairs(activeMatches) do endMatch(match, "Resource stopped.") end
end)

-- Public server API for other resources. These functions keep the validation and
-- state ownership in the core instead of exposing its tables.
function jobmanagerJoin(player, jobId)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local job = jobsById[jobId]
    return job and joinJob(player, job) or false
end

function jobmanagerLeave(player)
    return leaveLobby(player, true)
end

function jobmanagerGetState(player)
    local state = playerState[player]
    if not state then return false end
    return { kind = state.kind, lobbyId = state.lobbyId, matchId = state.matchId }
end

-- Called by v_phone when a player accepts a lobby invite. `id` is the lobby id
-- that was passed to phoneAddInvite.
function jobmanagerAcceptInvite(player, id)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local lobbyId = tonumber(id)
    if not lobbyId then return false end
    local lobby = lobbies[lobbyId]
    if lobby and lobby.invited then lobby.invited[player] = nil end
    return joinLobbyById(player, lobbyId)
end
