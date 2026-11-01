-- Equipment level exports (shared/equipment.lua). The bag and stretcher modules rescan on a change
-- of the element data, so setting it directly works as well.

-- level: "bls" | "als" | true (= EQUIPMENT.DEFAULT_LEVEL) | false / nil (no equipment) -> true | false
function setVehicleEquipment(vehicle, level)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    if level == true then level = EQUIPMENT.DEFAULT_LEVEL end
    if level and not EQUIPMENT.LEVELS[level] then return false end
    if getElementData(vehicle, EQUIPMENT.DATA_KEY) ~= (level or nil) then
        if level then setElementData(vehicle, EQUIPMENT.DATA_KEY, level)
        else removeElementData(vehicle, EQUIPMENT.DATA_KEY) end
    end
    return true
end

-- "bls" | "als" | false
function getVehicleEquipment(vehicle)
    return getEquipmentLevel(vehicle) or false
end
