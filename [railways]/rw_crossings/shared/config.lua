-- rw_crossings settings (server + client)

-- console debug output (outputDebugString) of this resource; the rail log file is not affected
DEBUG_ENABLED = false

CROSS = {
    TRACKS        = { 0, 3 },   -- tracks a crossing can belong to (within TRACK_RANGE of its centre)
    TRACK_RANGE   = 15,
    APPROACH      = 260,        -- m of track on each side of the road that closes the barriers
    STATION_GAP   = 15,         -- the zone ends this far before a station platform zone
    MIN_ZONE      = 30,         -- never shorter than this on a side (crossing next to a station)
    OPEN_DELAY    = 3000,       -- ms after the last train left before the arms rise
    MOVE_TIME     = 3500,       -- ms the arm takes to move
    ARM_UP        = 85,         -- degrees the arm is raised when open
    TICK          = 250,
    LIGHT_DISTANCE = 220,       -- client: flashing lights drawn within this distance
}
