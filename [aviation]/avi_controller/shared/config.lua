CTL = {
    -- Positions: the centre covers the CTA; every airport of avi_airports gets an APP (its TMA)
    -- and a TWR (its CTR + the ground). Ids: SACC_*_CTR, <ICAO>_APP, <ICAO>_TWR.
    -- Centre positions (type CTR, RADAR right): SACC_CTR alone has the whole CTA. The others split it
    -- (avi_airspace `centre` sectors: north / south of ZEPHR - PALIS - VINEW - east edge, upper above
    -- FL205); every sector belongs to the first staffed position of its chain, so any of them can be
    -- opened on its own:
    --   north lower: SACC_N_CTR > SACC_CTR          south lower: SACC_S_CTR > SACC_CTR
    --   north upper: SACC_NU_CTR > SACC_U_CTR > SACC_N_CTR > SACC_CTR
    --   south upper: SACC_SU_CTR > SACC_U_CTR > SACC_S_CTR > SACC_CTR
    CENTER = { id = "SACC_CTR", name = "San Andreas Control" },
    CENTERS = {
        { id = "SACC_CTR",    name = "San Andreas Control" },
        { id = "SACC_N_CTR",  name = "San Andreas Control North" },
        { id = "SACC_S_CTR",  name = "San Andreas Control South" },
        { id = "SACC_U_CTR",  name = "San Andreas Control Upper" },
        { id = "SACC_NU_CTR", name = "San Andreas Control North Upper" },
        { id = "SACC_SU_CTR", name = "San Andreas Control South Upper" },
    },
    APP_SUFFIX = "Approach",
    TWR_SUFFIX = "Tower",

    -- Radar refresh: the scope gets new target positions only at these intervals (ms, per position
    -- type); targets do not move in between. UPDATE_TICK_MS = how often the server checks who is due.
    UPDATE_MS = { TWR = 1000, APP = 2000, CTR = 3000 },
    UPDATE_TICK_MS = 250,
    UPPER_VIEW_BELOW = 2000,       -- ft: upper centre positions (SACC_U/NU/SU_CTR) see traffic down to this far
                                   -- below the upper split (FL205 - 2000 = 18 500 ft) + their own aircraft
    APP_HEADING_LOOKAHEAD = 4000,  -- m: an aircraft on a radar heading is checked this far ahead
                                   -- for crossing an approach sector (TMA / CTR)

    -- Work progress (work_core, work id = ATC work). Every accepted traffic action (clearance,
    -- level, heading, direct, transfer...) gives work XP; XP_ACTIONS overrides XP_DEFAULT per action.
    WORK_ID = "atc",
    XP_DEFAULT = 30,
    XP_ACTIONS = { cfl = 25, hdg = 25, nohdg = 15, dct = 20, nodct = 15, approach = 35, star = 35, xfer = 35 },

    -- Pay after logging out of a position (bank, itemised receipt):
    --   actions pay = actions * PAY_PER_ACTION
    --   multiplied by (1 + minutes * PAY_MINUTE_BONUS), capped at PAY_MAX_MULT
    PAY_PER_ACTION = 800,
    PAY_MINUTE_BONUS = 0.10,
    PAY_MAX_MULT = 3.0,
    PAY_MIN_ACTIONS = 1,       -- no payment below this many actions
    -- "Controlled traffic": every distinct aircraft the controller gave an accepted action to during
    -- the session pays this much (flat, not multiplied by the time)
    PAY_PER_AIRCRAFT = 500,

    -- Mistakes: every separation loss (avi_traffic alerts.lua) on an aircraft of the position costs
    -- this much; the sum is the "Mistakes" item of the pay. A negative total is taken from the bank.
    --   GND = two ground aircraft head-on, TMA / CTA = closer than 0.1 nm (and 1000 ft) there
    PENALTY = { GND = 500, TMA = 700, CTA = 1000 },

    -- scope
    LEVEL_STEP  = 500,         -- ft between the cleared levels offered in the menu ...
    LEVEL_STEP_HIGH = 1000,    -- ... and above LEVEL_FINE_MAX
    LEVEL_FINE_MAX = 20000,
    LEVEL_MIN   = 1000,
    LEVEL_MAX   = 39000,       -- FL390
    HISTORY_DOTS = 6,          -- past positions behind airborne targets
    HISTORY_EVERY = 3000,      -- ms between them
    VECTOR_STEP_NM = 0.1,      -- leader line length per step (nm); the controller sets 0..VECTOR_MAX_STEPS steps
    VECTOR_DEFAULT_STEPS = 2,
    VECTOR_MAX_STEPS = 5,
    GROUND_MIN_SCALE = 0.2,    -- px / m: ground traffic is hidden when zoomed out further
    TAXI_MIN_SCALE = 0.15,     -- px / m: taxiways / gates drawn from this zoom
}
