-- v_ownveh :: runtime + exports
--
-- Tracks the owned vehicles that are currently spawned in the world, manages
-- their radar blips, keeps their stored state fresh, and exposes the public
-- exports (see meta.xml / README.md).
--
--   spawned[id] = { veh = <vehicle>, owner = <accountName>, blip = <blip|nil> }

local spawned = {}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- Accepts a player element or an account-name string, returns the account name
-- for a logged-in player (or the string as-is), or nil.
local function resolveAccountName(who)
    if isElement(who) and getElementType(who) == "player" then
        local name = exports.v_accounts:getName(who)
        return (type(name) == "string" and name ~= "") and name or nil
    elseif type(who) == "string" and who ~= "" then
        return who
    end
    return nil
end

local function vehicleIsEmpty(veh)
    if not isElement(veh) then return true end
    for _, occupant in pairs(getVehicleOccupants(veh) or {}) do
        if isElement(occupant) then return false end
    end
    return true
end

-- The id of the account's currently summoned vehicle, or nil. Only one owned
-- vehicle may be out at a time.
local function accountSpawnedId(accountName)
    for id, entry in pairs(spawned) do
        if entry.owner == accountName and isElement(entry.veh) then
            return id
        end
    end
    return nil
end

-- Rebuilds the owner's "owned_vehicle_ids" account data ("1,2,3"). Works for
-- offline owners too (setAccData takes an account-name string).
local function refreshOwnedIds(accountName)
    if type(accountName) ~= "string" or accountName == "" then return end

    local ids = {}
    for _, row in ipairs(OwnVeh.dbGetByAccount(accountName)) do
        ids[#ids + 1] = tonumber(row.id)
    end
    exports.v_mysql:setAccData(accountName, "owned_vehicle_ids", table.concat(ids, ","))
end

--------------------------------------------------------------------------------
-- Blips
--------------------------------------------------------------------------------

local function addBlip(entry)
    if isElement(entry.blip) or not isElement(entry.veh) then return end
    local b = Vehicles.config.blip
    entry.blip = createBlipAttachedTo(entry.veh, b.icon, b.size, b.r, b.g, b.b, b.a,
        b.ordering, b.visibleDistance)
    if not isElement(entry.blip) then return end

    -- v_radar only pins a native blip to the minimap edge when it is off-screen
    -- if it carries "isFarVisibility"; "tooltipText" is its hover label on the
    -- pause bigmap. Without these the blip is invisible until you are almost on
    -- top of the car, which reads as "there is no blip".
    if b.farShow then
        setElementData(entry.blip, "isFarVisibility", true)
    end
    if b.tooltip and b.tooltip ~= "" then
        setElementData(entry.blip, "tooltipText", b.tooltip)
    end
end

local function removeBlip(entry)
    if isElement(entry.blip) then
        destroyElement(entry.blip)
    end
    entry.blip = nil
end

--------------------------------------------------------------------------------
-- Internal despawn / persist
--------------------------------------------------------------------------------

-- Saves a spawned vehicle's live state back to the database (if it is alive and
-- not flagged destroyed).
local function persistEntry(id, entry)
    if not isElement(entry.veh) then return end
    local row = OwnVeh.dbGetById(id)
    if row and tonumber(row.isDestroyed) == 1 then return end
    OwnVeh.dbUpdateState(id, OwnVeh.captureState(entry.veh))
end

-- Removes a spawned vehicle from the world. `save` = persist its state first.
local function despawnEntry(id, save)
    local entry = spawned[id]
    if not entry then return end
    if save then persistEntry(id, entry) end
    removeBlip(entry)
    if isElement(entry.veh) then
        destroyElement(entry.veh)
    end
    spawned[id] = nil
end

--------------------------------------------------------------------------------
-- World events
--------------------------------------------------------------------------------

-- Owner gets in the driver seat -> hide the blip (they found the car).
addEventHandler("onVehicleEnter", root, function(player, seat)
    if seat ~= 0 then return end
    local id = tonumber(getElementData(source, "ownveh:id"))
    local entry = id and spawned[id]
    if not entry then return end
    if resolveAccountName(player) == entry.owner then
        removeBlip(entry)
    end
end)

-- Owner leaves the driver seat -> show the blip again.
addEventHandler("onVehicleExit", root, function(player, seat)
    if seat ~= 0 then return end
    local id = tonumber(getElementData(source, "ownveh:id"))
    local entry = id and spawned[id]
    if not entry then return end
    if resolveAccountName(player) == entry.owner then
        addBlip(entry)
    end
end)

