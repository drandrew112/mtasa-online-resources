-- police_system / shared/reasons.lua
-- Predefined reasons. Wanted (GTA wanted level): id -> base level; external scripts add them with
-- exports.police_system:addWanted(player, id [, level]). Warrants: the BTK crimes / public order items
-- (btk.json "warrant": true, their "minutes" = jail time) plus the three below.
-- Text: police_system.reason.<id>, police_system.btk.<id> (the keys are listed literally at the bottom, so the
-- v_locals build keeps them).

WANTED_REASONS = {
    failure_to_stop   = { level = 1 },
    evading_police    = { level = 2 },
    ramming_police    = { level = 2 },
    shots_near_police = { level = 2 },
    shots_at_police   = { level = 3 },
    police_down       = { level = 4 },
    police_vehicle_destroyed = { level = 3 },
    shop_robbery      = { level = 2 },
    vehicle_theft     = { level = 1 },
    assault           = { level = 1 },
    robbery           = { level = 2 },
    homicide          = { level = 3 },
    reckless_driving  = { level = 1 },
    escape_custody    = { level = 3 },
    public_shooting   = { level = 2 },
    dirty_money       = { level = 2 },   -- biz_core: dirty money withdrawn from a company
}

-- extra warrant reasons (not in the penal code)
WARRANT_EXTRA = {
    { id = "unpaid_fines", minutes = 2 },
    { id = "escape_custody", minutes = 5 },
    { id = "evading_arrest", minutes = 4 },
}

-- text keys (literal list for the v_locals build)
POLICE_TEXT_KEYS = {
    "police_system.reason.failure_to_stop", "police_system.reason.evading_police", "police_system.reason.ramming_police",
    "police_system.reason.shots_near_police", "police_system.reason.shots_at_police", "police_system.reason.police_down",
    "police_system.reason.police_vehicle_destroyed", "police_system.reason.shop_robbery", "police_system.reason.vehicle_theft",
    "police_system.reason.assault", "police_system.reason.robbery", "police_system.reason.homicide",
    "police_system.reason.reckless_driving", "police_system.reason.escape_custody", "police_system.reason.public_shooting",
    "police_system.reason.dirty_money",
    "police_system.reason.unpaid_fines", "police_system.reason.evading_arrest",
    "police_system.btk_cat.traffic", "police_system.btk_cat.parking", "police_system.btk_cat.vehicle",
    "police_system.btk_cat.pedestrian", "police_system.btk_cat.public", "police_system.btk_cat.order",
    "police_system.btk_cat.crimes", "police_system.btk_cat.warnings",
    "police_system.btk.traffic.speeding", "police_system.btk.traffic.red_light", "police_system.btk.traffic.failure_to_yield",
    "police_system.btk.traffic.illegal_overtaking", "police_system.btk.traffic.wrong_way",
    "police_system.btk.traffic.reckless_driving", "police_system.btk.traffic.obstructing_emergency",
    "police_system.btk.traffic.street_racing", "police_system.btk.parking.no_parking",
    "police_system.btk.parking.sidewalk_parking", "police_system.btk.parking.crosswalk_parking",
    "police_system.btk.parking.blocking_access", "police_system.btk.vehicle.no_plate",
    "police_system.btk.vehicle.invalid_registration", "police_system.btk.vehicle.expired_inspection",
    "police_system.btk.vehicle.unsafe_vehicle", "police_system.btk.vehicle.illegal_modification",
    "police_system.btk.pedestrian.jaywalking", "police_system.btk.pedestrian.ped_red_light",
    "police_system.btk.pedestrian.restricted_road", "police_system.btk.pedestrian.trespassing",
    "police_system.btk.pedestrian.obstructing_traffic", "police_system.btk.public.littering",
    "police_system.btk.public.noise", "police_system.btk.public.drunk_disorder", "police_system.btk.public.public_urination",
    "police_system.btk.public.graffiti", "police_system.btk.order.obstruction", "police_system.btk.order.ignoring_order",
    "police_system.btk.order.false_identity", "police_system.btk.order.false_report", "police_system.btk.order.brawling",
    "police_system.btk.order.harassment", "police_system.btk.crime.theft", "police_system.btk.crime.vehicle_theft",
    "police_system.btk.crime.robbery", "police_system.btk.crime.burglary", "police_system.btk.crime.assault",
    "police_system.btk.crime.homicide", "police_system.btk.warning.minor_speeding", "police_system.btk.warning.no_indicator",
    "police_system.btk.warning.minor_parking", "police_system.btk.warning.no_seatbelt", "police_system.btk.warning.minor_defect",
    "police_system.btk.warning.minor_disorder", "police_system.btk.warning.minor_pedestrian",
}

function wantedReasonKey(id) return "police_system.reason." .. tostring(id) end
function btkKey(id) return "police_system.btk." .. tostring(id) end
function btkCategoryKey(id) return "police_system.btk_cat." .. tostring(id) end
