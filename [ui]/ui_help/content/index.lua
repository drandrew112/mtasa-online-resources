-- Help content index (client). The text format is described in README.md.
--
-- categories: { id, order, title }
--     title = plain string, { en = "...", hu = "..." } or a v_locals message
-- topics:     { id, category, order, file, title, keywords, related, hidden }
--     file     = path under content/<lang>/ (falls back to content/en/);
--                every file must also be listed in meta.xml
--     title    = optional, default: the first "# " line of the file
--     keywords = optional extra search words ("a, b" or { "a", "b" })
--     related  = optional list of topic ids shown under the page
--     hidden   = true: not listed on the left, only reachable by search / links
--
-- home = optional landing page file (content/<lang>/home.txt). Without it the
-- panel shows a table of contents.
--
-- Example:
--   categories = {
--       { id = "basics", order = 10, title = { en = "Getting started", hu = "Kezdő lépések" } },
--   },
--   topics = {
--       { id = "first_steps", category = "basics", order = 10, file = "basics/first_steps.txt" },
--   },

HELP_INDEX = {
    home = nil,
    categories = {
        { id = "features", order = 10, title = { en = "Menus and apps", hu = "Menük és alkalmazások" } },
        { id = "binds", order = 20, title = { en = "Key binds", hu = "Billentyűk" } },
        { id = "medical", order = 40, title = { en = "Medical system", hu = "Orvosi rendszer" } },
    },
    topics = {
        -- features: one page per menu / app
        { id = "feature_pause",       category = "features", order = 10, file = "features/pause.txt" },
        { id = "feature_interaction", category = "features", order = 20, file = "features/interaction.txt" },
        { id = "feature_social",      category = "features", order = 30, file = "features/social.txt" },
        { id = "feature_phone",       category = "features", order = 40, file = "features/phone.txt" },
        { id = "feature_browser",     category = "features", order = 50, file = "features/browser.txt" },

        -- binds: overview + one page per panel (linked from the overview)
        { id = "binds",             category = "binds", order = 10,  file = "binds/overview.txt" },
        { id = "binds_chat",        category = "binds", order = 20,  file = "binds/chat.txt" },
        { id = "binds_pause",       category = "binds", order = 30,  file = "binds/pause.txt" },
        { id = "binds_interaction", category = "binds", order = 40,  file = "binds/interaction.txt" },
        { id = "binds_social",      category = "binds", order = 50,  file = "binds/social.txt" },
        { id = "binds_phone",       category = "binds", order = 60,  file = "binds/phone.txt" },
        { id = "binds_inventory",   category = "binds", order = 70,  file = "binds/inventory.txt" },
        { id = "binds_weapons",     category = "binds", order = 80,  file = "binds/weapons.txt" },
        { id = "binds_vehicle",     category = "binds", order = 90,  file = "binds/vehicle.txt" },
        { id = "binds_world",       category = "binds", order = 100, file = "binds/world.txt" },
        { id = "binds_work",        category = "binds", order = 110, file = "binds/work.txt" },
        { id = "binds_creator",     category = "binds", order = 120, file = "binds/creator.txt" },
        { id = "binds_admin",       category = "binds", order = 130, file = "binds/admin.txt" },

        -- medical: medsys / med_bag / mg_* minigames (overview links every page)
        { id = "medical",            category = "medical", order = 10, file = "medical/overview.txt" },
        { id = "medical_exam",       category = "medical", order = 20, file = "medical/exam.txt" },
        { id = "medical_diagnosis",  category = "medical", order = 30, file = "medical/diagnosis.txt" },
        { id = "medical_monitor",    category = "medical", order = 40, file = "medical/monitor.txt" },
        { id = "medical_injuries",   category = "medical", order = 50, file = "medical/injuries.txt" },
        { id = "medical_drugs",      category = "medical", order = 60, file = "medical/drugs.txt" },
        { id = "medical_procedures", category = "medical", order = 70, file = "medical/procedures.txt" },
        { id = "medical_minigames",  category = "medical", order = 80, file = "medical/minigames.txt" },
        { id = "medical_equipment",  category = "medical", order = 90, file = "medical/equipment.txt" },
        { id = "medical_cases",      category = "medical", order = 100, file = "medical/cases.txt" },
    },
}
