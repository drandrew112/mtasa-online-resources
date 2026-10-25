-- Shared config. Paintjobs live in paintjobs/<model id>/<name>.dds|.png|.jpg; run
-- /paintjobs update (rebuilds meta.xml), then restart the resource.
--
-- paintjobs/<model id>/_model.json (optional):
--   { "texture": "remap_octavia",                 -- texture name / pattern the paintjob replaces
--     "names": { "hu_omsz": "OMSZ Ambulance" } }  -- readable names (default: the file name)
PAINTJOBS = {
    FOLDER = "paintjobs",

    -- texture replaced when the model has no _model.json "texture": every GTA remap
    -- texture (and most modded ones) starts with "remap"
    DEFAULT_TEXTURE = "remap*",

    -- the same name in more formats: the first one wins (dds has mipmaps, loads fastest)
    FORMATS = { "dds", "png", "jpg" },
    MAX_SIZE = 2048,        -- larger textures are refused; > 1024 is logged as a warning

    -- GTA tints remap textures with primary colour 1: it is set to white while a paintjob
    -- is on and restored when it comes off (the old colour rides in customs:extras)
    WHITE_PRIMARY = true,

    ADMIN_LEVEL = 5,        -- account admin_level needed for /paintjobs (console always allowed)

    -- client: a texture nothing uses any more is freed after this many ms
    TEXTURE_TTL = 30000,

    DATA_KEY      = "paintjob:custom",      -- vehicle element data: the paintjob name
    EXTRAS_KEY    = "customPaintjob",       -- customs:extras (v_ownveh persists it)
    EXTRAS_COLOR  = "customPaintjobColor",  -- customs:extras: primary colour before the paintjob
    MANIFEST_FILE = "manifest.json",        -- generated: size / md5 of every paintjob file
    LOCAL_FILE    = "@downloaded.json",     -- client, private: path -> md5 of the downloaded files
}
