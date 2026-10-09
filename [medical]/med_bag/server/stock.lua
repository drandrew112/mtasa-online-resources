-- Consumables of the bags, the oxygen drain and the monitor links.
--
-- Which item serves a patient: same dimension / interior and within BAG.USE_RANGE of the patient
-- (carried, on the ground or on the stretcher's side), or stowed in the very ambulance the patient
-- sits in. A connected item (oxygen source, linked monitor) keeps working up to BAG.CONNECT_RANGE.
-- The medic's own carried item comes first, then the nearest one.
--
-- medsys (server/equipment.lua there) drives everything through the exports in server/exports.lua:
-- it asks what is near the patient before showing / starting an action, consumes after it, and
-- tells med_bag about an oxygen mask put on / a monitor attached. The 1 s tick here then drains
-- the oxygen and checks that the cylinder (the bag) and the monitor stay with the patient; if not,
-- it asks medsys to take the mask / the monitor off (removePatientEquipment).
-- Oxygen is used continuously by a patient with the mask on or intubated (ventilated): at the scene,
-- on the stretcher, in the ambulance (from the stowed bag) and at the handover. An intubated patient
-- without oxygen keeps the tube but it has no effect (medsys noOxygen) until a bag with oxygen is in
-- range again.

local MEDSYS = "medsys"

Oxygen = {}       -- patient -> { item = id }
MonitorLinks = {} -- patient -> item id
local linkedPatient = {} -- monitor item id -> patient

local function isMedsysRunning()
    local res = getResourceFromName(MEDSYS)
    return res and getResourceState(res) == "running"
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
    local x, y, z, src = itemPosition(item)
    if not x or not isElement(target) or not bagSameWorld(src, target) then return nil end
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

-- Remaining amount, or nil when the key is not counted (unlimited)
function stockAmount(item, category, key)
    local stock = item.stock
    if not stock then return 0 end
    if category == "drugs" then return stock.drugs[key] end
    return stock[category]
end

local function fullAmount(category, key)
    if category == "drugs" then return BAG.STOCK.drugs[key] end
    return BAG.STOCK[category]
end

function hasStock(item, category, key)
    local amount = stockAmount(item, category, key)
    return amount == nil or amount > 0
end

-- Drug display names from medsys (MEDIC_DRUGS), cached
local drugNames
function drugName(id)
    if not drugNames and isMedsysRunning() then drugNames = exports[MEDSYS]:getDrugNames() or nil end
    return drugNames and drugNames[id] or id
end

function stockLabel(category, key)
    if category == "drugs" then return drugName(key) end
    if category == "ivKits" then return "IV kits" end
    if category == "oxygen" then return "Oxygen" end
    return tostring(key or category)
end

-- Warns the crew once when a counted item gets low / runs out (reset by a restock)
local function checkLow(item, category, key)
    local amount, full = stockAmount(item, category, key), fullAmount(category, key)
    if amount == nil or not full or full <= 0 then return end
    item.warned = item.warned or {}
    local flag = category .. ":" .. tostring(key)
    local label = stockLabel(category, key)
    if amount <= 0 then
        if item.warned[flag] ~= "out" then
            item.warned[flag] = "out"
            notifyCrew(item.kit, ("Medical bag (%s): %s is out. Restock at a hospital."):format(kitLabel(item.kit), label), true)
        end
    elseif amount <= full * (category == "oxygen" and BAG.OXYGEN_LOW / 100 or BAG.LOW_STOCK_FRACTION) then
        if not item.warned[flag] then
            item.warned[flag] = "low"
            notifyCrew(item.kit, ("Medical bag (%s): %s is running low."):format(kitLabel(item.kit), label))
        end
    end
end

function consume(item, category, key, amount)
    local current = stockAmount(item, category, key)
    if current == nil then return true end  -- not counted
    if current <= 0 then return false end
    local left = math.max(0, current - (amount or 1))
    if category == "drugs" then item.stock.drugs[key] = left else item.stock[category] = left end
    checkLow(item, category, key)
    onStockChanged(item)
    return true
end

function restock(item)
    if not item.stock then return false end
    item.stock = fullStock()
    item.warned = nil
    onStockChanged(item)
    return true
end

-- Sum of the stock of every bag serving the target (what the medic can reach). Uncounted drugs
-- are left out (nil = unlimited on the medsys side).
function getReachableStock(target, medic)
    local bags = getServingItems(target, "bag", medic)
    if #bags == 0 then return nil end
    local total = { drugs = {}, ivKits = 0, oxygen = 0 }
    for _, bag in ipairs(bags) do
        for id, count in pairs(bag.stock.drugs) do total.drugs[id] = (total.drugs[id] or 0) + count end
        total.ivKits = total.ivKits + bag.stock.ivKits
        total.oxygen = math.max(total.oxygen, bag.stock.oxygen)
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
        removeFromPatient(other, "monitor", "Monitor disconnected - attached to another patient")
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
                        local what = state.intubated and "the tube has no effect" or "mask removed"
                        removeFromPatient(target, "oxygen", (empty and "Oxygen cylinder empty - " or
                            (session.item and "Oxygen disconnected, the bag is too far - " or "No oxygen - ")) .. what)
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
                    medsys:restorePatientEquipment(target, "oxygen", "Oxygen connected - ventilating with oxygen")
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
                removeFromPatient(target, "monitor", "Monitor disconnected - attach it again")
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

-- An item that is gone or back in the ambulance cannot feed a patient any more: the tick notices it
function onItemGone(item)
    local target = linkedPatient[item.id]
    if target then
        unlinkMonitor(target)
        removeFromPatient(target, "monitor", "Monitor disconnected")
    end
end
