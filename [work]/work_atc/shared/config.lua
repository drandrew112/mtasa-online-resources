if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- work_atc - shared configuration.
-- Positions: fine-tune with work_core's /workpos (on foot: marker point).

ATC = {
    WORK_ID = "atc",                 -- must match AVI.MARKER_WORK in avi_core
    NAME = L.text("work_atc.config.air_traffic_control"),
    DESCRIPTION = L.text("work_atc.config.air_traffic_controller_san_andreas_control"),
    COLOR = { 70, 130, 210 },

    -- Outfits (the Supervisor outfit unlocks at the last level)
    SKINS = {
        { model = 147,  name = L.text("work_atc.config.controller") },
        { model = 186,  name = L.text("work_atc.config.controller_casual") },
        { model = 265, name = L.text("work_atc.config.supervisor"), level = 14 },
    },

    -- Level table: XP curve + name and ATC rights of each level. Rights are cumulative by design
    -- (a higher rank keeps the lower positions). Rights: TWR / APP / RADAR (avi_core).
    -- XP is given by the aviation system through work_core:giveWorkXp(player, "atc", xp).
    LEVEL_BASE_XP = 400,
    LEVEL_STEP_XP = 250,
    LEVELS = {
        [1]  = { name = L.text("work_atc.config.trainee"),                    rights = { "TWR" } },
        [2]  = { name = L.text("work_atc.config.tower_controller_bronze"),    rights = { "TWR" } },
        [3]  = { name = L.text("work_atc.config.tower_controller_silver"),    rights = { "TWR" } },
        [4]  = { name = L.text("work_atc.config.tower_controller_gold"),      rights = { "TWR" } },
        [5]  = { name = L.text("work_atc.config.approach_controller_bronze"), rights = { "TWR", "APP" } },
        [6]  = { name = L.text("work_atc.config.approach_controller_silver"), rights = { "TWR", "APP" } },
        [7]  = { name = L.text("work_atc.config.approach_controller_gold"),   rights = { "TWR", "APP" } },
        [8]  = { name = L.text("work_atc.config.radar_controller_bronze"),    rights = { "TWR", "APP", "RADAR" } },
        [9]  = { name = L.text("work_atc.config.radar_controller_silver"),    rights = { "TWR", "APP", "RADAR" } },
        [10] = { name = L.text("work_atc.config.radar_controller_gold"),      rights = { "TWR", "APP", "RADAR" } },
        [11] = { name = L.text("work_atc.config.senior_controller_bronze"),   rights = { "TWR", "APP", "RADAR" } },
        [12] = { name = L.text("work_atc.config.senior_controller_silver"),   rights = { "TWR", "APP", "RADAR" } },
        [13] = { name = L.text("work_atc.config.senior_controller_gold"),     rights = { "TWR", "APP", "RADAR" } },
        [14] = { name = L.text("work_atc.config.supervisor"),                 rights = { "TWR", "APP", "RADAR" } },
    },

    -- Work stations: one duty marker for now (z = ground level). More can be added later.
    -- outside the SA Control building in San Fierro (the consoles are inside) (placeholder: tune with /workpos).
    STATIONS = {
        { name = "SA Control", duty = { -2169.13965, 247.03371, 34.32031 }, blip = 13 },
    },
}

ATC.MAX_LEVEL = #ATC.LEVELS
end)
