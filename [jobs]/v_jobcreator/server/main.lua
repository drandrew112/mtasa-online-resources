if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Editing sessions: entering / leaving the creator, permissions, locks, loading
-- and saving through v_jobmanager's MySQL storage (core/storage.lua), test runs.

-- v_jobmanager is a soft dependency: it may start after this resource, and it can restart on its own,
-- so every call resolves the export at use time (a cached exports.v_jobmanager would throw at load).
local jm = setmetatable({}, { __index = function(_, name)
    return function(_, ...) return exports.v_jobmanager[name](exports.v_jobmanager, ...) end
end })

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

local function adminLevel(player)
    if getElementData(player, "isLogged") ~= true then return 0 end
    return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
end

function isCreatorAdmin(player)
    return adminLevel(player) >= CREATOR.ADMIN_LEVEL
end

-- publishing official games (jobs_official)
function isOfficialAdmin(player)
    return adminLevel(player) >= CREATOR.OFFICIAL_LEVEL
end

-- official games are admin-only
local function canEdit(player, entry)
    if not entry then return false end
    if entry.official then return isCreatorAdmin(player) end
    return entry.owner == accountName(player) or isCreatorAdmin(player)
end

-- { id, name, type, owner, official, published, pending, imageVersion, updated } or nil
local function findEntry(id)
    return jm:jobmanagerGameEntry(id) or nil
end

--------------------------------------------------------------------------------
-- player state
--------------------------------------------------------------------------------

-- [weapon]/wp_manager (soft dependency): the creator uses a temporary loadout, so the player's own
-- weapons are neither taken nor snapshotted; without it the GTA weapons are taken and given back.
local function weaponManagerRunning()
    local res = getResourceFromName("wp_manager")
    return res and getResourceState(res) == "running"
end

-- weapon = nil: no weapon
local function setLoadout(player, weapon, ammo)
    if weaponManagerRunning() then
        exports.wp_manager:setPlayerTempLoadout(player, weapon and { { id = weapon, ammo = ammo } } or {}, weapon)
    else
        takeAllWeapons(player)
        if weapon then giveWeapon(player, weapon, ammo, true) end
    end
end

