if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Consumables of the bags, the oxygen drain and the monitor links.
--
-- The stock of a bag is what is really in it (v_inventory items): drug stacks ("drug_<id>"), IV
-- kits, bandages, splints, the glucometer, the airway kit and the oxygen cylinder (meta.oxygen %).
-- A medic may move them between bags in the inventory window; whatever a serving bag holds counts.
--
-- Which item serves a patient: same dimension / interior and within BAG.USE_RANGE of the patient
-- (carried, on the ground or on the stretcher's side), or stowed in the very ambulance the patient
-- sits in. A connected item (oxygen source, linked monitor) keeps working up to BAG.CONNECT_RANGE.
-- The medic's own carried item comes first, then the nearest one.
--
-- medsys (server/equipment.lua there) drives everything through the exports in server/exports.lua.
-- Oxygen is used continuously by a patient with the mask on or intubated: at the scene, on the
-- stretcher, in the ambulance (from the stowed bag) and at the handover. An intubated patient
-- without oxygen keeps the tube but it has no effect (medsys noOxygen) until a bag with oxygen is in
-- range again.

local MEDSYS = "medsys"

Oxygen = {}       -- patient -> { item = bag id }
MonitorLinks = {} -- patient -> item id
local linkedPatient = {} -- monitor item id -> patient
local oxygenLevel = {}   -- cylinder uid -> exact % (v_inventory meta is written on whole-% changes)

local function isMedsysRunning()
    local res = getResourceFromName(MEDSYS)
    return res and getResourceState(res) == "running"
end

-- ---------------------------------------------------------------------------------------------
-- Bag contents
-- ---------------------------------------------------------------------------------------------

-- v_inventory item id of a stock category (+ drug key) | nil (not an item: unlimited)
local function stockDef(category, key)
    if category == "drugs" then
        local id = BAG.DRUG_PREFIX .. tostring(key)
        return (isInventoryRunning() and inv():getItemDef(id)) and id or nil
    end
    if category == "oxygen" then return BAG.OXYGEN_ITEM end
    return BAG.STOCK_ITEMS[category]
end

-- { { uid, def, amount, meta } } of the bag
local function contents(bag)
    if not isInventoryRunning() then return {} end
    return inv():getContainerContents(bag.id) or {}
end

local function cylinderLevel(entry)
    local level = oxygenLevel[entry.uid]
    if level == nil then
        level = tonumber(type(entry.meta) == "table" and entry.meta.oxygen) or 0
        oxygenLevel[entry.uid] = level
    end
    return level
end

-- The fullest cylinder in the bag: entry, level
local function bestCylinder(bag)
    local best, bestLevel
    for _, entry in ipairs(contents(bag)) do
        if entry.def == BAG.OXYGEN_ITEM then
            local level = cylinderLevel(entry)
            if not bestLevel or level > bestLevel then best, bestLevel = entry, level end
        end
    end
    return best, bestLevel or 0
end

-- Remaining amount, or nil when the key is not counted (unlimited)
function stockAmount(bag, category, key)
    local def = stockDef(category, key)
    if not def then return nil end
    if category == "oxygen" then
        local _, level = bestCylinder(bag)
        return level
    end
    local n = 0
    for _, entry in ipairs(contents(bag)) do
        if entry.def == def then n = n + entry.amount end
    end
    return n
end

local function fullAmount(category, key)
    if category == "drugs" then return BAG.STOCK.drugs[key] end
    return BAG.STOCK[category]
end

function hasStock(bag, category, key)
    local amount = stockAmount(bag, category, key)
    return amount == nil or amount > 0
end

-- The bag's HUD / window lines: IV kits and oxygen
function refreshBagDisplay(bag)
    if not isInventoryRunning() or not Items[bag.id] then return end
    local iv = stockAmount(bag, "ivKits") or 0
    local _, o2 = bestCylinder(bag)
    local display = {
        { label = L.msg("med_bag.hud.iv_kits_label"), value = tostring(iv) },
        { label = L.msg("med_bag.hud.oxygen_label"), value = ("%d%%"):format(math.floor(o2 + 0.5)) },
    }
    local key = iv .. ":" .. math.floor(o2 + 0.5)
    if bag.displayKey == key then return end
    bag.displayKey = key
    inv():setItemMeta(bag.id, "display", display)
end

-- Fills the bag up to BAG.STOCK (a new kit, restocking)
function fillBag(bag)
    if not isInventoryRunning() then return end
    local i = inv()
    i:clearContainer(bag.id)
    local target = { type = "container", container = bag.id }
    for id, count in pairs(BAG.STOCK.drugs) do
        if count > 0 and i:getItemDef(BAG.DRUG_PREFIX .. id) then
            i:createItem(BAG.DRUG_PREFIX .. id, nil, target, { amount = count })
        end
    end
    for category, def in pairs(BAG.STOCK_ITEMS) do
        local count = BAG.STOCK[category] or 0
        if count > 0 then i:createItem(def, nil, target, { amount = count }) end
    end
    local full = BAG.STOCK.oxygen
    local cyl = i:createItem(BAG.OXYGEN_ITEM, {
        oxygen = full,
        bar = { label = L.msg("med_bag.hud.oxygen_label"), value = full, max = 100 },
    }, target)
    if cyl then oxygenLevel[cyl] = full end
    bag.warned, bag.displayKey = nil, nil
    refreshBagDisplay(bag)
end

-- An abandoned bag comes back empty: the drugs and the consumables are gone, the cylinder is empty
function emptyBag(bag)
    if not isInventoryRunning() then return end
    local i = inv()
    local gone = {}
    for _, category in ipairs(BAG.CONSUMABLES) do gone[BAG.STOCK_ITEMS[category]] = true end
    for _, entry in ipairs(contents(bag)) do
        if gone[entry.def] or entry.def:sub(1, #BAG.DRUG_PREFIX) == BAG.DRUG_PREFIX then
            i:destroyInventoryItem(entry.uid)
        elseif entry.def == BAG.OXYGEN_ITEM then
            setCylinder(entry.uid, 0)
        end
    end
    bag.displayKey = nil
    refreshBagDisplay(bag)
end

function setCylinder(uid, level)
    local old = oxygenLevel[uid]
    oxygenLevel[uid] = level
    if old == nil or math.floor(old + 0.5) ~= math.floor(level + 0.5) then
        local i = inv()
        i:setItemMeta(uid, "oxygen", level)
        i:setItemMeta(uid, "bar", { label = L.msg("med_bag.hud.oxygen_label"), value = math.floor(level + 0.5), max = 100 })
    end
end

-- ---------------------------------------------------------------------------------------------
-- Serving items
-- ---------------------------------------------------------------------------------------------

-- Distance of the item to the target (0: stowed in the ambulance the target sits in), or nil
function itemDistance(item, target)
    if not isElement(target) then return nil end
    if item.state == "stowed" then
        local vehicle = getElementType(target) ~= "vehicle" and getPedOccupiedVehicle(target)
        return (vehicle and vehicle == item.kit.vehicle) and 0 or nil
    end
    if item.state ~= "carried" and item.state ~= "ground" and item.state ~= "stretcher" then return nil end
    local x, y, z, dim, int = itemPosition(item)
    if not x or dim ~= getElementDimension(target) or int ~= getElementInterior(target) then return nil end
    local tx, ty, tz = rootPosition(target) -- a patient on a pushed stretcher
    return getDistanceBetweenPoints3D(x, y, z, tx, ty, tz)
end

function itemServes(item, target, range)
    local d = itemDistance(item, target)
    return d ~= nil and d <= (range or BAG.USE_RANGE)
end

-- Items of a kind serving the target, the medic's own carried one first, then by distance
function getServingItems(target, kind, medic, range)
    local list = {}
    for _, item in pairs(Items) do
        if item.kind == kind then
            local d = itemDistance(item, target)
            if d and d <= (range or BAG.USE_RANGE) then
                list[#list + 1] = { item = item, d = (medic and item.carrier == medic) and -1 or d }
            end
        end
    end
    table.sort(list, function(a, b) return a.d < b.d end)
    for i, entry in ipairs(list) do list[i] = entry.item end
    return list
end

-- ---------------------------------------------------------------------------------------------
-- Stock
-- ---------------------------------------------------------------------------------------------

-- Drug display names from medsys (MEDIC_DRUGS), cached
local drugNames
function drugName(id)
    if not drugNames and isMedsysRunning() then drugNames = exports[MEDSYS]:getDrugNames() or nil end
    return drugNames and drugNames[id] or id
end

local STOCK_LABELS = {
    ivKits = "med_bag.stock.iv_kits", oxygen = "med_bag.stock.oxygen", bandages = "med_bag.stock.bandages",
    splints = "med_bag.stock.splints", glucometers = "med_bag.stock.glucometer", airwayKits = "med_bag.stock.airway_kit",
}
function stockLabel(category, key)
    if category == "drugs" then return drugName(key) end
    if STOCK_LABELS[category] then return L.msg(STOCK_LABELS[category]) end
    return tostring(key or category)
end

-- Warns the crew once when a counted item gets low / runs out (reset by a restock)
local function checkLow(bag, category, key)
    local amount, full = stockAmount(bag, category, key), fullAmount(category, key)
    if amount == nil or not full or full <= 0 then return end
    bag.warned = bag.warned or {}
    local flag = category .. ":" .. tostring(key)
    local label = stockLabel(category, key)
    if amount <= 0 then
        if bag.warned[flag] ~= "out" then
            bag.warned[flag] = "out"
            notifyCrew(bag.kit, L.msg("med_bag.stock.medical_bag_is_out_restock_at", { kit = kitLabel(bag.kit), label = label }), true)
        end
    elseif amount <= full * (category == "oxygen" and BAG.OXYGEN_LOW / 100 or BAG.LOW_STOCK_FRACTION) then
        if not bag.warned[flag] then
            bag.warned[flag] = "low"
            notifyCrew(bag.kit, L.msg("med_bag.stock.medical_bag_is_running_low", { kit = kitLabel(bag.kit), label = label }))
        end
    end
end

-- Takes amount (default 1) from the bag. True if it was there (or is not counted).
function consume(bag, category, key, amount)
    local def = stockDef(category, key)
    if not def then return true end  -- not counted
    amount = amount or 1
    if category == "oxygen" then
        local cyl, level = bestCylinder(bag)
        if not cyl or level <= 0 then return false end
        setCylinder(cyl.uid, math.max(0, level - amount))
    else
        local stack
        for _, entry in ipairs(contents(bag)) do
            if entry.def == def then stack = entry break end
        end
        if not stack then return false end
        inv():takeItemAmount(stack.uid, math.min(stack.amount, math.max(1, math.floor(amount + 0.5))))
    end
    checkLow(bag, category, key)
    refreshBagDisplay(bag)
    return true
end

function restock(bag)
    if not Items[bag.id] then return false end
    fillBag(bag)
    return true
end

-- Sum of the stock of every bag serving the target (what the medic can reach). Uncounted drugs
-- are left out (nil = unlimited on the medsys side).
function getReachableStock(target, medic)
    local bags = getServingItems(target, "bag", medic)
    if #bags == 0 then return nil end
    local total = { drugs = {}, oxygen = 0 }
    for category in pairs(BAG.STOCK_ITEMS) do total[category] = 0 end
    local byDef = {}
    for category, def in pairs(BAG.STOCK_ITEMS) do byDef[def] = category end
    for _, bag in ipairs(bags) do
        for _, entry in ipairs(contents(bag)) do
            local def = entry.def
            if byDef[def] then
                total[byDef[def]] = total[byDef[def]] + entry.amount
            elseif def == BAG.OXYGEN_ITEM then
                total.oxygen = math.max(total.oxygen, cylinderLevel(entry))
            elseif def:sub(1, #BAG.DRUG_PREFIX) == BAG.DRUG_PREFIX then
                local id = def:sub(#BAG.DRUG_PREFIX + 1)
                total.drugs[id] = (total.drugs[id] or 0) + entry.amount
            end
        end
    end
    -- a drug that has an item but none in the bags is out (0), not unlimited
    if isInventoryRunning() then
        for id in pairs(BAG.STOCK.drugs) do
            if total.drugs[id] == nil and inv():getItemDef(BAG.DRUG_PREFIX .. id) then total.drugs[id] = 0 end
        end
    end
    total.oxygen = math.floor(total.oxygen + 0.5)
    return total
end

-- A serving bag that has the stock (the medic's own first), or false
function findStockBag(target, medic, category, key, range)
    for _, bag in ipairs(getServingItems(target, "bag", medic, range)) do
        if hasStock(bag, category, key) then return bag end
    end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Oxygen + monitor links (1 s tick)
-- ---------------------------------------------------------------------------------------------

local function removeFromPatient(target, kind, message)
    if isMedsysRunning() and isElement(target) then
        exports[MEDSYS]:removePatientEquipment(target, kind, message)
    end
end

-- The session also starts without a bag with oxygen: the tick then takes the mask off / leaves an
-- intubated patient without oxygen (the tube has no effect) until a bag with oxygen is in range.
function startOxygen(target, medic)
    local bag = findStockBag(target, medic, "oxygen")
    Oxygen[target] = { item = bag and bag.id or nil }
    return bag and bag.id or false
end

function stopOxygen(target)
    Oxygen[target] = nil
end

function unlinkMonitor(target)
    local id = MonitorLinks[target]
    MonitorLinks[target] = nil
    if id and linkedPatient[id] == target then linkedPatient[id] = nil end
end

-- Links the nearest serving monitor (the medic's own first) to the patient. A monitor already on
-- another patient is taken off there.
function linkMonitor(target, medic)
    local monitor = getServingItems(target, "monitor", medic)[1]
    if not monitor then return false end
    unlinkMonitor(target)
    local other = linkedPatient[monitor.id]
    if other and other ~= target then
        unlinkMonitor(other)
        removeFromPatient(other, "monitor", L.msg("med_bag.stock.monitor_disconnected_attached_to_another_patient"))
    end
    MonitorLinks[target] = monitor.id
    linkedPatient[monitor.id] = target
    return monitor.id
end

function getLinkedPatient(itemId)
    return linkedPatient[itemId]
end

local lastTick = getTickCount()

local function tick()
    local now = getTickCount()
    local dt = (now - lastTick) / 1000
    lastTick = now
    if not isMedsysRunning() then
        Oxygen, MonitorLinks, linkedPatient = {}, {}, {}
        return
    end
    local medsys = exports[MEDSYS]

    for target, session in pairs(Oxygen) do
        local state = isElement(target) and medsys:getMedicalState(target)
        if not state or state.dead or not (state.oxygenMask or state.intubated) then
            Oxygen[target] = nil
        else
            local bag = session.item and Items[session.item]
            if not bag or not itemServes(bag, target, BAG.CONNECT_RANGE) or not hasStock(bag, "oxygen") then
                -- another bag at the patient takes over
                local other = findStockBag(target, nil, "oxygen", nil, BAG.CONNECT_RANGE)
                if other then
                    session.item, bag = other.id, other
                else
                    bag = nil
                    if not session.starved then
                        local empty = session.item and Items[session.item]
                            and itemServes(Items[session.item], target, BAG.CONNECT_RANGE)
                        local what = state.intubated and L.msg("med_bag.stock.tube_has_no_effect") or L.msg("med_bag.stock.mask_removed")
                        removeFromPatient(target, "oxygen", (empty and L.msg("med_bag.stock.oxygen_cylinder_empty") or
                            (session.item and L.msg("med_bag.stock.oxygen_disconnected_bag_is_too_far") or L.msg("med_bag.stock.no_oxygen"))) .. what)
                        if state.intubated then
                            session.starved = true  -- keeps looking for a bag with oxygen
                        else
                            Oxygen[target] = nil    -- the mask is off, the session ends
                        end
                    end
                end
            end
            if bag then
                if session.starved then
                    session.starved = nil
                    medsys:restorePatientEquipment(target, "oxygen", L.msg("med_bag.stock.oxygen_connected_ventilating_with_oxygen"))
                end
                consume(bag, "oxygen", nil, BAG.OXYGEN_DRAIN * dt)
            end
        end
    end

    for target, id in pairs(MonitorLinks) do
        local state = isElement(target) and medsys:getMedicalState(target)
        if not state or state.dead or not state.monitor then
            unlinkMonitor(target)
        else
            local monitor = Items[id]
            if not monitor or not itemServes(monitor, target, BAG.CONNECT_RANGE) then
                unlinkMonitor(target)
                removeFromPatient(target, "monitor", L.msg("med_bag.stock.monitor_disconnected_attach_it_again"))
            end
        end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(tick, 1000, 0)
end)

-- medsys restarted: its patients lost their masks / monitors; the drug names may have changed
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= MEDSYS then return end
    Oxygen, MonitorLinks, linkedPatient, drugNames = {}, {}, {}, nil
end)

-- A medic moved things between bags: refresh the lines of the bags involved
addEventHandler("onInventoryItemMoved", root, function(uid, defId, from, to)
    for _, loc in ipairs({ from, to }) do
        local bag = loc and loc.type == "container" and Items[loc.container]
        if bag and bag.kind == "bag" then refreshBagDisplay(bag) end
    end
end)

addEventHandler("onInventoryItemDestroyed", root, function(uid)
    oxygenLevel[uid] = nil
end)

-- An item that is gone cannot feed a patient any more: the tick notices it
function onItemGone(item)
    local target = linkedPatient[item.id]
    if target then
        unlinkMonitor(target)
        removeFromPatient(target, "monitor", L.msg("med_bag.stock.monitor_disconnected"))
    end
end
