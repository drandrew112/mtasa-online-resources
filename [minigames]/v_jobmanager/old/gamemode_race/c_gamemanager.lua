
local currentCheckpoint = 1

-- start game - triggered by serverside
function start_race(active_job_id, raceID)
    -- set data
    currentCheckpoint = 1
    setTimer(function()
        setCameraTarget(localPlayer)
        uicore:toggleMoveControls(true)
        setTimer(function()
            fadeCamera(true, 1)
            setElementData(localPlayer, "hideHUD", false)
        end, 1000, 1)
    end, 1000, 1)
end
addEvent("start_race", true)
addEventHandler("start_race", getRootElement(), start_race)

function finish_race(active_job_id, raceID)
    setElementData(localPlayer, "hideHUD", true)
    uicore:toggleMoveControls(false)
    local x,y,z = races[raceID].finishCamera.pos[1], races[raceID].finishCamera.pos[2], races[raceID].finishCamera.pos[3]
    local lx,ly,lz = races[raceID].finishCamera.lookAt[1], races[raceID].finishCamera.lookAt[2], races[raceID].finishCamera.lookAt[3]
    setCameraMatrix(x,y,z, lx,ly,lz, races[raceID].finishCamera.roll, races[raceID].finishCamera.fov)
    setTimer(fadeCamera, 3800, 1, false, 1)
end
addEvent("finish_race", true)
addEventHandler("finish_race", getRootElement(), finish_race)

function race_nextCheckpoint(checkpointIndex, active_job_id, race_id)
    local totalCheckpoints = #races[race_id].checkpoints
    if checkpointIndex <= totalCheckpoints then
        if checkpointIndex == totalCheckpoints then
            -- Create finish checkpoint
            triggerServerEvent("race_createCheckpoint", localPlayer, localPlayer, active_job_id, race_id, checkpointIndex, true)
        else
            triggerServerEvent("race_createCheckpoint", localPlayer, localPlayer, active_job_id, race_id, checkpointIndex, false)
        end
    end
end
addEvent("race_nextCheckpoint", true)
addEventHandler("race_nextCheckpoint", getRootElement(), race_nextCheckpoint)

