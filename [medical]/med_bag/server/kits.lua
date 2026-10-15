if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Kits: every ambulance owns one kit = one medical bag + one Lifepak 15. Both are v_inventory items
-- (the bag is a container with the drugs, IV kits, the oxygen cylinder and the tools in it).
-- v_inventory keeps the items (hands, ground, objects, the window); med_bag decides where they may
-- go: the side door (stowed in the ambulance), the stretcher (attached / stowed "aboard"), the
-- medics' hands. The state of an item is read from its v_inventory location:
--   "stowed"    stored in its ambulance (tag "aboard": it went in on the stretcher with a patient)
--   "carried"   in a player's hand
--   "ground"    on the ground
--   "stretcher" attached to the side of its ambulance's stretcher
--   "other"     anywhere else (should not happen: players cannot store either item)
-- server/interaction.lua (menus), server/stock.lua and server/watch.lua are told about every
-- change through onItemChanged / onKitCreated / onKitDestroyed.

addEvent("onMedicalEquipmentChange")  -- source: vehicle, (itemId, kind, oldState, newState)
addEvent("onInventoryItemMoved")
addEvent("onInventoryItemDestroyed")
addEvent("onInventoryReady")

local INV_RES = "v_inventory"

Kits = {}         -- vehicle -> kit { vehicle, anchor, items = { bag, monitor }, menuId }
Items = {}        -- uid -> item { id, kind, kit, state, carrier, lastHolder, stretcher, aboard, ... }
local blown = {}  -- vehicle -> true between explode and respawn

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

function isInventoryRunning()
    local res = getResourceFromName(INV_RES)
    return res and getResourceState(res) == "running"
end

function inv()
    return exports[INV_RES]
end

function notify(player, text, title, alert)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    triggerClientEvent(player, "bag:notify", resourceRoot, title or L.msg("med_bag.kits.ems_equipment"), text, alert == true)
end

function kitLabel(kit)
    local vehicle = kit.vehicle
    local plate = isElement(vehicle) and getVehiclePlateText(vehicle) or ""
    plate = plate:gsub("^%s+", ""):gsub("%s+$", "")
    return plate ~= "" and plate or "ambulance"
end

-- The kit items a player holds: { bag = item, monitor = item } | nil
function getHands(player)
    local hands
    for _, item in pairs(Items) do
        if item.state == "carried" and item.carrier == player then
            hands = hands or {}
            hands[item.kind] = item
        end
    end
    return hands
end

function getCarried(player, kind)
    local hands = getHands(player)
    return hands and hands[kind]
end

-- Position of an element, taken from the top of its attachment chain
function rootPosition(element)
    local top, guard = element, 0
    while guard < 5 do
        local parent = getElementAttachedTo(top)
        if not parent then break end
        top, guard = parent, guard + 1
    end
    return getElementPosition(top)
end

-- Where the item is now -> x, y, z, dimension, interior | false
function itemPosition(item)
    if not isInventoryRunning() then return false end
    local x, y, z, dim, int = inv():getItemPosition(item.id)
    if not x then return false end
    return x, y, z, dim, int
end

function playAnim(player, anim)
    if not anim or not isElement(player) or isPedDead(player) or isPedInVehicle(player) then return end
    setPedAnimation(player, anim[1], anim[2], anim[3], false, false, false, false)
end

function openSideDoor(kit)
    local vehicle = kit.vehicle
    local door = isElement(vehicle) and BAG.SIDE_DOOR[getElementModel(vehicle)]
    if not door then return end
    setVehicleDoorOpenRatio(vehicle, door, 1, BAG.DOOR_TIME)
    setTimer(function()
        if isElement(vehicle) then setVehicleDoorOpenRatio(vehicle, door, 0, BAG.DOOR_TIME) end
    end, BAG.DOOR_TIME + 1200, 1)
end

-- Only medics may handle the kit items while medsys requires the role
local function itemAccess()
    if isMedicRoleRequired() then return { dataKey = "medic.role" } end
    return nil
end

-- ---------------------------------------------------------------------------------------------
-- State (from the v_inventory location)
-- ---------------------------------------------------------------------------------------------