local function snapshot(player)
    local x, y, z = getElementPosition(player)
    local weapons = {}
    for slot = 0, weaponManagerRunning() and -1 or 12 do
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
    if weaponManagerRunning() then exports.wp_manager:clearPlayerTempLoadout(player) else takeAllWeapons(player) end
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
    if test.mission then
        -- v_jobmanager ends the test match and puts the player back (onJobMissionFinished below)
        if not jm:jobmanagerStopTest(player) then
            session.test = nil
            setLoadout(player)
            if not silent then triggerClientEvent(player, "jobcreator:testStopped", resourceRoot) end
        end
        return
    end
    session.test = nil
    if isElement(test.vehicle) then destroyElement(test.vehicle) end
    setLoadout(player)
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
    -- quit: "save.position" stays for v_accounts' quit save (the place before the creator)
    if not quiet then removeElementData(player, "save.position") end
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
        notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.job_manager_is_not_running"))
        return false
    end
    if not jm:jobmanagerStorageReady() then
        notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.game_storage_is_not_ready"))
        return false
    end
    if jm:jobmanagerGetState(player) then
        notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.leave_your_lobby_or_match_first"))
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
    -- the account keeps the place before the creator, never the editor dimension (v_accounts savesys)
    local b = session.back
    setElementData(player, "save.position", { b.x, b.y, b.z, b.interior, b.dimension }, false)

    removePedFromVehicle(player)
    setLoadout(player)
    setPedArmor(player, 0)
    setElementHealth(player, 100)
    setElementDimension(player, session.dimension)

    triggerClientEvent(player, "jobcreator:opened", resourceRoot, {
        admin = isCreatorAdmin(player), officialAdmin = isOfficialAdmin(player),
        account = accountName(player), vehicleNames = vehicleNames(),
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
        return { name = L.msg("v_jobcreator.main.untitled_race"), type = "race", description = "", minPlayers = 1, maxPlayers = 8, objects = {},
            race = { vehicles = { 411 }, spawnpoints = {}, checkpoints = {} } }
    end
    if gameType == "mission" then
        return { name = L.msg("v_jobcreator.main.untitled_mission"), type = "mission", description = "", minPlayers = 1, maxPlayers = 4, objects = {},
            mission = { spawnpoints = {}, teamLives = 3, armour = 50, loadout = { { id = 24, ammo = 200 } },
                zones = {}, peds = {}, vehicles = {}, items = {}, points = {},
                stages = { { id = "s1", title = "Stage 1", objectives = {} } } } }
    end
    return { name = L.msg("v_jobcreator.main.untitled_deathmatch"), type = "deathmatch", description = "", minPlayers = 2, maxPlayers = 8, objects = {},
        deathmatch = { weapon = 24, ammo = 120, armour = 100, spawnpoints = {} } }
end

local GAME_TYPES = { race = true, deathmatch = true, mission = true }

local function sendGame(player, session, game, entry)
    triggerClientEvent(player, "jobcreator:loaded", resourceRoot, game, {
        id = session.gameId, published = entry and entry.published or false, pending = entry and entry.pending or false,
        owner = entry and entry.owner or accountName(player), official = entry and entry.official or false,
    })
    -- the saved thumbnail, for the editor's preview (read from MySQL, arrives a bit later)
    if session.gameId and entry and (entry.imageVersion or 0) > 0 then
        jm:jobmanagerSendImage(player, session.gameId, "jobcreator:thumbnailData")
    end
end

function loadGame(player, session, id)
    local entry = findEntry(id)
    if not entry then notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.that_game_does_not_exist")) return false end
    if not canEdit(player, entry) then notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.you_cannot_edit_this_game")) return false end
    if locks[id] and locks[id] ~= player then
        notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.is_editing_this_game_right_now", { player = getPlayerName(locks[id]) }))
        return false
    end
    local game = jm:jobmanagerGameLoad(id)
    if type(game) ~= "table" then notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.this_game_could_not_be_loaded")) return false end
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
    if not session or not GAME_TYPES[gameType] then return end
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

-- "mine" = own games, "all" = every community game (admin), "official" = official games + their drafts (admin)
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

-- publish: false = save only, true = save + publish into the game's own table,
-- "official" = save + publish as an official game (CREATOR.OFFICIAL_LEVEL)
addEvent("jobcreator:save", true)
addEventHandler("jobcreator:save", resourceRoot, function(doc, publish)
    local player, session = client, sessions[client]
    if not session or not session.type then return end
    local title = L.msg("v_jobcreator.core.job_creator")
    local admin = isCreatorAdmin(player)
    local owner = accountName(player)
    if publish ~= "official" then publish = publish == true end

    if not session.gameId and not admin then
        local count = #(jm:jobmanagerCommunityList(owner) or {})
        if count >= CREATOR.MAX_GAMES_PER_PLAYER then
            notify(player, title, L.msg("v_jobcreator.main.you_already_have_games_delete_one", { count = count }))
            return
        end
    end
    local entry = session.gameId and findEntry(session.gameId)
    if session.gameId and (not entry or not canEdit(player, entry)) then
        notify(player, title, L.msg("v_jobcreator.main.you_cannot_save_this_game"))
        return
    end
    if session.official and not admin then
        return notify(player, title, L.msg("v_jobcreator.main.only_admins_can_edit_official_games"))
    end
    -- official games are published by OFFICIAL_LEVEL only (so is a game made official);
    -- below that the game is still saved, just not published
    local officialPublish = publish == "official" or (publish and session.official)
    if officialPublish and not isOfficialAdmin(player) then
        notify(player, title, L.msg("v_jobcreator.main.only_level_can_publish_official_games", { level = CREATOR.OFFICIAL_LEVEL }))
        publish = false
    elseif publish and not admin then
        publish = false
    end

    local game = sanitizeGame(doc, session.type, admin and "keep" or session.storedMarker, session.official, isOfficialAdmin(player))
    if not game then return notify(player, title, L.msg("v_jobcreator.main.game_data_is_invalid")) end
    -- scriptOnly missions are official games without a world marker; publishing makes them official
    if game.scriptOnly then
        game.marker = nil
        if publish then publish = "official" end
    elseif session.official and entry and entry.scriptOnly and not isOfficialAdmin(player) then
        -- below OFFICIAL_LEVEL the flag cannot be cleared either
        game.scriptOnly = true
    end
    game.id = session.gameId
    local id, saved = jm:jobmanagerGameSave(game, entry and entry.owner or owner, session.image, game.scriptOnly and "official" or nil)
    if not id then return notify(player, title, L.msg("v_jobcreator.main.saving_failed", { err = tostring(saved) })) end
    if not session.gameId then locks[id] = player end
    session.gameId, session.image, session.storedMarker = id, nil, game.marker

    local message = session.official and L.msg("v_jobcreator.main.draft_saved_live_version_changes_on") or L.msg("v_jobcreator.main.saved")
    if publish then
        local ok, err = jm:jobmanagerGamePublish(id, publish == "official" and "official" or nil, owner)
        message = ok and L.msg("v_jobcreator.main.saved_and_published") or (L.msg("v_jobcreator.main.saved_but_not_published", { err = tostring(err) }))
        if ok and publish == "official" then session.official = true end
    end
    saved = findEntry(id) or saved
    triggerClientEvent(player, "jobcreator:saved", resourceRoot, {
        id = id, published = saved.published, pending = saved.pending, owner = saved.owner, official = saved.official,
    })
    notify(player, title, message)
end)

-- Validation report for "Check problems" (the same check Publish runs).
addEvent("jobcreator:validate", true)
addEventHandler("jobcreator:validate", resourceRoot, function(doc)
    local session = sessions[client]
    if not session or not session.type then return end
    local game = sanitizeGame(doc, session.type, "keep", session.official, isOfficialAdmin(client))
    local ok, err = false, L.msg("v_jobcreator.main.invalid_game_data")
    if game then ok, err = jm:jobmanagerValidateGame(game) end
    triggerClientEvent(client, "jobcreator:validated", resourceRoot, ok, err)
end)

-- action: publish | unpublish | delete | official (publish as an official game)
local function manage(player, id, action)
    local title = L.msg("v_jobcreator.core.job_creator")
    local entry = findEntry(id)
    if not entry then return notify(player, title, L.msg("v_jobcreator.main.that_game_does_not_exist")) end
    local admin, officialAdmin = isCreatorAdmin(player), isOfficialAdmin(player)
    local function done(ok, err, text)
        notify(player, title, ok and text or (L.msg("v_jobcreator.main.failed", { err = tostring(err) })))
    end

    if action == "publish" or action == "unpublish" or action == "official" then
        if (entry.official or action == "official") and not officialAdmin then
            return notify(player, title, L.msg("v_jobcreator.main.only_level_can_publish_official_games", { level = CREATOR.OFFICIAL_LEVEL }))
        end
        if not admin then return notify(player, title, L.msg("v_jobcreator.main.only_admins_can_publish_games")) end
        if action == "unpublish" then
            local ok, err = jm:jobmanagerGameUnpublish(id)
            return done(ok, err, entry.name .. L.msg("v_jobcreator.main.is_unpublished"))
        end
        local ok, err = jm:jobmanagerGamePublish(id, action == "official" and "official" or nil, accountName(player))
        local session = sessions[player]
        if ok and action == "official" and session and session.gameId == id then session.official = true end
        return done(ok, err, action == "official" and L.msg("v_jobcreator.main.is_now_an_official_game", { name = entry.name })
            or (entry.name .. L.msg("v_jobcreator.main.is_published_2")))
    elseif action == "delete" then
        if entry.official then
            if not officialAdmin or entry.published then
                return notify(player, title, L.msg("v_jobcreator.main.official_games_can_only_be_deleted", { level = CREATOR.OFFICIAL_LEVEL }))
            end
        elseif not canEdit(player, entry) or (entry.published and not admin) then
            return notify(player, title, L.msg("v_jobcreator.main.you_cannot_delete_this_game"))
        end
        if locks[id] and locks[id] ~= player then return notify(player, title, L.msg("v_jobcreator.main.someone_is_editing_this_game")) end
        local session = sessions[player]
        if session and session.gameId == id then return notify(player, title, L.msg("v_jobcreator.main.close_game_before_deleting_it")) end
        local ok, err = jm:jobmanagerGameDelete(id)
        done(ok, err, L.msg("v_jobcreator.main.was_deleted", { name = entry.name }))
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
    if session.type == "mission" then
        -- a real mission match, alone in the editor dimension, without rewards (v_jobmanager)
        local game = sanitizeGame(data.doc, "mission", nil, session.official, isOfficialAdmin(player))
        if not game then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.game_data_is_invalid")) end
        game.objects = {}       -- the editor already shows them (client-side objects)
        game.createdBy = accountName(player)
        game.minPlayers, game.maxPlayers = 1, 1
        removePedFromVehicle(player)
        setElementFrozen(player, false)
        setElementAlpha(player, 255)
        setElementCollisionsEnabled(player, true)
        session.test = { mission = true }
        local matchId, err = jm:jobmanagerTestMission(player, game, type(data.stage) == "string" and data.stage or nil)
        if not matchId then
            session.test = nil
            triggerClientEvent(player, "jobcreator:testStopped", resourceRoot)
            return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.test_failed", { err = tostring(err) }))
        end
        session.test.matchId = matchId
        triggerClientEvent(player, "jobcreator:testStarted", resourceRoot)
        return
    end
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
        setLoadout(player, weapon, math.min(tonumber(data.ammo) or 100, 9999))
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

-- the end of a mission test (F6, passed, failed): v_jobmanager has put the player back already
addEvent("onJobMissionFinished")
addEventHandler("onJobMissionFinished", root, function(matchId, missionId, result, info, tag)
    if tag ~= "__creator_test" or type(info) ~= "table" then return end
    for _, player in ipairs(info.players or {}) do
        local session = sessions[player]
        if session and session.test and session.test.mission and session.test.matchId == matchId then
            session.test = nil
            setLoadout(player)
            setPedArmor(player, 0)
            setElementHealth(player, 100)
            triggerClientEvent(player, "jobcreator:testStopped", resourceRoot, result)
        end
    end
end)

addEventHandler("onPlayerWasted", root, function()
    local session = sessions[source]
    if not session then return end
    -- mission tests: deaths and Team lives are v_jobmanager's
    if session.test and session.test.mission then return end
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
