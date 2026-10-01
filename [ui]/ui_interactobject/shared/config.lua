-- Tunables for the world interaction menus.

IO = {
    KEY_OPEN = "x",               -- open / close the focused menu
    KEY_PREV = "q",               -- focus the previous nearby menu (to the left on screen)
    KEY_NEXT = "e",               -- focus the next nearby menu (to the right on screen)
    KEY_BACK = "backspace",       -- submenu up / close
    KEY_PAGE = "0",               -- next page when a menu has more than ITEMS_PER_PAGE items

    ITEMS_PER_PAGE = 9,           -- number keys 1-9 (max 9)
    DEFAULT_RANGE = 3.0,          -- metres, per menu (def.range)
    MAX_RANGE = 15.0,             -- hard cap for def.range
    SCAN_INTERVAL = 150,          -- ms between nearby-element scans
    MAX_SUBMENU_DEPTH = 5,

    SERVER_RANGE_TOLERANCE = 2.0, -- extra metres the server accepts (latency)
    SELECT_COOLDOWN = 150,        -- ms between two accepted selections of a player

    -- Q/E and the mouse wheel switch weapons on foot; blocked while a menu is open or 2+ are in range.
    SUPPRESS_WEAPON_SWITCH = true,

    -- Element data flags of other panels (same list as ui_inac); while any is set, no menu shows.
    BLOCKING_DATA = {
        "paused", "socialPanelOpen", "phoneOpen", "browserOpen", "showChatInput",
        "reportPanelOpen", "textInputOpen", "interactionMenuOpen",
    },

    SOUNDS = true,
}
