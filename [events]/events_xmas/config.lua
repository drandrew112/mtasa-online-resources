-- Christmas event definition (registered in events_core).
-- The model ids must also be in v_modloader config EVENT_OBJECTS (files in v_modloader/objects),
-- the map must have "event": true in maps_loader/maps/<name>/settings.json.
EVENT_XMAS = {
    id = "xmas",
    name = "Christmas",
    description = "Christmas tree and gifts in Los Santos (ls_xmas_tree).",
    models = {
        3985,       -- tree
        19577, 19574, 19576, 19575, 2703,   -- gifts
    },
    maps = { "ls_xmas_tree" },
}