-- Vehicle blown up -> flag it destroyed, drop the blip, clean the wreck later.
addEventHandler("onVehicleExplode", root, function()
    local id = tonumber(getElementData(source, "ownveh:id"))
    local entry = id and spawned[id]
    if not entry then return end

    OwnVeh.dbSetDestroyed(id, true)
    removeBlip(entry)

    local wreck = entry.veh
    setTimer(function()
        if isElement(wreck) then destroyElement(wreck) end
    end, Vehicles.config.wreckCleanupDelay, 1)
    spawned[id] = nil
end)

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- Periodic autosave of every spawned owned vehicle.
setTimer(function()
    for id, entry in pairs(spawned) do
        persistEntry(id, entry)
    end
end, Vehicles.config.autosaveInterval, 0)

-- Player disconnects -> save and remove their empty summoned vehicles.
addEventHandler("onPlayerQuit", root, function()
    local accountName = resolveAccountName(source)
    if not accountName then return end
    for id, entry in pairs(spawned) do
        if entry.owner == accountName and vehicleIsEmpty(entry.veh) then
            despawnEntry(id, true)
        end
    end
end)

-- Resource stop -> save everything still out.
addEventHandler("onResourceStop", resourceRoot, function()
    for id, entry in pairs(spawned) do
        persistEntry(id, entry)
        removeBlip(entry)
    end
end)

--------------------------------------------------------------------------------
-- Exports
--------------------------------------------------------------------------------

-- Registers a new vehicle to an account. Money is the caller's problem.
--   who    : player element or account-name string
--   model  : vehicle model id
--   data   : optional { colors, paintjob, upgrades, handling, plate } already
--            serialised the way db.lua stores them (all optional)
-- -> id (number) | false, errorCode
function giveVehicle(who, model, data)
    local accountName = resolveAccountName(who)
    if not accountName then return false, "invalid_account" end

    model = tonumber(model)
    if not model or not getVehicleNameFromModel(model) then
        return false, "invalid_model"
    end

    data = type(data) == "table" and data or {}
    data.model = model

    local id = OwnVeh.dbInsert(accountName, data)
    if not id then return false, "db_error" end

    refreshOwnedIds(accountName)
    return id
end

-- Removes a vehicle from the database (sale or plain delete - same thing here).
-- Despawns it first if it is currently out.
-- -> true | false, errorCode
function deleteVehicle(id)
    id = tonumber(id)
    if not id then return false, "invalid_id" end

    local row = OwnVeh.dbGetById(id)
    if not row then return false, "not_found" end

    despawnEntry(id, false)
    OwnVeh.dbDelete(id)
    refreshOwnedIds(row.account_name)
    return true
end

-- Summons an owned vehicle, applies its stored state and gives it a blip.
--
-- Placement:
--   * boats / helicopters / airplanes -> the closest FREE spawn point of that
--     type, or `no_free_spawnpoint`.
--   * land -> the closest free land spawn point; but if that point is farther
--     than Vehicles.config.landDirectSpawnDistance (or there is none free), the
--     vehicle spawns right at the player and they are put in the driver seat -
--     no blip in that case (it reappears if they get out).
--
-- Only one owned vehicle may be summoned at a time (-> `already_spawned`).
--
--   player : the owner (player element)
--   id     : vehicle id
-- -> vehicle element | false, errorCode
--    errorCode: invalid_player | not_found | not_owner | destroyed |
--               already_spawned | no_free_spawnpoint | create_failed
function spawnOwnedVehicle(player, id)
    if not (isElement(player) and getElementType(player) == "player") then
        return false, "invalid_player"
    end

    id = tonumber(id)
    local row = id and OwnVeh.dbGetById(id)
    if not row then return false, "not_found" end

    local accountName = resolveAccountName(player)
    if not accountName or accountName ~= row.account_name then
        return false, "not_owner"
    end

    if tonumber(row.isDestroyed) == 1 then
        return false, "destroyed"
    end

    -- Already spawned -> hand back the existing element.
    local existing = spawned[id]
    if existing and isElement(existing.veh) then
        return existing.veh
    end

    -- One personal vehicle out at a time.
    if accountSpawnedId(accountName) then
        return false, "already_spawned"
    end

    local model = tonumber(row.model)
    local category = OwnVeh.categoryOf(model)
    local px, py, pz = getElementPosition(player)
    local point = OwnVeh.pickSpawnpoint(category, px, py, pz)

    local direct = false
    if category == "land" then
        if not point then
            direct = true
        else
            local d = getDistanceBetweenPoints3D(px, py, pz, point[1], point[2], point[3])
            if d > Vehicles.config.landDirectSpawnDistance then
                direct = true
            end
        end
    elseif not point then
        return false, "no_free_spawnpoint"
    end

    local plate = (row.plate and row.plate ~= "") and row.plate or nil
    local veh
    if direct then
        local _, _, prz = getElementRotation(player)
        veh = createVehicle(model, px, py, pz + 0.5, 0, 0, prz, plate)
    else
        veh = createVehicle(model, point[1], point[2], point[3],
            point[4], point[5], point[6], plate)
    end
    if not veh then return false, "create_failed" end

    OwnVeh.applyState(veh, row)
    setElementData(veh, "ownveh:id", id)
    setElementData(veh, "ownveh:owner", accountName)

    local entry = { veh = veh, owner = accountName, blip = nil }
    spawned[id] = entry

    if direct then
        -- Straight into the driver seat; owner is in it, so no blip.
        warpPedIntoVehicle(player, veh)
    else
        addBlip(entry)
    end
    return veh
