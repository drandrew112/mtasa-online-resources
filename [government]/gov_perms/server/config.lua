-- gov_perms / server/config.lua

loadstring(exports.gov_core:importLib())()

PERMS = PERMS or {}

PERMS.ADMIN_LEVEL = 5          -- the same as gov_core GOV.ADMIN_LEVEL: admins may do everything, also with system groups
PERMS.RESYNC_MS = 60000        -- groups, rights, appointments, branches re-read (the other instance may have changed them)
PERMS.BANK_SYNC_MS = 60000     -- state company bank access = the gov.<id>.bank.* rights (server/bank.lua)
PERMS.SALARY_TICK = 60         -- s: online seconds counted per tick (server/salary.lua)
PERMS.SALARY_HOUR = 3600       -- s of online time per salary
PERMS.PLAN_HOURS = 4           -- default expected online hours per day of an official (Budget plan), setting perms.salary.plan_hours
PERMS.MAX_SALARY = 1000000     -- € per hour
PERMS.MAX_GROUPS = 200
PERMS.MAX_GRANTS = 400         -- per group

-- resources that may appoint / dismiss through the exports (the election system later)
PERMS.AUTOMATION = {}

-- the menu categories of gov_core = the areas of the rights tree (order)
PERMS.AREAS = { "top", "economy", "revenue", "services", "employment", "organizations", "public", "admin", "other" }

-- v_bank access of a state account from the rights (strongest first)
PERMS.BANK_ROLES = {
    { perm = "manage", role = "owner" },
    { perm = "pay",    role = "manager" },
    { perm = "view",   role = "viewer" },
}

-- gov_branches, inserted only into an empty table (first start); editable on the Permissions page
PERMS.SEED_BRANCHES = {
    { "transport",    "Transport",    10 },   -- public transport, railways and aviation (SA Control)
    { "health",       "Health",       20 },
    { "finance",      "Finance",      30 },
    { "interior",     "Interior",     40 },   -- police, fire service, military (later)
    { "justice",      "Justice",      50 },   -- fines, courts, prisons (later)
    { "public_works", "Public works", 60 },
    { "media",        "Media",        70 },
    { "municipal",    "Municipal",    80 },   -- the city companies (City of Los Santos, ...)
    { "other",        "Other",        1000 },
}

-- the default positions, created once (by code) on the first start; salaries 0 until the Governor
-- / an admin sets them. grants: "key" or { "key", branch }
PERMS.SEED_GROUPS = {
    { code = "governor", name = "Governor", kind = "system", rank = 1000, max = 1, color = "#d4af37",
      description = "Head of the state: every right; appoints the officials.",
      grants = { "*" } },
    { code = "min_finance", name = "Finance Minister", rank = 900, max = 1, color = "#3fa66b",
      grants = { "treasury.*", "loans.*", "tax.*", "fees.view", "fees.register.*", "fees.rename.*",
                 "gov.*.view", "gov.*.bank.view", "gov.treasury.*", { "gov.*.*", "finance" } } },
    { code = "min_transport", name = "Transport Minister", rank = 900, max = 1, color = "#3f7fd4",
      grants = { "transport.*", "rail.*", "treasury.overview", "fees.view", "fees.airspace_takeoff.*",
                 "fees.airspace_landing.*", "fees.airspace_overflight.*", "works.traindriver.*", "works.atc.*",
                 { "gov.*.*", "transport" } } },
    { code = "min_health", name = "Health Minister", rank = 900, max = 1, color = "#d4493f",
      grants = { "health.*", "works.ems.*", "works.bloodtransport.*", { "gov.*.*", "health" } } },
    { code = "min_interior", name = "Interior Minister", rank = 900, max = 1, color = "#5a5f73",
      grants = { { "gov.*.*", "interior" } } },
    { code = "min_justice", name = "Justice Minister", rank = 900, max = 1, color = "#8a5ad4",
      grants = { "fines.*", { "gov.*.*", "justice" } } },
    { code = "min_employment", name = "Employment Minister", rank = 900, max = 1, color = "#d4893f",
      grants = { "works.*", "tax.view", "tax.income.edit" } },
    { code = "spokesperson", name = "Government Spokesperson", rank = 400, max = 1, color = "#3fb4c8",
      grants = { "news.*", "votes.*" } },
}

-- the old gov_members roles (migration, system groups)
local VIEW = { "legacy.viewer", "treasury.overview", "treasury.plan.view", "loans.view", "tax.view", "fees.view",
    "fines.view", "health.view", "transport.view", "rail.view", "works.*.view", "gov.*.view", "gov.*.bank.view",
    "votes.view", "news.view", "panel.log", "perms.view" }
local function plus(list, more)
    local out = {}
    for _, k in ipairs(list) do out[#out + 1] = k end
    for _, k in ipairs(more) do out[#out + 1] = k end
    return out
end
PERMS.LEGACY_GROUPS = {
    viewer = { code = "legacy_viewer", name = "Viewer (old role)", rank = 50, grants = VIEW },
    official = { code = "legacy_official", name = "Official (old role)", rank = 60,
        grants = plus(VIEW, { "legacy.official", "gov.*.*", "companies.*", "health.*" }) },
    minister = { code = "legacy_minister", name = "Minister (old role)", rank = 70,
        grants = { "legacy.*", "panel.*", "office.*", "treasury.*", "loans.*", "tax.*", "fees.*", "fines.*", "health.*",
            "transport.*", "rail.*", "works.*", "gov.*", "companies.*", "votes.*", "news.*", "perms.view" } },
}
