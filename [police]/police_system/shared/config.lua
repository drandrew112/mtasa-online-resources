-- police_system / shared/config.lua
-- Every tunable number of the police system (docs/plan/index.html). Texts are v_locals keys (police_system.*).

POLICE = {
    -- false while testing: everybody counts as police (like bt_core REQUIRE_RIGHT); work_police gives the right
    REQUIRE_POLICE_RIGHT = true,
    RIGHT_KEY = "pol.right",          -- player element data (subscribe: only the player itself gets it)
    WORK_ID = "police",
    ADMIN_LEVEL = 5,                  -- /polwanted, /poldebug

    -- Vehicles. isPoliceVehicle: these models; 598 only with the hu_pd paintjob (the EMS doctor car uses 598 too).
    VEHICLES = {
        [596] = { name = "Ford Crown Victoria", ai = { weight = 5, zones = { city = true } } },
        [598] = { name = "Skoda Octavia MK3", paintjob = "hu_pd", elsExtra = 1, ai = { weight = 5, zones = { city = true } } },
        -- [597] = { name = "GTA5 police car" },   -- later
        [599] = { name = "Police Ranger", ai = { weight = 6, zones = { rural = true } } },
        [432] = { name = "Rhino", aiOnly = true, ai = { minLevel = 5 } },
    },
    TANK_MODEL = 432,
    PAINTJOB_KEY = "paintjob:custom", -- v_paintjobs element data

    -- Stations (only LSPD for now). No blips anywhere (the user's decision).
    -- duty / vehicle: work_police markers; handover: arrested suspects are handed over here; tow: where the tow
    -- truck leaves the towed vehicle; jail: the cell the arrested player is put in (inside the LSPD building, the
    -- map_ls_int_pd interior, measured live); release: where the player comes out after the jail time.
    STATIONS = {
        {
            id = "lspd", name = "LSPD",
            duty = { 1560.83, -1682.97, 15.20 },
            vehicle = { 1560.49, -1694.36, 4.90 },
            handover = { 1581.31, -1684.30, 14.00 },
            tow = { 1550.83, -1626.90, 12.38 },
            jail = { 1571.7, -1697.6, 13.6, rot = 0, interior = 0, dimension = 0, radius = 4.5 },
            release = { 1544.0, -1675.5, 13.6, rot = 90 },
        },
    },
    HANDOVER_RADIUS = 3,

    WANTED = {
        MAX = 6,
        FOLLOW_DIST = 80,         -- 1 -> 2: a unit with lights on follows within this...
        MOVING_TIME = 15,         -- ...and the suspect keeps moving this long (s)
        MOVING_SPEED = 2,         -- m/s: "moving" in a vehicle (on foot: running)
        HEAT = { damage = 25, kill = 100, vehicle = 60, nearShot = 5 },
        HEAT_LEVELS = { [4] = 150, [5] = 350, [6] = 700 },
        NEAR_SHOT_RADIUS = 30,    -- a shot this close to a police unit
        SURRENDER_DIST = 15,      -- "Hold E to surrender": a unit this close and the suspect stands
        SURRENDER_HOLD = 1500,
        QUIT_WARRANT_LEVEL = 2,   -- quitting at this level or above (or cuffed): automatic warrant
        RAM_FORCE = 400,          -- a collision with a police car this hard counts as ramming (1 -> 2)
        -- evasion: nobody sees the suspect (no police vehicle within VEHICLE_DIST, no officer on foot within
        -- FOOT_DIST) for `hold` s at the level; v_levelsys XP when the chase lasted MIN_CHASE s; COOLDOWN between
        EVADE = {
            [1] = { hold = 20, radius = 200, xp = 100 },
            [2] = { hold = 30, radius = 250, xp = 250 },
            [3] = { hold = 45, radius = 300, xp = 500 },
            [4] = { hold = 60, radius = 350, xp = 900 },
            [5] = { hold = 90, radius = 400, xp = 1500 },
            [6] = { hold = 120, radius = 450, xp = 2500 },
        },
        -- a new / higher wanted level: the police know where the suspect is for this long (s), the AI units are
        -- dispatched meanwhile (without it the suspect, with no unit near yet, starts evading at once and no unit
        -- would ever come: the AI sends none while the suspect is evading)
        DISPATCH_GRACE = 45,
        EVADE_VEHICLE_DIST = 180,
        EVADE_FOOT_DIST = 80,
        EVADE_MIN_CHASE = 60,
        EVADE_XP_COOLDOWN = 15 * 60,
        BLINK_PERIOD = 450,
    },

    CHASE = {
        TICK = 1000,
        PREDICT_EVERY = 2000,     -- route prediction refresh...
        PREDICT_DEVIATION = 40,   -- ...only when the suspect left the predicted path this far
        PREDICT_LENGTH = 450,
        NPC_FLEE_SPEED = 1.35,
    },

    AI = {
        TICK = 500,               -- tactics (2 Hz)
        MAX_VEHICLES = 14,
        MAX_TANKS = 3,
        SHARE_DIST = 300,         -- suspects closer than this share the units
        LEVELS = {
            [1] = { cars = 1, tanks = 0, mode = "follow", aggression = 0.3, armed = false, accuracy = 0 },
            [2] = { cars = 2, tanks = 0, mode = "box",    aggression = 0.5, armed = true, accuracy = 0.25, weapon = 22 },
            [3] = { cars = 3, tanks = 0, mode = "pit",    aggression = 0.7, armed = true, accuracy = 0.35, weapon = 25 },
            [4] = { cars = 4, tanks = 0, mode = "ram",    aggression = 0.8, armed = true, accuracy = 0.45, weapon = 29, roadblock = true },
            [5] = { cars = 4, tanks = 1, mode = "ram",    aggression = 0.9, armed = true, accuracy = 0.55, weapon = 31, roadblock = true },
            [6] = { cars = 5, tanks = 2, mode = "ram",    aggression = 1.0, armed = true, accuracy = 0.65, weapon = 31, roadblock = true },
        },
        SPAWN_MIN = 180, SPAWN_MAX = 400,
        DESPAWN_DIST = 150,       -- gone only when unseen and this far from every player
        SPAWN_GAP = 2500,         -- ms between two new units of one chase
        FOOT_DIST = 40,           -- suspect stopped / on foot this close: the crew gets out
        BACK_TO_CAR = 70,         -- suspect drove off this far: the crew gets back in
        ARREST_DIST = 2,
        ARREST_TIME = 3000,
        INTERCEPT_LEVEL = 2,      -- from this level some units cut the suspect off on the predicted path
        ROADBLOCK_AHEAD = 260,    -- road block this far ahead on the predicted path
        SEARCH_RADIUS = 120,      -- evasion: the units search this far around the last known position
        SIREN_SWITCH = { 6000, 15000 },
        BLIP = { icon = 0, size = 1, color = { 60, 130, 255 } },   -- AI units on the radar, only for their suspect
        SKINS = { 280, 281, 282, 283, 284, 288 },
        RURAL_SKINS = { 283, 288 },
        TANK_SKIN = 287,
        CITY_BOX = { { 44, -2860, 2997, -1050 }, { -2997, -1050, -1350, 1550 }, { 680, 590, 2997, 2997 } },
    },

    UNITS = {
        NUMBER_MIN = 1, NUMBER_MAX = 999,
        ADAM_MIN = 2, ADAM_MAX = 4,   -- Adam: 2-4 officers (never alone); Lincoln: exactly 1
        INVITE_DIST = 15,
        INVITE_TIMEOUT = 60000,
    },

    PAY = {
        traffic_warning = 300, traffic_fine = 500, arrest_npc = 1500, arrest_player = 3000,
        pursuit_caught = 2000, backup = 200, duty_10min = 150,
        xp_traffic_warning = 40, xp_traffic_fine = 60, xp_arrest_npc = 150, xp_arrest_player = 300,
        xp_pursuit_caught = 200, xp_backup = 20, xp_duty_10min = 10,
        LEVEL_MULT = { 1, 1.4, 1.8, 2.2, 2.6, 3 },  -- player arrest pay x the wanted level
        WARNING_REPEAT = 600,     -- traffic stop with a warning: the same subject pays once per 10 min
        HOUR_CAP = 9000,          -- max pay per hour of shift
        AFK_MINUTES = 3,          -- no movement this long: the duty time stops counting
    },

    JAIL = {
        WARRANT_MAX_MINUTES = 10,
        CHECK = 2000,             -- ms: escape check
        ESCAPE_DIST = 12,
        ACC_KEY = "police.jail",  -- accData: { untilTs, minutes, station, reason }
    },

    STOP = {
        HOLD = 800,               -- hold E this long on a ped / player in front
        PED_RANGE = 4,
        VEH_RANGE = 25,
        VEH_CONE = 12,            -- degrees
        LEAVE_DIST = 15,          -- a stopped player farther than this: the stop ends (logged)
        PULLOVER_TIME = 20,       -- s for a player driver to stop
        SIREN_BLIP = 500,         -- ms of siren when the lights were off
        MENU_RANGE = 3.5,
    },

    ARREST = {
        CUFF_DIST = 1.5,
        CUFF_TIME = 2000,
        CUFF_BREAK = 2.0,
        PLACE_DIST = 4,
    },

    QUERY = { HIDE_AFTER = 30000 },
    PLATES = { RANGE = 25, MAX = 8, INTERVAL = 300 },
    MDC = { PAGE_SIZE = 25, FEED_INTERVAL = 2000, CACHE = 10000 },
    -- MDC computers (/mdcpc): the full MDC without a unit, J on foot next to one
    TERMINALS = {
        FILE = "mdc_terminals.json",  -- in the resource folder
        MODEL = 2190,             -- PC_1 (monitor + keyboard; its visual base is its origin)
        RANGE = 1.8,              -- J works this close
        CLOSE_DIST = 3.5,         -- the open MDC closes farther than this
        CHECK = 500,              -- ms: nearest computer check (the hint layer is on only near one)
        -- placement editor (/mdcpc, like gov_office /govpcs)
        EDIT_RANGE = 40,          -- a computer may be placed / moved this far from the admin
        ROT_STEP = 15,            -- degrees per wheel tick
        ROT_FINE = 1,             -- with Shift held
        HEIGHT_STEP = 0.02,       -- metres per wheel tick with Ctrl held
        RAY = 25,
    },

    TOW = { MODEL = 525, SPAWN_MIN = 150, SPAWN_MAX = 350, REQUEST_DIST = 15, SKIN = 50 },
    MEDICAL = { MODEL = 416, SPAWN_MIN = 150, SPAWN_MAX = 350, SKIN = 274, PAINTJOB = "hu_omsz" },

    -- work_police levels = ranks (police_system decides the rights by them)
    RANKS = {
        WARRANT_EDIT = 7,         -- Hadnagy: edit / revoke someone else's warrant
        FINE_REVIEW = 9,          -- Százados: review / refund fines
    },

    HISTORY = {
        WARRANT = 0.04, FINES = 0.30, WARNINGS = 0.25, SUSPENDED = 0.06,
        ALCOHOL = 0.05, ALCOHOL_NIGHT = 0.10, DRUG = 0.04,
        EXPIRED_INSPECTION = 0.07, STOLEN = 0.02, FLEE = 0.03, FLEE_WARRANT = 0.15,
        AGE = { 18, 72 },
        PLATE_CHECK = 12 * 3600 * 1000,   -- player vehicle plates re-read from v_ownveh
    },

    STATS_CACHE = 60,   -- s, getPublicStats (police_web)
    LOG_FLUSH = 30000,  -- ms, pol_shifts.events batches
}

-- the police vehicle test (shared: the client checks it before binding J)
function isPoliceModelVehicle(veh)
    if not isElement(veh) or getElementType(veh) ~= "vehicle" then return false end
    local def = POLICE.VEHICLES[getElementModel(veh)]
    if not def then return false end
    if def.paintjob and getElementData(veh, POLICE.PAINTJOB_KEY) ~= def.paintjob then return false end
    return true, def
end