local function applyLoc(item, loc)
    local old, oldAboard, oldStretcher = item.state, item.aboard, item.stretcher
    item.carrier, item.stretcher, item.aboard = nil, nil, nil
    local t = type(loc) == "table" and loc.type
    if t == "slot" then
        item.state, item.carrier = "carried", loc.player
        item.lastHolder = loc.player
    elseif t == "ground" then
        item.state = "ground"
    elseif t == "attached" then
        item.state, item.stretcher = "stretcher", loc.element
    elseif t == "vehicle" and loc.vehicle == item.kit.vehicle then
        item.state, item.aboard = "stowed", loc.tag == "aboard" or nil
    else
        item.state = "other"
    end
    if old ~= item.state or oldAboard ~= item.aboard or oldStretcher ~= item.stretcher then
        onItemChanged(item, old, oldStretcher)
        if isElement(item.kit.vehicle) then
            triggerEvent("onMedicalEquipmentChange", item.kit.vehicle, item.id, item.kind, old, item.state)
        end
    end
end

addEventHandler("onInventoryItemMoved", root, function(uid, defId, from, to)
    local item = Items[uid]
    if item then applyLoc(item, to) end
end)

-- ---------------------------------------------------------------------------------------------
-- Transitions (callers check the rules first). -> true | false, reason
-- ---------------------------------------------------------------------------------------------

local function result(ok, reason)
    if ok then return true end
    return false, reason
end

-- From the ambulance, the ground or the stretcher into a free hand
function takeItem(item, player)
    if not isInventoryRunning() then return false end
    local ok, reason = inv():giveItemToPlayer(player, item.id)
    return result(ok, reason)
end
pickUpItem = takeItem

-- Back into its own ambulance. aboard = it went in on the stretcher with a patient (it comes out on
-- the stretcher again when the stretcher is taken out with a patient).
function stowItem(item, aboard)
    if not isInventoryRunning() or not isElement(item.kit.vehicle) then return false end
    local ok, reason = inv():storeItemInVehicle(item.id, item.kit.vehicle, aboard and "aboard" or nil)
    return result(ok, reason)
end

