
addEvent("acc:startWorldCheck", true)

local worldTimer
local worldCheckCompleted = false
local preloadStarted = false
local stableChecks = 0

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

    triggerServerEvent("acc:clientWorldLoaded", localPlayer)
end

addEventHandler("acc:startWorldCheck", localPlayer, function()
    stopWorldCheck()

    worldCheckCompleted = false
    preloadStarted = false
    stableChecks = 0

    worldTimer = setTimer(checkWorldLoaded, 200, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopWorldCheck()
end)
