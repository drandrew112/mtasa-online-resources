-- biz_weed / shared/config.lua
-- Weed farm (illegal, supply/deliver). Supply turns into product while the
-- founder is online; product is sold in delivery missions (biz_missions).

WEED = {
    BASE_CAPACITY = 100,       -- supply and product maximum
    UNIT_SECONDS  = 180,       -- online seconds per converted unit

    PRODUCT_VALUE = 1500,      -- euro per product unit (before the weekly multiplier)
    SUPPLY_VALUE  = 900,       -- euro per supply unit (company value, bought supply price)

    -- bought supply: arrives after `seconds` of online time
    PACKS = {
        { id = "s20", units = 20, price = 18000, seconds = 1800 },
        { id = "s50", units = 50, price = 45000, seconds = 2700 },
    },

    UPGRADES = {
        capacity = { price = 220000, capacity = 160 },   -- bigger stock
        staff    = { price = 180000, unitSeconds = 120 }, -- faster production
    },

    -- missions (biz_missions)
    STEAL_UNITS  = { 20, 30 },
    PER_VEHICLE  = 40,          -- product units per delivery vehicle
    MISSION_COOLDOWN = 300,     -- seconds between two missions of a farm

    HUD_PUSH_MS = 2000,
}
