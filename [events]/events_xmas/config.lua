-- Christmas event definition (registered in events_core).
-- The model ids must also be in v_modloader config EVENT_OBJECTS (files in v_modloader/objects),
-- the map must have "event": true in maps_loader/maps/<name>/settings.json.
EVENT_XMAS = {
    id = "xmas",
    name = "Christmas",
    description = "Christmas tree and gifts in Los Santos (ls_xmas_tree).",
    models = {
        3985,       -- tree
        2702, 2880, 2881, 2782, 2703,       -- gifts (GTA CJ_PIZZA_1, CJ_BURG_2, CJ_PIZZA_2, CJ_OYSTER_2, CJ_BURG_1)
    },
    maps = { "ls_xmas_tree" },
    -- v_collectibles list ids (data/lists/<id>.json made in /collecteditor with "Event list" on);
    -- they are only visible while the event runs, e.g. collectibles = { "xmas_gifts" },
    collectibles = {
        "2026_christmas"
    },
}
