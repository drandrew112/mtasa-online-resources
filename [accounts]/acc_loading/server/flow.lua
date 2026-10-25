-- acc_loading - from Join game to onPlayerLoaded.
--
--   beginLoading(player, mode)
--     loading screen on, onPlayerLoadingStarted, gate (gate.lua)
--     normal: acc_savesys:spawnFromSave -> v_mapcam:preSpawn -> client world check
--             -> loading screen off -> v_mapcam:playSpawn -> v_mapcam:onFinish
--     fresh:  acc_savesys:spawnFromSave(fresh) -> loading screen off right away
--             (new account: v_introduce takes over on onPlayerLoaded, no mapcam)
--   -> "loaded" = true, onPlayerLoaded (accountName), client onClientPlayerLoaded

addEvent("v_mapcam:onFinish")
addEvent("acc_loading:clientWorldLoaded", true)

local loading = {}   -- [player] = { mode, stage = "gate" | "world" | "spawn", timer }

-- the client reports the world well before this (its own check gives up after 20 s)
local WORLD_TIMEOUT = 30000

local afterWorld

local function killStageTimer(l)
    if l and isTimer(l.timer) then killTimer(l.timer) end
end

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function screen(player, show, info)
    triggerClientEvent(player, "acc_loading:screen", player, show, info)
end

local function done(player)
    killStageTimer(loading[player])
    loading[player] = nil
    if not isElement(player) then return end
    setElementData(player, "loaded", true)
    local accName = getElementData(player, "accName")
    triggerEvent("onPlayerLoaded", player, accName)
    triggerClientEvent(player, "acc_loading:playerLoaded", player, accName)
end

local function afterGate(player)
    local l = loading[player]
    if not l or not isElement(player) then return end

    if l.mode == "fresh" then
        exports.acc_savesys:spawnFromSave(player, "fresh")
        setElementData(player, "loaded", true)
        exports.acc_savesys:savePlayer(player)
        screen(player, false)
        return done(player)
    end

    local x, y, z = exports.acc_savesys:spawnFromSave(player, "normal")
    if not resourceRunning("v_mapcam") then
        screen(player, false)
        return done(player)
    end
    if x then exports.v_mapcam:preSpawn(player, x, y, z) end
    l.stage = "world"
    triggerClientEvent(player, "acc_loading:startWorldCheck", player)
    l.timer = setTimer(function()
        if loading[player] ~= l or l.stage ~= "world" then return end
        outputServerLog(("[acc_loading] no world report from %s, spawning anyway")
            :format(isElement(player) and getPlayerName(player) or "?"))
        afterWorld(player)
    end, WORLD_TIMEOUT, 1)
end

-- the world around the spawn point is streamed in (or the wait timed out):
-- loading screen off, spawn camera, then done
afterWorld = function(player)
    local l = loading[player]
    if not l or l.stage ~= "world" or not isElement(player) then return end
    killStageTimer(l)
    l.stage = "spawn"
    screen(player, false)

    -- one-shot: the handler must not stay on the player, else every later
    -- v_mapcam teleport would fire onPlayerLoaded again
    local function onFinish()
        removeEventHandler("v_mapcam:onFinish", player, onFinish)
        if loading[player] == l then done(player) end
    end
    addEventHandler("v_mapcam:onFinish", player, onFinish)
    if not resourceRunning("v_mapcam") or not exports.v_mapcam:playSpawn(player) then
        removeEventHandler("v_mapcam:onFinish", player, onFinish)
        return done(player)
    end

    -- v_mapcam ends some sessions without onFinish (player wasted, cancel(),
    -- another resource's teleport, v_mapcam stopped): finish the loading then too
    l.timer = setTimer(function()
        if loading[player] ~= l then return end
        local active = resourceRunning("v_mapcam") and exports.v_mapcam:isActive(player)
        if not active then
            if isElement(player) then removeEventHandler("v_mapcam:onFinish", player, onFinish) end
            done(player)
        end
    end, 1000, 0)
end

addEventHandler("acc_loading:clientWorldLoaded", root, function()
    afterWorld(client)
end)

-- Exported. Called by acc_menu (Join game) or acc_savesys (new account).
function beginLoading(player, mode)
    if not isElement(player) or getElementData(player, "isLogged") ~= true then return false end
    if getElementData(player, "loaded") == true or loading[player] then return false end
    mode = mode == "fresh" and "fresh" or "normal"
    loading[player] = { mode = mode, stage = "gate" }
    screen(player, true, { mode = mode })
    runGate(player, {}, afterGate)
    return true
end

function isPlayerLoading(player)
    return loading[player] ~= nil
end

addEventHandler("onPlayerQuit", root, function()
    killStageTimer(loading[source])
    loading[source] = nil
end)