-- Onto the side of a stretcher (its ambulance's: the caller checks it)
function putOnStretcher(item, stretcherObj)
    if not isInventoryRunning() then return false end
    if item.state == "stretcher" and item.stretcher == stretcherObj then return false end
    local ok, reason = inv():attachItem(item.id, stretcherObj, BAG.STRETCHER_OFFSETS[item.kind])
    return result(ok, reason)
end

-- Puts the player's kit items down in front of them (or beside the point px, py: next to a patient)
function dropCarried(player, px, py)
    local hands = getHands(player)
    if not hands or not isInventoryRunning() then return false end
    local uids = {}
    for _, item in pairs(hands) do uids[#uids + 1] = item.id end
    return (inv():dropPlayerItems(player, { "left", "right" }, px, py, uids) or 0) > 0
end

-- ---------------------------------------------------------------------------------------------
-- Kits
-- ---------------------------------------------------------------------------------------------

local function createKitItem(kit, kind)
    local uid = inv():createItem(BAG.ITEM_DEFS[kind], nil, { type = "vehicle", vehicle = kit.vehicle },
        { access = itemAccess() })
    if not uid then return nil end
    local item = { id = uid, kind = kind, kit = kit, state = "stowed" }
    kit.items[kind] = item
    Items[uid] = item
    if kind == "bag" then fillBag(item) end
    return item
end

local function createKit(vehicle)
    if Kits[vehicle] or blown[vehicle] or not isInventoryRunning() then return end
    local x, y, z = getElementPosition(vehicle)
    local anchor = createObject(BAG.ANCHOR_MODEL, x, y, z)
    if not anchor then return end
    setElementAlpha(anchor, 0)
    setElementCollisionsEnabled(anchor, false)
    setElementDimension(anchor, getElementDimension(vehicle))
    setElementInterior(anchor, getElementInterior(vehicle))
    local p = bagSidePoint(vehicle)
    attachElements(anchor, vehicle, p[1], p[2], p[3])
    setElementData(anchor, BAG_DATA.KIND, "anchor")

    local kit = { vehicle = vehicle, anchor = anchor, items = {} }
    Kits[vehicle] = kit
    for _, kind in ipairs(BAG.KINDS) do
        if not createKitItem(kit, kind) then
            outputDebugString("[med_bag] could not create the " .. kind .. " of an ambulance", 2)
        end
    end
    onKitCreated(kit)
end

-- quiet: the items are already gone in v_inventory, only our side is cleaned up
local function destroyKit(kit, quiet)
    if Kits[kit.vehicle] ~= kit then return end
    Kits[kit.vehicle] = nil
    for _, item in pairs(kit.items) do
        local holder = item.carrier
        Items[item.id] = nil
        item.state = "gone"
        onItemGone(item)
        if not quiet and isInventoryRunning() then inv():destroyInventoryItem(item.id) end
        if isElement(holder) and not quiet then
            notify(holder, L.msg("med_bag.kits.was_lost_with_its_ambulance", { kind = bagItemName(item.kind) }))
        end
    end
    onKitDestroyed(kit)
    if isElement(kit.anchor) then destroyElement(kit.anchor) end
end

-- An item of ours was destroyed in v_inventory: the next scan builds a new kit
addEventHandler("onInventoryItemDestroyed", root, function(uid)
    local item = Items[uid]
    if item and Kits[item.kit.vehicle] == item.kit then destroyKit(item.kit, false) end
end)

local function isAmbulance(vehicle)
    return getElementType(vehicle) == "vehicle" and BAG.VEHICLE_MODELS[getElementModel(vehicle)] == true
end

function scanVehicles()
    if not isInventoryRunning() then return end
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        if isAmbulance(vehicle) then
            if not Kits[vehicle] and not blown[vehicle] then createKit(vehicle) end
        elseif Kits[vehicle] then
            destroyKit(Kits[vehicle])
        end
    end
end

local scanPending = false
local function requestScan()
    if scanPending then return end
    scanPending = true
    setTimer(function()
        scanPending = false
        scanVehicles()
    end, 50, 1)
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- elements created during the start reach the clients after the menus that refer to them
    setTimer(scanVehicles, 500, 1)
    if addDebugHook then
        addDebugHook("postFunction", requestScan, { "createVehicle", "setElementModel" })
    end
    setTimer(scanVehicles, BAG.SCAN_INTERVAL, 0)
end)

-- v_inventory (re)started or stopped: every item is gone, the kits are built again
local function forgetAll()
    for _, kit in pairs(Kits) do destroyKit(kit, true) end
    Items = {}
end

addEventHandler("onInventoryReady", root, function()
    forgetAll()
    setTimer(scanVehicles, 200, 1)
end)

addEventHandler("onResourceStop", root, function(res)
    if getResourceName(res) == INV_RES then forgetAll() end
end)

-- med_bag stops: its items go with it (v_inventory destroys the items of a stopped creator)

addEventHandler("onElementModelChange", root, function()
    if getElementType(source) == "vehicle" then requestScan() end
end)

addEventHandler("onVehicleExplode", root, function()
    blown[source] = true
    if Kits[source] then destroyKit(Kits[source]) end
end)

addEventHandler("onVehicleRespawn", root, function()
    blown[source] = nil
    if isAmbulance(source) then createKit(source) end
end)

-- The anchor follows the ambulance into another dimension / interior
local function followWorld()
    local kit = Kits[source]
    if kit and isElement(kit.anchor) then
        setElementDimension(kit.anchor, getElementDimension(source))
        setElementInterior(kit.anchor, getElementInterior(source))
    end
end
addEventHandler("onElementDimensionChange", root, followWorld)
addEventHandler("onElementInteriorChange", root, followWorld)

addEvent("onPlayerMedicChange") -- medsys: the role was taken (off duty): the kit items go down
addEventHandler("onPlayerMedicChange", root, function(enabled)
    if not enabled and isMedicRoleRequired() then dropCarried(source) end
end)

addEventHandler("onElementDestroy", root, function()
    if getElementType(source) ~= "vehicle" then return end
    blown[source] = nil
    if Kits[source] then destroyKit(Kits[source]) end
end)

-- ---------------------------------------------------------------------------------------------
-- Lookups
-- ---------------------------------------------------------------------------------------------

-- Returns the item to its ambulance (admin / abandon); emptyStock = true empties the bag
function returnItemToVehicle(item, emptyStock)
    if not Items[item.id] then return false end
    stowItem(item)
    if emptyStock and item.kind == "bag" then emptyBag(item) end
    return true
end

function eachKit() return pairs(Kits) end
