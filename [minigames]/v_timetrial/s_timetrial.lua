if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
local activeIndex = ACTIVE_TIMETRIAL
local trial = Timetrials[activeIndex]
local startMarker, endMarker, startBlip
local BLIP_ICON = 61

addEvent("tt:requestActive", true)
addEvent("tt:start", true)

-- Every run is tracked here; the client only shows it. The reward is paid only for a run that
-- the server started in the start marker and that reached the finish within the trial time.
local FINISH_GRACE = 1500 -- ms of network / timer slack after the trial time
local MAX_SPEED = 85      -- m/s; a run faster than the straight line at this speed is rejected
local runs = {} -- [player] = { trial, test, startTick, deadline, timer }

local function endRun(player, success)
    local run = runs[player]
    if not run then return end
    runs[player] = nil
    if isTimer(run.timer) then killTimer(run.timer) end
    if isElement(player) then
        triggerClientEvent(player, "tt:finish", player, success)
    end
end

-- shortest possible time for a trial in ms (straight line at MAX_SPEED)
local function minimumTime(tr)
    return (tr.finish - tr.start).length / MAX_SPEED * 1000
end

local function createMarkers()
    if isElement(startMarker) then destroyElement(startMarker) end
    if isElement(endMarker) then destroyElement(endMarker) end
    if isElement(startBlip) then destroyElement(startBlip) end

    startMarker = createMarker(
        trial.start.x, trial.start.y, trial.start.z - 1,
        "cylinder", 4, 0, 150, 255, 120
    )

    startBlip = createBlipAttachedTo(startMarker, BLIP_ICON, 2, 255, 255, 255, 255, 0, 99999)

    setElementData(startMarker, "tt:start", true)
    setElementID(startMarker, "tt:start")

    endMarker = createMarker(
        trial.finish.x, trial.finish.y, trial.finish.z - 1,
        "cylinder", 6, 255, 255, 0, 120
    )

    setElementData(endMarker, "tt:end", true)
    setElementID(endMarker, "tt:end")

    setElementAlpha(endMarker, 0)
end

addEventHandler("onResourceStart", resourceRoot, createMarkers)

-- Called by v_weekly (and usable by anything else): switches the active trial.
function setActiveTimetrial(index)
    index = tonumber(index)
    if not index or not Timetrials[index] then return false end
    if index == activeIndex then return true end

    activeIndex = index
    trial = Timetrials[index]
    for p, run in pairs(runs) do
        if not run.test then endRun(p, false) end
    end
    for _, p in ipairs(getElementsByType("player")) do
        setElementData(p, "tt:canStart", false)
    end
    createMarkers()
    triggerClientEvent(root, "tt:setActive", resourceRoot, index)
    return true
end

function getActiveTimetrial()
    return activeIndex
end

-- -> { [index] = { name, time, reward } }
function getTimetrials()
    local list = {}
    for i, t in ipairs(Timetrials) do
        list[i] = { name = t.name, time = t.time, reward = t.reward }
    end
    return list
end

addEventHandler("tt:requestActive", root, function()
    triggerClientEvent(client, "tt:setActive", resourceRoot, activeIndex)
end)

-- === TEST MODE (/tttest, admin >= 4) ===
-- Private markers visible only to the tester; any trial, no reward.
local TEST_ADMIN_LEVEL = 4
local tests = {} -- [player] = { index, start, finish }

local function notice(player, text)
    triggerClientEvent(player, "tt:notice", resourceRoot, text)
end

local function stopTest(player, silent)
    local t = tests[player]
    if not t then return end
    tests[player] = nil
    if runs[player] and runs[player].test then
        local run = runs[player]
        runs[player] = nil
        if isTimer(run.timer) then killTimer(run.timer) end
    end
    if isElement(t.start) then destroyElement(t.start) end
    if isElement(t.finish) then destroyElement(t.finish) end
    if isElement(t.blip) then destroyElement(t.blip) end
    if isElement(player) then
        setElementData(player, "tt:canStart", false)
        triggerClientEvent(player, "tt:test", resourceRoot, false)
        if not silent then notice(player, L.msg("v_timetrial.timetrial.time_trial_test_stopped")) end
    end
end

