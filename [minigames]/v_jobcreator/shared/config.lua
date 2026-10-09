CREATOR = {
    -- admin level (v_mysql accData "admin_level") for publishing, opening anyone's
    -- game and placing the world marker
    ADMIN_LEVEL = 3,
    -- games one (non-admin) account may own
    MAX_GAMES_PER_PLAYER = 10,

    -- every editing session gets its own dimension: DIMENSION_BASE + slot
    DIMENSION_BASE = 45000,

    LIMITS = {
        objects = 300,          -- = COMMUNITY_MAX_OBJECTS in v_jobmanager
        spawnpoints = 32,
        checkpoints = 150,
        vehicles = 10,
        maxPlayers = 16,
        name = 40,
        description = 300,
    },

    KEYS = {
        menu = "m",             -- editor hub (ui_inac temp menu)
        camera = "f5",          -- freecam <-> on foot
        look = "mouse2",        -- freecam: hold to look around (cursor otherwise)
        place = "mouse1",       -- place / select
        cancel = "backspace",   -- leave placing / moving
        confirm = "enter",
        photo = "space",
        undo = "z",             -- with lctrl
        redo = "y",             -- with lctrl
        testStop = "f6",
    },

    FREECAM = { speed = 0.5, fast = 3.0, slow = 0.1, sensitivity = 0.15 },
    MOVE = { step = 0.25, rotStep = 5, fastMul = 8, slowMul = 0.2 },

    THUMB = { width = 640, height = 360, quality = 85 },

    -- helper models for elements that have no world model of their own
    HELPER = { checkpoint = 1318, finish = 1318, marker = 1239, camera = 1886 },
}
