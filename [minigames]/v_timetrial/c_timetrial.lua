uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

local trial = Timetrials[ACTIVE_TIMETRIAL]
local timeLeft = 0
local active = false
local timer

-- === 3D TEXT ===
local function drawText3D(pos, text)
    local camX, camY, camZ = getCameraMatrix()
    local dist = getDistanceBetweenPoints3D(camX, camY, camZ, pos.x, pos.y, pos.z)

    if dist > 30 then return end

    local sx, sy = getScreenFromWorldPosition(pos.x, pos.y, pos.z + 2)
    if not sx then return end

    dxDrawText(
        text,
        sx, sy,
        sx, sy,
        tocolor(255, 255, 255, 255),
        ui(1.3),
        "default-bold",
        "center", "center",
        false, false, false, true
    )
end

addEventHandler("onClientRender", root, function()
    drawText3D(trial.start,
        "\n#dd00ffTIME TRIAL" ..
        "\n#ffffff" .. trial.name ..
        "\nTIME: " .. trial.time .. " sec" ..
        "\nREWARD: $" .. trial.reward
    )

    if active then
        uicore:drawTimer(timeLeft)
    end
end)

-- === INDÍTÁS ===
bindKey("e", "down", function()
    if not getElementData(localPlayer, "tt:canStart") then return end
    if active then return end

    active = true
    timeLeft = trial.time

    setElementAlpha(getElementByID("tt:end"), 160)
    setElementData(localPlayer, "tt:active", true)
    uicore:setBanner("TIME TRIAL STARTED", "Good luck!")

    timer = setTimer(function()
        timeLeft = timeLeft - 1
        if timeLeft <= 0 then
            triggerEvent("tt:finish", localPlayer, false)
        end
    end, 1000, trial.time)
end)

-- === BEFEJEZÉS ===
addEvent("tt:finish", true)
addEventHandler("tt:finish", root, function(success)
    if timer and isTimer(timer) then killTimer(timer) end

    active = false
    setElementAlpha(getElementByID("tt:end"), 0)
    setElementData(localPlayer, "tt:active", false)

    if success then
        uicore:setBanner("TIME TRIAL COMPLATED", "Reward: $" .. trial.reward)
    else
        uicore:setBanner("TIME TRIAL FAILED", "Out of time")
    end
end)


-- show infobox


addEventHandler("onClientMarkerHit", root, function()
    if getElementData(source, "tt:start") then
        uicore:setInfobox("Press [E] to start time trial")
    end
end)
