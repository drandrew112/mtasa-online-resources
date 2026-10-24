TR = {
    -- airspace usage fees (server/fees.lua), used when gov_tax does not run (its /gov values win)
    FEES = { takeoff = 1500, landing = 2000, overflight = 800 },
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
    TAXI_SEP    = 60,         -- m: taxiing aircraft stop this far behind the one ahead on their path (queue)
    TAXI_SEP_LAT = 18,        -- m: sideways from the path that still counts as "on the path"
    PUSH_KTS    = 8,
    PUSH_DIST   = 35,         -- m pushed back from the stand
    LAND_DECISION_DIST = 400, -- m before the threshold: no landing clearance (controlled) = go-around
    APP_CLR_ANGLE = 30,       -- deg: max intercept angle of the extended centre line for a vectored "cleared approach"
    APP_CLR_FAR   = 2.5,      -- x final length: the vectors must intercept the centre line within this distance of the threshold
    APP_CALL_DIST = 3500,     -- m from the final fix: the pilots call for the approach clearance (yellow frame)
    LAND_CALL_DIST = 1500,    -- m from the final fix: the pilots call for the landing clearance (yellow frame)
    STAR_CALL_DIST = 2500,    -- m from the TMA entry fix without an arrival procedure: they ask for one

    FIX_PASS_DIST  = 120,     -- m: a fly-by fix counts as passed this close at the latest (small turns)
    FLYBY_MAX_TURN = 120,     -- deg: fly-by turn anticipation is computed for at most this much turn
    FLYOVER_PASS_DIST = 30,   -- m: a fly-over fix counts as passed this close (or once it is abeam / behind)
    CLIMB_OUT_AGL  = 800,     -- ft: fly runway heading until this high after take-off
    INITIAL_CLIMB  = 3000,    -- ft: cleared level after take-off when a controller has the aircraft
    FINAL_AGL      = 1200,    -- ft above the field at the final fix (glide = FINAL_AGL / final distance)
    GO_AROUND_MARGIN = 500,   -- ft: higher than the glide path + this at the final fix = go-around
    GO_AROUND_ALT  = 3000,    -- ft: every go-around procedure (avi_nav <ICAO>GA) climbs to this
    MAX_LEVEL      = 39000,   -- ft: highest cleared level / requested cruise level (FL390)
    DESCENT_FT_PER_M = 0.9,   -- automatic descent planning (only without a controller)
    SPEED_LIMIT_ALT = 10000,  -- ft: max 250 kts below this
    APPROACH_SLOW_DIST = 2500,-- m before the final fix: slow down to approach + 30 kts

    GATE_WAIT = { 60, 150 },  -- s at the gate before taxiing out
    HOLD_TIME = 8,            -- s holding short before an uncontrolled aircraft enters / crosses
    PARK_TIME = 90,           -- s parked after arrival, then removed
    MAX_AGE   = 40 * 60,      -- s: anything older is removed (stuck)
    EXIT_MARGIN = 300,        -- m outside the CTA = gone
    ENTRY_LEAD_NM = 5.5,      -- nm: external flights appear this far before the CTA border (on the extended first leg)
    M_PER_NM = 1852,          -- world metres per nm (the scope's scale)

    MAX_ACTIVE    = 44,       -- simultaneous flights (overflights before the border included)
    INITIAL_SPAWN = 4,        -- flights started right after the resource starts
    SCHEDULE = true,          -- start flights by the real clock (flights.json period / offset)

    -- workload keeper (server/schedule.lua): every staffed position always has some traffic.
    -- load = aircraft in its sector + PIPELINE_WEIGHT x aircraft heading for it (departures still
    -- on the ground, arrivals not yet in the sector); below MIN_LOAD an extra flight is started.
    MIN_LOAD = 2,
    PIPELINE_WEIGHT = 0.5,
    LOAD_CHECK = 15,          -- s between checks
    LOAD_COOLDOWN = 75,       -- s: at most one extra flight per position this often
    LOAD_MAX_ACTIVE = 52,     -- the keeper may go above MAX_ACTIVE up to this

    -- scope alerts / separation (server/alerts.lua); each loss is a fine in avi_controller
    SEP_AIR_DIST = 185.2,     -- m (0.1 nm): two airborne aircraft in a TMA / the CTA closer than this ...
    SEP_AIR_VERT = 1000,      -- ft: ... and closer than this vertically = separation loss (STCA)
    SEP_GND_DIST = 60,        -- m: two ground aircraft head-on within this = separation loss
    SEP_GND_ANGLE = 45,       -- deg: "head-on" = headings opposite and each ahead of the other within this
    SEP_RESET = 10,           -- s after a conflict ended before the same pair can be fined again
    RAM_ANGLE = 90,           -- deg off the bearing to the next route point ...
    RAM_TIME  = 40,           -- s ... for this long = route deviation alert (RAM)

    -- base centre position (CTA) in avi_controller; the split ones (SACC_N_CTR, SACC_U_CTR ...) come from the
    -- sector chains of avi_airspace `centre`
    CENTER_POSITION = "SACC_CTR",

    -- work_atc training (server/tutorial.lua): the tower training arrival appears in the CTR / TMA of the
    -- airport, this far (m) from the final fix of the runway in use, flying to it, cleared for the
    -- approach (as the closed approach would hand it to the tower). The farthest distance that fits,
    -- straight in on the extended centre line or from the side: ANGLES = deg off the extended centre line.
    TUTORIAL_FINAL_DIST = { 2600, 2200, 1800, 1400, 1000 },
    TUTORIAL_FINAL_ANGLES = { 0, 30, -30, 45, -45, 60, -60 },
    TUTORIAL_MAX_SCALE = 8,   -- setTutorialTimeScale: at most this many simulation steps per tick
    -- approach training (kind tma_arr): an arrival in the CTA this far (m) before its TMA entry fix (the
    -- farthest one still outside the TMA), at this level (LOA: at most 4000 ft at the entry fix)
    TUTORIAL_TMA_DIST = { 3200, 2600, 2000, 1500, 1000 },
    TUTORIAL_TMA_ALT = 4000,
    -- radar training: external entries (kinds inbound / overflight) appear this far (m) before the CTA
    -- border; the conflict pair starts this far (m) each side of the middle of a leg, at least this high
    TUTORIAL_ENTRY_LEAD = 1500,
    TUTORIAL_CONFLICT_DIST = 3500,
    TUTORIAL_CONFLICT_MIN_ALT = 12000,
}
