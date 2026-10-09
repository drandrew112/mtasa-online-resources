-- Kits and items: every ambulance owns one kit = one medical bag + one monitor. The server is the
-- only authority. An item is in exactly one state:
--   "stowed"   in its ambulance, no world object
--   "carried"  in a player's hand: no server object, the carrier's BAG_DATA.HANDS lists it and
--              every client draws a local object on the hand bone (client/carry.lua)
--   "ground"   a server object on the ground with its own pick-up menu
--   "stretcher" a server object attached to the side of its ambulance's stretcher (med_stretcher)
--              (server/stretcher.lua: pushing with items in the hands, the stretcher menu)
-- A stowed item has `aboard` set when it went into the ambulance on the stretcher: it comes out on
-- the stretcher again when the stretcher is taken out with a patient.
-- Nothing else creates items, an item only goes back into its own ambulance / onto its own
-- ambulance's stretcher, and its world object exists only on the ground / on the stretcher:
-- duplication is impossible.
-- server/interaction.lua (menus), server/stock.lua and server/watch.lua are told about every
-- change through onItemChanged / onKitCreated / onKitDestroyed.

addEvent("bag:snapResult", true)
addEvent("onMedicalEquipmentChange")  -- source: vehicle, (itemId, kind, oldState, newState)

Kits = {}         -- vehicle -> kit { vehicle, anchor, items = { bag, monitor }, menuId }
Items = {}        -- id -> item { id, kind, kit, state, object, carrier, stock, lastHolder, ... }
local byObject = {}  -- ground / stretcher object -> item
local Hands = {}     -- player -> { bag = item, monitor = item }
local blown = {}     -- vehicle -> true between explode and respawn
local nextId = 0
local resolvedModel = {} -- kind -> model id that could be created (id or fallback)

-- ---------------------------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------------------------

function notify(player, text, title, alert)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    triggerClientEvent(player, "bag:notify", resourceRoot, title or "EMS equipment", text, alert == true)
end

function kitLabel(kit)
    local vehicle = kit.vehicle
    local plate = isElement(vehicle) and getVehiclePlateText(vehicle) or ""
    plate = plate:gsub("^%s+", ""):gsub("%s+$", "")
    return plate ~= "" and plate or "ambulance"
end

function getHands(player)
    return Hands[player]
end

function getCarried(player, kind)
    local hands = Hands[player]
    return hands and hands[kind]
end

-- The carrier's HANDS data: the models (client/carry.lua) + the carried bag's IV kits and oxygen
-- (the carry HUD, client/hud.lua)
local function syncHands(player)
    if not isElement(player) then return end
    local hands = Hands[player]
    if not hands or (not hands.bag and not hands.monitor) then
        Hands[player] = nil
        removeElementData(player, BAG_DATA.HANDS)
        for _, control in ipairs(BAG.CARRY_LOCKED_CONTROLS) do toggleControl(player, control, true) end
        return
    end
    local stock = hands.bag and hands.bag.stock
    setElementData(player, BAG_DATA.HANDS, {
        bag = hands.bag and resolvedModel.bag or nil,
        monitor = hands.monitor and resolvedModel.monitor or nil,
        ivKits = stock and stock.ivKits or nil,
        oxygen = stock and math.floor(stock.oxygen + 0.5) or nil,
    })
    for _, control in ipairs(BAG.CARRY_LOCKED_CONTROLS) do toggleControl(player, control, false) end
end

-- Position of an element, taken from the top of its attachment chain (the server-side position of
-- an attached element is not reliable: a patient on a stretcher that a medic pushes, an item on it)
function rootPosition(element)
    local top, guard = element, 0
    while guard < 5 do
        local parent = getElementAttachedTo(top)
        if not parent then break end
        top, guard = parent, guard + 1
    end
    return getElementPosition(top)
end

-- Where the item is now (world position + its dimension / interior source element)
function itemPosition(item)
    if item.state == "ground" and isElement(item.object) then
        local x, y, z = getElementPosition(item.object)
        return x, y, z, item.object
    elseif item.state == "stretcher" and isElement(item.stretcher) then
        local x, y, z = rootPosition(item.stretcher)
        return x, y, z, item.stretcher
    elseif item.state == "carried" and isElement(item.carrier) then
        local x, y, z = getElementPosition(item.carrier)
        return x, y, z, item.carrier
    elseif isElement(item.kit.vehicle) then
        local x, y, z = getElementPosition(item.kit.vehicle)
        return x, y, z, item.kit.vehicle
    end
    return false
end

local function setState(item, state)
    local old = item.state
    item.state = state
    onItemChanged(item, old)
    if isElement(item.kit.vehicle) then
        triggerEvent("onMedicalEquipmentChange", item.kit.vehicle, item.id, item.kind, old, state)
    end
