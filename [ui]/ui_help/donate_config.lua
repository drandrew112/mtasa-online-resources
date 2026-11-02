-- Donate panel (F3) settings, shared. Server: server/donate.lua, client: client/donate.lua.
DONATE = {
    url            = "https://webadmin.synhosting.eu/p/drandrew112/?id=10",
    key            = "F3",
    baseMultiplier = 10,          -- bank money per paid point; the same as v_admin ADMIN.payments.minMultiplier
    maxMultiplier  = 1000,        -- highest event multiplier (v_admin ADMIN.payments.maxMultiplier)
    maxEventHours  = 24 * 30,     -- longest event
    adminLevel     = 4,           -- /donateevent (the same as the v_admin "payments" right)
    table          = "payments",  -- created by v_admin (server/pages/payments.lua), only read here
    historyLimit   = 50,          -- payments shown on the panel
    eventsFile     = "donate_events.json", -- events are kept in this file, not in MySQL
    keepEventsDays = 90,          -- ended events are dropped from the file after this
}
