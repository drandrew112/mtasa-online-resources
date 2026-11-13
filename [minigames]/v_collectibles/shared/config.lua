-- v_collectibles shared config.
COLLECT = {
    ADMIN_LEVEL   = 5,          -- account admin_level needed for /collecteditor
    PICKUP_RANGE  = 3.0,        -- client: the player must get closer than this (3D) to pick an item up
    SERVER_RANGE  = 8.0,        -- server re-check (lag tolerance) of the pickup distance
    STREAM_IN     = 150,        -- client: items closer than this (2D) get their object created
    STREAM_OUT    = 180,        -- ... and farther than this get it destroyed
    STREAM_MS     = 1000,       -- client: object streaming check interval
    PICKUP_MS     = 150,        -- client: pickup distance check interval
    SPIN_SPEED    = 90,         -- degrees / second for lists with "spin": true

    FOLDER        = "data/lists/",      -- one <id>.json per list
    INDEX         = "data/index.json",  -- list ids (fallback when pathListDir is missing)

    DATA_KEY      = "collectibles.lists", -- LOCAL client element data read by ui_inac (Collectibles menu)

    DEFAULT_REWARD = 2000,      -- money (euro) per picked-up item when a list has no "reward"
    MAX_REWARD    = 1000000,    -- editor limit per item

    MAX_ITEMS     = 2000,       -- per list
    MAX_MODELS    = 32,         -- per list header
    ID_PATTERN    = "^[a-z0-9_]+$",
    ID_MAX        = 32,
    NAME_MAX      = 48,

    EDITOR_LABEL_RANGE = 80,    -- editor: "#id" labels above items closer than this
}