end

local function playAnim(player, anim)
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

-- Creates the item's world object with the configured model, or the fallback if the server does
-- not know the model
local function createItemObject(kind, x, y, z, rz)
    local def = BAG.MODELS[kind]
    local obj
    if resolvedModel[kind] then
        obj = createObject(resolvedModel[kind], x, y, z, 0, 0, rz or 0)
    else
        obj = createObject(def.id, x, y, z, 0, 0, rz or 0)
        resolvedModel[kind] = obj and def.id or nil
        if not obj and def.fallback then
            outputDebugString(("[med_bag] model %d (%s) is not available, using %d"):format(def.id, kind, def.fallback), 2)
            obj = createObject(def.fallback, x, y, z, 0, 0, rz or 0)
            resolvedModel[kind] = obj and def.fallback or nil
        end
    end
    if obj and def.scale and def.scale ~= 1 then setObjectScale(obj, def.scale) end
    return obj
end

local function resolveModels()
    for _, kind in ipairs(BAG.KINDS) do
        if not resolvedModel[kind] then
            local obj = createItemObject(kind, 0, 0, -100)
            if isElement(obj) then destroyElement(obj) end
        end
    end
end

local function destroyItemObject(item)
    local obj = item.object
    item.object = nil
    if obj then
        byObject[obj] = nil
        onItemObjectGone(item, obj)
        if isElement(obj) then destroyElement(obj) end
    end
end

local function releaseCarrier(item)
    local carrier = item.carrier
    item.carrier = nil
    if not carrier then return end
    local hands = Hands[carrier]
    if hands and hands[item.kind] == item then hands[item.kind] = nil end
    syncHands(carrier)
end

-- ---------------------------------------------------------------------------------------------
-- Transitions (callers check the rules first)
-- ---------------------------------------------------------------------------------------------

function takeItem(item, player)
    if item.state ~= "stowed" then return false end
    item.aboard = nil
    Hands[player] = Hands[player] or {}
    Hands[player][item.kind] = item
    item.carrier, item.lastHolder = player, player
    syncHands(player)
    setState(item, "carried")
    return true
end

-- From the ground or off the stretcher into the hands
function pickUpItem(item, player)
    if item.state ~= "ground" and item.state ~= "stretcher" then return false end
    destroyItemObject(item)
    item.stretcher = nil
    Hands[player] = Hands[player] or {}
    Hands[player][item.kind] = item
    item.carrier, item.lastHolder = player, player
    syncHands(player)
    playAnim(player, BAG.TAKE_ANIM)
    setState(item, "carried")
    return true
end

-- Back into its own ambulance (from a hand, the ground or the stretcher). aboard = the stretcher
-- it went in on (it comes out on it again with a patient), nil otherwise.
function stowItem(item, aboard)
    if item.state == "stowed" then
        item.aboard = aboard
        return false
    end
    releaseCarrier(item)
    destroyItemObject(item)
    item.stretcher, item.aboard = nil, aboard
    setState(item, "stowed")
    return true
end