local function startTest(player, index)
    stopTest(player, true)
    local tr = Timetrials[index]
    local sm = createMarker(tr.start.x, tr.start.y, tr.start.z - 1, "cylinder", 4, 0, 150, 255, 120)
    local fm = createMarker(tr.finish.x, tr.finish.y, tr.finish.z - 1, "cylinder", 6, 255, 255, 0, 120)
    for _, m in ipairs({ sm, fm }) do
        setElementVisibleTo(m, root, false)
        setElementVisibleTo(m, player, true)
    end
    local blip = createBlipAttachedTo(sm, BLIP_ICON, 2, 255, 255, 255, 255, 0, 99999)
    setElementVisibleTo(blip, root, false)
    setElementVisibleTo(blip, player, true)
    tests[player] = { index = index, start = sm, finish = fm, blip = blip }

    local veh = getPedOccupiedVehicle(player)
    local target = veh or player
    setElementPosition(target, tr.start.x, tr.start.y, tr.start.z + 1)
    triggerClientEvent(player, "tt:test", resourceRoot, index, sm, fm)
end

addCommandHandler("tttest", function(player, _, arg)
    if getElementData(player, "isLogged") ~= true
        or (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) < TEST_ADMIN_LEVEL then
        return
    end
    if arg == "stop" then
        if not tests[player] then return notice(player, "No test running") end
        return stopTest(player)
    end
    local index = tonumber(arg)
    if not index or not Timetrials[index] then
        local parts = {}
        for i, t in ipairs(Timetrials) do parts[#parts + 1] = i .. " = " .. t.name end
        return notice(player, "/tttest <1-" .. #Timetrials .. "|stop>   " .. table.concat(parts, "  |  "))
    end
    startTest(player, index)
    notice(player, "Testing: " .. Timetrials[index].name .. " (no reward)")
end)

addEventHandler("onPlayerQuit", root, function()
    stopTest(source, true)
    local run = runs[source]
    if run and isTimer(run.timer) then killTimer(run.timer) end
    runs[source] = nil
end)
addEventHandler("onResourceStop", resourceRoot, function()
    for p in pairs(tests) do stopTest(p, true) end
end)

-- The player pressed E in the start marker (c_timetrial.lua). Everything is checked here.
addEventHandler("tt:start", resourceRoot, function()
    local player = client
    if not isElement(player) or runs[player] then return end
    if getElementData(player, "isLogged") ~= true or isPedDead(player) then return end
    if not isLandDriver(player) then return end

    local t = tests[player]
    local tr = t and Timetrials[t.index] or trial
    local start = t and t.start or startMarker
    if not isElement(start) or not isElementWithinMarker(player, start) then return end

    local now = getTickCount()
    local run = { trial = tr, test = t ~= nil, startTick = now, deadline = now + tr.time * 1000 + FINISH_GRACE }
    run.timer = setTimer(endRun, run.deadline - now, 1, player, false)
    runs[player] = run
    setElementData(player, "tt:canStart", false)
    triggerClientEvent(player, "tt:started", resourceRoot, tr.time)
end)

local function tryFinish(player, marker)
    local run = runs[player]
    if not run then return end
    local t = tests[player]
    local finish = run.test and (t and t.finish) or endMarker
    if marker ~= finish then return end
    if not isLandDriver(player) then return end

    local elapsed = getTickCount() - run.startTick
    if elapsed > run.trial.time * 1000 + FINISH_GRACE then return endRun(player, false) end
    if elapsed < minimumTime(run.trial) then
        outputServerLog(("[v_timetrial] rejected run of %s: %d ms on %s (minimum %d ms)")
            :format(getPlayerName(player), elapsed, run.trial.name, math.floor(minimumTime(run.trial))))
        return endRun(player, false)
    end

    if not run.test then
        givePlayerMoney(player, run.trial.reward)
        exports.ui_core:showMoney(player, "add", run.trial.reward, "cash")
    end
    endRun(player, true)
end

addEventHandler("onPlayerMarkerHit", root, function(marker)
    local t = tests[source]
    if t and marker == t.start or (not t and marker == startMarker) then
        if not runs[source] then setElementData(source, "tt:canStart", true) end
        return
    end
    tryFinish(source, marker)
end)

-- leaving the vehicle or dying ends the run
addEventHandler("onPlayerVehicleExit", root, function() endRun(source, false) end)
addEventHandler("onPlayerWasted", root, function() endRun(source, false) end)

addEventHandler("onPlayerMarkerLeave", root, function(marker)
    local t = tests[source]
    if marker == startMarker or (t and marker == t.start) then
        setElementData(source, "tt:canStart", false)
    end
end)
