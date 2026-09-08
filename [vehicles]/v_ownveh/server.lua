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
-- for a real (non-guest) account, or nil.
local function resolveAccountName(who)
    if isElement(who) and getElementType(who) == "player" then
        local account = getPlayerAccount(who)
        if account and not isGuestAccount(account) then
            return getAccountName(account)
        end
        return nil
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

-- Rebuilds the owner's "owned_vehicle_ids" account data ("1,2,3"). Works for
-- offline owners too (getAccount).
local function refreshOwnedIds(accountName)
    local account = getAccount(accountName)
    if not account then return end

    local ids = {}
    for _, row in ipairs(OwnVeh.dbGetByAccount(accountName)) do
        ids[#ids + 1] = tonumber(row.id)
    end
    setAccountData(account, "owned_vehicle_ids", table.concat(ids, ","))
end

--------------------------------------------------------------------------------
-- Blips
--------------------------------------------------------------------------------

local function addBlip(entry)
    if isElement(entry.blip) or not isElement(entry.veh) then return end
    local b = Vehicles.config.blip
    entry.blip = createBlipAttachedTo(entry.veh, b.icon, b.size, b.r, b.g, b.b, b.a,
        b.ordering, b.visibleDistance)
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

-- Summons an owned vehicle onto the nearest free spawn point for its type,
-- applies its stored state and gives it a blip.
--   player : the owner (player element)
--   id     : vehicle id
-- -> vehicle element | false, errorCode
--    errorCode: invalid_player | not_found | not_owner | destroyed |
--               no_free_spawnpoint | create_failed
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

    local model = tonumber(row.model)
    local category = OwnVeh.categoryOf(model)
    local px, py, pz = getElementPosition(player)
    local point = OwnVeh.pickSpawnpoint(category, px, py, pz)
    if not point then return false, "no_free_spawnpoint" end

    local plate = (row.plate and row.plate ~= "") and row.plate or nil
    local veh = createVehicle(model, point[1], point[2], point[3],
        point[4], point[5], point[6], plate)
    if not veh then return false, "create_failed" end

    OwnVeh.applyState(veh, row)
    setElementData(veh, "ownveh:id", id)
    setElementData(veh, "ownveh:owner", accountName)

    local entry = { veh = veh, owner = accountName, blip = nil }
    spawned[id] = entry
    addBlip(entry)
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
