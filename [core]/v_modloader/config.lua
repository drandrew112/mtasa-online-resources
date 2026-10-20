-- Shared config. Every category maps a folder to the model-ID range it may replace.
-- Drop "<id>.dff", "<id>.txd" (and optionally "<id>.col") into the folder, run /modloader update, restart.
MODLOADER = {
    categories = {
        { name = "vehicles", min = 400, max = 611 },
        { name = "skins",    min = 0,   max = 312 },
        { name = "weapons",  min = 321, max = 373 },
        { name = "objects",  min = 615, max = 19999 },
    },

    ADMIN_LEVEL = 5,        -- account admin_level needed for /modloader (console always allowed)

    -- client: load mods in slices so the game does not freeze
    SLICE_MS    = 30,       -- max ms of loading per slice
    SLICE_PAUSE = 50,       -- ms between slices

    LOG_FILE    = "logs/modloader.log",
    LOG_MAX     = 1024 * 1024,
    NAMES_FILE  = "models.json",
}
