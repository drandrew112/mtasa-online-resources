CTL = {
    -- Positions: the centre covers the CTA; every airport of avi_airports gets an APP (its TMA)
    -- and a TWR (its CTR + the ground). Ids: SACC_CTR, <ICAO>_APP, <ICAO>_TWR.
    CENTER = { id = "SACC_CTR", name = "San Andreas Control" },
    APP_SUFFIX = "Approach",
    TWR_SUFFIX = "Tower",

    UPDATE_MS = 1000,          -- traffic updates to the logged-in controllers

    -- Work progress (work_core, work id = ATC work). Every accepted traffic action (clearance,
    -- level, heading, direct, transfer...) gives work XP; XP_ACTIONS overrides XP_DEFAULT per action.
    WORK_ID = "atc",
    XP_DEFAULT = 5,
    XP_ACTIONS = { cfl = 3, hdg = 3, nohdg = 2, dct = 3, nodct = 2, xfer = 6 },

    -- Pay after logging out of a position (bank, itemised receipt):
    --   actions pay = actions * PAY_PER_ACTION
    --   multiplied by (1 + minutes * PAY_MINUTE_BONUS), capped at PAY_MAX_MULT
    PAY_PER_ACTION = 700,
    PAY_MINUTE_BONUS = 0.25,
    PAY_MAX_MULT = 5.0,
    PAY_MIN_ACTIONS = 1,       -- no payment below this many actions

    -- scope
    LEVEL_STEP  = 500,         -- ft between the cleared levels offered in the menu
    LEVEL_MIN   = 1000,
    LEVEL_MAX   = 25000,
    HISTORY_DOTS = 6,          -- past positions behind airborne targets
    HISTORY_EVERY = 3000,      -- ms between them
    VECTOR_SECONDS = 60,       -- speed vector length (where the aircraft will be)
    GROUND_MIN_SCALE = 0.2,    -- px / m: ground traffic is hidden when zoomed out further
    TAXI_MIN_SCALE = 0.15,     -- px / m: taxiways / gates drawn from this zoom
}
