-- Editing sessions: entering / leaving the creator, permissions, locks, loading
-- and saving through v_jobmanager's community storage, test runs.

local jm = exports.v_jobmanager

-- player -> session
--   { slot, dimension, back = {...}, gameId, type, storedMarker, image, test }
local sessions = {}
local slots = {}        -- slot -> player
local locks = {}        -- gameId -> player (one editor per game, ever)

local function notify(player, title, text)
    triggerClientEvent(player, "jobcreator:notify", resourceRoot, title, text)
end

local function accountName(player)
    local name = exports.v_accounts:getName(player)
    return type(name) == "string" and name ~= "" and name or nil
end

function isCreatorAdmin(player)
    if getElementData(player, "isLogged") ~= true then return false end
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= CREATOR.ADMIN_LEVEL
end

-- official games (games/<id>.json) are admin-only
local function canEdit(player, entry)
    if not entry then return false end
    if entry.official then return isCreatorAdmin(player) end
    return entry.owner == accountName(player) or isCreatorAdmin(player)
end

-- community index entry, or an official game's entry (official = true)
local function findEntry(id)
    for _, entry in ipairs(jm:jobmanagerCommunityList() or {}) do
        if entry.id == id then return entry end
    end
    for _, entry in ipairs(jm:jobmanagerOfficialList() or {}) do
        if entry.id == id then return entry end
    end
end

--------------------------------------------------------------------------------
-- player state
--------------------------------------------------------------------------------

