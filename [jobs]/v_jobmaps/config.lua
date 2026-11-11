-- v_jobmaps settings (server + client)
--
-- A job map is a folder:  maps/<name>/<name>.map   objects (MTA map editor format; model="hr01" is a custom
--                                                  model of map.json, model="1234" a normal GTA model)
--                         maps/<name>/map.json     title, texture archives, custom model definitions
--                         maps/<name>/models|col|textures/   the files (listed in meta.xml by tools/build.py)
-- maps/index.json lists the maps; `python -I tools/build.py import <zip> <name>` / `meta` write all of it.

JOBMAPS = {
    MAPS_DIR = "maps",
    INDEX_FILE = "maps/index.json",

    -- engineRequestModel("object", PARENT_MODEL): every custom model of a loaded map takes a new free
    -- object model id that inherits the physical properties of this model (1337 = MTA's default)
    PARENT_MODEL = 1337,

    ADMIN_LEVEL = 5,          -- account admin_level for the /jobmap test command

    -- the client builds a map step by step (one txd / model per step) so the game does not freeze
    STEP_DELAY = 40,          -- ms between two load steps
}

-- events
EV_LOAD = "v_jobmaps:load"           -- server -> client: map payload for this player
EV_UNLOAD = "v_jobmaps:unload"       -- server -> client: name
EV_READY = "v_jobmaps:ready"         -- client -> server: name (models + objects exist)
EV_FAILED = "v_jobmaps:failed"       -- client -> server: name, reason
EV_REQUEST = "v_jobmaps:request"     -- client -> server: a restarted client asks for its maps again
