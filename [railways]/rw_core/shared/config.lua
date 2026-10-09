-- rw_core settings (server + client)

RW = {
    -- the railway company running the network (web map, ui_browser site, UI texts)
    COMPANY       = "Sunline Rail",
    COMPANY_SHORT = "SLR",
    SITE_URL      = "sunline-rail.sa",          -- ui_browser address (services category)

    -- Railway role ("vasutas jog"): with REQUIRE_RAILWAY_ROLE, only role holders may assemble /
    -- spawn trains and throw switches. Driving is open to everyone either way. The role is
    -- given by other resources (work_traindriver) or admins (/rwrole).
    REQUIRE_RAILWAY_ROLE = true,
    -- work_core work whose players on duty are the only ones who see the depot markers and blips
    -- (false = everyone sees them). work_core must be running.
    DEPOT_WORK = "traindriver",
    DATA_ROLE   = "rw.role",                     -- player element data mirror (server-owned)
    ADMIN_LEVEL = 1,                             -- v_mysql admin_level for /rwrole, /rwdespawn
    SPAWN_ADMIN_LEVEL = 3,                       -- admin_level to create a free train in a depot (others apply for services)

    -- "tracks" = the lines of rw_customtracks (0 = main line loop, 3 = second track loop); a
    -- track position (tp) is the distance along the line. Trains elsewhere (yards, crossovers,
    -- Cranberry tracks 3 / 4) have no track.
    TRACKS      = { 0, 3 },
    TRACK_NAMES = { [0] = "Main line", [3] = "Second track", [5] = "Cranberry track 3", [6] = "Cranberry track 4" },

    -- consist extent on a line (the network trains use rw_customtracks NET.STOCK lengths)
    CAR_SPACING = 20.87,
    HALF_LENGTH = 11,                            -- metres from a vehicle centre to its end

    -- rolling stock. kind = loco | coach | wagon. module = rw_loco module that drives it.
    -- numbers = running number range of a locomotive class: every spawned locomotive gets a
    -- free one at random, the train is called after it ("BR 232 1112") while it has no service.
    VEHICLES = {
        br232     = { model = 538, kind = "loco",  name = "BR 232",          module = "br232", numbers = { 1101, 1199 } },
        passenger = { model = 570, kind = "coach", name = "Passenger coach", passenger = true, seats = 64 },
    },
    MAX_CARRIAGES = 4,

    -- ready-made compositions offered in the depot menu
    PRESETS = {
        { id = "light", name = "BR 232 light engine",  loco = "br232", cars = {} },
        { id = "re2",   name = "BR 232 + 2 coaches",   loco = "br232", cars = { "passenger", "passenger" } },
        { id = "re3",   name = "BR 232 + 3 coaches",   loco = "br232", cars = { "passenger", "passenger", "passenger" } },
        { id = "re4",   name = "BR 232 + 4 coaches",   loco = "br232", cars = { "passenger", "passenger", "passenger", "passenger" } },
    },

    -- Spawn points: the lead's centre lands on (x, y) projected onto `track`; dir = +1 faces
    -- increasing track position, -1 the other way. Main line (0) +1 runs
    -- Unity -> Market -> Cranberry -> Yellow Bell -> Linden -> Unity; second track (3) +1 runs
    -- towards San Fierro.
    SPAWNS = {
        { id = "unity_1", name = "Unity Station, track 1 (to SF)",     track = 0, x = 1745, y = -1953.8, dir = 1 },
        { id = "unity_1e", name = "Unity Station, track 1 (to LV)",    track = 0, x = 1745, y = -1953.8, dir = -1 },
        { id = "unity_2", name = "Unity Station, track 2 (from SF)",   track = 3, x = 1745, y = -1957.9, dir = -1 },
        { id = "unity_e", name = "Unity East yard, track 2",           track = 3, x = 2150, y = -1957.9, dir = 1 },
        { id = "cranb_2", name = "Cranberry Station (to LS)",          track = 0, x = -1944.1, y = 150, dir = -1 },
        -- Cranberry track 2 = the second track's through platform (anticlockwise ICs from SF start here)
        { id = "cranb_2t", name = "Cranberry Station, track 2 (to LS)", track = 3, x = -1947.8, y = 150, dir = -1 },
        { id = "cranb_1", name = "Cranberry Station (to LV)",          track = 0, x = -1944.1, y = 150, dir = 1 },
        -- Cranberry hall track 3 (dead end, line 5): LS-bound regionals start here facing south
        { id = "cranb_3", name = "Cranberry Station, track 3 (to LS)", track = 5, x = -1933.5, y = 95, dir = -1 },
        { id = "yb_ls",   name = "Yellow Bell Station (to SF)",        track = 0, x = 1433, y = 2632.3, dir = -1 },
        { id = "yb_lv",   name = "Yellow Bell Station (to Linden)",    track = 0, x = 1433, y = 2632.3, dir = 1 },
        { id = "lin_ls",  name = "Linden Station (to LS)",             track = 0, x = 2854.6, y = 1292, dir = 1 },
        { id = "lin_sf",  name = "Linden Station (to Yellow Bell)",    track = 0, x = 2854.6, y = 1292, dir = -1 },
    },

    -- Depots: railway staff open the depot menu in these markers (E). spawns = ids above.
    DEPOTS = {
        { name = "Unity Station depot", x = 1771.5, y = -1936.5, z = 13.56, spawns = { "unity_1", "unity_1e", "unity_2", "unity_e" } },
        { name = "Cranberry depot",     x = -1957.51904, y = 175.79410, z = 26.28125, spawns = { "cranb_2", "cranb_1", "cranb_2t", "cranb_3" } },
        --{ name = "Yellow Bell depot",   x = 1433.0, y = 2624.0,  z = 11.82, spawns = { "yb_ls", "yb_lv" } },
        --{ name = "Linden depot",        x = 2852.0, y = 1290.0,  z = 11.82, spawns = { "lin_ls", "lin_sf" } },
    },
    DEPOT_KEY = "e",


    -- Railway event log (server/log.lua): services, delays, hold-ups, switches, signals, trains.
    -- Kept in memory (KEEP newest entries, /rwlog, export getRailLog) and appended to a daily
    -- file logs/rail_YYYY-MM-DD.log inside rw_core.
    LOG = {
        KEEP        = 3000,
        FILE        = true,
        FILE_DIR    = "logs/",
        FLUSH_EVERY = 2000,        -- ms between file writes (entries are buffered)
        -- categories that are recorded at all (signal aspect changes are frequent)
        CATEGORIES  = {
            train = true, service = true, delay = true, stop = true, hold = true, stuck = true,
            switch = true, signal = true, spad = true, safety = true, auto = true, loco = true,
        },
        DEBUG_ENABLED = false,     -- log to server debug output (outputDebugString)
        DEBUG_LEVEL = "warn",      -- these levels and above also go to the server debug output
        HOLD_MIN    = 3,           -- s standing at a restriction before a hold is logged
        BLOCK_DIST  = 60,          -- m: a standing train this close to its authority end is held
        STUCK_AFTER = 120,         -- s held (or an automatic train standing) -> "stuck" warning
        CMD         = "rwlog",     -- /rwlog [category|train number|all] [count] (railway admins)
        CMD_LINES   = 15,
    },

    -- 3D info board above the locomotives (client/trainlabel.lua)
    LABEL = {
        MAX_DIST  = 90,        -- metres from the camera
        FULL_DIST = 20,        -- full size up to this distance
        MIN_SCALE = 0.55,
        HEIGHT    = -2,       -- metres above the locomotive roof
        TOGGLE_CMD = "rwlabels",
    },
}
