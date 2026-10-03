-- Claude MCP bridge - shared configuration

CMCP = {
    VERSION = "1.0.0",
    API_VERSION = 1,

    -- jobs (async requests that wait for the probe client / timers)
    JOB_KEEP = 120000,          -- ms a finished job result stays pollable
    JOB_MAX_RUNTIME = 60000,    -- ms before a running job is failed
    PROBE_TIMEOUT = 15000,      -- ms default wait for one probe client reply
    PROBE_STALE = 20000,        -- ms without a heartbeat -> probe considered gone

    -- probe streaming range: the client only has collision / models loaded near its camera
    PROBE_RANGE = 280,          -- m, beyond this a world query focuses the probe camera first
    FOCUS_SETTLE = 1500,        -- ms wait after moving the camera for streaming

    -- scan limits
    MAX_RADIUS = 400,
    MAX_RAYS = 12000,
    MAX_ENTITIES = 500,         -- per bridge instance (all workspaces)

    -- screenshots
    SHOT_MAX_W = 1920,
    SHOT_MAX_H = 1080,
    SHOT_TIMEOUT = 30000,

    -- default workspace
    DEFAULT_WORKSPACE = "default",
    ID_PREFIX = "tmp",

    -- log ring buffer
    LOG_SIZE = 600,

    -- resources whose status is reported (integrations)
    INTEGRATIONS = { "veh_manager", "medsys", "med_scenemanager", "med_erm", "v_radar", "ui_interactobject" },

    -- generic ped poses (setPedAnimation): id -> { block, anim, loop }
    -- loop = false: played once and held on the last frame
    POSES = {
        none      = { label = "Standing (no animation)" },
        lie_back  = { label = "Lying on back",       block = "CRACK",  anim = "crckdeth2",         loop = false },
        lie_front = { label = "Lying face down",     block = "PED",    anim = "KO_shot_front",     loop = false },
        injured   = { label = "Injured, rolling",    block = "SWEET",  anim = "Sweet_injuredloop", loop = true },
        sit_ground= { label = "Sitting on ground",   block = "BEACH",  anim = "ParkSit_M_loop",    loop = true },
        crouch    = { label = "Crouching / cowering",block = "PED",    anim = "cower",             loop = true },
        hold_side = { label = "Holding side",        block = "CRACK",  anim = "crckidle2",         loop = true },
        lean      = { label = "Leaning",             block = "GANGS",  anim = "leanIDLE",          loop = true },
        hands_up  = { label = "Hands up",            block = "PED",    anim = "handsup",           loop = false },
        phone     = { label = "Talking on phone",    block = "PED",    anim = "phone_talk",        loop = true },
        idle_chat = { label = "Chatting",            block = "GANGS",  anim = "prtial_gngtlkA",    loop = true },
        wave      = { label = "Waving",              block = "ON_LOOKERS", anim = "wave_loop",     loop = true },
        look      = { label = "Onlooker",            block = "ON_LOOKERS", anim = "lkaround_loop", loop = true },
        cpr       = { label = "Kneeling (CPR)",      block = "MEDIC",  anim = "CPR",               loop = true },
        sit_chair = { label = "Sitting (seat)",      block = "PED",    anim = "SEAT_idle",         loop = true },
    },

    -- vehicle damage presets (health + door / panel / light / wheel states)
    DAMAGE = {
        repair = { health = 1000 },
        light  = { health = 750, doors = { 0, 0, 0, 0, 0, 0 }, panels = { 1, 0, 0, 0, 0, 1, 0 }, lights = { 1, 0, 0, 0 } },
        heavy  = { health = 420, doors = { 2, 0, 2, 3, 0, 0 }, panels = { 3, 2, 2, 1, 2, 3, 1 }, lights = { 1, 1, 0, 0 } },
        wreck  = { health = 300, doors = { 3, 2, 4, 4, 2, 3 }, panels = { 3, 3, 3, 3, 3, 3, 3 }, lights = { 1, 1, 1, 1 }, wheels = { 1, 0, 0, 0 } },
    },
}
