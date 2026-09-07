

function startVote(lobby_id)
    local lobby = active_lobbys[lobby_id]
    if not lobby then return end
    if not lobby.vote.isVoteActive then
        lobby.vote.isVoteActive = true
        lobby.vote.voteTimer = setTimer(function() endVote(lobby_id, false) end, 30000, 1)
        
        for _, player in ipairs(lobby.players) do
            player.voted = false
        end
        
        for i,player in ipairs(lobby.players) do
            triggerClientEvent(player.element, "onVoteStart", player.element)
        end
    end
end

function endVote(lobby_id, votes)
    if not active_lobbys[lobby_id] then return end

    killTimer(active_lobbys[lobby_id].vote.voteTimer)
    active_lobbys[lobby_id].vote.isVoteActive = false

    if votes then
        -- get results
        local maxVotes = 0
        local selectedOption = nil
        for key,value in pairs(votes) do
            if value > maxVotes then
                maxVotes = value
                selectedOption = key
            end
        end
        outputDebugString("winner vote: "..selectedOption)

        -- do as voted
        if selectedOption then
            for i,player in ipairs(active_lobbys[lobby_id].players) do
                triggerClientEvent(player.element, "onVoteEnd", player.element, selectedOption)
                player.voted = nil
            end

            if selectedOption == "Freemode" then
                deleteLobby(lobby_id)
            elseif selectedOption == "Restart" then
                for i,player in ipairs(active_lobbys[lobby_id].players) do
                    triggerClientEvent(player.element, "openLobbyPanel", player.element, lobby_id)
                end
                active_lobbys[lobby_id].locked = false
            elseif selectedOption == "Random" then
                active_lobbys[lobby_id].job_id = math.random(1, #jobs)
                setElementDimension(player, getJobDim(active_lobbys[lobby_id].job_id))
                for i,player in ipairs(active_lobbys[lobby_id].players) do
                    triggerClientEvent(player.element, "openLobbyPanel", player.element, lobby_id)
                end
                active_lobbys[lobby_id].locked = false
            else
                active_lobbys[lobby_id].job_id = selectedOption
                setElementDimension(player, getJobDim(active_lobbys[lobby_id].job_id))
                for i,player in ipairs(active_lobbys[lobby_id].players) do
                    triggerClientEvent(player.element, "openLobbyPanel", player.element, lobby_id)
                end
                active_lobbys[lobby_id].locked = false
            end
        end
    else
        deleteLobby(lobby_id)
        -- Random
        --[[
        for _, player in ipairs(active_lobbys[lobby_id].players) do
            triggerClientEvent(player.element, "onVoteEnd", player.element, "Random")
        end
        active_lobbys[lobby_id].job_id = math.random(1, #jobs)
        for i,player in ipairs(active_lobbys[lobby_id].players) do
            triggerClientEvent(player.element, "openLobbyPanel", player.element, lobby_id)
        end
        active_lobbys[lobby_id].locked = false
        ]]
    end
end


addEvent("onPlayerVote", true)
addEventHandler("onPlayerVote", getRootElement(), function(player, lobby_id, option)
    if not lobby_id then return end

    for i, v in ipairs(active_lobbys[lobby_id].players) do
        if v.element == player then
            outputDebugString("onPlayerVote: player "..v.name..", voted "..option)
            active_lobbys[lobby_id].players[i].voted = option
            checkVotes(lobby_id)
            break
        end
    end
end)

function checkVotes(lobby_id)
    local totalVotes = 0
    local votes = {}
    for i, player in ipairs(active_lobbys[lobby_id].players) do
        if player.voted then
            totalVotes = totalVotes + 1
            if votes[player.voted] then
                votes[player.voted] = votes[player.voted] + 1
            else
                votes[player.voted] = 1
            end
        end
    end

    if totalVotes == #active_lobbys[lobby_id].players then
        endVote(lobby_id, votes)
    end
end