local function snapshot(player)
    local x, y, z = getElementPosition(player)
    local weapons = {}
    for slot = 0, 12 do
        local weapon, ammo = getPedWeapon(player, slot), getPedTotalAmmo(player, slot)
        if weapon and weapon > 0 and ammo > 0 then weapons[#weapons + 1] = { weapon, ammo } end
    end
    return {
        x = x, y = y, z = z, rot = select(3, getElementRotation(player)),
        dimension = getElementDimension(player), interior = getElementInterior(player),
        health = getElementHealth(player), armour = getPedArmor(player), weapons = weapons,
    }
end

local function restore(player, back)
    takeAllWeapons(player)
    removePedFromVehicle(player)
    setElementFrozen(player, false)
    setElementAlpha(player, 255)
    setElementCollisionsEnabled(player, true)
    if isPedDead(player) then
        spawnPlayer(player, back.x, back.y, back.z, back.rot, getElementModel(player), back.interior, back.dimension)
    else
        setElementInterior(player, back.interior)
        setElementDimension(player, back.dimension)
        setElementPosition(player, back.x, back.y, back.z)
    end
    setElementHealth(player, back.health > 0 and back.health or 100)
    setPedArmor(player, back.armour)
    for _, w in ipairs(back.weapons) do giveWeapon(player, w[1], w[2]) end
end

local function vehicleNames()
    local names = {}
    local vm = getResourceFromName("veh_manager")
    local useVm = vm and getResourceState(vm) == "running"
    for _, cat in ipairs(CATALOG.vehicles) do
        for _, model in ipairs(cat.items) do
            names[model] = (useVm and exports.veh_manager:getModelName(model)) or getVehicleNameFromModel(model) or tostring(model)
        end
    end
    return names
end

--------------------------------------------------------------------------------
-- tests
--------------------------------------------------------------------------------

local function stopTest(player, session, silent)
    local test = session.test
    if not test then return end
    session.test = nil
    if isElement(test.vehicle) then destroyElement(test.vehicle) end
    takeAllWeapons(player)
    setPedArmor(player, 0)
    if isPedDead(player) then
        spawnPlayer(player, test.x, test.y, test.z, 0, getElementModel(player), 0, session.dimension)
    else
        removePedFromVehicle(player)
        setElementPosition(player, test.x, test.y, test.z)
    end
    setElementHealth(player, 100)
    if not silent then triggerClientEvent(player, "jobcreator:testStopped", resourceRoot) end
end

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function unlock(player, session)
    if session.gameId and locks[session.gameId] == player then locks[session.gameId] = nil end
end

-- quiet: the player quit (nothing to restore); immediate: restore now (resource stop kills timers)
local function closeCreator(player, quiet, immediate)
    local session = sessions[player]
    if not session then return false end
    stopTest(player, session, true)
    unlock(player, session)
    slots[session.slot] = nil
    sessions[player] = nil
    setElementData(player, "jobCreator", false)
    if not quiet then
        -- the client stops its freecam first, otherwise it would move the player back
        triggerClientEvent(player, "jobcreator:closed", resourceRoot)
        if immediate then restore(player, session.back) return true end
        setTimer(function()
            if isElement(player) and not sessions[player] then restore(player, session.back) end
        end, 300, 1)
    end
    return true
end

local loadGame

local function openCreator(player, gameId)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if sessions[player] then return false end
    if getElementData(player, "isLogged") ~= true or not accountName(player) then return false end
    local jmRes = getResourceFromName("v_jobmanager")
    if not jmRes or getResourceState(jmRes) ~= "running" then
        notify(player, "Job Creator", "The job manager is not running.")
        return false
    end
    if jm:jobmanagerGetState(player) then
        notify(player, "Job Creator", "Leave your lobby or match first.")
        return false
    end
    if isPedDead(player) then return false end

    local slot = 1
    while slots[slot] do slot = slot + 1 end
    local session = {
        slot = slot, dimension = CREATOR.DIMENSION_BASE + slot, back = snapshot(player),
    }
    slots[slot] = player
    sessions[player] = session
    setElementData(player, "jobCreator", true)

    removePedFromVehicle(player)
    takeAllWeapons(player)
    setPedArmor(player, 0)
    setElementHealth(player, 100)
    setElementDimension(player, session.dimension)

    triggerClientEvent(player, "jobcreator:opened", resourceRoot, {
        admin = isCreatorAdmin(player), account = accountName(player), vehicleNames = vehicleNames(),
        dimension = session.dimension,
    })
    if gameId then loadGame(player, session, gameId) end
    return true
end

--------------------------------------------------------------------------------
-- games
--------------------------------------------------------------------------------

local function defaultGame(gameType)
    if gameType == "race" then
        return { name = "Untitled race", type = "race", description = "", minPlayers = 1, maxPlayers = 8, objects = {},
            race = { vehicles = { 411 }, spawnpoints = {}, checkpoints = {} } }
    end
    return { name = "Untitled deathmatch", type = "deathmatch", description = "", minPlayers = 2, maxPlayers = 8, objects = {},
        deathmatch = { weapon = 24, ammo = 120, armour = 100, spawnpoints = {} } }
end

local function sendGame(player, session, game, entry)
    triggerClientEvent(player, "jobcreator:loaded", resourceRoot, game, {
        id = session.gameId, published = entry and entry.published or false, pending = entry and entry.pending or false,
        owner = entry and entry.owner or accountName(player), official = entry and entry.official or false,
    })
    -- the saved thumbnail, for the editor's preview
    if session.gameId and entry and (entry.imageVersion or 0) > 0 then
        local bytes
        if entry.official then bytes = jm:jobmanagerOfficialImage(session.gameId) else bytes = jm:jobmanagerCommunityImage(session.gameId) end
        if bytes then triggerLatentClientEvent(player, "jobcreator:thumbnailData", 200000, false, resourceRoot, bytes) end
    end
end

function loadGame(player, session, id)
    local entry = findEntry(id)
    if not entry then notify(player, "Job Creator", "That game does not exist.") return false end
    if not canEdit(player, entry) then notify(player, "Job Creator", "You cannot edit this game.") return false end
    if locks[id] and locks[id] ~= player then
        notify(player, "Job Creator", getPlayerName(locks[id]) .. " is editing this game right now.")
        return false
    end
    local game
    if entry.official then game = jm:jobmanagerOfficialLoad(id) else game = jm:jobmanagerCommunityLoad(id) end
    if type(game) ~= "table" then notify(player, "Job Creator", "This game could not be loaded.") return false end
    unlock(player, session)
    locks[id] = player
    session.gameId, session.type, session.image, session.official = id, game.type, nil, entry.official == true
    session.storedMarker = game.marker
    sendGame(player, session, game, entry)
    return true
end

addEvent("jobcreator:new", true)
addEventHandler("jobcreator:new", resourceRoot, function(gameType)
    local session = sessions[client]
    if not session or (gameType ~= "race" and gameType ~= "deathmatch") then return end
    unlock(client, session)
    session.gameId, session.type, session.image, session.storedMarker, session.official = nil, gameType, nil, nil, nil
    sendGame(client, session, defaultGame(gameType), nil)
end)

-- back to the start menu: the game is free for others again
addEvent("jobcreator:closeGame", true)
addEventHandler("jobcreator:closeGame", resourceRoot, function()
    local session = sessions[client]
    if not session then return end
    stopTest(client, session, true)
    unlock(client, session)
    session.gameId, session.type, session.image, session.storedMarker, session.official = nil, nil, nil, nil, nil
end)

addEvent("jobcreator:load", true)
addEventHandler("jobcreator:load", resourceRoot, function(id)
    local session = sessions[client]
    if session and type(id) == "string" then loadGame(client, session, id) end
end)

-- "mine" = own games, "all" = every community game (admin), "official" = games/*.json (admin)
addEvent("jobcreator:requestList", true)
addEventHandler("jobcreator:requestList", resourceRoot, function(scope)
    if not sessions[client] then return end
    if scope == "official" then
        if not isCreatorAdmin(client) then return end
        triggerClientEvent(client, "jobcreator:list", resourceRoot, scope, jm:jobmanagerOfficialList() or {})
        return
    end
    local all = scope == "all" and isCreatorAdmin(client)
    local list = jm:jobmanagerCommunityList(not all and accountName(client) or nil) or {}
    table.sort(list, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
    triggerClientEvent(client, "jobcreator:list", resourceRoot, scope, list)
end)

addEvent("jobcreator:save", true)
addEventHandler("jobcreator:save", resourceRoot, function(doc, publish)
    local player, session = client, sessions[client]
    if not session or not session.type then return end
    local admin = isCreatorAdmin(player)
    local owner = accountName(player)

    if not session.gameId and not admin then
        local count = #(jm:jobmanagerCommunityList(owner) or {})
        if count >= CREATOR.MAX_GAMES_PER_PLAYER then
            notify(player, "Job Creator", "You already have " .. count .. " games. Delete one to make room.")
            return
        end
    end
    local entry = session.gameId and findEntry(session.gameId)
    if session.gameId and (not entry or not canEdit(player, entry)) then
        notify(player, "Job Creator", "You cannot save this game.")
        return
    end

    if session.official then
        if not admin then return notify(player, "Job Creator", "Only admins can edit official games.") end
        local game = sanitizeGame(doc, session.type, "keep", true)
        if not game then return notify(player, "Job Creator", "The game data is invalid.") end
        game.id = session.gameId
        local id, err = jm:jobmanagerOfficialSave(game, session.image)
        if not id then return notify(player, "Job Creator", "Saving failed: " .. tostring(err)) end
        session.image = nil
        local message, published = "Draft saved. The live version changes on Publish.", false
        if publish then
            local ok
            ok, err = jm:jobmanagerOfficialPublish(id)
            published = ok
            message = ok and "Saved and published." or ("Saved, but not published: " .. tostring(err))
        end
        triggerClientEvent(player, "jobcreator:saved", resourceRoot, {
            id = id, published = true, pending = not published, owner = entry.owner, official = true,
        })
        return notify(player, "Job Creator", message)
    end

    local game = sanitizeGame(doc, session.type, admin and "keep" or session.storedMarker)
    if not game then notify(player, "Job Creator", "The game data is invalid.") return end
    game.id = session.gameId
    local id, saved = jm:jobmanagerCommunitySave(game, entry and entry.owner or owner, session.image)
    if not id then notify(player, "Job Creator", "Saving failed: " .. tostring(saved)) return end
    if not session.gameId then locks[id] = player end
    session.gameId, session.image, session.storedMarker = id, nil, game.marker

    local message = "Saved."
    if publish and admin then
        local ok, err = jm:jobmanagerCommunityPublish(id)
        message = ok and "Saved and published." or ("Saved, but not published: " .. tostring(err))
        saved = findEntry(id) or saved
    end
    triggerClientEvent(player, "jobcreator:saved", resourceRoot, {
        id = id, published = saved.published, pending = saved.pending, owner = saved.owner,
    })
    notify(player, "Job Creator", message)
end)

-- Validation report for "Check problems" (the same check Publish runs).
addEvent("jobcreator:validate", true)
addEventHandler("jobcreator:validate", resourceRoot, function(doc)
    local session = sessions[client]
    if not session or not session.type then return end
    local game = sanitizeGame(doc, session.type, "keep", session.official)
    local ok, err = false, "invalid game data"
    if game then ok, err = jm:jobmanagerValidateGame(game) end
    triggerClientEvent(client, "jobcreator:validated", resourceRoot, ok, err)
end)

local function manage(player, id, action)
    local entry = findEntry(id)
    if not entry then return notify(player, "Job Creator", "That game does not exist.") end
    local admin = isCreatorAdmin(player)
    if entry.official then
        if not admin or action ~= "publish" then
            return notify(player, "Job Creator", "Official games can only be edited and published by admins.")
        end
        local ok, err = jm:jobmanagerOfficialPublish(id)
        return notify(player, "Job Creator", ok and (entry.name .. " is published.") or ("Failed: " .. tostring(err)))
    end
    if action == "publish" or action == "unpublish" then
        if not admin then return notify(player, "Job Creator", "Only admins can publish games.") end
        local ok, err
        if action == "publish" then ok, err = jm:jobmanagerCommunityPublish(id) else ok, err = jm:jobmanagerCommunityUnpublish(id) end
        notify(player, "Job Creator", ok and (entry.name .. (action == "publish" and " is published." or " is unpublished.")) or ("Failed: " .. tostring(err)))
    elseif action == "delete" then
        if not canEdit(player, entry) or (entry.published and not admin) then
            return notify(player, "Job Creator", "You cannot delete this game.")
        end
        if locks[id] and locks[id] ~= player then return notify(player, "Job Creator", "Someone is editing this game.") end
        local session = sessions[player]
        if session and session.gameId == id then return notify(player, "Job Creator", "Close the game before deleting it.") end
        jm:jobmanagerCommunityDelete(id)
        notify(player, "Job Creator", entry.name .. " was deleted.")
    end
end

addEvent("jobcreator:manage", true)
addEventHandler("jobcreator:manage", resourceRoot, function(id, action)
    if not sessions[client] or type(id) ~= "string" then return end
    manage(client, id, action)
    triggerClientEvent(client, "jobcreator:managed", resourceRoot)
end)

addEvent("jobcreator:thumbnail", true)
addEventHandler("jobcreator:thumbnail", resourceRoot, function(bytes)
    local session = sessions[client]
    if not session then return end
    if bytes == false then
        session.image = false
    elseif type(bytes) == "string" and #bytes < 400 * 1024 and bytes:sub(1, 2) == "\255\216" then
        session.image = bytes
    end
end)

--------------------------------------------------------------------------------
-- test runs (the vehicle / weapons have to be server-side)
--------------------------------------------------------------------------------

addEvent("jobcreator:testStart", true)
addEventHandler("jobcreator:testStart", resourceRoot, function(data)
    local player, session = client, sessions[client]
    if not session or session.test or type(data) ~= "table" then return end
    local x, y, z, rot = tonumber(data.x), tonumber(data.y), tonumber(data.z), tonumber(data.rot) or 0
    if not (x and y and z) then return end
    local px, py, pz = getElementPosition(player)
    session.test = { x = px, y = py, z = pz }
    setElementFrozen(player, false)
    setElementAlpha(player, 255)
    setElementCollisionsEnabled(player, true)
    if session.type == "race" then
        local model = tonumber(data.model)
        if not CATALOG.vehicleAllowed[model] then session.test = nil return end
        local vehicle = createVehicle(model, x, y, z, 0, 0, rot)
        if not vehicle then session.test = nil return end
        setElementDimension(vehicle, session.dimension)
        session.test.vehicle = vehicle
        setElementPosition(player, x, y, z + 1)
        warpPedIntoVehicle(player, vehicle)
    else
        local weapon = tonumber(data.weapon)
        if not CATALOG.weaponAllowed[weapon] then session.test = nil return end
        setElementPosition(player, x, y, z)
        setElementRotation(player, 0, 0, rot)
        giveWeapon(player, weapon, math.min(tonumber(data.ammo) or 100, 9999), true)
        setPedArmor(player, math.min(tonumber(data.armour) or 0, 100))
    end
    triggerClientEvent(player, "jobcreator:testStarted", resourceRoot)
end)

addEvent("jobcreator:testStop", true)
addEventHandler("jobcreator:testStop", resourceRoot, function()
    local session = sessions[client]
    if not session then return end
    if session.test then
        stopTest(client, session)
    else
        triggerClientEvent(client, "jobcreator:testStopped", resourceRoot)
    end
end)

addEventHandler("onPlayerWasted", root, function()
    local session = sessions[source]
    if not session then return end
    local player = source
    setTimer(function()
        if sessions[player] ~= session then return end
        if session.test then
            stopTest(player, session)
        elseif isPedDead(player) then
            local x, y, z = getElementPosition(player)
            if z < -50 then x, y, z = session.back.x, session.back.y, session.back.z end
            spawnPlayer(player, x, y, z + 1, 0, getElementModel(player), 0, session.dimension)
        end
    end, 2000, 1)
end)

-- Leaving the vehicle during a race test ends the test (no walking around with it).
addEventHandler("onVehicleExit", root, function(player)
    local session = sessions[player]
    if session and session.test and session.test.vehicle == source then stopTest(player, session) end
end)

--------------------------------------------------------------------------------
-- entry points
--------------------------------------------------------------------------------

addEvent("jobcreator:open", true)
addEventHandler("jobcreator:open", resourceRoot, function(gameId)
    openCreator(client, type(gameId) == "string" and gameId or nil)
end)

addEvent("jobcreator:close", true)
addEventHandler("jobcreator:close", resourceRoot, function()
    closeCreator(client)
end)

addCommandHandler("creator", function(player, _, gameId)
    if sessions[player] then closeCreator(player) else openCreator(player, gameId) end
end)

addEventHandler("onPlayerQuit", root, function()
    closeCreator(source, true)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do closeCreator(player, false, true) end
end)

-- exports
function jobcreatorOpen(player, gameId) return openCreator(player, gameId) end
function jobcreatorClose(player) return closeCreator(player) end
function jobcreatorIsActive(player) return sessions[player] ~= nil end
