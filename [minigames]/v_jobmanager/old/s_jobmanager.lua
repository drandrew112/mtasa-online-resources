
function init_jobs()
    for i, job in ipairs(jobs) do
        local x,y,z = job.join_marker.pos[1], job.join_marker.pos[2], job.join_marker.pos[3]
        local r,g,b,a = job.join_marker.rgba[1], job.join_marker.rgba[2], job.join_marker.rgba[3], job.join_marker.rgba[4]
        local marker = createMarker(x,y,z-1, "cylinder", job.join_marker.size, r,g,b,a, getRootElement())
        local blip = createBlipAttachedTo(marker, job.join_marker.blip_icon, 2, 255,255,255,255, 0, 500, getRootElement())
        setElementData(marker, "job_marker", true)
        setElementData(marker, "job_id", i)
    end
end
addEventHandler("onResourceStart", getResourceRootElement(), init_jobs)

function joinPlayerJob(player, jobID)
    local lobby_id = joinPlayerLobby(player, jobID)
    if lobby_id then
        triggerClientEvent(player, "openLobbyPanel", player, lobby_id)
    else
        outputDebugString("joinPlayerJob failed: lobby_id = false")
    end
end
addEvent("joinPlayerJob", true)
addEventHandler("joinPlayerJob", getRootElement(), joinPlayerJob)

function startJob(lobbyID)
    if active_lobbys[lobbyID] then
        if #active_lobbys[lobbyID].players >= jobs[active_lobbys[lobbyID].job_id].min_players then
            -- lock lobby
            active_lobbys[lobbyID].locked = true

            local active_job_id = #active_jobs+1
            table.insert(active_jobs, active_job_id, {
                job_id = active_lobbys[lobbyID].job_id,
                host = active_lobbys[lobbyID].host,
                players = active_lobbys[lobbyID].players,
                lobby_id = lobbyID,
            })

            -- close lobby panel for all players in lobby
            for i,player in ipairs(active_lobbys[lobbyID].players) do
                triggerClientEvent(player.element, "startJob", player.element, active_job_id)
            end

            local job_type = jobs[active_lobbys[lobbyID].job_id].type
            local race_id = jobs[active_lobbys[lobbyID].job_id].race_id

            setTimer(function()
                -- Start gamemode
                if     job_types.ctf == job_type then
                elseif job_types.dm == job_type then
                elseif job_types.mission == job_type then
                elseif job_types.race == job_type then
                    start_race(active_job_id, race_id)
                else
                    outputDebugString("not enough players to start")
                end
            end, 2000, 1)
        end
    end
end
addEvent("startJob", true)
addEventHandler("startJob", getRootElement(), startJob)

function endJob(active_job_id)
    local lobby_id = active_jobs[active_job_id].lobby_id
    local job_id = active_jobs[active_job_id].job_id
    active_lobbys[lobby_id].active_job_id = nil
    table.remove(active_jobs, active_job_id)
    for i,player in ipairs( active_lobbys[lobby_id].players ) do
        triggerClientEvent( player.element, "endJob", player.element, job_id )
    end
    setTimer(function()
        startVote(lobby_id)
    end, (10)*1000, 1)
end