-- Onto the side of a stretcher (its ambulance's: the caller checks it)
function putOnStretcher(item, stretcherObj)
    if item.state == "stretcher" and item.stretcher == stretcherObj then return false end
    releaseCarrier(item)
    destroyItemObject(item)
    item.aboard = nil
    local x, y, z = getElementPosition(stretcherObj)
    local obj = createItemObject(item.kind, x, y, z)
    if not obj then
        setState(item, "stowed")
        return false
    end
    setElementDimension(obj, getElementDimension(stretcherObj))
    setElementInterior(obj, getElementInterior(stretcherObj))
    setElementCollisionsEnabled(obj, false)
    setElementData(obj, BAG_DATA.KIND, item.kind)
    setElementData(obj, BAG_DATA.ITEM, item.id)
    local o = BAG.STRETCHER_OFFSETS[item.kind]
    attachElements(obj, stretcherObj, o[1], o[2], o[3], o[4], o[5], o[6])
    item.object, item.stretcher = obj, stretcherObj
    byObject[obj] = item
    setState(item, "stretcher")
    return true
end

-- On the ground at x, y, z (the feet level); `snapper`'s client corrects the height to the real
-- ground (the server has no ground data)
function dropItem(item, x, y, z, rz, dimension, interior, snapper)
    if item.state == "ground" then return false end
    releaseCarrier(item)
    destroyItemObject(item)  -- off the stretcher
    item.stretcher, item.aboard = nil, nil
    local g = BAG.MODELS[item.kind].ground
    local obj = createItemObject(item.kind, x + g[1], y + g[2], z + g[3], (rz or 0) + g[6])
    if not obj then
        -- cannot exist in the world: back into the ambulance rather than vanish
        setState(item, "stowed")
        return false
    end
    setElementDimension(obj, dimension or 0)
    setElementInterior(obj, interior or 0)
    setElementFrozen(obj, true)
    setElementData(obj, BAG_DATA.KIND, item.kind)
    setElementData(obj, BAG_DATA.ITEM, item.id)
    item.object = obj
    byObject[obj] = item
    setState(item, "ground")
    if isElement(snapper) then triggerClientEvent(snapper, "bag:snap", resourceRoot, obj, g[3]) end
    return true
end

addEventHandler("bag:snapResult", resourceRoot, function(obj, z)
    local item = byObject[obj]
    if not item or type(z) ~= "number" then return end
    local cx, cy, cz = getElementPosition(client)
    local x, y, oldZ = getElementPosition(obj)
    if getDistanceBetweenPoints3D(cx, cy, cz, x, y, oldZ) > 15 or math.abs(z - oldZ) > 2.5 then return end
    setElementPosition(obj, x, y, z)
end)

-- Puts the player's carried items down in front of them (or around the point px, py: next to a
-- patient, on the side towards the player)
function dropCarried(player, px, py)
    local hands = Hands[player]
    if not hands then return false end
    local x, y, z = getElementPosition(player)
    local _, _, rz = getElementRotation(player)
    local dim, int = getElementDimension(player), getElementInterior(player)
    local feet = z - 1.0
    local dropped = false
    for _, kind in ipairs(BAG.KINDS) do
        local item = hands[kind]
        if item then
            local o = BAG.DROP_OFFSETS[kind]
            local wx, wy
            if px then
                -- beside the patient, towards the medic, spread left / right
                local dx, dy = x - px, y - py
                local len = math.max(0.01, math.sqrt(dx * dx + dy * dy))
                dx, dy = dx / len, dy / len
                local side = o[1] < 0 and -1 or 1
                wx = px + dx * BAG.DROP_PATIENT_DISTANCE - dy * 0.45 * side
                wy = py + dy * BAG.DROP_PATIENT_DISTANCE + dx * 0.45 * side
            else
                local rad = math.rad(rz)
                wx = x + o[1] * math.cos(rad) - o[2] * math.sin(rad)
                wy = y + o[1] * math.sin(rad) + o[2] * math.cos(rad)
            end
            dropItem(item, wx, wy, feet, rz, dim, int, player)
            dropped = true
        end
    end
    if dropped then playAnim(player, BAG.PUT_ANIM) end
    return dropped
end

-- ---------------------------------------------------------------------------------------------
-- Kits
-- ---------------------------------------------------------------------------------------------

local function newStock()
    local stock = { drugs = {} }
    for id, count in pairs(BAG.STOCK.drugs) do stock.drugs[id] = count end
    stock.ivKits, stock.oxygen = BAG.STOCK.ivKits, BAG.STOCK.oxygen
    return stock
end
fullStock = newStock

local function createKit(vehicle)
    if Kits[vehicle] or blown[vehicle] then return end
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
    for _, kind in ipairs(BAG.KINDS) do
        nextId = nextId + 1
        local item = { id = kind .. ":" .. nextId, kind = kind, kit = kit, state = "stowed" }
        if kind == "bag" then item.stock = newStock() end
        kit.items[kind] = item
        Items[item.id] = item
    end
    Kits[vehicle] = kit
    onKitCreated(kit)
end

local function destroyKit(kit)
    if Kits[kit.vehicle] ~= kit then return end
    Kits[kit.vehicle] = nil
    for _, item in pairs(kit.items) do
        local holder = item.carrier
        releaseCarrier(item)
        destroyItemObject(item)
        Items[item.id] = nil
        item.state = "gone"
        onItemGone(item)
        if isElement(holder) then notify(holder, bagItemName(item.kind) .. " was lost with its ambulance.") end
    end
    onKitDestroyed(kit)
    if isElement(kit.anchor) then destroyElement(kit.anchor) end
end

local function isAmbulance(vehicle)
    return getElementType(vehicle) == "vehicle" and BAG.VEHICLE_MODELS[getElementModel(vehicle)] == true
end

function scanVehicles()
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
    resolveModels()
    -- elements created during the start reach the clients after the menus that refer to them
    setTimer(scanVehicles, 500, 1)
    if addDebugHook then
        addDebugHook("postFunction", requestScan, { "createVehicle", "setElementModel" })
    end
    setTimer(scanVehicles, BAG.SCAN_INTERVAL, 0)
end)

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

-- ---------------------------------------------------------------------------------------------
-- Carriers
-- ---------------------------------------------------------------------------------------------

