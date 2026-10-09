-- v_stats configuration (shared).
--
-- Every stat is registered here. `id` is the stable string key used by the
-- exports and stored in the players' account data - never rename a live id.
--
-- Fields:
--   id       (string, required)  unique, stable
--   name     (string, required)  shown in UI
--   unit     (string)            "km" | "s" | "" (plain count)
--   achStat  (string)            optional: v_achievements stat key. The stat's
--                                value is pushed there (exports.v_achievements
--                                :setStat) every time it changes. Using the same
--                                key as the id lets you add achievements for it
--                                later from v_achievements/config.lua only.

STATS = {}

-- account data key holding the per-player JSON blob
STATS.STORAGE_KEY = "stats"

-- dirty stats are written back to MySQL this often (ms)
STATS.FLUSH_INTERVAL = 60000

-- changed stats are forwarded to v_achievements at most this often (ms)
STATS.ACH_PUSH_INTERVAL = 10000

-- movement sampling period (ms)
STATS.TICK = 1000

-- A sample moving faster than this (m/s) is treated as a teleport / warp and
-- ignored for distance.
STATS.MAX_SPEED = { foot = 15, land = 120, water = 80, air = 250 }

STATS.LIST = {
    { id = "drive_km",  name = "Distance driven (land vehicles)",  unit = "km", achStat = "drive_km" },
    { id = "walk_km",   name = "Distance walked",                  unit = "km", achStat = "walk_km"  },
    { id = "sail_km",   name = "Distance sailed (water vehicles)", unit = "km", achStat = "sail_km"  },
    { id = "fly_km",    name = "Distance flown (air vehicles)",    unit = "km", achStat = "fly_km"   },

    { id = "drive_time", name = "Time driving (land vehicles)",  unit = "s", achStat = "drive_time" },
    { id = "sail_time",  name = "Time sailing (water vehicles)", unit = "s", achStat = "sail_time"  },
    { id = "fly_time",   name = "Time flying (air vehicles)",    unit = "s", achStat = "fly_time"   },

    { id = "kills_peds",    name = "Kills (peds)",    unit = "", achStat = "kills_peds"    },
    { id = "kills_players", name = "Kills (players)", unit = "", achStat = "kills_players" },

    { id = "deaths",            name = "Deaths (all)",               unit = "", achStat = "deaths"            },
    { id = "deaths_by_players", name = "Deaths (killed by players)", unit = "", achStat = "deaths_by_players" },
}
