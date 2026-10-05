-- Server side session handling. Results are reported to other resources via
-- the "onSplintGameFinish" event (source = player).

addEvent("onSplintGameFinish", false)
addEvent("mg_splinting:onResult", true)
addEvent("mg_splinting:ready", true)

local sessions = {} -- [player] = { id, count, options, ped, animated, startTick, timer }
local lastId = 0

local function finishSession(player, reason, hits, total)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil

    if isTimer(session.timer) then killTimer(session.timer) end

    hits, total = hits or 0, total or 0
    local success = reason == "completed" and splintIsSuccess(hits, total, session.options.passPercent)
    if isElement(player) then
        if session.animated then setPedAnimation(player) end
        -- success, hits, total, percent, reason, sessionId
        triggerEvent("onSplintGameFinish", player, success, hits, total, splintPercent(hits, total), reason, session.id)
    end
end

-- Starts the splinting minigame for a player.
-- ped: optional ped/player being treated - the player is placed next to it and plays a kneeling animation
-- count: wraps needed, defaults to 8
-- options: { speed = 1.0, passPercent = 70, time = 40 }
-- Returns the session id, or false if the player/ped is invalid or the player is already playing.
function startSplintGame(player, ped, count, options)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end
    if ped ~= nil then
        if not isElement(ped) or ped == player then return false end
        local pedType = getElementType(ped)
        if pedType ~= "ped" and pedType ~= "player" then return false end
    end

    count = splintClampCount(count)
    options = splintNormalizeOptions(options)
    if ped and isPedInVehicle(player) then removePedFromVehicle(player) end

    lastId = lastId + 1
    local session = {
        id = lastId,
        count = count,
        options = options,
        ped = ped,
        startTick = getTickCount(),
    }
    local timeout = (SPLINT.COUNTDOWN + options.time + SPLINT.RESULT_TIME + 15) * 1000
    session.timer = setTimer(finishSession, timeout, 1, player, "timeout")
    sessions[player] = session

    triggerClientEvent(player, "mg_splinting:start", resourceRoot, session.id, count, options, ped)
    return session.id
end

-- Aborts a running game. onSplintGameFinish fires with reason "cancelled".
function stopSplintGame(player)
    if not sessions[player] then return false end
    triggerClientEvent(player, "mg_splinting:stop", resourceRoot)
    finishSession(player, "cancelled")
    return true
end

function isSplintGameActive(player)
    return sessions[player] ~= nil
end

-- The client has placed itself next to the ped, start the (synced) animation
addEventHandler("mg_splinting:ready", resourceRoot, function(sessionId)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId or not session.ped or session.animated then return end

    session.animated = true
    setPedAnimation(player, SPLINT.ANIM_BLOCK, SPLINT.ANIM_NAME, -1, true, false, false, false)
end)

addEventHandler("mg_splinting:onResult", resourceRoot, function(sessionId, hits, total, reason)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId then return end

    hits = math.floor(tonumber(hits) or -1)
    total = math.floor(tonumber(total) or -1)
    local elapsed = (getTickCount() - session.startTick) / 1000

    if type(reason) ~= "string" or (reason ~= "completed" and reason ~= "expired")
        or hits < 0 or total < hits or total > session.count
        or elapsed < splintMinDuration(session.count, session.options.speed) then
        outputDebugString(("mg_splinting: rejected result from %s (reason=%s, hits=%d, total=%d, %.1fs)")
            :format(getPlayerName(player), tostring(reason), hits, total, elapsed), 2)
        finishSession(player, "invalid")
        return
    end

    finishSession(player, reason, hits, total)
end)

addEventHandler("onPlayerWasted", root, function()
    if not sessions[source] then return end
    triggerClientEvent(source, "mg_splinting:stop", resourceRoot)
    finishSession(source, "died")
end)

addEventHandler("onPlayerQuit", root, function()
    finishSession(source, "quit")
end)

if SPLINT.TEST_COMMAND then
    local testPeds = {}

    addCommandHandler("splinttest", function(player, _, count, speed, withPed)
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
        if startSplintGame(player, ped, tonumber(count), { speed = tonumber(speed) }) then
            testPeds[player] = ped
        elseif ped then
            destroyElement(ped)
        end
    end)

    addEventHandler("onSplintGameFinish", root, function(success, hits, total, percent, reason)
        outputChatBox(("[mg_splinting] %s - %d/%d (%d%%), reason: %s")
            :format(success and "SUCCESS" or "FAILED", hits, total, percent, reason), source, 255, 200, 0)
        local ped = testPeds[source]
        testPeds[source] = nil
        if isElement(ped) then setTimer(destroyElement, 3000, 1, ped) end
    end)
end
