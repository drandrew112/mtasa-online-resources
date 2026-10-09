-- Equipment adapter (med_bag). Interventions need the medical bag / the monitor near the patient
-- (MEDIC_EQUIPMENT); the bag's consumables (medicines, IV kits, oxygen) run out. Everything goes
-- through this file, so medsys works unchanged when MEDIC.REQUIRE_EQUIPMENT is false or med_bag is
-- not running (then no equipment is asked for at all).
-- Tutorial patients (setTutorialPatient) need no equipment either, unless they were marked with
-- useEquipment (the EMS tutorial teaches the bag and the monitor on its patient).

local function isRunning(name)
    local resource = getResourceFromName(name)
    return resource and getResourceState(resource) == "running"
end

-- Is the equipment checked right now
function isEquipmentActive()
    return MEDIC.REQUIRE_EQUIPMENT == true and isRunning(MEDIC.EQUIPMENT_RESOURCE)
end

local function bagResource()
    return exports[MEDIC.EQUIPMENT_RESOURCE]
end

local function isExempt(target)
    return isEquipmentExemptPatient(target)
end

local ITEM_MISSING = { bag = "Needs the medical bag", monitor = "Needs the monitor" }
local STOCK_EMPTY = { ivKits = "Out of IV kits - restock at a hospital", oxygen = "Oxygen cylinder empty" }

-- What reaches the patient (med_bag getEquipmentNear) or nil when the equipment is not checked.
-- One call per panel snapshot / treatment start.
function getPatientEquipment(target, medic)
    if not isEquipmentActive() or isExempt(target) then return nil end
    local ok, result = pcall(function() return bagResource():getEquipmentNear(target, medic) end)
    return ok and result or nil
end

-- Can the action be done with the equipment at hand? -> true | false, reason
-- equipment: the result of getPatientEquipment (nil = not checked)
function checkActionEquipment(equipment, action, state, option)
    if not equipment then return true end
    local need = MEDIC_EQUIPMENT[action]
    if not need then return true end
    -- taking the mask off needs nothing
    if action == "oxygen" and state and state.oxygenMask then return true end
    if not equipment[need.item] then return false, ITEM_MISSING[need.item] end
    local stock = equipment.stock
    if need.stock and stock and (stock[need.stock] or 0) <= 0 then
        return false, STOCK_EMPTY[need.stock]
    end
    if action == "medication" and option and stock then
        local left = stock.drugs[option]
        if left ~= nil and left <= 0 then
            local drug = MEDIC_DRUGS[option]
            return false, (drug and drug.name or option) .. " - out of stock"
        end
    end
    return true
end

-- Applies the equipment rules to the availability table of the panel
function applyEquipmentAvailability(result, equipment, state)
    if not equipment then return end
    for action in pairs(MEDIC_EQUIPMENT) do
        if result[action] == true then
            local ok, reason = checkActionEquipment(equipment, action, state)
            if not ok then result[action] = reason end
        end
    end
end

-- The panel's view of the equipment: { bag, monitor, stock } (nil = not checked)
function getEquipmentSnapshot(equipment)
    if not equipment then return nil end
    return { bag = equipment.bag and true or false, monitor = equipment.monitor and true or false, stock = equipment.stock }
end

-- ---------------------------------------------------------------------------------------------
-- Treatment hooks (server/treatment.lua)
-- ---------------------------------------------------------------------------------------------

local function call(fn, ...)
    if not isEquipmentActive() then return nil end
    local args = { ... }
    local ok, result = pcall(function()
        local res = bagResource()
        return res[fn](res, unpack(args))
    end)
    if not ok then outputDebugString("[medsys] med_bag:" .. fn .. " failed: " .. tostring(result), 2) end
    return ok and result or nil
end

-- Before a procedure starts. -> true | false, reason
function onEquipmentTreatmentCheck(medic, target, action, option, state)
    local equipment = getPatientEquipment(target, medic)
    return checkActionEquipment(equipment, action, state, option)
end

-- The procedure started (minigame / timer running)
function onEquipmentTreatmentStart(medic, target, action)
    if isExempt(target) then return end
    call("onTreatmentStart", medic, target)
    -- an IV attempt uses a kit whatever the result
    if action == "iv" and getPatientEquipment(target, medic) then
        local item = call("findStockItem", target, medic, "ivKits")
        if item then call("consumeStock", item, "ivKits") end
    end
end

-- The procedure finished with success (state already updated by apply)
function onEquipmentTreatmentDone(medic, target, action, option, state)
    if not isEquipmentActive() or isExempt(target) then return end
    if action == "medication" then
        local item = call("findStockItem", target, medic, "drugs", option)
        if item then call("consumeStock", item, "drugs", option) end
    elseif action == "oxygen" then
        if state.oxygenMask then call("startPatientOxygen", target, medic) else call("stopPatientOxygen", target) end
    elseif action == "airway" then
        -- the ventilated patient breathes oxygen from the bag too; without any the tube does nothing
        call("startPatientOxygen", target, medic)
    elseif action == "monitor" then
        call("linkPatientMonitor", target, medic)
    end
end

-- Glucometer reading (no stock): only the bag must be there
function checkGlucometerEquipment(medic, target)
    return checkActionEquipment(getPatientEquipment(target, medic), "glucometer")
end

-- ---------------------------------------------------------------------------------------------
-- Called by med_bag
-- ---------------------------------------------------------------------------------------------

-- med_bag takes the oxygen mask ("oxygen") or the monitor ("monitor") off the patient: the bag went
-- away / the cylinder is empty / the monitor was carried away. message is shown on the panels.
function removePatientEquipment(target, kind, message)
    local state = isElement(target) and Patients[target]
    if not state or state.dead then return false end
    if kind == "oxygen" then
        if state.intubated then
            -- the tube stays but has no effect until oxygen is back (isVentilated)
            if state.noOxygen then return false end
            state.noOxygen = true
            if message then notifyExaminers(target, message, true) end
            sendPanelUpdates(state)
            return true
        end
        if not state.oxygenMask then return false end
        state.oxygenMask = false
    elseif kind == "monitor" then
        if not state.monitor then return false end
        state.monitor = nil
    else
        return false
    end
    writeVitalsData(state)
    if message then notifyExaminers(target, message, true) end
    sendPanelUpdates(state)
    return true
end

-- med_bag found oxygen again for an intubated patient (a bag came back / another bag): the tube works
function restorePatientEquipment(target, kind, message)
    local state = isElement(target) and Patients[target]
    if not state or state.dead or kind ~= "oxygen" or not state.noOxygen then return false end
    state.noOxygen = nil
    if message then notifyExaminers(target, message, false) end
    sendPanelUpdates(state)
    return true
end

-- med_bag (re)started: it forgot its oxygen sessions, so nobody may stay without oxygen
addEventHandler("onResourceStart", root, function(resource)
    if getResourceName(resource) ~= MEDIC.EQUIPMENT_RESOURCE then return end
    for _, state in pairs(Patients) do state.noOxygen = nil end
end)

-- { [drugId] = display name } for med_bag's messages
function getDrugNames()
    local names = {}
    for id, drug in pairs(MEDIC_DRUGS) do names[id] = drug.name end
    return names
end
