-- acc_loading configuration (client).

-- Resources whose client side must report exports.acc_loading:resourceReady()
-- before the player is spawned. A listed resource that is not running on the
-- client is not waited for.
LOADING_REQUIRED = {
    "ui_inac", "ui_pause", "ui_phone", "v_admin", "v_introduce", "v_weekly",
    "v_socialpanel", "v_jobmanager", "v_jobcreator", "v_arenawar",
    "med_erm", "work_ems", "rw_loco", "shader_colors", "v_modloader",
    "world_clothes-shop", "world_ferriswheel",
    -- resources whose shared configs / tables hold texts (v_locals L.config or own gate)
    "v_stats", "v_radar", "v_nametags", "v_customs", "v_els",
    "medsys", "medsys_effects", "medsys_events", "med_bag", "med_hospitals",
    "mg_airway", "mg_cpr", "mg_intravenous",
    "rw_core", "rw_customtracks", "rw_signals", "rw_timetable",
    "work_atc", "work_traindriver", "world_elevators", "map_int_sacontrol",
}

-- log the still missing reports this often while waiting (ms)
LOADING_WARN_INTERVAL = 10000
