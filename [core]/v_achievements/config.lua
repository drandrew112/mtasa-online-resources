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
    { id = "work",    name = "Work" },
    { id = "games",   name = "Games" },
}

-- unlocked by v_achievements itself on the player's first onPlayerLoaded
ACH.LOGIN_ACHIEVEMENT = "welcome_sa"

ACH.LIST = {
    { id = "welcome_sa", type = "once", category = "general",
      name = "Welcome to San Andreas", desc = "Log in for the first time.", xp = 100 },

    -- work_ems
    { id = "ems_duty", type = "once", category = "work",
      name = "First Responder", desc = "Go on duty in EMS.", xp = 150 },

    -- work_ems: +1 per completed hospital handover, every unit member
    { id = "ems_patients_1",   type = "progress", stat = "ems_patients", goal = 1,   category = "work",
      series = "ems_patients", tier = 1, unit = "patients",
      name = "First Patient",   desc = "Treat 1 patient.",    xp = 50 },
    { id = "ems_patients_5",   type = "progress", stat = "ems_patients", goal = 5,   category = "work",
      series = "ems_patients", tier = 2, unit = "patients",
      name = "Caregiver",       desc = "Treat 5 patients.",   xp = 100 },
    { id = "ems_patients_10",  type = "progress", stat = "ems_patients", goal = 10,  category = "work",
      series = "ems_patients", tier = 3, unit = "patients",
      name = "Paramedic",       desc = "Treat 10 patients.",  xp = 150 },
    { id = "ems_patients_25",  type = "progress", stat = "ems_patients", goal = 25,  category = "work",
      series = "ems_patients", tier = 4, unit = "patients",
      name = "Life Saver",      desc = "Treat 25 patients.",  xp = 250 },
    { id = "ems_patients_50",  type = "progress", stat = "ems_patients", goal = 50,  category = "work",
      series = "ems_patients", tier = 5, unit = "patients",
      name = "Guardian Angel",  desc = "Treat 50 patients.",  xp = 400 },
    { id = "ems_patients_100", type = "progress", stat = "ems_patients", goal = 100, category = "work",
      series = "ems_patients", tier = 6, unit = "patients",
      name = "Miracle Worker",  desc = "Treat 100 patients.", xp = 750 },

    -- work_traindriver
    { id = "train_duty", type = "once", category = "work",
      name = "All Aboard", desc = "Go on duty as a train driver.", xp = 150 },

    -- work_traindriver: +1 per paid (completed) rail service
    { id = "train_services_1",   type = "progress", stat = "train_services", goal = 1,   category = "work",
      series = "train_services", tier = 1, unit = "services",
      name = "First Departure",  desc = "Complete 1 service.",    xp = 50 },
    { id = "train_services_5",   type = "progress", stat = "train_services", goal = 5,   category = "work",
      series = "train_services", tier = 2, unit = "services",
      name = "Regular Service",  desc = "Complete 5 services.",   xp = 100 },
    { id = "train_services_10",  type = "progress", stat = "train_services", goal = 10,  category = "work",
      series = "train_services", tier = 3, unit = "services",
      name = "On Schedule",      desc = "Complete 10 services.",  xp = 150 },
    { id = "train_services_25",  type = "progress", stat = "train_services", goal = 25,  category = "work",
      series = "train_services", tier = 4, unit = "services",
      name = "Seasoned Driver",  desc = "Complete 25 services.",  xp = 250 },
    { id = "train_services_50",  type = "progress", stat = "train_services", goal = 50,  category = "work",
      series = "train_services", tier = 5, unit = "services",
      name = "Rail Veteran",     desc = "Complete 50 services.",  xp = 400 },
    { id = "train_services_100", type = "progress", stat = "train_services", goal = 100, category = "work",
      series = "train_services", tier = 6, unit = "services",
      name = "Sunline Legend",   desc = "Complete 100 services.", xp = 750 },

    -- v_jobmanager (host starts a match)
    { id = "host_game", type = "once", category = "games",
      name = "Game Master", desc = "Host a game.", xp = 100 },

    -- v_arenawar
    { id = "arena_war", type = "once", category = "games",
      name = "Into the Arena", desc = "Join Arena War.", xp = 100 },

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
