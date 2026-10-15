-- ai_land_traffic settings (shared). Distances in metres, speeds in m/s, times in ms unless noted.

TRAFFIC = {
    GEO_FILE = "data/runtime/geo.dat",   -- geometry, server + client (tools/build_runtime.py)
    SIM_FILE = "data/runtime/sim.dat",   -- topology, server only

    -- simulation area: traffic only exists within SIM_RADIUS of online players (dimension 0, interior 0)
    SIM_RADIUS = 300,
    DESPAWN_RADIUS = 330,
    TICK = 100,                 -- server simulation step
    MAX_AGENTS = 140,           -- whole server
    MAX_PER_PLAYER = 20,        -- vehicles within SIM_RADIUS of one player (moving at FULL_SPEED); hard cap
                                -- for EVERY player near a spawn point, so players together share one budget
    AREA_RADIUS = 100,          -- regional limit: no new vehicle where this circle around the spawn point...
    AREA_MAX = 9,               -- ...already holds this many (traffic + released vehicles)
    LANE_PER_VEHICLE = 90,      -- metres of spawnable route lane per vehicle (density) before the cap
    SPAWN_INTERVAL = 500,
    SPAWN_PER_PLAYER = 2,       -- spawn attempts per player per SPAWN_INTERVAL
    SPAWN_MIN_DIST = 120,       -- normally spawn this far from every player...
    SPAWN_MIN_DIST_EMPTY = 60,  -- ...but closer while the area is still almost empty (join, teleport)
    SPAWN_VISIBLE_MIN = 200,    -- a spawn point a camera looks at must be at least this far from it
    SPAWN_GAP = 14,             -- free space needed around a new vehicle

    -- spawn area = the player's expected route: the lanes reachable forward along the road graph
    -- within ROUTE_LENGTH (heading from the velocity / vehicle / camera), their oncoming lanes and
    -- the lanes feeding into them at junctions
    ROUTE_LENGTH = 300,
    ROUTE_START_RADIUS = 40,    -- route starts on lanes this close to the player...
    ROUTE_FALLBACK_RADIUS = 120,-- ...or, when there is none (off-road), on any lane this close
    ROUTE_REFRESH = 1000,       -- recompute at most this often...
    ROUTE_REFRESH_MOVE = 25,    -- ...when the player moved this far or turned
    ROUTE_MAX_LANES = 1500,     -- search guard
    STILL_SPEED = 2,            -- m/s: below this the player counts as standing (heading from vehicle/camera)
    FULL_SPEED = 14,            -- m/s: full density from this speed
    STILL_FACTOR = 0.35,        -- density factor while standing (linear up to FULL_SPEED)

    -- cameras: clients report their camera; a vehicle no camera can see (behind / far to the side)
    -- disappears after CULL_AFTER if it is farther than CULL_MIN_DIST from every player
    VIEW_SEND = 300,            -- client camera report interval
    VIEW_STALE = 3000,          -- a player without a fresh report counts as seeing everything
    VIEW_HALF_ANGLE = 75,       -- degrees from the look direction (screen + vehicle size margin)
    VIEW_NEAR = 12,             -- always visible this close to a camera
    CULL_MIN_DIST = 40,
    CULL_AFTER = 3000,

    -- speeds per lane type (driver factor DRIVER_FACTOR on top)
    SPEED_ROAD = 15.5,          -- ~56 km/h
    SPEED_HIGHWAY = 26,         -- ~94 km/h
    SPEED_UNPAVED = 10,
    SPEED_PARKING = 5,
    DRIVER_FACTOR = { 0.85, 1.1 },

    -- car following (Intelligent Driver Model)
    IDM_ACCEL = 2.2,
    IDM_DECEL = 3.2,            -- comfortable braking
    IDM_MAX_DECEL = 9.0,
    IDM_GAP = 2.2,              -- standstill gap
    IDM_HEADWAY = 1.3,          -- s
    LOOKAHEAD_MIN = 45,

    -- junctions
    STOP_LINE = 1.0,            -- stop this far before the lane end
    YIELD_WATCH = 28,           -- vehicles closer than this to a priority approach must be let through
    DEADLOCK_WAIT = 6000,       -- after waiting this long only occupied conflicts block
    CLAIM_AFTER = 4000,         -- after waiting this long newcomers on conflicting paths let the agent go
    SIGNAL_CYCLE = {            -- global cycle, drives GTA's traffic lights too (setTrafficLightState)
        { state = 0, time = 13000 },  -- N-S green
        { state = 1, time = 3000 },   -- N-S yellow
        { state = 2, time = 2000 },   -- all red
        { state = 3, time = 13000 },  -- E-W green
        { state = 4, time = 3000 },   -- E-W yellow
        { state = 5, time = 2000 },   -- all red
    },

    -- route choice weights at lane ends
    TURN_WEIGHT = { S = 3, L = 1, R = 1.2, U = 0.05 },
    WEIGHT_EMERGENCY = 0.05,    -- GTA emergency-vehicles-only paths
    WEIGHT_UNPAVED = 0.3,
    WEIGHT_PARKING = 0,
    WEIGHT_SINK = 0.02,
    WEIGHT_TRAP = 0,            -- lanes that never lead back to the main network

    -- emergency vehicles (v_els). Two levels of noticing, rolled per driver while in range:
    --   lights only (mkjState): rarely noticed -> slows down and makes some room
    --   siren (sirenState / sirenHorn): mostly noticed -> pulls over (stops when it is close)
    -- rate = chance per second at close range (scaled down with distance)
    ELS_DATA = "mkjState",
    ELS_SIREN_DATA = { "sirenState", "sirenHorn" },
    ELS_NOTICE_LIGHTS = 0.08,
    ELS_NOTICE_SIREN = 2.5,
    ELS_LIGHTS_SPEED = 8,       -- lights noticed: speed cap ahead of it
    ELS_LIGHTS_PULL = 0.5,      -- lights noticed: fraction of the pull-over offset
    ELS_MANEUVER_SPEED = 3.5,   -- keep rolling at least this fast until pulled over (cars steer, not slide)
    ELS_SLOPE = 0.22,           -- steering for pulling over (lateral m per m, ~12 deg)
    ELS_RANGE = 75,             -- vehicles ahead within this distance give way
    ELS_NOTICE_RANGE = 130,      -- drivers within this distance may notice it
    ELS_STOP_DIST = 40,         -- pull over and stop when the emergency vehicle is this close behind
    ELS_CRAWL_SPEED = 3,
    ELS_ONCOMING_RANGE = 45,
    ELS_ONCOMING_SPEED = 6,
    ELS_JUNCTION_RANGE = 60,    -- cross traffic does not enter a junction it is approaching (at least this far)
    ELS_JUNCTION_TIME = 5,      -- ... or this many seconds of the emergency vehicle's travel, whichever is more
    ELS_PASS_MARGIN = 8,        -- stay pulled over until the emergency vehicle is this far ahead of the car
    ELS_PULL_RIGHT = 2.4,       -- lateral shift (right) in the outer lane / on single lane roads
    ELS_HOLD = 2500,            -- keep the yield this long after the emergency vehicle passed
    RETURN_SLOPE = 0.15,        -- steering back to the lane centre

    -- lanes on multi-lane carriageways: traffic keeps to the outer (rightmost) lane, the inner lane is for passing
    LANE_CHANGE_SLOPE = 0.1,    -- steering of a lane change (lateral m per m, eased)
    LANE_CHANGE_COOLDOWN = 6000,-- min time between two lane changes of a vehicle
    LANE_MIN_SPEED = 3,         -- no lane changes below this speed
    LANE_GAP = 6,               -- free space (besides the car lengths) needed ahead / behind in the target lane...
    LANE_GAP_TIME = 0.7,        -- ...plus this many seconds of travel...
    LANE_GAP_CLOSING = 2.0,     -- ...plus this many seconds of closing speed (gap closes by the speed difference)
    LANE_GAP_RELAXED = 0.5,     -- gap factor for a driver giving way to an emergency vehicle
    LANE_JUNCTION_DIST = 50,    -- no lane change when a junction (signal / conflicts) is this close ahead
    LANE_PASS_LEADER = 0.8,     -- passing: the leader drives below this fraction of the wanted speed...
    LANE_PASS_AFTER = 1500,     -- ...for this long
    LANE_PASS_HOLD = 3000,      -- stay in the inner lane at least this long after passing started
    LANE_TURN_LOOK = 130,       -- left / u-turn (stay inner) or right turn (stay outer) planned within this distance

    -- obstacles (players, their vehicles, other non-traffic vehicles and peds)
    OBSTACLE_RANGE = 55,
    OBSTACLE_HALF_WIDTH = 1.2,
    OVERTAKE_AFTER = 4000,      -- pass a standing obstacle after waiting this long
    OVERTAKE_SPEED = 3,
    OVERTAKE_SLOPE = 0.3,       -- steering out around a standing obstacle (eased, peak ~2x this)
    HORN_AFTER = 3500,
    OBSTACLE_GAP = 3,           -- extra standstill distance behind a non-traffic obstacle
    OBSTACLE_MARGIN = 0.3,      -- lateral safety margin when judging a collision course
    BYPASS_MARGIN = 0.7,        -- free space needed next to everything else on the way around an obstacle
    BYPASS_AHEAD = 14,          -- the way around must be free this far beyond the obstacle
    BYPASS_RECHECK = 800,       -- ms between checks whether passing became possible

    -- sync
    SEND_POS_ERR = 0.3,         -- resend when the client prediction is this far off
    SEND_SPEED_ERR = 0.5,
    SEND_MAX_AGE = 2500,
    SERVER_POS_REFRESH = 4000,  -- element position on the server (other resources, joiners)

    -- releasing a vehicle from the simulation (it becomes a normal physics vehicle)
    CRASH_FORCE = 450,          -- onClientVehicleCollision force reported by the hitting player
    RELEASED_CLEANUP_DIST = 300,
    RELEASED_MIN_LIFE = 30000,

    -- scripted vehicles (exports of other resources, server/scripted.lua)
    SCRIPTED_END_LIFE = 180000, -- removed this long after the last target is done (unless a new one comes)
    SCRIPTED_SNAP_RADIUS = 60,  -- a vehicle / target must be this close to a lane
    SCRIPTED_SNAP_Z = 10,       -- ...and at most this far above / below it (bridges)
    SCRIPTED_STOP_END = 8,      -- a stop stays this far from the end of its lane (stop line)
    SCRIPTED_ARRIVE_GAP = 2.5,  -- stopped with the front this close to the stop point = arrived
    SCRIPTED_LANE_CHANGE = 25,  -- route search cost (m) of a lane change
    SCRIPTED_TURN_COST = { U = 150, L = 6, R = 6 },
    SCRIPTED_MAX_NODES = 40000, -- route search guard

    DRIVER_THROTTLE = 0.02,     -- tiny analog throttle on the drivers (client): stops GTA locking the wheels
    ADMIN_LEVEL = 4,            -- /traffic commands (elementData admin_level)
    DEBUG = false,
}

