if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- work_bloodtransport - shared configuration.
-- Positions come from /hosppos (on foot: the duty marker; in a vehicle: the vehicle marker and spawns).

BTWORK = {
    WORK_ID = "bloodtransport",
    NAME = L.text("work_bloodtransport.config.name"),
    DESCRIPTION = L.text("work_bloodtransport.config.description"),
    COLOR = { 200, 40, 60 },
    BLIP = 14,

    -- Outfits (work_core picks one at duty start; the player can change it at the marker)
    SKINS = {
        { model = 70, name = L.text("work_bloodtransport.config.skin_lab_coat") },
        { model = 17, name = L.text("work_bloodtransport.config.skin_suit") },
        { model = 98, name = L.text("work_bloodtransport.config.skin_business") },
        { model = 150, name = L.text("work_bloodtransport.config.skin_business_woman") },
    },

    -- Work levels (work_core). XP per delivered task is given by bt_dispatch.
    MAX_LEVEL = 10,
    LEVEL_XP = 500,
    LEVEL_STEP = 250,
    LEVEL_NAMES = {
        [1] = L.text("work_bloodtransport.config.level_trainee"), [3] = L.text("work_bloodtransport.config.level_courier"),
        [6] = L.text("work_bloodtransport.config.level_senior_courier"), [9] = L.text("work_bloodtransport.config.level_chief_courier"),
    },

    PLATE_PREFIX = "BT-",
    PLATE_DIGITS = 4,
    VEHICLES = {
        { model = 415, name = L.text("work_bloodtransport.config.vehicle"), sirenType = "soundoff" },
        { model = 598, name = L.text("work_bloodtransport.config.vehicle_ovsz"), paintjob = "hu_ovsz", elsExtra = 1,
          sirenType = "fsvas320",
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60, driveType = "awd" } },
    },

    -- Stations: duty marker, vehicle marker and the vehicle spawn points { x, y, z, rot }
    STATIONS = {
        {
            name = "Los Santos",
            duty = { 926.16626, -1435.76489, 12.33220 },
            vehicle = {
                marker = { 924.97876, -1432.19080, 12.44920 },
                spawns = {
                    { 924.64, -1440.80, 13.35, 0 },
                    { 924.84, -1452.79, 13.39, 0 },
                    { 924.83, -1461.12, 13.45, 0 },
                },
            },
        },
        {
            name = "Las Venturas",
            duty = { 1366.76, 1901.08, 10.47 },
            vehicle = {
                marker = { 1367.46, 1905.18, 10.47 },
                spawns = {
                    { 1374.51, 1901.51, 11.02, 270 },
                    { 1380.28, 1886.47, 10.76, 0 },
                    { 1380.26, 1893.91, 10.75, 0 },
                    { 1380.24, 1903.41, 10.76, 0 },
                },
            },
        },
        {
            name = "San Fierro",
            duty = { -2713.57, 130.52, 3.34 },
            vehicle = {
                marker = { -2712.94, 134.71, 3.34 },
                spawns = {
                    { -2712.46, 124.02, 4.27, 0 },
                    { -2712.47, 114.86, 4.27, 0 },
                    { -2712.23, 143.34, 4.27, 0 },
                },
            },
        },
    },
}
end)
