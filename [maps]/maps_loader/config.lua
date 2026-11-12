-- maps_loader settings (server + client)
--
-- Every map is a folder:  maps/<name>/<name>.map          (MTA map editor format)
--                         maps/<name>/settings.json       (optional, see below)
-- /maploader update finds new / removed folders and writes maps/index.json; a restart loads them.
--
-- settings.json (all optional):
--   { "disabled": false,
--     "event": false,                     -- true: event map, built only while switched on
--                                         -- (exports setEventMapEnabled / isEventMapEnabled, /maploader event)
--     "lod": "auto" | "none",             -- "none": no low LOD clones for this map at all
--     "indoor": [ { "name": "...", "min": [x, y, z], "max": [x, y, z], "margin": 12,
--                   "keep": [model, ...] } ] }
--   indoor: furniture inside a building. Objects inside the box exist only while the camera is
--   within `margin` metres of the box (behind walls they only cost draw calls), and never get a low
--   LOD clone. "keep" models are inside the box but always exist (e.g. an interior shell with floors).

MAPLOADER = {
    INDEX_FILE = "maps/index.json",
    MAPS_DIR = "maps",

    -- low LOD clones (drawdistance): only exterior objects at least this big (bounding radius x scale,
    -- metres). Small props are drawn only to their own GTA draw distance, like the game's own props.
    LOD_MIN_RADIUS = 10,

    -- a map's objects exist on a client only while the camera is within this distance of the map's
    -- bounding box: drawdistance far clip + ACTIVE_MARGIN; switched off again ACTIVE_HYSTERESIS later
    ACTIVE_MARGIN = 150,
    ACTIVE_HYSTERESIS = 100,
    ACTIVE_FALLBACK = 1600,      -- when drawdistance is not running
    CHECK_INTERVAL = 1000,       -- ms between map / indoor zone checks
    INDOOR_MARGIN = 12,          -- default indoor margin (settings.json "margin")
    INDOOR_CHECK = 250,          -- ms between indoor zone checks (the camera may walk through a door)

    -- objects whose model, position and rotation equal an earlier object (same map or another map)
    -- are skipped and reported (/maploader update, server log)
    DUP_POS = 0.02,              -- metres
    DUP_ROT = 0.5,               -- degrees

    ADMIN_LEVEL = 5,             -- account admin_level for /maploader (console always allowed)

    -- GTA occlusion zones stay in the world after removeWorldModel: inside rebuilt buildings they hide
    -- objects, players, peds and stretchers from some camera angles (players gone at 10-20 m).
    -- The old map_ls_int_pd turned them off for the whole server; maps_loader does it now.
    DISABLE_OCCLUSIONS = true,
}

-- events
EV_REQUEST = "maploader:request"     -- client -> server: send me the maps
EV_DATA = "maploader:data"           -- server -> client: { maps = { ... } }
DATA_DIMS = "maploader.dims"         -- resourceRoot element data: { [map] = { [dim] = "all" | "interior" } }
DATA_EVENTS = "maploader.events"     -- resourceRoot element data: { [event map] = true } while switched on
