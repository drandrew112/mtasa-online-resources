-- Test runs. The server puts the player into a vehicle (race) or gives the
-- weapon (deathmatch); race checkpoints run locally here. F6 ends the test.

Test = {}

local run = nil     -- { index, marker, blip, startTick }

local function clearMarker()
    if not run then return end
    if isElement(run.marker) then destroyElement(run.marker) end
    if isElement(run.blip) then destroyElement(run.blip) end
    run.marker, run.blip = nil, nil
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
    run.marker = createMarker(cp[1], cp[2], cp[3], "checkpoint", cp[4] or 5,
        isFinish and 255 or 255, isFinish and 70 or 200, isFinish and 70 or 0, 160)
    setElementDimension(run.marker, Editor.info.dimension)
    local nextCp = not isFinish and point(run.index + 1)
    if nextCp then setMarkerTarget(run.marker, nextCp[1], nextCp[2], nextCp[3]) end
    if isFinish then setMarkerIcon(run.marker, "finish") end
    run.blip = createBlipAttachedTo(run.marker, 0, 2, 255, 200, 0)
    setElementDimension(run.blip, Editor.info.dimension)
end

local function formatTime(ms)
    return string.format("%d:%02d.%03d", math.floor(ms / 60000), math.floor(ms / 1000) % 60, ms % 1000)
end

addEventHandler("onClientMarkerHit", root, function(hitElement, matchingDimension)
    if not run or source ~= run.marker or not matchingDimension then return end
    if hitElement ~= localPlayer and hitElement ~= getPedOccupiedVehicle(localPlayer) then return end
    local _, isFinish = point(run.index)
    playSoundFrontEnd(43)
    if isFinish then
        clearMarker()
        notify("Finished in " .. formatTime(getTickCount() - run.startTick) .. ".")
        setTimer(Test.stop, 2500, 1)
        return
    end
    run.index = run.index + 1
    showCheckpoint()
end)

function Test.start(x, y, z, rz, firstCheckpoint)
    if Editor.testing or not Editor.doc then return end
    local doc = Editor.doc
    if doc.type == "race" and not doc.race.finish then notify("Place the finish first.") return end
    Tools.cancel()
    Menus.close()
    if Editor.camMode == "free" then Freecam.stop() end
    Editor.testing = true
    Editor.selected = nil
    View.setHelpersVisible(false)
    iobj:setInteractionDisabled(true)
    run = { index = firstCheckpoint or 1, startTick = getTickCount() }
    triggerServerEvent("jobcreator:testStart", resourceRoot, {
        x = x, y = y, z = z, rot = rz,
        model = doc.race and doc.race.vehicles[1],
        weapon = doc.deathmatch and doc.deathmatch.weapon,
        ammo = doc.deathmatch and doc.deathmatch.ammo,
        armour = doc.deathmatch and doc.deathmatch.armour,
    })
end

addEvent("jobcreator:testStarted", true)
addEventHandler("jobcreator:testStarted", resourceRoot, function()
    if not run then return end
    run.startTick = getTickCount()
    if Editor.doc.type == "race" then
        showCheckpoint()
        notify("Test started.  F6 ends it.")
    else
        notify("Test started with your weapon.  F6 ends it.")
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

addEvent("jobcreator:testStopped", true)
addEventHandler("jobcreator:testStopped", resourceRoot, function()
    Test.cleanup()
    notify("Test ended.")
end)
