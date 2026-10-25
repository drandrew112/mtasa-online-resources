-- Waits until the world around the spawn point is streamed in (camera target
-- preloaded, collisions under the player loaded, 5 stable checks), then tells
-- the server (flow.lua) to drop the loading screen and play the spawn camera.

addEvent("acc_loading:startWorldCheck", true)

local WORLD_TIMEOUT = 20000 -- ms; go on anyway (interior spawn, ground that never reports loaded)

local worldTimer
local worldCheckCompleted = false
local preloadStarted = false
local stableChecks = 0
local worldStart = 0

local function stopWorldCheck()
    if isTimer(worldTimer) then
        killTimer(worldTimer)
    end
    worldTimer = nil
end

local function checkWorldLoaded()
    if worldCheckCompleted then
        stopWorldCheck()
        return
    end

    if getTickCount() - worldStart > WORLD_TIMEOUT then
        outputDebugString("[acc_loading] world check timed out, spawning anyway", 2)
        worldCheckCompleted = true
        stopWorldCheck()
        triggerServerEvent("acc_loading:clientWorldLoaded", localPlayer)
        return
    end

    local camX, camY, camZ, targetX, targetY, targetZ = getCameraMatrix()

    if not camX or not targetX then
        stableChecks = 0
        return
    end

    -- A kamera célpontja a spawnhely, nem a magasban lévő kamera.
    if not preloadStarted then
        preloadStarted = true

        if type(enginePreloadWorldArea) == "function" then
            enginePreloadWorldArea(targetX, targetY, targetZ, "all")
        end
    end

    -- A játékos ütközéseinek betöltését is ellenőrizzük.
    if isElementWaitingForGroundToLoad(localPlayer) then
        stableChecks = 0
        return
    end

    -- Több egymást követő ellenőrzés szükséges,
    -- hogy ne egyetlen pillanatnyi állapot alapján induljon el.
    stableChecks = stableChecks + 1

    if stableChecks < 5 then
        return
    end

    worldCheckCompleted = true
    stopWorldCheck()

    triggerServerEvent("acc_loading:clientWorldLoaded", localPlayer)
end

addEventHandler("acc_loading:startWorldCheck", localPlayer, function()
    stopWorldCheck()

    worldCheckCompleted = false
    preloadStarted = false
    stableChecks = 0
    worldStart = getTickCount()

    worldTimer = setTimer(checkWorldLoaded, 200, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopWorldCheck()
end)
