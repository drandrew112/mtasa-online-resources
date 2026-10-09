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
        { model = 50,  name = "Technician" },
        { model = 71,  name = "Station staff" },
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
