-- GTA 6 event definition (registered in events_core).
-- The model ids must also be in v_modloader config EVENT_OBJECTS (files in v_modloader/objects),
-- maps need "event": true in maps_loader/maps/<name>/settings.json.
EVENT_GTA6 = {
    id = "gta6",
    name = "GTA 6",
    description = "GTA 6 event: DVD_GTA6 (model 1455).",
    models = {
        1455,       -- DVD_GTA6
    },
    -- maps_loader map names that belong to the event (none yet)
    maps = {
    },
    -- v_collectibles list ids (data/lists/<id>.json made in /collecteditor with "Event list" on);
    -- they are only visible while the event runs, e.g. collectibles = { "gta6_dvds" }
    collectibles = {
    },
}
