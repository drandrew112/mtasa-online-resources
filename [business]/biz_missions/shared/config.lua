-- biz_missions / shared/config.lua
-- Supply/deliver missions of the activities (now: the weed farm).
--
-- Positions come from the claude-mcp verified ground spot cache (villages);
-- guards stand around the spot, the vans spawn next to it. Check them in game.

MIS = {
    DEADLINE = 30 * 60,            -- seconds for every mission (sell: then the cargo is lost)
    COOLDOWN = 300,                -- seconds before the next mission of the same property
    ATTACK_CHANCE = 0.5,           -- sell missions with enemies

    -- supply steal
    GUARDS = { 4, 7 },
    GUARD_SKINS = { 108, 109, 110, 173, 174, 175 },
    GUARD_WEAPONS = { { 30, 300 }, { 28, 400 }, { 22, 200 }, { 25, 60 } },
    GUARD_ACCURACY = 0.45,
    GUARD_GROUP = "biz_guards",
    SUPPLY_VAN = 440,              -- Rumpo
    CRATE_ITEM = "biz_supply_crate",
    DELIVER_RADIUS = 10,           -- van / crate this close to the property entrance = delivered
    STEAL_AREA_RADIUS = 60,        -- radar circle around the target

    -- sell
    SELL_VAN = 482,                -- Burrito
    -- the only places sell vans may spawn, per building (spawned at z + 1, physics drops them)
    VAN_SPAWNS = {
        bc_castillo = {
            { x = -378.95, y = 2251.86, z = 41.28, rot = 102 },
            { x = -379.97, y = 2234.92, z = 41.05, rot = 194 },
            { x = -372.85, y = 2233.38, z = 41.29, rot = 106 },
            { x = -370.97, y = 2228.22, z = 41.29, rot = 100 },
            { x = -370.44, y = 2222.61, z = 41.29, rot = 104 },
        },
    },
    BUYER_RADIUS = 10,
    BUYER_MIN_DIST = 800,          -- from the property
    BUYER_SPREAD = 600,            -- buyers of one delivery at least this far from each other
    DIST_BONUS_PER_KM = 0.10,      -- value bonus per km from the property ...
    DIST_BONUS_MAX = 0.30,         -- ... at most
    DISCONNECT_RETURN = 0.5,       -- cargo part going back to the stock when its driver disconnects
    VISIBLE_DIST = 800,            -- other players see the shipment's blip / get a notice within this
    HIDE_DIST = 900,               -- ... and lose it beyond this
    VAN_BLIP = 51,                 -- truck icon

    -- enemies on the road (ai_land_traffic pursuit)
    WAVE_FIRST = { 60, 120 },      -- seconds after the first van moves
    WAVE_GAP = { 90, 150 },
    WAVE_MAX = 3,                  -- per delivery (more vans: one more each, still capped)
    WAVE_CAP = 4,
    PURSUERS_PER_VAN = 2,          -- at the same time
    PURSUIT_SPAWN = { 260, 420 },  -- metres from the van, out of the players' view
    PURSUIT_MODELS = { 567, 534, 566, 412 },   -- Savanna, Remington, Tahoma, Voodoo
    PURSUIT_SKINS = { 105, 106, 107, 114, 115, 116 },
    PURSUIT_PASSENGERS = { 1, 2 },
    PURSUIT_WEAPONS = { { 30, 300 }, { 28, 400 }, { 32, 400 } },
    ENEMY_GROUP = "biz_raiders",
}

-- supply steal targets
MIS.SUPPLY_SPOTS = {
    { name = "Fort Carson",     x = -290.0,  y = 1140.0, z = 18.74 },
    { name = "Las Barrancas",   x = -800.0,  y = 1550.0, z = 26.12 },
    { name = "Lil' Probe Inn",  x = -130.0,  y = 1490.0, z = 19.21 },
    { name = "El Quebrados",    x = -1440.0, y = 2610.0, z = 54.84 },
    { name = "Verdant Meadows", x = 348.0,   y = 2304.9, z = 24.40 },
    { name = "Bayside",         x = -2624.0, y = 2402.5, z = 10.77 },
}

-- buyers of the product (on roads, the pursuers are lane bound)
MIS.BUYERS = {
    { name = "El Quebrados",   x = -1553.2, y = 2566.5, z = 54.84 },
    { name = "Fort Carson",    x = -130.0,  y = 1160.0, z = 18.74 },
    { name = "Las Barrancas",  x = -818.4,  y = 1485.0, z = 18.77 },
    { name = "Las Payasadas",  x = -339.5,  y = 2692.2, z = 62.07 },
    { name = "Regular Tom",    x = -440.5,  y = 1895.8, z = 58.34 },
    { name = "Valle Ocultado", x = -737.0,  y = 2738.1, z = 46.01 },
    { name = "Verdant Meadows", x = 371.0,  y = 2326.7, z = 24.46 },
    { name = "Bayside",        x = -2633.6, y = 2488.4, z = 29.36 },
    { name = "Hampton Barns",  x = 620.5,   y = 207.1,  z = 21.70 },
    { name = "Montgomery",     x = 1290.0,  y = 270.0,  z = 18.56 },
    { name = "Fern Ridge",     x = 1213.2,  y = -114.6, z = 39.37 },
    { name = "Blueberry",      x = 210.0,   y = -350.0, z = 2.72 },
}