end

-- Saves a summoned vehicle's current state and removes it from the world.
-- Refuses while anyone is inside.
-- -> true | false, errorCode  (not_spawned | occupied)
function storeVehicle(id)
    id = tonumber(id)
    local entry = id and spawned[id]
    if not entry then return false, "not_spawned" end
    if not vehicleIsEmpty(entry.veh) then return false, "occupied" end

    despawnEntry(id, true)
    return true
end

-- Sets / clears the isDestroyed flag. setVehicleDestroyed(id, false) is the
-- "unlock" that lets a wrecked vehicle be summoned again.
-- -> true | false, errorCode (not_found)
function setVehicleDestroyed(id, destroyed)
    id = tonumber(id)
    local row = id and OwnVeh.dbGetById(id)
    if not row then return false, "not_found" end

    OwnVeh.dbSetDestroyed(id, destroyed and true or false)
    return true
end

-- Lists an account's vehicles (for the phone MyVeh app, sell menus, etc.).
-- -> { { id, model, plate, isDestroyed, spawned }, ... }
function getOwnedVehicles(who)
    local accountName = resolveAccountName(who)
    if not accountName then return {} end

    local out = {}
    for _, row in ipairs(OwnVeh.dbGetByAccount(accountName)) do
        local id = tonumber(row.id)
        out[#out + 1] = {
            id          = id,
            model       = tonumber(row.model),
            plate       = row.plate,
            isDestroyed = tonumber(row.isDestroyed) == 1,
            spawned     = spawned[id] ~= nil and isElement(spawned[id].veh) or false,
        }
    end
    return out
end

-- Raw stored row for one vehicle, or false.
function getVehicleData(id)
    local row = OwnVeh.dbGetById(tonumber(id))
    if not row then return false end
    return {
        id          = tonumber(row.id),
        account_name = row.account_name,
        model       = tonumber(row.model),
        colors      = row.colors,
        paintjob    = tonumber(row.paintjob),
        upgrades    = row.upgrades,
        handling    = row.handling,
        customs     = row.customs,
        plate       = row.plate,
        isDestroyed = tonumber(row.isDestroyed) == 1,
    }
end

-- The live vehicle element for an id if it is currently summoned, else false.
function isVehicleSpawned(id)
    local entry = spawned[tonumber(id)]
    if entry and isElement(entry.veh) then return entry.veh end
    return false
end

-- Human-readable name for a vehicle model id. A custom override in models.lua
-- (Vehicles.modelNames) wins; otherwise GTA's built-in name is used
-- ("Infernus", "Sparrow", ...).
-- -> string | false
function getModelName(model)
    model = tonumber(model)
    if not model then return false end
    return Vehicles.customModelName(model) or getVehicleNameFromModel(model) or false
end

-- The id of the owned vehicle the given owner currently has summoned, or nil.
--   who : player element or account-name string
function getSpawnedVehicleId(who)
    local accountName = resolveAccountName(who)
    if not accountName then return nil end
    return accountSpawnedId(accountName)
end

-- Persists a summoned owned vehicle's live state to the database WITHOUT
-- removing it from the world. `which` is a vehicle id, a vehicle element, or a
-- player element (their currently summoned vehicle). Used by e.g. v_customs so
-- tuning survives a relog even if the player never stores the car.
-- -> true | false, errorCode (not_spawned)
function saveVehicle(which)
    local id = tonumber(which)
    if not id and isElement(which) then
        if getElementType(which) == "vehicle" then
            id = tonumber(getElementData(which, "ownveh:id"))
        elseif getElementType(which) == "player" then
            id = accountSpawnedId(resolveAccountName(which))
        end
    end
    local entry = id and spawned[id]
    if not entry then return false, "not_spawned" end
    persistEntry(id, entry)
    return true
end

-- Stores whichever owned vehicle the owner currently has summoned (saves its
-- state and removes it from the world). Convenience wrapper around storeVehicle
-- for callers that only know the player, not the vehicle id.
-- -> true | false, errorCode (invalid_account | not_spawned | occupied)
function storePersonalVehicle(who)
    local accountName = resolveAccountName(who)
    if not accountName then return false, "invalid_account" end

    local id = accountSpawnedId(accountName)
    if not id then return false, "not_spawned" end
    return storeVehicle(id)
end
