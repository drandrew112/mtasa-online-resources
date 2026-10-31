-- v_accounts: the players' basic data (modules.lua) between login and quit.
--
--   login (auth module onPlayerAccountLogin)
--     -> collectibles + preferences mirrored to element data, profile ready
--     -> new account: v_loading "fresh" right away (no account menu)
--        otherwise:   onPlayerDataReady -> v_mainmenu opens (or the loading, without v_mainmenu)
--   Join game -> v_loading -> spawnFromSave(player, mode)
--   autosave / quit / resource stop -> savePlayer (only once the player is loaded,
--   else the defaults would overwrite the account)

addEvent("onPlayerAccountLogin")
addEvent("onPlayerDataReady")

local function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function isLogged(player)
    return isElement(player) and getElementData(player, "isLogged") == true
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function getProfile(player)
    if not isLogged(player) then return false end
    local out = { account = getElementData(player, "accName") }
    for _, m in ipairs(MODULES) do
        if m.profile then m.profile(player, out) end
    end
    return out
end

-- v_loading: puts the player into the world from the saved state
function spawnFromSave(player, mode)
    if not isLogged(player) then return false end
    local ctx = { mode = mode == "fresh" and "fresh" or "normal" }
    for _, m in ipairs(MODULES) do
        if m.apply then m.apply(player, ctx) end
    end
    return ctx.x, ctx.y, ctx.z, ctx.rot
end

function savePlayer(player)
    if not isLogged(player) then return false end
    if getElementData(player, "loaded") ~= true then return false end
    local d = {}
    for _, m in ipairs(MODULES) do
        if m.save then m.save(player, d) end
    end
    exports.v_mysql:setAccData(player, d)
    return true
end

function getPreference(player, id)
    local def = PREFERENCES[id]
    if not def or not isElement(player) then return false end
    local v = getElementData(player, "pref." .. id)
    if def.values[v] then return v end
    return def.default
end

function setPreference(player, id, value)
    local def = PREFERENCES[id]
    if not def or not def.values[value] or not isLogged(player) then return false end
    setElementData(player, "pref." .. id, value)
    exports.v_mysql:setAccData(player, "pref." .. id, value)
    if id == "walkStyle" then applyWalkStyle(player) end
    return true
end

-- the walkStyle preference on the ped; medsys effects keeps a forced (injured) style on top of it
-- and restores this one afterwards (onPlayerWalkStyleApplied)
addEvent("onPlayerWalkStyleApplied")
function applyWalkStyle(player)
    if not isElement(player) or isPedDead(player) then return false end
    local style = WALK_STYLES[getPreference(player, "walkStyle")] or 0
    setPedWalkingStyle(player, style)
    triggerEvent("onPlayerWalkStyleApplied", player, style)
    return true
end

function getCollectibles(player)
    if not isLogged(player) then return false end
    local counts = COLLECTED[player] or loadCollectibles(player)
    local out = {}
    for i, def in ipairs(COLLECTIBLES) do
        out[i] = { id = def.id, label = def.label, count = counts[def.id] or 0, total = def.total or false }
    end
    return out
end

-- raises a collectible counter (a stunt jump done, a UFO part found); saved with the next save
function addCollectible(player, id, amount)
    if not isLogged(player) then return false end
    amount = math.floor(tonumber(amount) or 1)
    if amount <= 0 then return false end
    local counts = COLLECTED[player] or loadCollectibles(player)
    for _, def in ipairs(COLLECTIBLES) do
        if def.id == id then
            local n = (counts[id] or 0) + amount
            if def.total then n = math.min(n, def.total) end
            counts[id] = n
            setElementData(player, def.data, n)
            return n
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- login -> menu / loading
--------------------------------------------------------------------------------

addEventHandler("onPlayerAccountLogin", root, function(accountName, isNew)
    local player = source
    loadCollectibles(player)
    loadPreferences(player)

    if isNew then
        -- brand-new account: no menu, no mapcam - the loading hands the player to v_introduce
        if resourceRunning("v_loading") then exports.v_loading:beginLoading(player, "fresh") end
        return
    end
    if resourceRunning("v_mainmenu") then
        triggerEvent("onPlayerDataReady", player, accountName)
    elseif resourceRunning("v_loading") then
        exports.v_loading:beginLoading(player, "normal")
    end
end)

--------------------------------------------------------------------------------
-- weapons / weapon skills
--------------------------------------------------------------------------------

-- wp_manager (re)started without a parked state (e.g. it was not running at login): load from the DB
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "wp_manager" then return end
    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, "loaded") == true and not exports.wp_manager:isPlayerWeaponsLoaded(player) then
            loadWeapons(player)
        end
    end
end)

-- weapon skill stats are always maxed on spawn; the walking style of the preference
local WEAPON_STAT_IDS = { 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79 }
addEventHandler("onPlayerSpawn", root, function()
    for _, statID in ipairs(WEAPON_STAT_IDS) do
        setPedStat(source, statID, 1000)
    end
    if isLogged(source) then applyWalkStyle(source) end
end)

--------------------------------------------------------------------------------
-- saving
--------------------------------------------------------------------------------

setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do savePlayer(player) end
end, SAVE.INTERVAL, 0)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if getElementData(player, "loaded") == true then
            local veh = getPedOccupiedVehicle(player)
            if veh then
                removePedFromVehicle(player)
                setElementVelocity(veh, 0, 0, 0)
                local x, y, z = getElementPosition(player)
                setElementPosition(player, x, y, z + 2)
            end
            savePlayer(player)
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    savePlayer(source)
    COLLECTED[source] = nil
end)

-- v_accounts restarted with players online: their collectible counters come back from the DB
addEventHandler("onResourceStart", resourceRoot, function()
    for _, player in ipairs(getElementsByType("player")) do
        if isLogged(player) then
            loadCollectibles(player)
            loadPreferences(player)
            if getElementData(player, "loaded") == true then applyWalkStyle(player) end
        end
    end
end)

-- "save.position" / "pref.*" are set by server scripts only: a client cannot pick them
addEventHandler("onElementDataChange", root, function(key, old)
    if not client then return end
    if key == "save.position" or key:sub(1, 5) == "pref." then
        if old == nil then removeElementData(source, key) else setElementData(source, key, old, key ~= "save.position") end
    end
end)
