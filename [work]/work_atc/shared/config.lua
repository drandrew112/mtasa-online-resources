-- work_atc - shared configuration.
-- Positions: fine-tune with work_core's /workpos (on foot: marker point).

ATC = {
    WORK_ID = "atc",                 -- must match AVI.MARKER_WORK in avi_core
    NAME = "Air traffic control",
    DESCRIPTION = "Air traffic controller (San Fierro tower)",
    COLOR = { 70, 130, 210 },

    -- Outfits (the Supervisor outfit unlocks at the last level)
    SKINS = {
        { model = 17,  name = "Controller" },
        { model = 59,  name = "Controller (casual)" },
        { model = 187, name = "Supervisor", level = 14 },
    },

    -- Level table: XP curve + name and ATC rights of each level. Rights are cumulative by design
    -- (a higher rank keeps the lower positions). Rights: TWR / APP / RADAR (avi_core).
    -- XP is given by the aviation system through work_core:giveWorkXp(player, "atc", xp).
    LEVEL_BASE_XP = 400,
    LEVEL_STEP_XP = 250,
    LEVELS = {
        [1]  = { name = "Trainee",                    rights = { "TWR" } },
        [2]  = { name = "Tower Controller Bronze",    rights = { "TWR" } },
        [3]  = { name = "Tower Controller Silver",    rights = { "TWR" } },
        [4]  = { name = "Tower Controller Gold",      rights = { "TWR" } },
        [5]  = { name = "Approach Controller Bronze", rights = { "TWR", "APP" } },
        [6]  = { name = "Approach Controller Silver", rights = { "TWR", "APP" } },
        [7]  = { name = "Approach Controller Gold",   rights = { "TWR", "APP" } },
        [8]  = { name = "Radar Controller Bronze",    rights = { "TWR", "APP", "RADAR" } },
        [9]  = { name = "Radar Controller Silver",    rights = { "TWR", "APP", "RADAR" } },
        [10] = { name = "Radar Controller Gold",      rights = { "TWR", "APP", "RADAR" } },
        [11] = { name = "Senior Controller Bronze",   rights = { "TWR", "APP", "RADAR" } },
        [12] = { name = "Senior Controller Silver",   rights = { "TWR", "APP", "RADAR" } },
        [13] = { name = "Senior Controller Gold",     rights = { "TWR", "APP", "RADAR" } },
        [14] = { name = "Supervisor",                 rights = { "TWR", "APP", "RADAR" } },
    },

    -- Work stations: one duty marker for now (z = ground level). More can be added later.
    -- SF control tower base, in the room next to the wall screens (placeholder: tune with /workpos).
    STATIONS = {
        { name = "San Fierro Tower", duty = { -1264.01, 37.58, 13.14 }, blip = false },
    },
}

ATC.MAX_LEVEL = #ATC.LEVELS
