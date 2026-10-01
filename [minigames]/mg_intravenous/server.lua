-- Server side session handling. Results are reported to other resources via
-- the "onIVGameFinish" event (source = player).

addEvent("onIVGameFinish", false)
addEvent("mg_intravenous:onResult", true)
addEvent("mg_intravenous:ready", true)

local sessions = {} -- [player] = { id, options, ped, animated, startTick, timer }
local lastId = 0

local function finishSession(player, reason, attempts, quality)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil

    if isTimer(session.timer) then killTimer(session.timer) end

    local success = reason == "completed"
    if isElement(player) then
        if session.animated then setPedAnimation(player) end
        -- success, attempts used, quality (0-100), reason, sessionId
        triggerEvent("onIVGameFinish", player, success, attempts or 0, success and quality or 0, reason, session.id)
    end
end

-- Starts the IV cannulation minigame for a player.
-- ped: optional ped/player being treated - the player is placed next to it and plays a kneeling animation
-- options: { difficulty = 2, time = 45, attempts = 2, showDepth = true }
-- Returns the session id, or false if the player/ped is invalid or the player is already playing.
function startIVGame(player, ped, options)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end
    if ped ~= nil then
        if not isElement(ped) or ped == player then return false end
        local pedType = getElementType(ped)
        if pedType ~= "ped" and pedType ~= "player" then return false end
    end

    options = ivNormalizeOptions(options)
    if ped and isPedInVehicle(player) then removePedFromVehicle(player) end

    lastId = lastId + 1
    local session = {
        id = lastId,
        options = options,
        ped = ped,
        startTick = getTickCount(),
    }
    local timeout = (IV.COUNTDOWN + options.time + IV.RESULT_TIME + 15) * 1000
    session.timer = setTimer(finishSession, timeout, 1, player, "timeout")
    sessions[player] = session

    triggerClientEvent(player, "mg_intravenous:start", resourceRoot, session.id, options, ped)
    return session.id
end

-- Aborts a running game. onIVGameFinish fires with reason "cancelled".
function stopIVGame(player)
    if not sessions[player] then return false end
    triggerClientEvent(player, "mg_intravenous:stop", resourceRoot)
    finishSession(player, "cancelled")
    return true
end

function isIVGameActive(player)
    return sessions[player] ~= nil
end

-- The client has placed itself next to the ped, start the (synced) animation
addEventHandler("mg_intravenous:ready", resourceRoot, function(sessionId)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId or not session.ped or session.animated then return end

    session.animated = true
    setPedAnimation(player, IV.ANIM_BLOCK, IV.ANIM_NAME, -1, true, false, false, false)
end)

addEventHandler("mg_intravenous:onResult", resourceRoot, function(sessionId, reason, attempts, quality)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId then return end

    attempts = math.floor(tonumber(attempts) or -1)
    quality = math.floor(tonumber(quality) or -1)
    local elapsed = (getTickCount() - session.startTick) / 1000

    if type(reason) ~= "string" or not IV_CLIENT_REASONS[reason]
        or attempts < 1 or attempts > session.options.attempts
        or quality < 0 or quality > 100
        or elapsed < ivMinDuration(reason, session.options) then
        outputDebugString(("mg_intravenous: rejected result from %s (reason=%s, attempts=%d, quality=%d, %.1fs)")
            :format(getPlayerName(player), tostring(reason), attempts, quality, elapsed), 2)
        finishSession(player, "invalid")
        return
    end

    finishSession(player, reason, attempts, quality)
end)

addEventHandler("onPlayerWasted", root, function()
    if not sessions[source] then return end
    triggerClientEvent(source, "mg_intravenous:stop", resourceRoot)
    finishSession(source, "died")
end)

addEventHandler("onPlayerQuit", root, function()
    finishSession(source, "quit")
end)

if IV.TEST_COMMAND then
    local testPeds = {}

    addCommandHandler("ivtest", function(player, _, difficulty, withPed)
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
        if startIVGame(player, ped, { difficulty = tonumber(difficulty) }) then
            testPeds[player] = ped
        elseif ped then
            destroyElement(ped)
        end
    end)

    addEventHandler("onIVGameFinish", root, function(success, attempts, quality, reason)
        outputChatBox(("[mg_intravenous] %s - attempts: %d, quality: %d%%, reason: %s")
            :format(success and "SUCCESS" or "FAILED", attempts, quality, reason), source, 255, 200, 0)
        local ped = testPeds[source]
        testPeds[source] = nil
        if isElement(ped) then setTimer(destroyElement, 3000, 1, ped) end
    end)
end
