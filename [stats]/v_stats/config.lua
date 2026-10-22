if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- v_stats configuration (shared).
--
-- Every stat is registered here. `id` is the stable string key used by the
-- exports and stored in the players' account data - never rename a live id.
--
-- Fields:
--   id       (string, required)  unique, stable
--   name     (string, required)  shown in UI
--   unit     (string)            "km" | "s" | "" (plain count)
--   category (string)            "distance" | "vehicle_time" | "combat" | "work" |
--                                "activities" | "business" | "other" - groups the stats in the
--                                pause menu Stats tab and the account menu
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
    { id = "drive_km",  name = L.text("v_stats.config.distance_driven_land_vehicles"),  unit = "km", category = "distance", achStat = "drive_km" },
    { id = "walk_km",   name = L.text("v_stats.config.distance_walked"),                  unit = "km", category = "distance", achStat = "walk_km"  },
    { id = "sail_km",   name = L.text("v_stats.config.distance_sailed_water_vehicles"), unit = "km", category = "distance", achStat = "sail_km"  },
    { id = "fly_km",    name = L.text("v_stats.config.distance_flown_air_vehicles"),    unit = "km", category = "distance", achStat = "fly_km"   },

    { id = "drive_time", name = L.text("v_stats.config.time_driving_land_vehicles"),  unit = "s", category = "vehicle_time", achStat = "drive_time" },
    { id = "sail_time",  name = L.text("v_stats.config.time_sailing_water_vehicles"), unit = "s", category = "vehicle_time", achStat = "sail_time"  },
    { id = "fly_time",   name = L.text("v_stats.config.time_flying_air_vehicles"),    unit = "s", category = "vehicle_time", achStat = "fly_time"   },

    { id = "kills_peds",    name = L.text("v_stats.config.kills_peds"),    unit = "", category = "combat", achStat = "kills_peds"    },
    { id = "kills_players", name = L.text("v_stats.config.kills_players"), unit = "", category = "combat", achStat = "kills_players" },

    { id = "deaths",            name = L.text("v_stats.config.deaths_all"),               unit = "", category = "combat", achStat = "deaths"            },
    { id = "deaths_by_players", name = L.text("v_stats.config.deaths_killed_by_players"), unit = "", category = "combat", achStat = "deaths_by_players" },

    -- work counters, raised by the work resources (exports.v_stats:addStat)
    { id = "ems_patients",  name = L.text("v_stats.config.ems_patients"),  unit = "", category = "work", achStat = "ems_patients"  },
    { id = "bt_deliveries", name = L.text("v_stats.config.bt_deliveries"), unit = "", category = "work", achStat = "bt_deliveries" },
    { id = "train_shifts",  name = L.text("v_stats.config.train_shifts"),  unit = "", category = "work", achStat = "train_shifts"  },

    -- time on duty, measured by v_stats itself from the work_core duty events (STATS.DUTY_STATS)
    { id = "duty_time_ems",            name = L.text("v_stats.config.duty_time_ems"),            unit = "s", category = "work", achStat = "duty_time_ems"            },
    { id = "duty_time_bloodtransport", name = L.text("v_stats.config.duty_time_bloodtransport"), unit = "s", category = "work", achStat = "duty_time_bloodtransport" },
    { id = "duty_time_traindriver",    name = L.text("v_stats.config.duty_time_traindriver"),    unit = "s", category = "work", achStat = "duty_time_traindriver"    },
    { id = "duty_time_atc",            name = L.text("v_stats.config.duty_time_atc"),            unit = "s", category = "work", achStat = "duty_time_atc"            },

    -- gang wars (v_gangwar)
    { id = "gangwar_played", name = L.text("v_stats.config.gangwar_played"), unit = "", category = "activities", achStat = "gangwar_played" },
    { id = "gangwar_won",    name = L.text("v_stats.config.gangwar_won"),    unit = "", category = "activities", achStat = "gangwar_won"    },

    -- organizations (biz_*): exports.biz_core:addBizStat
    { id = "biz_weed_sold", name = L.text("v_stats.config.biz_weed_sold"), unit = "", category = "business", achStat = "biz_weed_sold" },
    { id = "biz_sales_income", name = L.text("v_stats.config.biz_sales_income"), unit = "", category = "business", achStat = "biz_sales_income" },
    { id = "biz_deliveries", name = L.text("v_stats.config.biz_deliveries"), unit = "", category = "business", achStat = "biz_deliveries" },
    { id = "biz_deliveries_lost", name = L.text("v_stats.config.biz_deliveries_lost"), unit = "", category = "business", achStat = "biz_deliveries_lost" },
    { id = "biz_supply_runs", name = L.text("v_stats.config.biz_supply_runs"), unit = "", category = "business", achStat = "biz_supply_runs" },
    { id = "biz_supply_stolen", name = L.text("v_stats.config.biz_supply_stolen"), unit = "", category = "business", achStat = "biz_supply_stolen" },
    { id = "biz_supply_bought", name = L.text("v_stats.config.biz_supply_bought"), unit = "", category = "business", achStat = "biz_supply_bought" },
    { id = "biz_hijacks", name = L.text("v_stats.config.biz_hijacks"), unit = "", category = "business", achStat = "biz_hijacks" },
    { id = "biz_casino_income", name = L.text("v_stats.config.biz_casino_income"), unit = "", category = "business", achStat = "biz_casino_income" },
    { id = "biz_laundered", name = L.text("v_stats.config.biz_laundered"), unit = "", category = "business", achStat = "biz_laundered" },
    { id = "biz_assoc_deliveries", name = L.text("v_stats.config.biz_assoc_deliveries"), unit = "", category = "business", achStat = "biz_assoc_deliveries" },
    { id = "biz_assoc_income", name = L.text("v_stats.config.biz_assoc_income"), unit = "", category = "business", achStat = "biz_assoc_income" },
}

-- work_core work id -> duty time stat id
STATS.DUTY_STATS = {
    ems            = "duty_time_ems",
    bloodtransport = "duty_time_bloodtransport",
    traindriver    = "duty_time_traindriver",
    atc            = "duty_time_atc",
}

-- duty time is credited at least this often (ms), so a crash loses little
STATS.DUTY_TICK = 60000
end)
