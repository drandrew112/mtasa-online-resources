-- Server side session handling. Results are reported to other resources via
-- the "onArrowsGameFinish" event (source = player).

addEvent("onArrowsGameFinish", false)
addEvent("mg_arrows:onResult", true)

local sessions = {} -- [player] = { id, count, options, startTick, timer }
local lastId = 0

local function finishSession(player, reason, hits)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil

    if isTimer(session.timer) then killTimer(session.timer) end

    hits = hits or 0
    local total = session.count
    local success = reason == "completed" and arrowsIsSuccess(hits, total, session.options.passPercent)

    if isElement(player) then
        -- success, hits, total, percent, reason, sessionId
        triggerEvent("onArrowsGameFinish", player, success, hits, total, arrowsPercent(hits, total), reason, session.id)
    end
end

-- Starts the minigame for a player.
-- count: number of arrows (default 15), options: { speed = 1.0, passPercent = 70 }
-- Returns the session id, or false if the player is invalid or already playing.
function startArrowsGame(player, count, options)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end

    count = arrowsClampCount(count)
    options = arrowsNormalizeOptions(options)

    lastId = lastId + 1
    local session = {
        id = lastId,
        count = count,
        options = options,
        startTick = getTickCount(),
    }
    local timeout = (arrowsMaxDuration(count, options.speed) + 15) * 1000
    session.timer = setTimer(finishSession, timeout, 1, player, "timeout", 0)
    sessions[player] = session

    triggerClientEvent(player, "mg_arrows:start", resourceRoot, session.id, count, options)
    return session.id
end

-- Aborts a running game. onArrowsGameFinish fires with reason "cancelled".
function stopArrowsGame(player)
    if not sessions[player] then return false end
    triggerClientEvent(player, "mg_arrows:stop", resourceRoot)
    finishSession(player, "cancelled", 0)
    return true
end

function isArrowsGameActive(player)
    return sessions[player] ~= nil
end

addEventHandler("mg_arrows:onResult", resourceRoot, function(sessionId, hits, total)
    local player = client
    local session = sessions[player]
    if not session or session.id ~= sessionId then return end

    hits = math.floor(tonumber(hits) or -1)
    local elapsed = (getTickCount() - session.startTick) / 1000

    if total ~= session.count or hits < 0 or hits > session.count
        or elapsed < arrowsMinDuration(session.count, session.options.speed) then
        outputDebugString(("mg_arrows: rejected result from %s (hits=%s, total=%s, %.1fs)")
            :format(getPlayerName(player), tostring(hits), tostring(total), elapsed), 2)
        finishSession(player, "invalid", 0)
        return
    end

    finishSession(player, "completed", hits)
end)

addEventHandler("onPlayerQuit", root, function()
    finishSession(source, "quit", 0)
end)

if ARROWS.TEST_COMMAND then
    addCommandHandler("arrowstest", function(player, _, count, speed)
        startArrowsGame(player, tonumber(count), { speed = tonumber(speed) })
    end)

    addEventHandler("onArrowsGameFinish", root, function(success, hits, total, percent, reason)
        outputChatBox(("[mg_arrows] %s - %d/%d (%d%%), reason: %s")
            :format(success and "SUCCESS" or "FAILED", hits, total, percent, reason), source, 255, 200, 0)
    end)
end
