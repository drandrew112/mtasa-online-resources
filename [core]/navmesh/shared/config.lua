-- navmesh settings (shared). Distances in metres, speeds in m/s, times in seconds unless noted.

NAV = {
    ROADS_FILE = "data/runtime/roads.nav",
    PEDS_FILE = "data/runtime/peds.nav",
    BOATS_FILE = "data/runtime/boats.nav",
    WALK_FILE = "data/runtime/walk.nav",

    ADMIN_LEVEL = 5,              -- /navmesh
    INDEX_CELL = 50,              -- spatial hash cell of the graphs

    -- walk grid
    WALK_CACHE_TILES = 600,       -- decoded 32x32 m tiles kept in memory (LRU)
    WALK_STEP = 0.55,             -- climbable height difference between neighbour cells
    WALK_MAX_NODES = 60000,       -- A* expansion guard per grid search
    WALK_DIRECT = 140,            -- ped routes up to this straight distance are searched on the grid only
    WALK_FAR = 700,               -- without ped graph nearby: grid-only routes up to this straight distance...
    WALK_FAR_NODES = 250000,      -- ...with this expansion guard (use requestRoute: it takes a while)
    DETOUR_FACTOR = 2.5,          -- graph route longer than this * straight distance: retried on the grid
    WALK_CONNECT = 70,            -- grid search radius from the route ends to the ped graph
    WALK_MARGIN = 40,             -- grid search box margin around the two ends

    -- road speeds per link class (1 highway 2 ramp 3 road 4 service), routing time model
    SPEED = { [1] = 33, [2] = 20, [3] = 14, [4] = 6 },
    SPEED_UNPAVED = 9,
    SIGNAL_DELAY = 8,             -- average wait at a signalled junction connection (s)
    TURN_DELAY = { S = 0, R = 2, L = 4, U = 10 },
    ROAD_MAX_NODES = 80000,

    -- vehicle profiles: cost multipliers on travel time
    VEHICLE = {
        car       = { unpaved = 1.6, emergencyOnly = 4,   service = 2,  trap = 1 },
        truck     = { unpaved = 3,   emergencyOnly = 6,   service = 3,  trap = 1, avoidClass = { [4] = 4 } },
        bike      = { unpaved = 1.3, emergencyOnly = 3,   service = 1.5, trap = 1 },
        bus       = { unpaved = 4,   emergencyOnly = 8,   service = 4,  trap = 1, preferClass = { [1] = 0.9 } },
        emergency = { unpaved = 1.3, emergencyOnly = 1,   service = 1,  trap = 1, signalFactor = 0.25 },
        offroad   = { unpaved = 0.8, emergencyOnly = 1.5, service = 1,  trap = 1 },
        gps       = { unpaved = 2,   emergencyOnly = 4,   service = 2,  trap = 1 },
    },

    -- ped roles: cost multipliers per metre on the ped graph (edge kinds) and on the walk grid (cell flags)
    -- graph kinds: 1 sidewalk 2 path 3 crossing 4 crossing with light
    -- grid: class 0 unknown 1 tarmac 2 pavement 3 grass 4 dirt 5 structure 6 shallow water 7 rough,
    --       road = vehicle lane, cross = ped crossing, ped = GTA ped path, edge = next to a wall / drop, steep
    PED = {
        civilian  = { kind = { 1, 1.15, 1.1, 1.0 }, lightWait = 12, class = { 1.3, 1.6, 1.0, 1.4, 1.6, 1.3, 4, 3 },
                      road = 8, cross = 1.0, ped = 0.9, edge = 1.3, steep = 2.5, useGraph = true },
        emergency = { kind = { 1, 1, 1, 1 }, lightWait = 0, class = { 1, 1, 1, 1, 1.1, 1, 2, 1.6 },
                      road = 1.3, cross = 1, ped = 1, edge = 1.1, steep = 1.4, useGraph = true },
        police    = { kind = { 1, 1, 1, 1 }, lightWait = 0, class = { 1, 1, 1, 1, 1.1, 1, 2, 1.6 },
                      road = 1.6, cross = 1, ped = 1, edge = 1.1, steep = 1.5, useGraph = true },
        hiker     = { kind = { 1.1, 1, 1.1, 1.0 }, lightWait = 8, class = { 1, 1.1, 1.1, 1, 1, 1.2, 3, 1.8 },
                      road = 6, cross = 1, ped = 1, edge = 1.2, steep = 1.6, useGraph = true },
        free      = { kind = { 1, 1, 1, 1 }, lightWait = 0, class = { 1, 1, 1, 1, 1, 1, 1.5, 1.2 },
                      road = 1, cross = 1, ped = 1, edge = 1, steep = 1.2, useGraph = false },
    },

    -- debug view (/navmesh)
    DEBUG_RADIUS = 160,           -- graph data sent around the admin
    DEBUG_WALK_RADIUS = 48,       -- walk grid tiles sent around the admin (tiles touching this radius)
    DEBUG_REFRESH_MOVE = 60,      -- resend when the admin moved this far
    DEBUG_DRAW_WALK = 28,         -- walk cells drawn within this distance
}

-- link classes / flags (roads.nav)
NAV_CLASS = { HIGHWAY = 1, RAMP = 2, ROAD = 3, SERVICE = 4 }
NAV_CLASS_NAME = { "highway", "ramp", "road", "service" }
NAV_KF = { UNPAVED = 1, EMERGENCY = 2, ROADBLOCK = 4, ESTIMATED = 8, FORCED = 16 }
NAV_LF = { TRAP = 1, PARKING = 2, SOURCE = 4 }
NAV_NF = { JUNCTION = 1, DEADEND = 2, PARKING = 4, SIGNAL = 8, HIGHWAY = 16, EMERGENCY = 32 }
-- ped edge kinds
NAV_PED_KIND = { SIDEWALK = 1, PATH = 2, CROSSING = 3, LIT = 4 }
NAV_PED_KIND_NAME = { "sidewalk", "path", "crossing", "crossing_light" }
-- walk cell flags
NAV_WF = { CLASS = 7, EDGE = 8, ROAD = 16, CROSS = 32, PED = 64, STEEP = 128 }
NAV_WALK_CLASS_NAME = { [0] = "unknown", "tarmac", "pavement", "grass", "dirt", "structure", "water", "rough" }
