-- v_achievements configuration (shared).
--
-- Every achievement is registered here. `id` is the stable key stored in the
-- players' account data - never rename an id once it is live, add a new one.
--
-- Fields:
--   id        (string, required)  unique, stable
--   type      (required)          "once" | "progress"
--   name      (string, required)  shown in UI
--   desc      (string, required)  shown in UI
--   goal      (number)            required for "progress"
--   stat      (string)            "progress" only: shared counter key. Every
--                                 achievement with the same stat advances
--                                 together (exports addStat / setStat), e.g.
--                                 drive_km -> Drive 50 / 100 / 250 / 500 km.
--   xp        (number)            XP granted on unlock (v_levelsys), default 0
--   category  (string)            id from ACH.CATEGORIES
--   series    (string)            groups tiers in UI, e.g. "drive"
--   tier      (number)            position inside the series
--   unit      (string)            progress unit for UI, e.g. "km"
--   hidden    (bool)              UI should mask it until unlocked
--   icon      (string)            optional icon path for UI

ACH = {}

-- account data key holding the per-player JSON blob
ACH.STORAGE_KEY = "achievements"

-- dirty progress is written back to MySQL this often (ms); unlocks are
-- always written immediately
ACH.FLUSH_INTERVAL = 60000

-- admin_level above this may use /ach
ACH.ADMIN_LEVEL = 2

ACH.CATEGORIES = {
    { id = "general", name = "General" },
    { id = "driving", name = "Driving" },
    { id = "walking", name = "Walking" },
    { id = "sailing", name = "Sailing" },
    { id = "flying",  name = "Flying" },
    { id = "work",    name = "Work" },
    { id = "games",   name = "Games" },
}

-- unlocked by v_achievements itself on the player's first onPlayerLoaded
ACH.LOGIN_ACHIEVEMENT = "welcome_sa"

ACH.LIST = {
    { id = "welcome_sa", type = "once", category = "general",
      name = "Welcome to San Andreas", desc = "Log in for the first time.", xp = 200 },

    -- work_ems
    { id = "ems_duty", type = "once", category = "work",
      name = "First Responder", desc = "Go on duty in EMS.", xp = 300 },

    -- work_ems: +1 per completed hospital handover, every unit member
    { id = "ems_patients_1",   type = "progress", stat = "ems_patients", goal = 1,   category = "work",
      series = "ems_patients", tier = 1, unit = "patients",
      name = "First Patient",   desc = "Treat 1 patient.",    xp = 100 },
    { id = "ems_patients_5",   type = "progress", stat = "ems_patients", goal = 5,   category = "work",
      series = "ems_patients", tier = 2, unit = "patients",
      name = "Caregiver",       desc = "Treat 5 patients.",   xp = 200 },
    { id = "ems_patients_10",  type = "progress", stat = "ems_patients", goal = 10,  category = "work",
      series = "ems_patients", tier = 3, unit = "patients",
      name = "Paramedic",       desc = "Treat 10 patients.",  xp = 300 },
    { id = "ems_patients_25",  type = "progress", stat = "ems_patients", goal = 25,  category = "work",
      series = "ems_patients", tier = 4, unit = "patients",
      name = "Life Saver",      desc = "Treat 25 patients.",  xp = 500 },
    { id = "ems_patients_50",  type = "progress", stat = "ems_patients", goal = 50,  category = "work",
      series = "ems_patients", tier = 5, unit = "patients",
      name = "Guardian Angel",  desc = "Treat 50 patients.",  xp = 800 },
    { id = "ems_patients_100", type = "progress", stat = "ems_patients", goal = 100, category = "work",
      series = "ems_patients", tier = 6, unit = "patients",
      name = "Miracle Worker",  desc = "Treat 100 patients.", xp = 1500 },

    -- work_traindriver
    { id = "train_duty", type = "once", category = "work",
      name = "All Aboard", desc = "Go on duty as a train driver.", xp = 300 },

    -- work_traindriver: +1 per paid (completed) rail service
    { id = "train_services_1",   type = "progress", stat = "train_services", goal = 1,   category = "work",
      series = "train_services", tier = 1, unit = "services",
      name = "First Departure",  desc = "Complete 1 service.",    xp = 100 },
    { id = "train_services_5",   type = "progress", stat = "train_services", goal = 5,   category = "work",
      series = "train_services", tier = 2, unit = "services",
      name = "Regular Service",  desc = "Complete 5 services.",   xp = 200 },
    { id = "train_services_10",  type = "progress", stat = "train_services", goal = 10,  category = "work",
      series = "train_services", tier = 3, unit = "services",
      name = "On Schedule",      desc = "Complete 10 services.",  xp = 300 },
    { id = "train_services_25",  type = "progress", stat = "train_services", goal = 25,  category = "work",
      series = "train_services", tier = 4, unit = "services",
      name = "Seasoned Driver",  desc = "Complete 25 services.",  xp = 500 },
    { id = "train_services_50",  type = "progress", stat = "train_services", goal = 50,  category = "work",
      series = "train_services", tier = 5, unit = "services",
      name = "Rail Veteran",     desc = "Complete 50 services.",  xp = 800 },
    { id = "train_services_100", type = "progress", stat = "train_services", goal = 100, category = "work",
      series = "train_services", tier = 6, unit = "services",
      name = "Sunline Legend",   desc = "Complete 100 services.", xp = 1500 },

    -- v_jobmanager (host starts a match)
    { id = "host_game", type = "once", category = "games",
      name = "Game Master", desc = "Host a game.", xp = 200 },

    -- v_arenawar
    { id = "arena_war", type = "once", category = "games",
      name = "Into the Arena", desc = "Join Arena War.", xp = 200 },

    -- Examples (uncomment / replace with real ones):
    --
    -- { id = "first_steps", type = "once", category = "general",
    --   name = "First Steps", desc = "Finish the introduction.", xp = 100 },
    --
    -- { id = "drive_50",  type = "progress", stat = "drive_km", goal = 50,
    --   category = "driving", series = "drive", tier = 1, unit = "km",
    --   name = "Sunday Driver", desc = "Drive 50 km.", xp = 100 },
    -- { id = "drive_100", type = "progress", stat = "drive_km", goal = 100,
    --   category = "driving", series = "drive", tier = 2, unit = "km",
    --   name = "Commuter", desc = "Drive 100 km.", xp = 200 },
    --
    -- { id = "ems_treat_25", type = "progress", goal = 25, category = "work",
    --   name = "Life Saver", desc = "Treat 25 patients.", xp = 250 },
}

