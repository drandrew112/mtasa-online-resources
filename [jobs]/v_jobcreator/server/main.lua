if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Editing sessions: entering / leaving the creator, permissions, locks, loading
-- and saving through v_jobmanager's community storage, test runs.

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
    local name = exports.acc_auth:getName(player)
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

    removePedFromVehicle(player)
    setLoadout(player)
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
        return { name = L.msg("v_jobcreator.main.untitled_race"), type = "race", description = "", minPlayers = 1, maxPlayers = 8, objects = {},
            race = { vehicles = { 411 }, spawnpoints = {}, checkpoints = {} } }
    end
    return { name = L.msg("v_jobcreator.main.untitled_deathmatch"), type = "deathmatch", description = "", minPlayers = 2, maxPlayers = 8, objects = {},
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
    if not entry then notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.that_game_does_not_exist")) return false end
    if not canEdit(player, entry) then notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.you_cannot_edit_this_game")) return false end
    if locks[id] and locks[id] ~= player then
        notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.is_editing_this_game_right_now", { player = getPlayerName(locks[id]) }))
        return false
    end
    local game
    if entry.official then game = jm:jobmanagerOfficialLoad(id) else game = jm:jobmanagerCommunityLoad(id) end
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
            notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.you_already_have_games_delete_one", { count = count }))
            return
        end
    end
    local entry = session.gameId and findEntry(session.gameId)
    if session.gameId and (not entry or not canEdit(player, entry)) then
        notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.you_cannot_save_this_game"))
        return
    end

    if session.official then
        if not admin then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.only_admins_can_edit_official_games")) end
        local game = sanitizeGame(doc, session.type, "keep", true)
        if not game then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.game_data_is_invalid")) end
        game.id = session.gameId
        local id, err = jm:jobmanagerOfficialSave(game, session.image)
        if not id then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.saving_failed", { err = tostring(err) })) end
        session.image = nil
        local message, published = L.msg("v_jobcreator.main.draft_saved_live_version_changes_on"), false
        if publish then
            local ok
            ok, err = jm:jobmanagerOfficialPublish(id)
            published = ok
            message = ok and L.msg("v_jobcreator.main.saved_and_published") or (L.msg("v_jobcreator.main.saved_but_not_published", { err = tostring(err) }))
        end
        triggerClientEvent(player, "jobcreator:saved", resourceRoot, {
            id = id, published = true, pending = not published, owner = entry.owner, official = true,
        })
        return notify(player, L.msg("v_jobcreator.core.job_creator"), message)
    end

    local game = sanitizeGame(doc, session.type, admin and "keep" or session.storedMarker)
    if not game then notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.game_data_is_invalid")) return end
    game.id = session.gameId
    local id, saved = jm:jobmanagerCommunitySave(game, entry and entry.owner or owner, session.image)
    if not id then notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.saving_failed_2", { saved = tostring(saved) })) return end
    if not session.gameId then locks[id] = player end
    session.gameId, session.image, session.storedMarker = id, nil, game.marker

    local message = "Saved."
    if publish and admin then
        local ok, err = jm:jobmanagerCommunityPublish(id)
        message = ok and L.msg("v_jobcreator.main.saved_and_published") or (L.msg("v_jobcreator.main.saved_but_not_published", { err = tostring(err) }))
        saved = findEntry(id) or saved
    end
    triggerClientEvent(player, "jobcreator:saved", resourceRoot, {
        id = id, published = saved.published, pending = saved.pending, owner = saved.owner,
    })
    notify(player, L.msg("v_jobcreator.core.job_creator"), message)
end)

-- Validation report for "Check problems" (the same check Publish runs).
addEvent("jobcreator:validate", true)
addEventHandler("jobcreator:validate", resourceRoot, function(doc)
    local session = sessions[client]
    if not session or not session.type then return end
    local game = sanitizeGame(doc, session.type, "keep", session.official)
    local ok, err = false, L.msg("v_jobcreator.main.invalid_game_data")
    if game then ok, err = jm:jobmanagerValidateGame(game) end
    triggerClientEvent(client, "jobcreator:validated", resourceRoot, ok, err)
end)

local function manage(player, id, action)
    local entry = findEntry(id)
    if not entry then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.that_game_does_not_exist")) end
    local admin = isCreatorAdmin(player)
    if entry.official then
        if not admin or action ~= "publish" then
            return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.official_games_can_only_be_edited"))
        end
        local ok, err = jm:jobmanagerOfficialPublish(id)
        return notify(player, L.msg("v_jobcreator.core.job_creator"), ok and (L.msg("v_jobcreator.main.is_published", { name = entry.name })) or (L.msg("v_jobcreator.main.failed", { err = tostring(err) })))
    end
    if action == "publish" or action == "unpublish" then
        if not admin then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.only_admins_can_publish_games")) end
        local ok, err
        if action == "publish" then ok, err = jm:jobmanagerCommunityPublish(id) else ok, err = jm:jobmanagerCommunityUnpublish(id) end
        notify(player, L.msg("v_jobcreator.core.job_creator"), ok and (entry.name .. (action == "publish" and L.msg("v_jobcreator.main.is_published_2") or L.msg("v_jobcreator.main.is_unpublished"))) or (L.msg("v_jobcreator.main.failed", { err = tostring(err) })))
    elseif action == "delete" then
        if not canEdit(player, entry) or (entry.published and not admin) then
            return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.you_cannot_delete_this_game"))
        end
        if locks[id] and locks[id] ~= player then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.someone_is_editing_this_game")) end
        local session = sessions[player]
        if session and session.gameId == id then return notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.close_game_before_deleting_it")) end
        jm:jobmanagerCommunityDelete(id)
        notify(player, L.msg("v_jobcreator.core.job_creator"), L.msg("v_jobcreator.main.was_deleted", { name = entry.name }))
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
