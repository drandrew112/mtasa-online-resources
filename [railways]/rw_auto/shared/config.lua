-- rw_auto settings (server + client)

-- console debug output (outputDebugString) of this resource; the rail log file is not affected
DEBUG_ENABLED = false

AUTO = {
    SPAWN_LEAD    = 55,     -- s before departure the train is created (players can board)
    DECIDE_LEAD   = 58,     -- s before departure: taken by a player? (rw_timetable TAKE_LEAD = 60)
    DESPAWN_AFTER = 60,     -- s after the final arrival the train is removed (unless it runs on)
    LATE_START    = 300,    -- s: a missed departure (blocked platform, restart) still starts this
                            -- late; after that the trip is cancelled (boards show "Cancelled")
    DOOR_OPEN     = 2,      -- s after stopping the doors open
    DOOR_CLOSE    = 6,      -- s before departure the doors close

    -- driving (the network's ATP does the braking for stops, signals and trains ahead)
    -- trains run at line speed between VLINE and VMAX (faster when late) and wait at the
    -- platform when early; the ATP brakes them for stops, signals and trains ahead
    VMAX   = 33.3,          -- m/s (120 km/h)
    VLINE  = 29,            -- m/s (~105 km/h): never slower than this on the open line
    ACCEL  = 0.45,          -- m/s^2 used for the timing estimate
    DECEL  = 0.6,           -- m/s^2 used for the timing estimate
    STOP_AHEAD   = 45,      -- m: the lead stops this far past the platform centre
    END_GAP      = 4,       -- m: on a dead-end track the lead stops at least this far before the end

    TICK        = 100,      -- ms simulation step
    SCHEDULE    = 1000,     -- ms between timetable checks
}
