
-- Creates a new lobby
function createLobbyforJob(jobID)
    table.insert(active_lobbys, {
        job_id = jobID,
        host = nil,
        players = {},
        locked = false,
        active_job_id = nil,
        vote = {isVoteActive=false, voteTimer=nil},
    })
    return #active_lobbys
end

-- Delete a lobby
function deleteLobby(lobbyID)
    if active_lobbys[lobbyID] then
        local playersInLobby = 0
        for i,player in ipairs(active_lobbys[lobbyID].players) do
            kickPlayerFromLobby(player.element, "The lobby has been deleted.")
        end
        table.remove(active_lobbys, lobbyID)
    end
    return false
end


-- returns the first available lobby
function getLobbyForJob(jobID)
    for i,lobby in ipairs(active_lobbys) do
        local lobby_id = i
        if lobby.locked==false then
            if lobby.job_id == jobID then
                if #lobby.players < jobs[jobID].max_players then
                    return lobby_id
                end
            end
        end
    end

    return false
end

-- get lobby_id of player
function getPlayerLobby(player)
    for lobby_id,lobby in ipairs(active_lobbys) do
        for i,v in ipairs(lobby.players) do
            if (v.element == player) then
                return lobby_id,i
            end
        end
    end

    return false
end


function joinPlayerLobby(player, jobID, mode)    
    local mode = mode or "auto"

    if mode == "auto" then
        local lobby_id = getLobbyForJob(jobID)
        if lobby_id then
            table.insert(
                active_lobbys[lobby_id].players,
                {element=player, name=getPlayerName(player), level=getElementData(player, "level")}
            )
            setElementDimension(player, getJobDim(jobID))
            return lobby_id
        else
            lobby_id = createLobbyforJob(jobID)
            if lobby_id then
                table.insert(
                    active_lobbys[lobby_id].players,
                    {element=player, name=getPlayerName(player), level=getElementData(player, "level")}
                )
                setElementDimension(player, getJobDim(jobID))
                active_lobbys[lobby_id].host = player
                return lobby_id
            end
        end
    elseif mode == "new" then
        local lobby_id = createLobbyforJob(jobID)
        if lobby_id then
            table.insert(
                active_lobbys[lobby_id].players,
                {element=player, name=getPlayerName(player), level=getElementData(player, "level")}
            )
            active_lobbys[lobby_id].host = player
            return lobby_id
        end
    end

    return false
end

-- Remove plaer from lobby
function leavePlayerLobby(player)
    local lobby_id, lobbyplayer_id = getPlayerLobby(player)
    if lobby_id then
        for i,v in ipairs(active_lobbys[lobby_id].players) do
            if v.element == player then
                if active_lobbys[lobby_id].host == player then
                    if #active_lobbys[lobby_id].players >= 2 then -- player not removed yet !!
                        active_lobbys[lobby_id].host = active_lobbys[lobby_id].players[1].element
                    else
                        table.remove(active_lobbys[lobby_id].players, i)
                        deleteLobby(lobby_id)
                        return
                    end
                end
                table.remove(active_lobbys[lobby_id].players, i)
                break
            end
        end
    end
end
addEvent("leavePlayerLobby", true)
addEventHandler("leavePlayerLobby", getRootElement(), leavePlayerLobby)

-- Kick player from lobby
function kickPlayerFromLobby(player, reason)
    local lobby_id, lobbyplayer_id = getPlayerLobby(player)
    if lobby_id then
        for i,v in ipairs(active_lobbys[lobby_id].players) do
            if v.element == player then
                table.remove(active_lobbys[lobby_id].players, i)
                triggerClientEvent(player, "leaveLobby", player, true, reason)
                break
            end
        end
    end
end