-- The carrier cannot keep the items: down where they stand
local function dropAll(player)
    if Hands[player] then dropCarried(player) end
end

addEventHandler("onPlayerQuit", root, function() dropAll(source) end)
addEventHandler("onPlayerWasted", root, function() dropAll(source) end)

addEvent("onPlayerMedicChange") -- medsys: the role was taken (off duty)
addEventHandler("onPlayerMedicChange", root, function(enabled)
    if not enabled then dropAll(source) end
end)

-- A player changing dimension / interior (teleport, tutorial) leaves the items at the old place
local function onPlayerWorldChange(old)
    if getElementType(source) ~= "player" or not Hands[source] then return end
    local hands = Hands[source]
    local x, y, z = getElementPosition(source)
    local dim = getElementDimension(source)
    local int = getElementInterior(source)
    if eventName == "onElementDimensionChange" then dim = old else int = old end
    for _, kind in ipairs(BAG.KINDS) do
        if hands[kind] then dropItem(hands[kind], x, y, z - 1.0, 0, dim, int, nil) end
    end
end
addEventHandler("onElementDimensionChange", root, onPlayerWorldChange)
addEventHandler("onElementInteriorChange", root, onPlayerWorldChange)

-- Vehicles: entering its own ambulance stows the carried items, any other vehicle is refused
addEventHandler("onVehicleStartEnter", root, function(player)
    local hands = Hands[player]
    if not hands then return end
    for _, item in pairs(hands) do
        if item.kit.vehicle ~= source then
            cancelEvent()
            notify(player, "Put the equipment down or back into its ambulance first.")
            return
        end
    end
end)

addEventHandler("onPlayerVehicleEnter", root, function(vehicle)
    local source = source
    local hands = Hands[source]
    if not hands then return end
    local x, y, z = getElementPosition(vehicle)
    local stowed = false
    for _, kind in ipairs(BAG.KINDS) do
        local item = hands[kind]
        if item then
            if item.kit.vehicle == vehicle then
                stowItem(item)
                stowed = true
            else
                -- warped into another vehicle by a script: the item stays outside
                dropItem(item, x + 2, y, z - 0.5, 0, getElementDimension(vehicle), getElementInterior(vehicle), nil)
            end
        end
    end
    if stowed then notify(source, "Equipment stowed in the ambulance.") end
end)

-- ---------------------------------------------------------------------------------------------
-- Destruction
-- ---------------------------------------------------------------------------------------------

addEventHandler("onElementDestroy", root, function()
    local source = source -- nested events (item changes) may replace the global
    local item = byObject[source]
    if item then
        -- somebody else destroyed the item's object: the item returns to its ambulance
        byObject[source] = nil
        item.object, item.stretcher = nil, nil
        if Items[item.id] then setState(item, "stowed") end
        return
    end
    -- a stretcher with items on it disappears: the items fall to the ground there
    if getElementType(source) == "object" then
        local x, y, z = getElementPosition(source)
        for _, it in pairs(Items) do
            if it.state == "stretcher" and it.stretcher == source then
                dropItem(it, x, y, z - 0.45, 0, getElementDimension(source), getElementInterior(source), nil)
            elseif it.aboard == source then
                it.aboard = nil
            end
        end
    end
    if getElementType(source) == "vehicle" then
        blown[source] = nil
        if Kits[source] then destroyKit(Kits[source]) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(Hands) do
        if isElement(player) then
            removeElementData(player, BAG_DATA.HANDS)
            for _, control in ipairs(BAG.CARRY_LOCKED_CONTROLS) do toggleControl(player, control, true) end
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Lookups
-- ---------------------------------------------------------------------------------------------

function getItemByObject(obj) return byObject[obj] end

-- Re-sends the carrier's HANDS data if the shown stock of the carried bag changed
function refreshCarriedStock(item)
    local carrier = item.state == "carried" and item.carrier
    if not isElement(carrier) or not item.stock then return end
    local data = getElementData(carrier, BAG_DATA.HANDS)
    if type(data) == "table" and data.ivKits == item.stock.ivKits
        and data.oxygen == math.floor(item.stock.oxygen + 0.5) then return end
    syncHands(carrier)
end
function getResolvedModel(kind) return resolvedModel[kind] end

-- Returns the item to its ambulance (admin / abandon); emptyStock = true empties the bag
function returnItemToVehicle(item, emptyStock)
    if not Items[item.id] then return false end
    stowItem(item)
    if emptyStock and item.stock then
        for id in pairs(item.stock.drugs) do item.stock.drugs[id] = 0 end
        item.stock.ivKits, item.stock.oxygen = 0, 0
        onStockChanged(item)
    end
    return true
end

function eachKit() return pairs(Kits) end
