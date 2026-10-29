-- Exports. medsys (server/equipment.lua there) uses the first block; the rest is for other scripts
-- and admins. Items are referred to by their v_inventory uid.

-- ---------------------------------------------------------------------------------------------
-- medsys
-- ---------------------------------------------------------------------------------------------

-- What reaches the patient: { bag = id|false, monitor = id|false, stock = { drugs, ivKits, bandages,
-- splints, glucometers, airwayKits, oxygen } | nil }. stock is the sum of every serving bag; a drug
-- missing from stock.drugs is not counted (unlimited).
function getEquipmentNear(target, medic)
    if not isElement(target) then return false end
    local bag = getServingItems(target, "bag", medic)[1]
    local monitor = getServingItems(target, "monitor", medic)[1]
    return {
        bag = bag and bag.id or false,
        monitor = monitor and monitor.id or false,
        stock = getReachableStock(target, medic),
    }
end

-- A serving bag with stock of category ("drugs" + key, "ivKits", "bandages", "splints",
-- "glucometers", "airwayKits", "oxygen"): id | false
function findStockItem(target, medic, category, key)
    local bag = findStockBag(target, medic, category, key)
    return bag and bag.id or false
end

-- Takes amount (default 1) from the bag. True if it was there (or is not counted).
function consumeStock(itemId, category, key, amount)
    local item = Items[itemId]
    if not item or item.kind ~= "bag" then return false end
    return consume(item, category, key, amount)
end

-- The oxygen mask went on: the serving bag with oxygen feeds it (drained every second)
function startPatientOxygen(target, medic)
    return startOxygen(target, medic)
end

function stopPatientOxygen(target)
    stopOxygen(target)
    return true
end

-- The monitor was attached: link the serving monitor to the patient (it disconnects beyond
-- BAG.CONNECT_RANGE)
function linkPatientMonitor(target, medic)
    return linkMonitor(target, medic)
end

function unlinkPatientMonitor(target)
    unlinkMonitor(target)
    return true
end

-- A procedure starts: the medic's carried kit items go down next to the patient
function onTreatmentStart(medic, target)
    if not BAG.AUTO_DROP_ON_TREAT or not isElement(medic) or not getHands(medic) then return false end
    if not isElement(target) or isPedInVehicle(medic) then return false end
    local x, y = getElementPosition(target)
    return dropCarried(medic, x, y)
end

-- ---------------------------------------------------------------------------------------------
-- Others
-- ---------------------------------------------------------------------------------------------

-- { bag = id, monitor = id } | false
function getVehicleKit(vehicle)
    local kit = Kits[vehicle]
    if not kit or not kit.items.bag or not kit.items.monitor then return false end
    return { bag = kit.items.bag.id, monitor = kit.items.monitor.id }
end

-- { kind, state, vehicle, carrier, x, y, z, linkedTo } | false
function getItemInfo(itemId)
    local item = Items[itemId]
    if not item then return false end
    local x, y, z = itemPosition(item)
    return {
        kind = item.kind, state = item.state, vehicle = item.kit.vehicle, carrier = item.carrier or false,
        x = x or false, y = y, z = z, linkedTo = getLinkedPatient(item.id) or false,
    }
end

-- { bag = id|nil, monitor = id|nil }
function getPlayerItems(player)
    local hands = getHands(player)
    return {
        bag = hands and hands.bag and hands.bag.id or nil,
        monitor = hands and hands.monitor and hands.monitor.id or nil,
    }
end

-- The bag's stock { drugs = { id = n }, ivKits, bandages, splints, glucometers, airwayKits, oxygen } | false
function getItemStock(itemId)
    local item = Items[itemId]
    if not item or item.kind ~= "bag" then return false end
    local stock = { drugs = {} }
    for id in pairs(BAG.STOCK.drugs) do stock.drugs[id] = stockAmount(item, "drugs", id) end
    for category in pairs(BAG.STOCK_ITEMS) do stock[category] = stockAmount(item, category) or 0 end
    stock.oxygen = stockAmount(item, "oxygen") or 0
    return stock
end

function restockItem(itemId)
    local item = Items[itemId]
    return item and item.kind == "bag" and restock(item) or false
end

-- Forces the item back into its ambulance (stock kept)
function returnItem(itemId)
    local item = Items[itemId]
    return item and returnItemToVehicle(item, false) or false
end
