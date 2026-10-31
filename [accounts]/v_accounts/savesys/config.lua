-- v_accounts savesys configuration (server).

SAVE = {
    INTERVAL      = 120000,   -- ms, periodic autosave
    DEFAULT_SKIN  = 295,
    -- first spawn of a new account / no saved position
    DEFAULT_SPAWN = { x = 1685.6845703125, y = -2330.2578125, z = -1.6796875, rot = 0 },
}

-- Collectibles: one JSON blob in accData "collectibles" = { [id] = count }.
-- `data` is the element data mirrored on the player (ui_inac Collectibles menu),
-- `label` a v_locals key, `total` the number that exists (nil = unknown).
COLLECTIBLES = {
    { id = "stunts_air",  data = "collectibles_stuntsair",    label = "ui_inac.main.stunts_air",          total = nil },
    { id = "stunts_land", data = "collectibles_stuntsland",   label = "ui_inac.main.stunts_land",         total = nil },
    { id = "ufo_parts",   data = "collectibles_ufoshipparts", label = "ui_inac.main.ufo_spaceship_parts", total = nil },
}

-- Walking styles of the walkStyle preference: id -> GTA style (setPedWalkingStyle).
-- The menus (ui_inac Preferences, v_mainmenu Settings) list the same ids, label "common.walk.<id>".
WALK_STYLES = {
    default = 0,   man = 118,      shuffle = 119,   oldman = 120,    gang1 = 121,
    gang2 = 122,   oldfatman = 123, fatman = 124,   jogger = 125,    drunkman = 126,
    blindman = 127, swat = 128,    woman = 129,     shopping = 130,  busywoman = 131,
    sexywoman = 132, pro = 133,    oldwoman = 134,  fatwoman = 135,  jogwoman = 136,
    oldfatwoman = 137,
}

local walkValues = {}
for id in pairs(WALK_STYLES) do walkValues[id] = true end

-- Preferences: accData "pref.<id>", mirrored as element data "pref.<id>".
PREFERENCES = {
    spawnLocation = { values = { last = true, random = true }, default = "last" },
    walkStyle     = { values = walkValues, default = "default" },
}
