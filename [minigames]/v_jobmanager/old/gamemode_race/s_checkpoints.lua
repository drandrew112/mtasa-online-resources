local activeCheckpoints = {}

function race_createCheckpoint(player, active_job_id, race_id, checkpointIndex, isFinish)
    local checkpointData = races[race_id].checkpoints[checkpointIndex]
    local r,g,b,a = 255,255,0,80
    if isFinish then
        checkpointData = races[race_id].finish
        r,g,b,a = 0,160,210,150
    end
    if checkpointData then
        local x, y, z, size = checkpointData[1], checkpointData[2], checkpointData[3], checkpointData[4]
        outputDebugString("create checkpoint for "..getPlayerName(player).." cpid: "..checkpointIndex)
        local checkpoint = createMarker(x, y, z, "checkpoint", size, r,g,b,a, player)
        setElementDimension(checkpoint, getJobDim(active_jobs[active_job_id].job_id))
        activeCheckpoints[player] = checkpoint
        local next_checkpoint = nil
        if not isFinish then
            local next_checkpointData = races[race_id].checkpoints[checkpointIndex + 1]
            local x, y, z, size = next_checkpointData[1], next_checkpointData[2], next_checkpointData[3], next_checkpointData[4]
            next_checkpoint = createMarker(x, y, z, "checkpoint", size, 255,255,255,120, player)
            setElementDimension(next_checkpoint, getJobDim(active_jobs[active_job_id].job_id))
        end
        addEventHandler("onMarkerHit", checkpoint, function(hitElement)
            if hitElement == player then
                destroyElement(checkpoint)
                if not isFinish then destroyElement(next_checkpoint) end
                if isFinish then
                    finish_raceForPlayer(player, active_job_id, race_id)
                else
                    triggerClientEvent(player, "race_nextCheckpoint", player, checkpointIndex + 1, active_job_id, race_id)
                end
            end
        end)
    end
end
addEvent("race_createCheckpoint", true)
addEventHandler("race_createCheckpoint", root, race_createCheckpoint)

function race_startCheckpointsForPlayer(player, active_job_id, race_id)
    race_createCheckpoint(player, active_job_id, race_id, 1, false)
end
