-- gov_core / server/config.lua

GOV.ADMIN_LEVEL = 5          -- admins from this level count as "minister" without a gov_members row
GOV.RESYNC_MS = 60000        -- settings, members and state companies re-read (the other server instance may have changed them)
GOV.REQUEST_TIMEOUT = 30000  -- ms a module has to answer a panel request

-- the groups of the /gov side menu: id, order, text key (gov_core.menu.<id>). "top" has no header
-- (Overview). A page with an unknown category goes under "other". A module may add a category
-- (registerModule{ categories = { { id, order }, ... } }, text key <module>.menu.<id>).
GOV_CATEGORIES = {
    { id = "top",           order = 0 },
    { id = "economy",       order = 10 },
    { id = "revenue",       order = 20 },
    { id = "services",      order = 30 },
    { id = "employment",    order = 40 },
    { id = "organizations", order = 50 },
    { id = "public",        order = 60 },
    { id = "admin",         order = 70 },
    { id = "other",         order = 1000 },
}
