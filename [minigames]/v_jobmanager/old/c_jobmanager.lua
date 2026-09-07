
in_lobby = false

job_id = nil
lobby_id = nil
active_job_id = nil

job_name = ""
job_desc = ""
job_bg = ""
job_creator = ""
job_rating = 100
job_min_players = 0
job_max_players = 0
job_openrank = 1
job_type = nil

function openLobbyPanel(lobbyID)
    in_lobby = true
    fadeCamera(false, 1)
    setElementData(localPlayer, "hideHUD", true)
    setTimer(function()
        -- init data
        job_id = active_lobbys[lobbyID].job_id
        lobby_id = lobbyID
        job_name = jobs[active_lobbys[lobbyID].job_id].name
        job_desc = jobs[active_lobbys[lobbyID].job_id].desc
        job_bg = jobs[active_lobbys[lobbyID].job_id].lobby.bg_img
        job_creator = jobs[active_lobbys[lobbyID].job_id].creator
        job_rating = jobs[active_lobbys[lobbyID].job_id].rating
        job_min_players = jobs[active_lobbys[lobbyID].job_id].min_players
        job_max_players = jobs[active_lobbys[lobbyID].job_id].max_players
        job_openrank = jobs[active_lobbys[lobbyID].job_id].openrank
        job_type = jobs[active_lobbys[lobbyID].job_id].type
        -- set camera
        uicore:toggleMoveControls(false)
        local cx,cy,cz = jobs[job_id].lobby.camera.pos[1], jobs[job_id].lobby.camera.pos[2], jobs[job_id].lobby.camera.pos[3]
        local lx,ly,lz = jobs[job_id].lobby.camera.lookAt[1], jobs[job_id].lobby.camera.lookAt[2], jobs[job_id].lobby.camera.lookAt[3]
        setCameraMatrix(cx,cy,cz, lx,ly,lz, jobs[job_id].lobby.camera.roll, jobs[job_id].lobby.camera.fov)
        -- open panel
        setTimer(function()
            fadeCamera(true, 1)
            setTimer(function()
                show_lobbypanel = true
            end, 500,1)
        end, 2000, 1)
    end, 1000, 1)
end
addEvent("openLobbyPanel", true)
addEventHandler("openLobbyPanel", getRootElement(), openLobbyPanel)

function leaveLobby(isKick, reason)
    in_lobby = false
    local isKick = isKick or false
    local reason = reason or false
    if isKick then
        local reason = reason or "No Reason"
    else
        triggerServerEvent("leavePlayerLobby", localPlayer, localPlayer)
    end
    -- close lobby panel
    show_lobbypanel = false
    fadeCamera(false, 1)
    setTimer(function() 
        if isKick then
            local x,y,z = jobs[job_id].exit[1], jobs[job_id].exit[2], jobs[job_id].exit[3]+1
            setElementPosition(localPlayer, x,y,z)
        else
            setElementPosition(localPlayer, jobs[job_id].lobby.exit[1], jobs[job_id].lobby.exit[2], jobs[job_id].lobby.exit[3]+1)
        end
        setElementDimension(localPlayer, 0)
        setCameraTarget(localPlayer)
        setTimer(function()
            fadeCamera(true, 1)
            uicore:toggleMoveControls(true)
            setElementData(localPlayer, "hideHUD", false)
            -- reset data
            job_id = nil
            lobby_id = nil
            job_name = ""
            job_desc = ""
            job_bg = ""
            job_creator = ""
            job_rating = 100
            job_min_players = 0
            job_max_players = 0
            job_openrank = 1
            job_type = nil
        end, 1500, 1)
    end, 1000, 1)
end
addEvent("leaveLobby", true)
addEventHandler("leaveLobby", getRootElement(), leaveLobby)

function startJob(_active_job_id)
    -- close lobby panel and get ready for game
    show_lobbypanel = false
    fadeCamera(false, 1)
    setElementData(localPlayer, "hideHUD", true)
    uicore:toggleMoveControls(false)
    -- set data
    active_job_id = _active_job_id
end
addEvent("startJob", true)
addEventHandler("startJob", getRootElement(), startJob)

function endJob(jobID)
    setElementData(localPlayer, "hideHUD", true)
    fadeCamera(false, 1)
    -- set camera
    local cx,cy,cz = jobs[jobID].endCamera.pos[1], jobs[jobID].endCamera.pos[2], jobs[jobID].endCamera.pos[3]
    local lx,ly,lz = jobs[jobID].endCamera.lookAt[1], jobs[jobID].endCamera.lookAt[2], jobs[jobID].endCamera.lookAt[3]
    setCameraMatrix(cx,cy,cz, lx,ly,lz, jobs[jobID].endCamera.roll, jobs[jobID].endCamera.fov)
    setTimer(function()
        uicore:toggleMoveControls(false)
        setTimer(function()
            -- open panel
            fadeCamera(true, 1)
            setTimer(function()
                show_endJobPanel = true
            end, 500,1)
        end, 1000, 1)
    end, 1000, 1)
end
addEvent("endJob", true)
addEventHandler("endJob", getRootElement(), endJob)



addCommandHandler("dim", function()
    outputDebugString("dim: "..getElementDimension(localPlayer))
end)

setElementDimension(localPlayer, 0)
uicore:toggleMoveControls(true)
setCameraTarget(localPlayer)
fadeCamera(true)
