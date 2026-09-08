-- Account System - post-login loading gate
--
-- After a successful login or registration the player is shown a black
-- "Loading account data" screen instead of being spawned right away. External
-- data providers (currently only v_mysql's account-data sync) each report back
-- through the exported loadingComplete(player, type). Only once every expected
-- type has arrived - or a safety timeout elapses - is the player actually
-- spawned and their saved state restored.

local LOAD_TIMEOUT = 10000 -- ms; spawn anyway if a provider never answers

-- state[player] = { required = {type=true}, done = {type=true}, onReady = fn, timer = t }
local state = {}
-- earlyDone[player] = {type=true} for completions that arrived before beginLoading()
local earlyDone = {}

local function clearPlayer(player)
    local s = state[player]
    if s and isTimer(s.timer) then killTimer(s.timer) end
    state[player] = nil
    earlyDone[player] = nil
end

local function tryFinish(player)
    local s = state[player]
    if not s then return end
    for t in pairs(s.required) do
        if not s.done[t] then return end
    end
    local onReady = s.onReady
    clearPlayer(player)
    if onReady and isElement(player) then
        onReady(player)
    end
end

-- Starts the loading gate for a player. `types` is a list of provider ids to
-- wait for (may be empty). `onReady(player)` runs once they have all reported.
function beginLoading(player, types, onReady)
    clearPlayer(player)

    local required, done = {}, {}
    for _, t in ipairs(types) do
        required[t] = true
    end
    if earlyDone[player] then
        for t in pairs(earlyDone[player]) do
            done[t] = true
        end
    end

    state[player] = {
        required = required,
        done     = done,
        onReady  = onReady,
        timer    = setTimer(function()
            if not state[player] then return end
            outputServerLog(("[v_accounts] loading gate timed out for %s, spawning anyway")
                :format(isElement(player) and getPlayerName(player) or "?"))
            for t in pairs(state[player].required) do
                state[player].done[t] = true
            end
            tryFinish(player)
        end, LOAD_TIMEOUT, 1),
    }

    tryFinish(player)
end

-- Exported. A data provider calls this when it has finished preparing `type`
-- for the player. Tolerates being called before beginLoading().
function loadingComplete(player, loadType)
    if not isElement(player) then return end
    loadType = tostring(loadType)

    local s = state[player]
    if not s then
        earlyDone[player] = earlyDone[player] or {}
        earlyDone[player][loadType] = true
        return
    end

    s.done[loadType] = true
    tryFinish(player)
end

addEventHandler("onPlayerQuit", root, function()
    clearPlayer(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(state) do
        clearPlayer(player)
    end
end)
