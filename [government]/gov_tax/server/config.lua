-- gov_tax / server/config.lua
-- Defaults of the tax.* and fee.* settings (stored in gov_core's gov_settings; a key without a row
-- uses the value here). RANGE = what the panel accepts.

loadstring(exports.gov_core:importLib())()

GOV.TAX_RUN_DELAY = 30        -- s after the full hour the company tax run starts
GOV.TAX_CATCHUP_HOURS = 24    -- unclaimed hours caught up on start
GOV.CACHE_MS = 60000          -- the tax run list (overview, gov_web) is re-read this often

-- VAT product groups (tax.vat keys), in the order of the Taxes page. The shops name their group
-- (VAT.gross / VAT.split of the importVat lib); a new group needs a shop that uses it.
GOV_VAT_GROUPS = { "weapons", "clothing", "vehicles", "tuning", "repair", "services", "real_estate" }

-- the taxes whose money goes to a state account chosen on the Taxes page (setting tax.targets:
-- tax -> state account code, e.g. "treasury" or a state company code; no entry = the money disappears)
GOV_TAXES = { "company", "income", "vat", "property" }

-- the fees of the Fees page (fee.<key>), their money goes to the account in fee.targets
GOV.FEES = { "register", "rename", "bay_fine", "airspace.takeoff", "airspace.landing", "airspace.overflight" }

-- the fees that are fines (Justice: rights fines.<id>.*, the others fees.<id>.*; gov_perms)
GOV.FINES = { bay_fine = true }

--- the permission target of a fee key ("airspace.takeoff" -> "airspace_takeoff")
function GOV.feeTarget(key) return (tostring(key):gsub("%.", "_")) end

-- setting key -> default value
GOV_DEFAULTS = {
    ["tax.company"] = 0.10,                                 -- hourly company income tax
    ["tax.income_keys"] = { standard = 0.12, exempt = 0 },  -- personal income tax rate keys
    -- VAT on top of the shop price, per product group
    ["tax.vat"] = { weapons = 0.27, clothing = 0.27, vehicles = 0.27, tuning = 0.27, repair = 0.27,
                    services = 0.27, real_estate = 0.05 },
    ["tax.property"] = 0.005,                               -- of the property price, every 24 online hours
    ["tax.targets"] = {},                                   -- tax -> state account code (none = disappears)

    -- every fee goes to the state account set for it in fee.targets (none = it disappears)
    ["fee.targets"] = {},              -- fee key -> state account code
    ["fee.register"] = 50000,          -- company registration fee
    ["fee.rename"] = 10000,            -- company rename fee
    ["fee.bay_fine"] = 500,            -- hospital bay fine per interval (booked when the bay is left)
    ["fee.airspace.takeoff"] = 1500,   -- airspace usage fees (money from nothing, the AI airline pays)
    ["fee.airspace.landing"] = 2000,
    ["fee.airspace.overflight"] = 800,
}

GOV_RANGE = {
    tax = { 0, 0.5 },
    vat = { 0, 0.5 },
    propertyTax = { 0, 0.1 },
    fee = { 0, 10000000 },
}
