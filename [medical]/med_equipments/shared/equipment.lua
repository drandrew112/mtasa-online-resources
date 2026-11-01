-- Which vehicles carry EMS equipment (the bag kit and the stretcher). The model alone is not enough:
-- only vehicles handed out by the EMS work (work_ems) get it, marked with the element data below.
-- The value is the equipment level; the bag module decides what a level contains (BAG.LEVELS).
-- "basic" = only the stretcher (a work_ems vehicle before its crew signs in on the ERM tablet);
-- med_erm sets "bls" / "als" by the unit type at sign-in and "basic" again at sign-out.
-- The models that can carry it at all stay in BAG.VEHICLE_MODELS / STRETCHER.VEHICLE_MODELS.

EQUIPMENT = {
    DATA_KEY = "med.equipment",    -- vehicle element data: "basic" | "bls" | "als" (work_ems, med_erm)
    LEVELS = { basic = true, bls = true, als = true },
    DEFAULT_LEVEL = "als",         -- setVehicleEquipment(vehicle, true)
}

-- The vehicle's equipment level ("basic" | "bls" | "als") or nil when it carries none
function getEquipmentLevel(vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return nil end
    local level = getElementData(vehicle, EQUIPMENT.DATA_KEY)
    return EQUIPMENT.LEVELS[level] and level or nil
end
