-- rw_passengers settings (server + client). See DESIGN.md.

-- console debug output (outputDebugString) of this resource; the rail log file is not affected
DEBUG_ENABLED = false

RWP = RWP or {}

-- coach id = dimension of its interior: DIM_BASE + 1 .. DIM_BASE + DIM_COUNT (never 0)
RWP.DIM_BASE  = 30000
RWP.DIM_COUNT = 9999

-- a door is usable when the train stands (|v| < STAND_SPEED for STAND_TIME s) and the doors are
-- released on that side (rw.doors of the lead); released doors already mean a station platform
RWP.STAND_SPEED = 0.2       -- m/s
RWP.STAND_TIME  = 1.0       -- s

RWP.CAPACITY = 30           -- passengers per coach

-- outside door anchors (invisible, non-colliding objects attached to the coach)
RWP.ANCHOR_MODEL = 1319
RWP.ANCHOR_RANGE = 2.6

-- passenger coach (model 570, measured 2026-10-04): body half width 1.74 m, one door per side in
-- the middle of the car (y = 0); the car centre is 2.595 m above the rail.
-- side = -1 left / +1 right of the coach's own front.
RWP.COACH_DOORS = {
    { side = -1, x = -1.9, y = 0, z = -0.6 },
    { side =  1, x =  1.9, y = 0, z = -0.6 },
}
RWP.EXIT_LATERAL = 2.8      -- m from the coach centre line where a leaving passenger is put down

RWP.FADE_MS       = 300

RWP.WINDOWS = { ENABLED = true, BLUR_TAPS = 4, CLASS_BLEND = 40 }

-- rw_core vehicle types that are passenger coaches (RW.VEHICLES[...].passenger)
RWP.COACH_TYPES = { passenger = true }
RWP.COACH_RAIL_HEIGHT = 2.595   -- coach centre above the rail (rw_customtracks NET.STOCK.passenger.base)
RWP.STATE_MS = 500              -- ride state push to the passengers (windows, display, sounds)

-- client ride effects
RWP.SOUNDS = {
    RUN    = ":rw_customtracks/sounds/run.wav",
    CLACK  = ":rw_customtracks/sounds/clack.wav",
    SQUEAL = ":rw_customtracks/sounds/squeal.wav",
    CHIME  = "sounds/chime.wav",
    VOLUME = 0.55,
    CLACK_EVERY = 23.5,         -- m between wheel clacks (rail joints)
}
RWP.ANNOUNCE_TIME = 6000        -- ms an announcement banner stays
