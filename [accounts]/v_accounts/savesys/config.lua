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

-- Preferences: accData "pref.<id>", mirrored as element data "pref.<id>".
PREFERENCES = {
    spawnLocation = { values = { last = true, random = true }, default = "last" },
}
