-- Account System - post-login loading gate
--
-- After a successful login or registration the player is shown a black
-- "Loading" screen instead of being spawned right away. External data
-- providers may register a step to wait for through the exported
-- loadingComplete(player, type); only once every expected step has arrived -
-- or a safety timeout elapses - is the player spawned and their saved state
-- restored. Today no provider registers a step, so the gate resolves at once,
-- but the plumbing stays for future ones.
--
-- When the player is finally ready, v_accounts fires the custom server event
--   onPlayerLoaded ( accountName )   -- source = player, arg 1 = name string
-- This is the point every other resource should hook to load a player's
-- account data. Each consumer must addEvent("onPlayerLoaded") on its own side.
--
-- Before any of that, the gate waits until every resource that was running
-- when the player logged in has started on the player's client
-- (onPlayerResourceStart), so onPlayerLoaded never fires while the client is
-- still downloading. There is no timeout on this wait on purpose; a resource
-- stopped meanwhile is dropped from the list.

addEvent("onPlayerLoaded")

local LOAD_TIMEOUT = 10000 -- ms; spawn anyway if a provider never answers

-- state[player] = { required = {type=true}, done = {type=true}, onReady = fn, timer = t }
local state = {}
-- earlyDone[player] = {type=true} for completions that arrived before beginLoading()
local earlyDone = {}

-- clientStarted[player] = {[resource]=true} resources started on that client
local clientStarted = {}
-- clientWait[player] = { pending = {[resource]=true}, onReady = fn, warnTimer = t }
local clientWait = {}

local CLIENT_WAIT_WARN = 60000 -- ms; log the still-missing resources after this

local function clearClientWait(player)
    local w = clientWait[player]
    if w and isTimer(w.warnTimer) then killTimer(w.warnTimer) end
    clientWait[player] = nil
end

local function tryFinishClientWait(player)
    local w = clientWait[player]
    if not w or next(w.pending) then return end
    clearClientWait(player)
    if isElement(player) then
        w.onReady(player)
    end
end

-- Runs onReady(player) once every currently running resource has started on
-- the player's client.
local function waitClientResources(player, onReady)
    clearClientWait(player)

    local started = clientStarted[player] or {}
    local pending = {}
    for _, res in ipairs(getResources()) do
        if getResourceState(res) == "running" and not started[res] then
            pending[res] = true
        end
    end

    clientWait[player] = {
        pending   = pending,
        onReady   = onReady,
        warnTimer = setTimer(function()
            local w = clientWait[player]
            if not w then return end
            local names = {}
            for res in pairs(w.pending) do
                names[#names + 1] = getResourceName(res)
            end
            outputServerLog(("[v_accounts] %s still waiting for client resources: %s")
                :format(isElement(player) and getPlayerName(player) or "?", table.concat(names, ", ")))
        end, CLIENT_WAIT_WARN, 0),
    }

    tryFinishClientWait(player)
end

addEventHandler("onPlayerResourceStart", root, function(res)
    clientStarted[source] = clientStarted[source] or {}
    clientStarted[source][res] = true

    local w = clientWait[source]
    if w then
        w.pending[res] = nil
        tryFinishClientWait(source)
    end
end)

addEventHandler("onResourceStop", root, function(res)
    for player, started in pairs(clientStarted) do
        started[res] = nil
    end
    for player, w in pairs(clientWait) do
        if w.pending[res] then
            w.pending[res] = nil
            tryFinishClientWait(player)
        end
    end
end)

-- v_accounts (re)started: players already on the server missed the earlier
-- onPlayerResourceStart events. Their client had everything except what has
-- not reported in yet, so assume every other running resource is started.
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        local started = {}
        for _, res in ipairs(getResources()) do
            if getResourceState(res) == "running" and res ~= resource then
                started[res] = true
            end
        end
        clientStarted[player] = started
    end
end)

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

local startProviderGate

-- Starts the loading gate for a player. First waits for the client to have
-- every resource started, then for the provider ids in `types` (may be empty).
-- `onReady(player)` runs once they have all reported.
function beginLoading(player, types, onReady)
    waitClientResources(player, function(p)
        startProviderGate(p, types, onReady)
    end)
end

startProviderGate = function(player, types, onReady)
    local early = earlyDone[player]
    clearPlayer(player)

    local required, done = {}, {}
    for _, t in ipairs(types) do
        required[t] = true
    end
    if early then
        for t in pairs(early) do
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
    clearClientWait(source)
    clientStarted[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(state) do
        clearPlayer(player)
    end
    for player in pairs(clientWait) do
        clearClientWait(player)
    end
end)
