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

    SOUND_FOLDER  = "sounds/",  -- list header "sound": file name in this folder (must be a <file> in meta.xml)
    SOUND_RANGE   = 20,         -- client: the loop of the nearest uncollected item is audible closer than this (3D)
    SOUND_FULL    = 2,          -- ... at full (SOUND_VOLUME) volume closer than this, fading out towards SOUND_RANGE
    SOUND_VOLUME  = 0.08,       -- very quiet on purpose
    SOUND_MS      = 300,        -- client: nearest item check interval
    SOUND_PREVIEW_MS = 6000,    -- editor: length of the sound preview
    SOUND_MAX     = 64,         -- max file name length

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
