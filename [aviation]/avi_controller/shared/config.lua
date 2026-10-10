CTL = {
    -- Positions: the centre covers the CTA; every airport of avi_airports gets an APP (its TMA)
    -- and a TWR (its CTR + the ground). Ids: SACC_CTR, <ICAO>_APP, <ICAO>_TWR.
    CENTER = { id = "SACC_CTR", name = "San Andreas Control" },
    APP_SUFFIX = "Approach",
    TWR_SUFFIX = "Tower",

    -- Radar refresh: the scope gets new target positions only at these intervals (ms, per position
    -- type); targets do not move in between. UPDATE_TICK_MS = how often the server checks who is due.
    UPDATE_MS = { TWR = 1000, APP = 2000, CTR = 3000 },
    UPDATE_TICK_MS = 250,

    -- Work progress (work_core, work id = ATC work). Every accepted traffic action (clearance,
    -- level, heading, direct, transfer...) gives work XP; XP_ACTIONS overrides XP_DEFAULT per action.
    WORK_ID = "atc",
    XP_DEFAULT = 25,
    XP_ACTIONS = { cfl = 20, hdg = 20, nohdg = 10, dct = 20, nodct = 10, xfer = 30 },

    -- Pay after logging out of a position (bank, itemised receipt):
    --   actions pay = actions * PAY_PER_ACTION
    --   multiplied by (1 + minutes * PAY_MINUTE_BONUS), capped at PAY_MAX_MULT
    PAY_PER_ACTION = 800,
    PAY_MINUTE_BONUS = 0.10,
    PAY_MAX_MULT = 3.0,
    PAY_MIN_ACTIONS = 1,       -- no payment below this many actions

    -- scope
    LEVEL_STEP  = 500,         -- ft between the cleared levels offered in the menu
    LEVEL_MIN   = 1000,
    LEVEL_MAX   = 25000,
    HISTORY_DOTS = 6,          -- past positions behind airborne targets
    HISTORY_EVERY = 3000,      -- ms between them
    VECTOR_STEP_NM = 0.1,      -- leader line length per step (nm); the controller sets 0..VECTOR_MAX_STEPS steps
    VECTOR_DEFAULT_STEPS = 2,
    VECTOR_MAX_STEPS = 5,
    GROUND_MIN_SCALE = 0.2,    -- px / m: ground traffic is hidden when zoomed out further
    TAXI_MIN_SCALE = 0.15,     -- px / m: taxiways / gates drawn from this zoom
}
