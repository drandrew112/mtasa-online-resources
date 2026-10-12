if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- work_traindriver - shared configuration.
-- No vehicle marker: trains are spawned through the rw_core depot menu.
-- Positions: fine-tune with work_core's /workpos (on foot: marker point).

TRAINDRIVER = {
    WORK_ID = "traindriver",
    NAME = L.text("work_traindriver.config.train_driver"),
    DESCRIPTION = L.text("work_traindriver.config.sunline_rail_locomotive_driver"),
    COLOR = { 255, 170, 30 },

    -- Outfits
    SKINS = {
        { model = 255, name = L.text("work_traindriver.config.driver") },
        { model = 50,  name = L.text("work_traindriver.config.technician"), level = 2 },
        { model = 71,  name = L.text("work_traindriver.config.station_staff"), level = 3 },
    },

    -- Work levels (work_core). XP is earned per completed service.
    MAX_LEVEL = 10,
    LEVEL_XP = 400,                    -- XP for level 2
    LEVEL_STEP = 200,                  -- added for every further level
    LEVEL_NAMES = {
        [1] = L.text("work_traindriver.config.trainee"), [2] = L.text("work_traindriver.config.driver"), [4] = L.text("work_traindriver.config.senior_driver"), [6] = L.text("work_traindriver.config.express_driver"),
        [8] = L.text("work_traindriver.config.chief_driver"), [10] = L.text("work_traindriver.config.master_driver"),
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
            { max = 60,  amount = 500, label = L.text("work_traindriver.config.punctuality_bonus") },
            { max = 180, amount = 250, label = L.text("work_traindriver.config.punctuality_bonus_minor_delay") },
        },
        SKIP_FINE = 1000,                    -- per skipped stop
        EARLY_FINE = 250,                   -- per early departure
        DELAY_FINE_FROM = false,            -- max delay (s) above which DELAY_FINE applies (false = off)
        DELAY_FINE = 500,
    },

    -- Duty markers (z = ground level)
    STATIONS = {
        { name = L.text("work_traindriver.config.unity_station"),     duty = { 1764.41846, -1938.67603, 12.57635 },  blip = false },
        { name = L.text("work_traindriver.config.cranberry_station"), duty = { -1958.68762, 167.07697, 26.69405 },   blip = false }
    },
}
