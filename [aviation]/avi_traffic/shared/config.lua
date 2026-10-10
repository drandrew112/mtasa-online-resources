TR = {
    TICK = 1000,              -- simulation step (ms)

    -- The GTA map is ~1/10 of a real area, so aircraft move slower than their shown speed:
    -- world m/s = kts * 0.5144 * scale. Labels show the real knots / feet / ft per min.
    AIR_SCALE  = 0.2,         -- airborne (above SCALE_BLEND_FT above the field)
    ROLL_SCALE = 0.35,        -- take-off / landing roll (blends into AIR_SCALE while climbing)
    TAXI_SCALE = 0.6,         -- taxiing
    SCALE_BLEND_FT = 1000,

    TURN_RATE   = 6,          -- deg / s in the air
    ACCEL_AIR   = 2,          -- kts / s
    ACCEL_ROLL  = 6,          -- kts / s on the take-off roll
    DECEL_ROLL  = 5,          -- kts / s after touch-down
    TAXI_KTS    = 25,         -- on taxiways
    RWY_TAXI_KTS = 50,        -- taxiing on a runway (backtrack, crossing, vacating)
    RWY_ZONE_MARGIN = 5,      -- m beyond the runway edge: entering this needs a runway clearance
    RWY_ZONE_EXT = 30,        -- m beyond the runway ends that still count as the runway
    BACKTRACK_DIST = 80,      -- m from the threshold: entering further down needs a backtrack
    PUSH_KTS    = 8,
    PUSH_DIST   = 35,         -- m pushed back from the stand
    LAND_DECISION_DIST = 400, -- m before the threshold: no landing clearance (controlled) = go-around

    FIX_PASS_DIST  = 120,     -- m: a fix counts as passed this close
    CLIMB_OUT_AGL  = 800,     -- ft: fly runway heading until this high after take-off
    INITIAL_CLIMB  = 3000,    -- ft: cleared level after take-off when a controller has the aircraft
    FINAL_AGL      = 1200,    -- ft above the field at the final fix (glide = FINAL_AGL / final distance)
    GO_AROUND_MARGIN = 500,   -- ft: higher than the glide path + this at the final fix = go-around
    MISSED_ALT_AGL = 2500,    -- ft above the field after a go-around
    DESCENT_FT_PER_M = 0.9,   -- automatic descent planning (only without a controller)
    SPEED_LIMIT_ALT = 10000,  -- ft: max 250 kts below this
    APPROACH_SLOW_DIST = 2500,-- m before the final fix: slow down to approach + 30 kts

    GATE_WAIT = { 60, 150 },  -- s at the gate before taxiing out
    HOLD_TIME = 8,            -- s holding short before an uncontrolled aircraft enters / crosses
    PARK_TIME = 90,           -- s parked after arrival, then removed
    MAX_AGE   = 40 * 60,      -- s: anything older is removed (stuck)
    EXIT_MARGIN = 300,        -- m outside the CTA = gone

    MAX_ACTIVE    = 14,       -- simultaneous flights
    INITIAL_SPAWN = 4,        -- flights started right after the resource starts
    SCHEDULE = true,          -- start flights by the real clock (flights.json period / offset)

    CENTER_POSITION = "SACC_CTR",   -- position id of the centre (CTA) in avi_controller
}