-- Distance sets. Fed by stat counters (exports addStat / setStat), the counters
-- themselves are tracked elsewhere (v_stats): "drive_km" = km driven in land
-- vehicles, "walk_km" = km travelled on foot,
-- "sail_km" = km in water vehicles, "fly_km" = km in air vehicles.
local function distanceSet(stat, category, prefix, verb, unit, tiers)
    for i, t in ipairs(tiers) do
        local km = tostring(t.km):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        ACH.LIST[#ACH.LIST + 1] = {
            id = prefix .. t.km, type = "progress", stat = stat, goal = t.km,
            category = category, series = prefix:gsub("_$", ""), tier = i, unit = "km",
            name = t.name, desc = verb .. " " .. km .. " km" .. unit .. ".", xp = t.xp,
        }
    end
end

distanceSet("drive_km", "driving", "drive_", "Drive", " in land vehicles", {
    { km = 10,      xp = 100,  name = "Test Drive" },
    { km = 50,      xp = 200,  name = "Sunday Driver" },
    { km = 100,     xp = 300,  name = "Commuter" },
    { km = 1000,    xp = 500,  name = "Road Tripper" },
    { km = 5000,    xp = 800,  name = "Highway Regular" },
    { km = 10000,   xp = 1200, name = "Long Hauler" },
    { km = 25000,   xp = 1600, name = "Cross-Country" },
    { km = 50000,   xp = 2000, name = "Road Warrior" },
    { km = 100000,  xp = 3000, name = "Asphalt Veteran" },
    { km = 250000,  xp = 4000, name = "Endless Highway" },
    { km = 500000,  xp = 5000, name = "Wheels of Legend" },
    { km = 1000000, xp = 8000, name = "Million Mile Club" },
})

distanceSet("walk_km", "walking", "walk_", "Walk", "", {
    { km = 10,      xp = 100,  name = "First Steps" },
    { km = 50,      xp = 200,  name = "Stroller" },
    { km = 100,     xp = 300,  name = "Pedestrian" },
    { km = 1000,    xp = 500,  name = "Hiker" },
    { km = 5000,    xp = 800,  name = "Trailblazer" },
    { km = 10000,   xp = 1200, name = "Wanderer" },
    { km = 25000,   xp = 1600, name = "Marathoner" },
    { km = 50000,   xp = 2000, name = "Globetrotter" },
    { km = 100000,  xp = 3000, name = "Pathfinder" },
    { km = 250000,  xp = 4000, name = "Tireless Walker" },
    { km = 500000,  xp = 5000, name = "Legs of Steel" },
    { km = 1000000, xp = 8000, name = "Million Step Legend" },
})

distanceSet("sail_km", "sailing", "sail_", "Sail", " in water vehicles", {
    { km = 10, xp = 100, name = "Maiden Voyage" },
    { km = 50, xp = 200, name = "Weekend Sailor" },
    { km = 100, xp = 300, name = "Harbor Hopper" },
    { km = 1000, xp = 500, name = "Deckhand" },
    { km = 5000, xp = 800, name = "Coastal Cruiser" },
    { km = 10000, xp = 1200, name = "Sea Dog" },
    { km = 25000, xp = 1600, name = "Blue Water Sailor" },
    { km = 50000, xp = 2000, name = "Captain" },
    { km = 100000, xp = 3000, name = "Admiral" },
    { km = 250000, xp = 4000, name = "Ocean Master" },
    { km = 500000, xp = 5000, name = "Poseidon's Pick" },
    { km = 1000000, xp = 8000, name = "Seven Seas Legend" },
})

distanceSet("fly_km", "flying", "fly_", "Fly", " in air vehicles", {
    { km = 10, xp = 100, name = "First Flight" },
    { km = 50, xp = 200, name = "Weekend Pilot" },
    { km = 100, xp = 300, name = "Hop Skip Jump" },
    { km = 1000, xp = 500, name = "Frequent Flyer" },
    { km = 5000, xp = 800, name = "Sky Courier" },
    { km = 10000, xp = 1200, name = "Jet Setter" },
    { km = 25000, xp = 1600, name = "Ace Pilot" },
    { km = 50000, xp = 2000, name = "Squadron Leader" },
    { km = 100000, xp = 3000, name = "High Altitude" },
    { km = 250000, xp = 4000, name = "Sky Marshal" },
    { km = 500000, xp = 5000, name = "Cloud Sovereign" },
    { km = 1000000, xp = 8000, name = "Million Mile Aviator" },
})
