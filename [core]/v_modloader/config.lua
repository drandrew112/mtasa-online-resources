-- Shared config. Every category maps a folder to the model-ID range it may replace.
-- Drop "<id>.dff", "<id>.txd" (and optionally "<id>.col") into the folder, run /modloader update, restart.
--
--   download  "auto"   the files are in meta.xml normally, every client downloads them on join
--             "manual" download="false": only downloaded from Settings > Models (or auto-update)
--   setting   the ui_pause setting (Settings > Models) that turns loading the category on / off
--   default   loading on / off while the player never changed the setting
MODLOADER = {
    categories = {
        { name = "vehicles", min = 400, max = 611,   download = "manual", setting = "models_vehicles", default = false },
        { name = "skins",    min = 0,   max = 312,   download = "auto",   setting = "models_skins",    default = true },
        { name = "weapons",  min = 321, max = 373,   download = "auto",   setting = "models_weapons",  default = true },
        { name = "objects",  min = 615, max = 19999, download = "auto",   setting = "models_objects",  default = true },
    },

    -- object IDs that are always loaded, also with "Custom object models" turned off
    ALWAYS_LOAD_OBJECTS = {
    },

    -- auto-update: every new / changed "manual" model is downloaded after the login
    AUTOUPDATE_SETTING = "models_autoupdate",
    AUTOUPDATE_DEFAULT = false,

    ADMIN_LEVEL = 5,        -- account admin_level needed for /modloader (console always allowed)

    -- client: load mods in slices so the game does not freeze
    SLICE_MS    = 30,       -- max ms of loading per slice
    SLICE_PAUSE = 50,       -- ms between slices

    -- client: downloadFile retries of one file before it is skipped
    DOWNLOAD_RETRIES = 1,

    LOG_FILE      = "logs/modloader.log",
    LOG_MAX       = 1024 * 1024,
    NAMES_FILE    = "models.json",
    MANIFEST_FILE = "manifest.json",        -- generated: size / md5 / added time of every model file
    LOCAL_FILE    = "@downloaded.json",     -- client, private: path -> md5 of the downloaded files
}

function modloaderCategory(name)
    for _, cat in ipairs(MODLOADER.categories) do
        if cat.name == name then return cat end
    end
end
