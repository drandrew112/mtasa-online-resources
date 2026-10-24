-- v_gov / shared/config.lua
-- Defaults of every state setting (DESIGN.md). The /gov panel stores changes in gov_settings;
-- a setting without a row uses the value here. RANGE = what the panel accepts.

GOV = {
    ADMIN_LEVEL = 5,          -- admins from this level count as "minister" without a gov_members row
    RESYNC_MS = 60000,        -- settings re-read (the other server instance may have changed them)
    TAX_RUN_DELAY = 30,       -- s after the full hour the company tax run starts
    TAX_CATCHUP_HOURS = 24,   -- unclaimed hours caught up on start

    ROLES = { viewer = 1, official = 2, minister = 3 },

    HISTORY_DAYS = 30,        -- financial rows / sums are shown at most this far back (/gov + gov_web)
    VOTE_CHECK_MS = 60000,    -- open votes past their end are closed this often
    VOTE_MAX_OPTIONS = 10,
    VOTE_MAX_HOURS = 24 * 14,
    PUBLIC_REFRESH_MS = 60000, -- the gov_web snapshot (getPublicState) is rebuilt this often
}

-- VAT product groups (tax.vat keys), in the order of the Taxes page. The shops name their group
-- (VAT.gross / VAT.split of the importVat lib); a new group needs a shop that uses it.
GOV_VAT_GROUPS = { "weapons", "clothing", "vehicles", "tuning", "repair", "services", "real_estate" }

-- the taxes whose money goes to a state account chosen on the Taxes page (setting tax.targets:
-- tax -> state account code, e.g. "treasury" or a state company code; no entry = the money disappears)
GOV_TAXES = { "company", "income", "vat", "property" }

-- setting key -> default value
GOV_DEFAULTS = {
    ["tax.company"] = 0.10,                                 -- hourly company income tax
    ["tax.income_keys"] = { standard = 0.12, exempt = 0 },  -- personal income tax rate keys
    -- VAT on top of the shop price, per product group
    ["tax.vat"] = { weapons = 0.27, clothing = 0.27, vehicles = 0.27, tuning = 0.27, repair = 0.27,
                    services = 0.27, real_estate = 0.05 },
    ["tax.property"] = 0.005,                               -- of the property price, every 24 online hours
    ["tax.targets"] = {},                                   -- tax -> state account code (none = disappears)

    ["fee.register"] = 50000,          -- company registration fee -> treasury
    ["fee.rename"] = 10000,            -- company rename fee -> disappears
    ["fee.bay_fine"] = 500,            -- hospital bay fine per interval -> treasury (when the bay is left)
    ["fee.airspace.takeoff"] = 1500,   -- airspace usage fees -> SA Control (money from nothing)
    ["fee.airspace.landing"] = 2000,
    ["fee.airspace.overflight"] = 800,

    ["health.enabled"] = true,
    ["health.hp_price"] = 50,
    -- injury / condition type -> price by severity 1 / 2 / 3 ("default" for types not listed)
    ["health.injuries"] = {
        gunshot = { 800, 2000, 4500 },
        fracture = { 500, 1200, 2500 },
        burn = { 400, 1500, 4000 },
        head_injury = { 700, 2000, 5000 },
        default = { 300, 800, 2000 },
    },
}

-- per-work defaults (the Works page): anything not listed = system payer, "standard" tax key,
-- multiplier 1
GOV_WORK_DEFAULTS = {
    ems            = { payer = "state:treasury", taxKey = "exempt" },
    bloodtransport = { payer = "state:treasury", taxKey = "exempt" },
    atc            = { payer = "state:sacontrol" },
}

GOV_RANGE = {
    tax = { 0, 0.5 },
    vat = { 0, 0.5 },
    propertyTax = { 0, 0.1 },
    multiplier = { 0, 5 },
    fee = { 0, 10000000 },
    hpPrice = { 0, 100000 },
    injuryPrice = { 0, 1000000 },
    wageFactor = 10,          -- a wage parameter may be at most this many times its default (abs)
}
