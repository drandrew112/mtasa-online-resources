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

local loading = {}   -- [player] = { mode, stage = "gate" | "world" | "spawn" }

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function screen(player, show, info)
    triggerClientEvent(player, "acc_loading:screen", player, show, info)
end

local function done(player)
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
end

-- the client has the world around the spawn point streamed in
addEventHandler("acc_loading:clientWorldLoaded", root, function()
    local player = client
    local l = loading[player]
    if not l or l.stage ~= "world" then return end
    l.stage = "spawn"
    screen(player, false)

    -- one-shot: the handler must not stay on the player, else every later
    -- v_mapcam teleport would fire onPlayerLoaded again
    local function onFinish()
        removeEventHandler("v_mapcam:onFinish", player, onFinish)
        if loading[player] == l then done(player) end
    end
    addEventHandler("v_mapcam:onFinish", player, onFinish)
    if not exports.v_mapcam:playSpawn(player) then
        removeEventHandler("v_mapcam:onFinish", player, onFinish)
        done(player)
    end
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
    loading[source] = nil
end)
