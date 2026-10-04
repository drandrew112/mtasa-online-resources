-- rw_customtracks settings (server + client)

NET = {
    -- network data: the manifest lists the data files (server reads them, clients get the data
    -- from the server). Saving through the exports keeps every item in the file it came from and
    -- adds new files to the manifest.
    DATA_DIR = "data/network/",
    MANIFEST = "data/network/files.json",

    STEP  = 1,          -- resampling step along a segment (m of 3D arc length)
    DENSE = 0.5,        -- spline evaluation step before resampling (m)
    CELL  = 64,         -- spatial grid cell for projections (m)

    -- vehicle height: centre z = rail z + getElementDistanceFromCentreOfMassToBaseOfModel + RAIL_Z.
    -- Measured on GTA trains standing on real rails (2026-10-04): 538 centre 0.171 above the
    -- rail (base 0.203), 570 2.55 (base 2.595) -> -0.04 for both.
    RAIL_Z = -0.04,

    -- validation limits (server/validate.lua)
    VALIDATE = {
        GAP        = 0.3,    -- segment ends meeting at a node must be this close (m)
        KINK       = 3,      -- max direction change across a node (degrees)
        MIN_RADIUS = 60,     -- tighter curves are reported (m)
        MAX_GRADE  = 0.05,   -- steeper gradients are reported (5 %)
        MIN_LENGTH = 2,      -- shorter segments are reported (m)
        -- curves / gradients of these kinds are GTA's own geometry: reported as "info" only
        GTA_KINDS  = { main = true, second = true, spur = true },
    },

    -- debug drawing (client/debugdraw.lua)
    DRAW = {
        CMD      = "rwnet",
        DIST     = 220,      -- metres from the camera
        LABEL_DIST = 120,
        COLORS = {
            main      = { 80, 160, 255 },
            second    = { 0, 220, 200 },
            spur      = { 120, 255, 120 },
            crossover = { 255, 170, 0 },
            junction  = { 220, 90, 255 },
            other     = { 255, 255, 255 },
        },
    },

    ADMIN_LEVEL = 1,         -- v_mysql admin level for the debug / edit commands (via rw_core)

    -- lines (shared/lines.lua): the "track" numbers the other rw_ resources use (as before: 0 = main
    -- line loop, 3 = second track), now with their own continuous tp along the network
    LINES = {
        [0] = { start = "M01", families = { "M" } },
        [3] = { start = "S01", families = { "S", "N", "NB", "NC", "M" } },
        -- Cranberry hall dead-end tracks (open lines from W21a to their buffer stops, +1 = north):
        -- 5 = track 3 (C02 / C03), 6 = track 4 (C02 / P401)
        [5] = { start = "C02", families = { "C" } },
        [6] = { start = "C02", families = { "P", "C" } },
    },

    -- ------------------------------------------------------------------ trains (phase 2)

    -- rolling stock. length = coupler to coupler (m), bogie = bogie centre distance, mass in t,
    -- power kW + maxForce kN (locos), base = fallback centre height above the base of the model
    -- (used before the model streams in), ride = where attached passengers stand
    -- (x across, y along the car, z above the car centre).
    STOCK = {
        br232 = { model = 538, kind = "loco", name = "BR 232", length = 20.87, bogie = 13.5, mass = 116,
                  power = 2200, maxForce = 350, base = 0.203 },
        passenger = { model = 570, kind = "coach", name = "Passenger coach", length = 20.87, bogie = 14.5, mass = 45,
                  base = 2.595, ride = { z = -0.3, spots = {
                      { -0.6, -7 }, { 0.6, -5 }, { -0.6, -3 }, { 0.6, -1 }, { -0.6, 1 }, { 0.6, 3 }, { -0.6, 5 }, { 0.6, 7 },
                      { 0.6, -7 }, { -0.6, -5 }, { 0.6, -3 }, { -0.6, -1 }, { 0.6, 1 }, { -0.6, 3 }, { 0.6, 5 }, { -0.6, 7 } } } },
    },
    PRESETS = {
        light = { "br232" },
        re2   = { "br232", "passenger", "passenger" },
        re3   = { "br232", "passenger", "passenger", "passenger" },
        re4   = { "br232", "passenger", "passenger", "passenger", "passenger" },
    },

    SIM = {
        TICK       = 100,    -- server simulation step (ms; the real elapsed time is used)
        SNAPSHOT   = 500,    -- state broadcast to the clients (ms), plus on every input change
        SERVER_POS = 1000,   -- server-side element positions of unoccupied cars (streaming)
        VMAX       = 40,     -- m/s hard cap (144 km/h)
        BRAKE      = 0.9,    -- service brake at full (m/s^2)
        EMERGENCY  = 1.4,    -- emergency brake (m/s^2)
        CONTROL_RATE = 0.6,  -- driver controller change per second while W / S is held
        -- running resistance a = R0 + R1 * v + R2 * v^2 (m/s^2)
        R0 = 0.01, R1 = 0.0002, R2 = 0.00006,
        -- GTA's tracks have gradients up to ~24 %: the physics only feels a scaled, capped part
        GRADE_FACTOR = 0.3, GRADE_CAP = 0.04,
        LOOKAHEAD  = 60,     -- metres of route kept ahead of the train
        CRASH_SPEED = 1.5,   -- m/s: hitting a buffer / train faster than this is a crash event
        SPAWN_CLEAR = 30,    -- free track needed around a new train (m)
        IDLE_DESPAWN = 15 * 60,   -- s a train may stand without driver and riders before removal
        LOG_INPUT  = false,  -- debug: log every driver input
    },
    -- switches (phase 3): always thrown by the system - a train with a destination gets its
    -- route reserved switch by switch ahead of it and an authority (ATP) up to the first switch it
    -- could not get or its destination.
    SWITCHES = {
        LOCK_MARGIN   = 30,    -- a switch with a train on it or this close (m) cannot be thrown
        HORIZON_MIN   = 250,   -- reserve the route this far ahead (m) ...
        HORIZON_EXTRA = 150,   -- ... or braking distance + this, whichever is more
        AUTHORITY_GAP = 15,    -- stop this far before a switch that could not be reserved (m)
        DEST_GAP      = 1,     -- stop this far before the destination point (m)
        TRAIN_GAP     = 30,    -- stop this far behind another train on the route
        STOP_GAP      = 8,     -- stop this far before a red signal (rw_signals stop points)
        LOOKAHEAD     = 2000,  -- trains without a destination: authority looks this far ahead
        ROUTER_TICK   = 250,   -- ms
        REPAIR_TIME   = 120,   -- s until a trailed (damaged) switch is repaired automatically
        SYNC          = 500,   -- ms, switch info to the clients when something changed
    },
    -- client side
    CLIENT = {
        CORR_MS  = 300,      -- a snapshot error is blended out over this many ms
        SWEEP    = true,     -- push peds / vehicles out of the way (client/sweeper.lua)
        SOUND_DIST = 120,    -- train sounds within this distance of the camera
        JOINT    = 25,       -- rail joint every n metres (clack sound)
        SQUEAL_RADIUS = 150, -- curve squeal below this radius
    },
}
