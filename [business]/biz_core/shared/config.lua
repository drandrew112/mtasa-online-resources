if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / shared/config.lua
if not VAT then loadstring(exports.v_gov:importVat())() end -- VAT lib of v_gov (shared/vat.lua)
-- Tunables of the organization system. Prices are in euro, times in seconds
-- unless the name says ms. Every simulation counter runs in ONLINE seconds of
-- the founder (nothing happens while the founder is offline).

BIZ = {
    -- registration (sabusinessregistry.eu): paid from the founder's own bank account
    REG_FEE        = 50000,
    NAME_MIN       = 3,
    NAME_MAX       = 32,
    RENAME_COST    = 10000,         -- paid from the company account
    RENAME_COOLDOWN = 24 * 3600,    -- real seconds between two renames

    -- selling the organization: the balance is paid out in full, everything
    -- else (properties, upgrades, stock) at this ratio
    SALE_ASSET_RATIO = 0.6,
    -- selling a single property back
    PROPERTY_SELL_RATIO = 0.5,

    -- online simulation
    TICK_MS          = 60000,       -- one tick per online minute of the founder
    UPKEEP_INTERVAL  = 2 * 3600,    -- upkeep of every property + the office, in online seconds
    PROPERTY_TAX_INTERVAL = 24 * 3600, -- property tax (v_gov rate x property price), in online seconds

    -- temporary associates (founder + 3 associates = 4 members)
    MAX_ASSOCIATES   = 3,
    INVITE_TTL       = 120,         -- seconds an invitation stays valid
    ASSOCIATE_SHARE  = 0.8,         -- an associate keeps this part of his own delivery
    THIEF_SHARE      = 0.6,         -- a stranger delivering a stolen shipment gets this

    -- caches
    REGISTRY_REFRESH_MS = 60000,    -- public registry / top list re-read
    RESYNC_MS           = 60000,    -- balances of loaded companies re-read (other instances)
    LEDGER_CACHE        = 200,      -- newest ledger rows kept in memory per loaded company

    -- interiors (biz_int): dimension = DIM_BASE + unit id
    DIM_BASE = 30000,
    DIM_MAX  = 45999,

    -- admin (v_admin Organizations page)
    ADMIN_VIEW = 3,
    ADMIN_EDIT = 5,

    -- accData keys (consequences of dirty money come later)
    ACC_DIRTY_WITHDRAWN = "biz_dirty_withdrawn",
    ACC_DIRTY_RECEIVED  = "biz_dirty_received",
}

-- activity kinds: weekly sale multipliers only apply to supply_deliver businesses
BIZ.KIND_SUPPLY_DELIVER = "supply_deliver"
BIZ.KIND_PASSIVE        = "passive"

--- the price of a property with VAT "real_estate" (v_gov) on top -> gross, vat. Illegal sites
--- are bought without VAT (the state does not know about them).
function BIZ.grossPrice(p)
    if not p then return 0, 0 end
    if p.illegal then return p.price, 0 end
    return VAT.split("real_estate", p.price)
end
