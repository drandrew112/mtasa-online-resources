-- Shared config. Every category maps a folder to the model-ID range it may replace.
-- Drop "<id>.dff", "<id>.txd" (and optionally "<id>.col") into the folder, run /modloader update, restart.
--
--   setting   the ui_pause setting (Settings > Models) that turns loading the category on / off
--   default   loading on / off while the player never changed the setting
MODLOADER = {
    categories = {
        { name = "vehicles", min = 400, max = 611,   setting = "models_vehicles", default = true  },
        { name = "skins",    min = 0,   max = 312,     setting = "models_skins",    default = true },
        { name = "weapons",  min = 321, max = 373,     setting = "models_weapons",  default = true },
        { name = "objects",  min = 615, max = 19999,   setting = "models_objects",  default = true },
    },

    -- object IDs that are always loaded, also with "Custom object models" turned off.
    -- The models of the maps (maps_loader) are here: the maps are built for them (bus station, LSPD
    -- interior, zebra crossings, SF garage), turning them off would break the map.
    ALWAYS_LOAD_OBJECTS = {
        14802,                  -- volan: LS bus station (ls_busstation)
        3976, 4230, 14846,      -- int_lspd: LSPD building, its texture set and the interior (ls_int_pd)
        7557,                   -- zebra: double zebra crossings (ls_zebra)
        11326, 11387, 11389,    -- sf_garage: garage textures (sf_garage)
    },

    -- event models: object IDs that are loaded ONLY while an event asks for them (server exports
    -- setEventModelEnabled(id, bool) / isEventModelEnabled / getEventModels, like the event maps of
    -- maps_loader). Not loaded at join, independent of the "Custom object models" setting; the files
    -- are still downloaded with the resource. The state is not saved: a restart switches all off.
    EVENT_OBJECTS = {
        3985, 19577, 19574, 19576, 19575, 2703,
    },
    DATA_EVENT_MODELS = "modloader.events",   -- resourceRoot element data: { [id] = true } while on

    -- engineSetModelLODDistance while the replacement is loaded (reset when it unloads)
    MODEL_LOD = {
        [14802] = 300,          -- volan (was map_ls_busstation/client.lua)
    },

    -- engineSetModelFlag flags set while the replacement is loaded (reset when it unloads)
    -- (dont_receive_shadows has no effect on map buildings: GTA copies it to the building only
    --  when the map loads; see AS_OBJECT)
    MODEL_FLAGS = {
    },

    -- map buildings removed and created again as objects while the replacement is loaded.
    -- GTA casts tree / pole shadows on map buildings only, so the object gets none.
    -- lod = model ID of its LOD building (removed and recreated as well)
    AS_OBJECT = {
        [5708] = { x = 1134.25, y = -1338.078125, z = 23.15625, rz = 0, lod = 5930 },  -- hospital: palm shadows were projected into the rooms
    },

    ADMIN_LEVEL = 5,        -- account admin_level needed for /modloader (console always allowed)

    -- client: load mods in slices so the game does not freeze
    SLICE_MS    = 30,       -- max ms of loading per slice
    SLICE_PAUSE = 50,       -- ms between slices

    LOG_FILE      = "logs/modloader.log",
    LOG_MAX       = 1024 * 1024,
    NAMES_FILE    = "models.json",
    MANIFEST_FILE = "manifest.json",        -- generated: size / md5 / added time of every model file
}

function modloaderCategory(name)
    for _, cat in ipairs(MODLOADER.categories) do
        if cat.name == name then return cat end
    end
end
