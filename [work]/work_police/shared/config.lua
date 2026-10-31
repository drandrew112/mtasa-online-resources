if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- work_police - shared configuration. Only LSPD for now (the user's decision); no blips anywhere.
-- Positions: the user measured them (2026-10-30). Fine-tune with work_core's /workpos.

POLICE_WORK = {
    WORK_ID = "police",
    NAME = "Police",
    DESCRIPTION = L.text("work_police.config.description"),
    COLOR = { 40, 100, 220 },

    SKINS = {
        { model = 280, name = L.text("work_police.config.skin_ls_officer") },
        { model = 281, name = L.text("work_police.config.skin_sf_officer") },
        { model = 282, name = L.text("work_police.config.skin_lv_officer") },
        { model = 283, name = L.text("work_police.config.skin_county_sheriff") },
        { model = 284, name = L.text("work_police.config.skin_motorbike_officer") },
        { model = 288, name = L.text("work_police.config.skin_desert_sheriff") },
    },

    -- work levels = ranks (police_system decides the rights by them: Hadnagy 7 warrants of others, Százados 9 fines)
    MAX_LEVEL = 15,
    LEVEL_XP = 600,
    LEVEL_STEP = 300,
    LEVEL_NAMES = {
        [1] = L.text("work_police.rank.1"), [2] = L.text("work_police.rank.2"), [3] = L.text("work_police.rank.3"),
        [4] = L.text("work_police.rank.4"), [5] = L.text("work_police.rank.5"), [6] = L.text("work_police.rank.6"),
        [7] = L.text("work_police.rank.7"), [8] = L.text("work_police.rank.8"), [9] = L.text("work_police.rank.9"),
        [10] = L.text("work_police.rank.10"), [11] = L.text("work_police.rank.11"), [12] = L.text("work_police.rank.12"),
        [13] = L.text("work_police.rank.13"), [14] = L.text("work_police.rank.14"), [15] = L.text("work_police.rank.15"),
    },

    -- vehicles (no platePrefix: a unique number plate). 597 (GTA5 police car) later.
    PLATE_PREFIX = "",
    PLATE_DIGITS = 6,
    VEHICLES = {
        { model = 596, name = L.text("work_police.config.crown_victoria"),
          tuning = { engine = 2, turbo = 2, brakes = 2 } },
        { model = 598, name = L.text("work_police.config.skoda_octavia"), paintjob = "hu_pd", elsExtra = 1,
          tuning = { engine = 2, turbo = 2, brakes = 2, driveType = "awd" } },
        { model = 599, name = L.text("work_police.config.police_ranger"), level = 2,
          tuning = { engine = 2, turbo = 2, brakes = 2 } },
        -- { model = 597, name = "GTA5 police car" },   -- later
    },

    STATIONS = {
        {
            name = L.text("work_police.config.lspd"),
            duty = { 1560.83, -1682.97, 15.20 },
            blip = false,
            vehicle = {
                marker = { 1560.49, -1694.36, 4.90 },
                spawns = {
                    { 1566.09, -1710.58, 5.47, 0 },
                    { 1570.39, -1710.41, 5.47, 0 },
                    { 1575.00, -1709.63, 5.47, 0 },
                    { 1579.06, -1710.70, 5.47, 0 },
                    { 1583.74, -1710.96, 5.47, 0 },
                    { 1587.77, -1710.66, 5.47, 0 },
                },
            },
        },
    },
}
end)
