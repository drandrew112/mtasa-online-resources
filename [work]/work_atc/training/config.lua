-- work_atc training modules - shared configuration. The texts of the steps are in client/*.lua
-- (v_locals work_atc.trn.*). Positions: /workpos of work_core.

TRAINING = {
    -- true: the SCOPE module is offered on EVERY duty start, even when it was completed / declined
    DEBUG = false,

    COMMAND = "atctraining",           -- /atctraining stop ends the running module (not completed)
    ACC_PREFIX = "atc.training.",      -- v_mysql account data atc.training.<module> = true once completed
    OFFER_KEY = "atc.training.offered",-- true once the first-duty offer was answered
    DIMENSION_BASE = 44000,            -- every session gets its own dimension from here
    FADE_TIME = 1.2,                   -- seconds of a camera fade
    CURSOR_KEY = "F2",                 -- shows / hides the cursor for the training card buttons
    POLL = 500,                        -- ms, server check of the training aircraft
    -- the training aircraft fly this many times faster while the player only has to watch (the
    -- sub-steps marked `fast` in client/*.lua) and none of the player's own aircraft asks for something
    FAST_SCALE = 4,

    -- The training marker in the SA Control operations room (live dimension): E opens the module list.
    -- Visible only to players on duty in the work (work_core setElementVisibleToWork).
    MARKER = { x = 214.42, y = 193.64, z = 1057.16, interior = 3, dimension = 0,
        size = 1.4, color = { 230, 170, 40, 150 }, key = "e", labelDistance = 20 },

    -- A module started away from the room (the first-duty offer) puts the player here, in the room of
    -- the session's dimension; one started at the marker keeps the player where they stand.
    START = { 215.20518, 199.86151, 1058.15942, 0, interior = 3 },
    -- every module ends here, in the live room (also the saved position while a module runs)
    FINISH = { 214.51, 196.54, 1057.616, interior = 3, dimension = 0 },
    -- the map of the room: its interior objects are copied into the session's dimension
    -- (createDimensionCopy / destroyDimensionCopy), a module does not start without it
    MAP_RESOURCE = "map_int_sacontrol",
    AIRPORT = "SASF",                  -- the airport of the scope, tower and approach modules

    -- The modules. right = the avi_core ATC right that unlocks it (work level, see ATC.LEVELS);
    -- position = the tutorial login of avi_controller (the live position stays free meanwhile).
    -- SCOPE is the short tour of the scope itself (offered at the first duty); the others take it as known.
    ORDER = { "scope", "adc", "apc", "acc" },
    OFFER = "scope",                   -- the module the first duty start offers
    MODULES = {
        scope = { code = "SCOPE", right = "TWR", position = "SASF_TWR", minutes = 5 },
        adc = { code = "ADC", right = "TWR",   position = "SASF_TWR", minutes = 15 },
        apc = { code = "APC", right = "APP",   position = "SASF_APP", minutes = 15 },
        acc = { code = "ACC", right = "RADAR", position = "SACC_CTR", minutes = 15 },
    },

    -- callsigns of the training aircraft per module and role
    CALLSIGNS = {
        scope = { dep = "TUT100" },
        adc = { dep = "TUT101", arr = "TUT202" },
        apc = { dep = "TUT111", arr = "TUT212", vec = "TUT213" },
        acc = { ovf = "TUT321", cfa = "TUT331", cfb = "TUT332", inb = "TUT341" },
    },
    GATE_WAIT = 3,                     -- s a training departure waits at the stand before it calls
    ALERT_SQUAWK = "7700",             -- the alert demonstration of ADC (EMRG over the label)

    -- Keys named in the texts (avi_core AVI.MARKER_KEY)
    KEYS = { console = "E" },
}
