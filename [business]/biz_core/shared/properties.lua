-- biz_core / shared/properties.lua
-- Buildings (entrances on the map) and the property catalog. Buyable things are
-- listed here only; the interiors (GTA interior, spawn, exit, computer, props)
-- are biz_int templates. Several properties may share one building: every
-- company still gets its own dimension behind the same door.
--
-- Positions marked "approx" come from verified ground spots (claude-mcp scene
-- spot cache) near the planned place, not from a door: check them in game and
-- move them with /bizpos building <id> (biz_int) if needed.

BIZ.BUILDINGS = {
    ls_commerce   = { name = "Commerce Tower",      city = "Los Santos",   x = 1727.64,  y = -1636.88, z = 19.22, rot = 0 },   -- Atrium door
    ls_downtown   = { name = "Downtown Plaza",      city = "Los Santos",   x = 1534.00,  y = -1262.00, z = 16.41, rot = 0 },   -- approx
    sf_financial  = { name = "SF Financial",        city = "San Fierro",   x = -1826.62, y = 859.75,   z = 28.67, rot = 0 },   -- approx
    sf_queens     = { name = "Queens Office",       city = "San Fierro",   x = -2425.94, y = 337.87,   z = 36.00, rot = 0 },   -- Vank Hoff door
    lv_civic      = { name = "LV Civic",            city = "Las Venturas", x = 2412.60,  y = 1123.81,  z = 9.85,  rot = 90 },  -- Planning Dep. door
    lv_redsands   = { name = "Redsands Tower",      city = "Las Venturas", x = 1796.31,  y = 2100.14,  z = 9.97,  rot = 0 },   -- approx
    bc_castillo   = { name = "Castillo del Diablo", city = "Bone County",  x = -380.45,  y = 2248.48,  z = 41.62, rot = 0 },   -- approx
    lv_casino     = { name = "The Casino",          city = "Las Venturas", x = 1659.42,  y = 2249.69,  z = 10.07, rot = 0 },   -- Redsands West casino door
}

-- kind:     office | weed | casino
-- activity: the activity resource key (biz_weed registers "weed", biz_casino "casino")
-- tier:     offices only (standard / exclusive; one interior per tier)
-- upkeep:   paid every BIZ.UPKEEP_INTERVAL online seconds
BIZ.PROPERTIES = {
    { id = "office_commerce",     kind = "office", tier = "exclusive", building = "ls_commerce",  template = "office_exclusive", price = 1200000, upkeep = 5000 },
    { id = "office_downtown_ls",  kind = "office", tier = "standard",  building = "ls_downtown",  template = "office_standard",  price = 650000,  upkeep = 3000 },
    { id = "office_sf_financial", kind = "office", tier = "exclusive", building = "sf_financial", template = "office_exclusive", price = 950000,  upkeep = 5000 },
    { id = "office_sf_queens",    kind = "office", tier = "standard",  building = "sf_queens",    template = "office_standard",  price = 450000,  upkeep = 3000 },
    { id = "office_lv_civic",     kind = "office", tier = "standard",  building = "lv_civic",     template = "office_standard",  price = 550000,  upkeep = 3000 },
    { id = "office_lv_redsands",  kind = "office", tier = "standard",  building = "lv_redsands",  template = "office_standard",  price = 250000,  upkeep = 1500 },

    { id = "weed_castillo",   kind = "weed",   activity = "weed",   building = "bc_castillo", template = "weed_farm", price = 450000,  upkeep = 3000,  illegal = true },
    { id = "casino_redsands", kind = "casino", activity = "casino", building = "lv_casino",   template = "casino",    price = 3500000, upkeep = 12000 },
}

BIZ.PROPERTY_BY_ID = {}
for _, p in ipairs(BIZ.PROPERTIES) do BIZ.PROPERTY_BY_ID[p.id] = p end

function BIZ.property(id) return BIZ.PROPERTY_BY_ID[id] end

--- English display name of a property (stored data and the web pages use English).
function BIZ.propertyName(id)
    local p = BIZ.PROPERTY_BY_ID[id]
    if not p then return tostring(id) end
    local b = BIZ.BUILDINGS[p.building]
    if p.kind == "office" then return b and b.name or id end
    if p.kind == "weed" then return (b and b.name or id) .. " farm" end
    return b and b.name or id
end
