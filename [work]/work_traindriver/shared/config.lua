-- work_traindriver - shared configuration.
-- No vehicle marker: trains are spawned through the rw_core depot menu.
-- Positions: fine-tune with work_core's /workpos (on foot: marker point).

TRAINDRIVER = {
    WORK_ID = "traindriver",
    NAME = "Train driver",
    DESCRIPTION = "Sunline Rail locomotive driver",
    COLOR = { 255, 170, 30 },

    -- Outfits
    SKINS = {
        { model = 255, name = "Driver" },
        { model = 50,  name = "Technician", level = 2 },
        { model = 71,  name = "Station staff", level = 3 },
    },

    -- Work levels (work_core). XP is earned per completed service.
    MAX_LEVEL = 10,
    LEVEL_XP = 400,                    -- XP for level 2
    LEVEL_STEP = 200,                  -- added for every further level
    LEVEL_NAMES = {
        [1] = "Trainee", [2] = "Driver", [4] = "Senior Driver", [6] = "Express Driver",
        [8] = "Chief Driver", [10] = "Master Driver",
    },
    XP = {
        BASE = { RB = 50, IC = 90 },    -- by line prefix, like PAY.BASE
        BASE_DEFAULT = 40,
        PER_STOP = 10,                  -- per served stop
        PUNCTUAL_BONUS = 25,            -- when a PAY.PUNCTUAL tier matched
        SKIP_PENALTY = 10,              -- per skipped stop (XP never goes below 10)
    },

    -- Pay for a completed service (rw_timetable onRailServiceComplete), paid via work_core:payWork
    PAY = {
        BASE = { RB = 2500, IC = 5000 },    -- by line prefix (rw_timetable line id prefix)
        BASE_DEFAULT = 1500,
        PER_STOP = 1000,                     -- per served stop
        PUNCTUAL = {                        -- arrival delay (s) <= max -> bonus (first match)
            { max = 60,  amount = 500, label = "Punctuality bonus" },
            { max = 180, amount = 250, label = "Punctuality bonus (minor delay)" },
        },
        SKIP_FINE = 1000,                    -- per skipped stop
        EARLY_FINE = 250,                   -- per early departure
        DELAY_FINE_FROM = false,            -- max delay (s) above which DELAY_FINE applies (false = off)
        DELAY_FINE = 500,
    },

    -- Duty markers (z = ground level)
    STATIONS = {
        { name = "Unity Station",     duty = { 1764.41846, -1938.67603, 12.57635 },  blip = false },
        { name = "Cranberry Station", duty = { -1958.68762, 167.07697, 26.69405 },   blip = false }
    },
}
