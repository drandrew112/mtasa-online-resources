-- Server side session handling. Results are reported to other resources via
-- the "onCPRGameFinish" event (source = player).

addEvent("onCPRGameFinish", false)
addEvent("mg_cpr:onResult", true)
addEvent("mg_cpr:ready", true)

local sessions = {} -- [player] = { id, duration, options, ped, animated, startTick, timer }
local lastId = 0

local function finishSession(player, reason, good, total, avgBPM)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil

    if isTimer(session.timer) then killTimer(session.timer) end

    good, total = good or 0, total or 0
    local success = reason == "completed" and cprIsSuccess(good, total, session.options.passPercent)

    if isElement(player) then
        if session.animated then setPedAnimation(player) end
        -- success, good, total, percent, reason, sessionId, avgBPM
        triggerEvent("onCPRGameFinish", player, success, good, total, cprPercent(good, total),
            reason, session.id, avgBPM or 0)
    end
end

-- Starts the CPR minigame for a player.
-- duration: seconds of compressions (default 30)
-- ped: optional ped/player being resuscitated - the player is placed next to it and plays the CPR animation
-- options: { minBPM = 90, maxBPM = 130, passPercent = 70, guide = true }
-- Returns the session id, or false if the player/ped is invalid or the player is already playing.
function startCPRGame(player, duration, ped, options)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end
    if ped ~= nil then
        if not isElement(ped) or ped == player then return false end
        local pedType = getElementType(ped)
        if pedType ~= "ped" and pedType ~= "player" then return false end
    end

    duration = cprClampDuration(duration)
    options = cprNormalizeOptions(options)

    if ped and isPedInVehicle(player) then removePedFromVehicle(player) end

    lastId = lastId + 1
    local session = {
        id = lastId,
        duration = duration,
        options = options,
        ped = ped,
        startTick = getTickCount(),
    }
    local timeout = (CPR.COUNTDOWN + duration + CPR.RESULT_TIME + 15) * 1000
    session.timer = setTimer(finishSession, timeout, 1, player, "timeout")
    sessions[player] = session

    triggerClientEvent(player, "mg_cpr:start", resourceRoot, session.id, duration, options, ped)
    return session.id
end

-- Aborts a running game. onCPRGameFinish fires with reason "cancelled".
function stopCPRGame(player)
    if not sessions[player] then return false end
    triggerClientEvent(player, "mg_cpr:stop", resourceRoot)
    finishSession(player, "cancelled")
    return true
end

function isCPRGameActive(player)
    return sessions[player] ~= nil
end

-- The client has placed itself next to the ped, start the (synced) animation
addEventHandler("mg_cpr:ready", resourceRoot, function(sessionId)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId or not session.ped or session.animated then return end

    session.animated = true
    setPedAnimation(player, CPR.ANIM_BLOCK, CPR.ANIM_NAME, -1, true, false, false, false)
end)

addEventHandler("mg_cpr:onResult", resourceRoot, function(sessionId, good, judged, missed, avgBPM)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId then return end

    good = math.floor(tonumber(good) or -1)
    judged = math.floor(tonumber(judged) or -1)
    missed = math.floor(tonumber(missed) or -1)
    local total = judged + missed
    local elapsed = (getTickCount() - session.startTick) / 1000

    if good < 0 or judged < good or missed < 0
        or good > cprMaxGood(session.duration, session.options)
        or total < cprMinTotal(session.duration, session.options)
        or elapsed < (CPR.COUNTDOWN + session.duration) * 0.9 then
        outputDebugString(("mg_cpr: rejected result from %s (good=%d, judged=%d, missed=%d, %.1fs)")
            :format(getPlayerName(player), good, judged, missed, elapsed), 2)
        finishSession(player, "invalid")
        return
    end

    finishSession(player, "completed", good, total, math.floor(tonumber(avgBPM) or 0))
end)

addEventHandler("onPlayerWasted", root, function()
    if not sessions[source] then return end
    triggerClientEvent(source, "mg_cpr:stop", resourceRoot)
    finishSession(source, "died")
end)

addEventHandler("onPlayerQuit", root, function()
    finishSession(source, "quit")
end)

if CPR.TEST_COMMAND then
    local testPeds = {}

    addCommandHandler("cprtest", function(player, _, duration, withPed)
        local ped
        if withPed ~= "0" then
            local x, y, z = getElementPosition(player)
            local _, _, rz = getElementRotation(player)
            local a = math.rad(rz)
            ped = createPed(math.random(7, 30), x - math.sin(a) * 2, y + math.cos(a) * 2, z, rz + 90)
            setElementInterior(ped, getElementInterior(player))
            setElementDimension(ped, getElementDimension(player))
            setTimer(function()
                if isElement(ped) then setPedAnimation(ped, "PED", "KO_shot_front", -1, false, false, false, true) end
            end, 100, 1)
        end
        if startCPRGame(player, tonumber(duration), ped) then
            testPeds[player] = ped
        elseif ped then
            destroyElement(ped)
        end
    end)

    addEventHandler("onCPRGameFinish", root, function(success, good, total, percent, reason, _, avgBPM)
        outputChatBox(("[mg_cpr] %s - %d/%d good (%d%%), avg %d BPM, reason: %s")
            :format(success and "SUCCESS" or "FAILED", good, total, percent, avgBPM, reason), source, 255, 200, 0)
        local ped = testPeds[source]
        testPeds[source] = nil
        if isElement(ped) then setTimer(destroyElement, 3000, 1, ped) end
    end)
end
