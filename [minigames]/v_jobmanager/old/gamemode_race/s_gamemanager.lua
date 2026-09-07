
function start_race(active_job_id, race_id)
    setTimer(function()
        -- spawn players
        local vehicles = {}
        for i,player in ipairs(active_jobs[active_job_id].players) do
            triggerClientEvent( player.element, "start_race", player.element, active_job_id, race_id )
            active_jobs[active_job_id].players[i].finishedRace = false

            local selected_vehicle = races[race_id].settings.vehicles[1] or 411
            local spawnpoint = races[race_id].spawnpoints[i]
            local x,y,z,rot = spawnpoint[1], spawnpoint[2], spawnpoint[3], spawnpoint[4]
            local veh = createVehicle(selected_vehicle, x,y,z, 0,0,rot)
            setElementVisibleTo(veh, getRootElement()) -- érthetetlen bugot javítani akaró sor
            setElementDimension(veh, getJobDim(active_job_id))
            warpPedIntoVehicle(player.element, veh)
            setElementFrozen(getPedOccupiedVehicle(player.element), true)
            table.insert(vehicles, veh)
        end
        setTimer(function()
            -- Countdown
            local countdown = 3
            setTimer(function()
                if countdown == 0 then -- GO
                    for i,player in ipairs(active_jobs[active_job_id].players) do
                        setElementFrozen(getPedOccupiedVehicle(player.element), false)
                        race_startCheckpointsForPlayer(player.element, active_job_id, race_id)
                        triggerClientEvent( player.element, "race_countdown", player.element, active_job_id, race_id, countdown )
                    end
                else
                    for i,player in ipairs(active_jobs[active_job_id].players) do
                        triggerClientEvent( player.element, "race_countdown", player.element, active_job_id, race_id, countdown )
                    end
                    countdown = countdown - 1
                end
            end, 1500, 4)
        end, 2000,1)
    end, 1000,1)
end

function finish_raceForPlayer(player, active_job_id, race_id)
    -- cancel onPlayerDamage
    setElementHealth(player, 100)
    addEventHandler("onPlayerDamage", player, function()
        cancelEvent()
    end)
    -- remove from vehicle
    local veh = getPedOccupiedVehicle(player)
    removePedFromVehicle(player)
    setElementPosition(0,0,3)

    -- set player finished the race
    for i,v in ipairs(active_jobs[active_job_id].players) do
        if v.element == player then
            active_jobs[active_job_id].players[i].finishedRace = true
        end
    end

    triggerClientEvent( player, "finish_race", player, active_job_id, race_id )
    setTimer(function()
        -- remove vehicle
        destroyElement(veh)
        -- is that was the last player?
    end, 5000, 1)
    finish_race(active_job_id, race_id)
end

function finish_race(active_job_id, race_id)
    for i,player in ipairs(active_jobs[active_job_id].players) do
        if player.finishedRace==false then
            return false
        end
    end
    setTimer(function()
        endJob(active_job_id)
    end, 5000, 1)
end