-- vehicle pool: { model, weight, length }
TRAFFIC_MODELS = {
    -- compacts / sedans
    { 400, 3, 4.8 }, { 401, 3, 4.7 }, { 404, 2, 4.9 }, { 405, 3, 5.0 }, { 410, 3, 4.2 }, { 419, 2, 5.2 },
    { 421, 2, 5.3 }, { 426, 3, 5.0 }, { 436, 3, 4.6 }, { 445, 3, 5.1 }, { 458, 2, 5.0 }, { 466, 3, 5.2 },
    { 467, 2, 5.2 }, { 479, 2, 5.0 }, { 491, 2, 5.1 }, { 492, 2, 5.0 }, { 496, 3, 4.4 }, { 507, 3, 5.3 },
    { 516, 3, 5.1 }, { 517, 2, 5.1 }, { 518, 2, 5.0 }, { 526, 2, 4.9 }, { 527, 2, 4.6 }, { 529, 2, 5.0 },
    { 533, 1, 4.8 }, { 540, 3, 5.2 }, { 542, 2, 5.0 }, { 546, 3, 5.1 }, { 547, 3, 5.0 }, { 549, 2, 4.9 },
    { 550, 3, 5.2 }, { 551, 3, 5.4 }, { 560, 1, 4.7 }, { 561, 2, 5.0 }, { 562, 1, 4.6 }, { 566, 2, 5.4 },
    { 567, 1, 5.6 }, { 580, 2, 5.1 }, { 585, 2, 5.1 }, { 587, 1, 4.9 }, { 589, 2, 4.4 }, { 600, 2, 5.2 },
    { 602, 1, 4.9 }, { 603, 1, 5.2 },
    -- SUVs, pickups, vans
    { 418, 2, 5.3 }, { 422, 2, 5.0 }, { 440, 2, 5.6 }, { 442, 1, 5.6 }, { 478, 1, 4.8 }, { 482, 2, 5.6 },
    { 489, 2, 5.4 }, { 495, 1, 5.2 }, { 500, 1, 4.4 }, { 505, 1, 5.4 }, { 543, 2, 5.4 }, { 554, 2, 5.8 },
    { 579, 2, 5.4 }, { 582, 1, 5.8 },
    -- work / heavy
    { 413, 1, 5.4 }, { 414, 1, 6.5 }, { 455, 1, 9.0 }, { 498, 1, 7.0 }, { 499, 1, 7.0 },
    { 609, 1, 7.0 }, { 420, 2, 5.2 }, { 438, 1, 5.2 },
    -- no buses (431 Bus, 437 Coach): those only exist as scripted vehicles (server/scripted.lua)
}

