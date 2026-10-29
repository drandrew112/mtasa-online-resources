if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Test runs. The server puts the player into a vehicle (race) or gives the
-- weapon (deathmatch); race checkpoints run locally here and are drawn by
-- v_jobmanager's checkpoint visuals (raceCheckpointsShow). A mission test is a real
-- v_jobmanager mission match alone in the editor dimension. F6 ends the test.

Test = {}

local run = nil     -- { index, marker, blip, startTick, mission }

local function jobmanagerRunning()
    local res = getResourceFromName("v_jobmanager")
    return res and getResourceState(res) == "running"
end

local function clearMarker()
    if not run then return end
    if isElement(run.marker) then destroyElement(run.marker) end
    if isElement(run.blip) then destroyElement(run.blip) end
    run.marker, run.blip = nil, nil
    if run.visuals and jobmanagerRunning() then exports.v_jobmanager:raceCheckpointsClear() end
    run.visuals = nil
end

local function point(index)
    local race = Editor.doc.race
    local cp = race.checkpoints[index]
    if cp then return cp, false end
    return race.finish, true
end

local function showCheckpoint()
    clearMarker()
    local cp, isFinish = point(run.index)
    if not cp then return end
    local nextCp, nextFinish = nil, false
    if not isFinish then nextCp, nextFinish = point(run.index + 1) end
    local after = nextCp and not nextFinish and point(run.index + 2) or nil
    -- the shader checkpoint of the real races; without v_jobmanager the GTA one
    local visuals = jobmanagerRunning() and exports.v_jobmanager:raceCheckpointsShow({
        cp = cp, isFinish = isFinish, next = nextCp or false, nextFinish = nextFinish or false, after = after or false,
    })
    run.visuals = visuals and true or nil
    -- with the shader visuals only an invisible colshape counts the hit: a GTA "checkpoint"
    -- marker still draws at alpha 0
    if visuals then
        run.marker = createColTube(cp[1], cp[2], cp[3] - 6, cp[4] or 5, 18)
    else
        run.marker = createMarker(cp[1], cp[2], cp[3], "checkpoint", cp[4] or 5,
            255, isFinish and 70 or 200, isFinish and 70 or 0, 160)
    end
    setElementDimension(run.marker, Editor.info.dimension)
    if not visuals then
        if nextCp then setMarkerTarget(run.marker, nextCp[1], nextCp[2], nextCp[3]) end
        if isFinish then setMarkerIcon(run.marker, "finish") end
        run.blip = createBlipAttachedTo(run.marker, 0, 2, 255, 200, 0)
        setElementDimension(run.blip, Editor.info.dimension)
    end
end

local function formatTime(ms)
    return string.format("%d:%02d.%03d", math.floor(ms / 60000), math.floor(ms / 1000) % 60, ms % 1000)
end

local function onCheckpointHit(hitElement, matchingDimension)
    if not run or source ~= run.marker or not matchingDimension then return end
    if hitElement ~= localPlayer and hitElement ~= getPedOccupiedVehicle(localPlayer) then return end
    local _, isFinish = point(run.index)
    playSoundFrontEnd(43)
    if isFinish then
        clearMarker()
        notify(L("v_jobcreator.test.finished_in", { start_tick = formatTime(getTickCount() - run.startTick) }))
        setTimer(Test.stop, 2500, 1)
        return
    end
    run.index = run.index + 1
    showCheckpoint()
end
addEventHandler("onClientMarkerHit", root, onCheckpointHit)
addEventHandler("onClientColShapeHit", root, onCheckpointHit)

local function begin()
    Tools.cancel()
    Menus.close()
    if Editor.camMode == "free" then Freecam.stop() end
    Editor.testing = true
    Editor.selected = nil
    View.setHelpersVisible(false)
    iobj:setInteractionDisabled(true)
end

function Test.start(x, y, z, rz, firstCheckpoint)
    if Editor.testing or not Editor.doc then return end
    local doc = Editor.doc
    if doc.type == "race" and not doc.race.finish then notify(L("v_jobcreator.test.place_finish_first")) return end
    begin()
    run = { index = firstCheckpoint or 1, startTick = getTickCount() }
    triggerServerEvent("jobcreator:testStart", resourceRoot, {
        x = x, y = y, z = z, rot = rz,
        model = doc.race and doc.race.vehicles[1],
        weapon = doc.deathmatch and doc.deathmatch.weapon,
        ammo = doc.deathmatch and doc.deathmatch.ammo,
        armour = doc.deathmatch and doc.deathmatch.armour,
    })
end

-- stageId: the stage the test starts with
function Test.startMission(stageId)
    if Editor.testing or not Editor.doc or Editor.doc.type ~= "mission" then return end
    if not jobmanagerRunning() then notify(L("v_jobcreator.main.job_manager_is_not_running")) return end
    if #Editor.doc.mission.spawnpoints == 0 then notify(L("v_jobcreator.menus.place_spawnpoint_1_first")) return end
    begin()
    run = { mission = true, startTick = getTickCount() }
    triggerServerEvent("jobcreator:testStart", resourceRoot, { doc = Editor.doc, stage = stageId })
end

addEvent("jobcreator:testStarted", true)
addEventHandler("jobcreator:testStarted", resourceRoot, function()
    if not run then return end
    run.startTick = getTickCount()
    if run.mission then
        notify(L("v_jobcreator.test.mission_test_started"))
    elseif Editor.doc.type == "race" then
        showCheckpoint()
        notify(L("v_jobcreator.test.test_started_f6_ends_it"))
    else
        notify(L("v_jobcreator.test.test_started_with_your_weapon_f6"))
    end
end)

function Test.stop()
    if not Editor.testing then return end
    triggerServerEvent("jobcreator:testStop", resourceRoot)
end

function Test.cleanup()
    clearMarker()
    run = nil
    if Editor.testing then
        Editor.testing = false
        View.setHelpersVisible(true)
        iobj:setInteractionDisabled(false)
    end
end

-- result: the mission test's "success" | "fail" | "aborted" (nil for race / DM)
addEvent("jobcreator:testStopped", true)
addEventHandler("jobcreator:testStopped", resourceRoot, function(result)
    Test.cleanup()
    if result == "success" then
        notify(L("v_jobcreator.test.mission_passed"))
    elseif result == "fail" then
        notify(L("v_jobcreator.test.mission_failed"))
    else
        notify(L("v_jobcreator.test.test_ended"))
    end
end)
