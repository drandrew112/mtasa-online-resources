if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
uicore = exports.ui_core
ui = function(z) return uicore:ui(z) end

local trial = Timetrials[ACTIVE_TIMETRIAL]
local timeLeft = 0
local active = false
local timer

-- admin test mode (/tttest): private trial + markers, no reward
local test -- { trial, start, finish }

local function currentTrial()
    return test and test.trial or trial
end

local function endMarkerElement()
    if test then return isElement(test.finish) and test.finish or nil end
    local m = getElementByID("tt:end")
    return isElement(m) and m or nil
end

local objectiveId

local function clearObjective()
    if objectiveId then
        exports.v_radar:removeObjective(objectiveId)
        objectiveId = nil
    end
end

-- the countdown HUD is attached from tt:started until the run ends (tt:finish, reset, stop)
local function drawCountdown()
    if isPlayerMapVisible() or getElementData(localPlayer, "paused") then return end
    uicore:drawTimer(timeLeft)
end

local function setActive(on)
    if on == active then return end
    active = on
    exports.ui_core:setMarkerUIsHidden(on)   -- no start card during a run
    if on then
        addEventHandler("onClientRender", root, drawCountdown)
    else
        removeEventHandler("onClientRender", root, drawCountdown)
    end
end

local function stopRun()
    if timer and isTimer(timer) then killTimer(timer) end
    timer = nil
    setActive(false)
end

local function resetRun()
    clearObjective()
    stopRun()
    timeLeft = 0
end

addEvent("tt:notice", true)
addEventHandler("tt:notice", resourceRoot, function(text)
    uicore:setBanner(L("v_timetrial.timetrial.time_trial_test"), text)
end)

addEvent("tt:test", true)
addEventHandler("tt:test", resourceRoot, function(index, startM, finishM)
    resetRun()
    if index and Timetrials[index] then
        test = { trial = Timetrials[index], start = startM, finish = finishM }
        if isElement(finishM) then setElementAlpha(finishM, 0) end
    else
        test = nil
    end
    refreshTrialCard()
end)

-- the server switches the active trial (weekly schedule)
addEvent("tt:setActive", true)
addEventHandler("tt:setActive", resourceRoot, function(index)
    if not Timetrials[index] then return end
    resetRun()
    trial = Timetrials[index]
    refreshTrialCard()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("tt:requestActive", localPlayer)
end)

-- === 3D LABEL: a ui_core marker UI above the start of the current trial ===
local LABEL_HEIGHT, LABEL_DISTANCE, LABEL_FULL, LABEL_MIN_SCALE = 1.8, 40, 12, 0.55
local ACCENT = { 170, 70, 255 }

-- the hint inside the start marker depends on the vehicle
local function cardMeta()
    return { hintActive = isLandDriver(localPlayer) and L.msg("v_timetrial.timetrial.press_e_to_start")
        or L.msg("v_timetrial.timetrial.land_vehicle_required") }
end

-- (re)defines the card of the current trial; hidden while a run is active
function refreshTrialCard()
    local tr = currentTrial()
    if not tr or not tr.start then return exports.ui_core:removeMarkerUI("trial") end
    local isTest = test ~= nil
    exports.ui_core:createMarkerUI("trial", {
        type = "timetrial", color = ACCENT, icon = L.msg("v_timetrial.timetrial.tt"),
        x = tr.start.x, y = tr.start.y, z = tr.start.z, dimension = -1, size = 4,
        name = isTest and L.msg("v_timetrial.timetrial.time_trial_test_2") or L.msg("v_timetrial.timetrial.time_trial"),
        title = tr.name,
        hint = L.msg("v_timetrial.timetrial.sec", { time = tr.time,
            reward = isTest and L.msg("v_timetrial.timetrial.no_reward") or ("EUR " .. tr.reward) }),
        radius = LABEL_DISTANCE, fullRadius = LABEL_FULL, minScale = LABEL_MIN_SCALE, height = LABEL_HEIGHT,
    })
    exports.ui_core:setMarkerUIMeta("trial", cardMeta())
end

local function refreshCardMeta() exports.ui_core:setMarkerUIMeta("trial", cardMeta()) end
addEvent("onClientMarkerUIHit")
addEventHandler("onClientMarkerUIHit", resourceRoot, refreshCardMeta)
addEventHandler("onClientPlayerVehicleEnter", localPlayer, refreshCardMeta)
addEventHandler("onClientPlayerVehicleExit", localPlayer, refreshCardMeta)
addEvent("onClientMarkerUISystemStart")
addEventHandler("onClientMarkerUISystemStart", root, refreshTrialCard)
addEventHandler("onClientResourceStart", resourceRoot, refreshTrialCard)

-- === INDÍTÁS ===
-- E only asks the server; the run starts when the server answers with tt:started.
local requested = 0
bindKey("e", "down", function()
    if not getElementData(localPlayer, "tt:canStart") then return end
    if active then return end
    if not isLandDriver(localPlayer) then return end
    if getTickCount() - requested < 1000 then return end
    requested = getTickCount()
    triggerServerEvent("tt:start", resourceRoot)
end)

addEvent("tt:started", true)
addEventHandler("tt:started", resourceRoot, function(duration)
    stopRun()
    setActive(true)
    local tr = currentTrial()
    timeLeft = tonumber(duration) or tr.time

    local endM = endMarkerElement()
    if endM then setElementAlpha(endM, 160) end
    clearObjective()
    objectiveId = exports.v_radar:addObjective(tr.finish.x, tr.finish.y, tr.finish.z, tr.name) or nil
    uicore:setBanner(L("v_timetrial.timetrial.time_trial_started"), L("v_timetrial.timetrial.good_luck"))

    -- countdown display only: the server decides success / timeout and sends tt:finish
    timer = setTimer(function()
        timeLeft = math.max(0, timeLeft - 1)
    end, 1000, timeLeft)
end)

-- === BEFEJEZÉS ===
addEvent("tt:finish", true)
addEventHandler("tt:finish", localPlayer, function(success)
    stopRun()
    clearObjective()
    local endM = endMarkerElement()
    if endM then setElementAlpha(endM, 0) end

    if success then
        uicore:setBanner(L("v_timetrial.timetrial.time_trial_completed"), test and L("v_timetrial.timetrial.test_run_no_reward") or (L("v_timetrial.timetrial.reward", { reward = trial.reward })))
    else
        uicore:setBanner(L("v_timetrial.timetrial.time_trial_failed"), L("v_timetrial.timetrial.out_of_time"))
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    stopRun()
    clearObjective()
end)