-- civilian driver skins
TRAFFIC_SKINS = {
    7, 9, 10, 11, 12, 13, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 29, 31, 32, 33, 34, 35, 36, 37,
    38, 39, 40, 41, 43, 44, 46, 47, 48, 49, 54, 55, 56, 57, 58, 59, 60, 61, 62, 68, 69, 72, 73, 76, 78, 79,
    88, 89, 91, 93, 94, 95, 98, 100, 101, 128, 129, 130, 131, 132, 133, 141, 142, 143, 147, 148, 150, 151,
    153, 157, 158, 159, 160, 161, 170, 171, 172, 176, 177, 179, 182, 183, 184, 185, 186, 187, 188, 189, 190,
    191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 206, 210, 211, 212, 213, 214, 215, 216, 217,
    218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 231, 232, 233, 234, 235, 236, 239, 240, 241,
    242, 250, 258, 259, 260, 261, 262,
}

-- lane flags (sim.dat)
LF_HIGHWAY, LF_EMERGENCY, LF_PARKING, LF_UNPAVED, LF_ROADBLOCK, LF_SINK, LF_TRAP = 1, 2, 4, 8, 16, 32, 64

-- events
EV_READY = "ai_traffic:ready"         -- client -> server: geometry loaded
EV_STATE = "ai_traffic:state"         -- server -> client: agent state batch
EV_RELEASE = "ai_traffic:release"     -- server -> client: vehicle left the simulation
EV_REPORT = "ai_traffic:report"       -- client -> server: crash / damage by the local player
EV_VIEW = "ai_traffic:view"           -- client -> server: camera position + look direction
