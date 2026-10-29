-- v_bank / shared/keys.lua
-- The ONLY list of what can happen to a balance (DESIGN.md 4). A booking with an unknown key,
-- or with an account on a side the key does not allow, is refused ("bad_key").
--
-- A booking moves money from one side to the other. A side is:
--   "system"   - outside the economy: the money is created / disappears (shops, market, rewards)
--   "cash"     - the player's cash (deposit / withdrawal only)
--   "settled"  - leaves now, the caller books the matching income later in one sum
--   "treasury" - the State Treasury (filled in by v_bank when the caller gives none)
--   "payer"    - a state or company account given by the caller, or system when none
--   "payee"    - a state account given by the caller, or system (the money disappears) when none
--   "org"      - a state or company account given by the caller, or system when none (either side)
--   { personal = true, company = true, state = true } - an account of these kinds
--
--   force   = the paying account may go below 0 (debt, paid off by its next income)
--   admin   = also works on frozen / closed accounts
--   taxable = legal company income for the hourly company tax (gov_tax)
--   params  = the params kept in the ledger row (anything else is dropped)
--
-- Text: "v_bank.tx.<key>.in" / ".out" (the side of the viewer), falling back to "v_bank.tx.<key>".

local P  = { personal = true }
local C  = { company = true }
local S  = { state = true }
local PC = { personal = true, company = true }
local ANY = { personal = true, company = true, state = true }

TX_KEYS = {
    -- cash edge
    ["cash.deposit"]   = { from = "cash", to = P },
    ["cash.withdraw"]  = { from = P, to = "cash" },

    -- transfers on the bank website
    ["transfer.account"] = { from = ANY, to = ANY, params = { "note" } },

    -- works (work_core payWork)
    ["work.pay"]       = { from = "payer", to = P, force = true, params = { "work" } },
    ["work.deduction"] = { from = P, to = "payer", force = true, params = { "work" } },

    -- fines
    ["fine.hospital_bay"]        = { from = P, to = "settled", force = true, params = { "hospital" } },
    ["fine.hospital_bay_income"] = { from = "settled", to = "payee", params = { "player", "hospital", "count" } },

    -- shops (from the bank part of a purchase)
    ["shop.weapon"]         = { from = P, to = "system", params = { "item" } },
    ["shop.weapon_refund"]  = { from = "system", to = P, params = { "item" } },
    ["shop.vehicle"]        = { from = P, to = "system", params = { "item" } },
    ["shop.vehicle_refund"] = { from = "system", to = P, params = { "item" } },
    ["shop.tuning"]         = { from = P, to = "system", params = { "item" } },
    ["shop.repair"]         = { from = P, to = "system", params = { "item" } },
    ["phone.service"]       = { from = P, to = "system", params = { "contact", "action" } },

    -- organizations (biz_core)
    -- the fees go to the state account set for them on the /gov Fees page (getFeeTarget), or
    -- disappear when none is set; a refund comes back from the same account
    ["biz.register_fee"]     = { from = P, to = "payee", params = { "company" } },
    ["biz.register_refund"]  = { from = "payee", to = P, force = true, params = { "company" } },
    ["biz.office_purchase"]  = { from = P, to = "system", params = { "property" } },
    ["biz.office_refund"]    = { from = "system", to = P, params = { "property" } },
    ["biz.deposit"]          = { from = P, to = C, params = { "company", "player" } },
    ["biz.withdraw"]         = { from = C, to = P, params = { "company", "player" } },
    ["biz.close_payout"]     = { from = C, to = P, params = { "company" } },
    ["biz.asset_sale"]       = { from = "system", to = P, params = { "company" } },
    ["biz.property_buy"]     = { from = C, to = "system", params = { "property" } },
    ["biz.property_refund"]  = { from = "system", to = C, params = { "property" } },
    ["biz.property_sell"]    = { from = "system", to = C, params = { "property" } },
    ["biz.property_upgrade"] = { from = C, to = "system", params = { "property", "upgrade" } },
    ["biz.upkeep"]           = { from = C, to = "system", params = { "count" } },
    ["biz.rename_fee"]       = { from = C, to = "payee", params = { "name" } },
    ["biz.launder"]          = { from = "system", to = C, params = { "amount", "fee" } },
    ["biz.casino_hour"]      = { from = "system", to = C, taxable = true, params = { "event" } },
    ["biz.casino_loss"]      = { from = C, to = "system", force = true, taxable = true, params = { "event" } },
    ["biz.weed_supply"]      = { from = C, to = "system", params = { "units" } },
    ["biz.write_off"]        = { from = "system", to = C, admin = true, params = { "company" } },

    -- state (gov_tax): every tax goes to the state account set for it on the /gov Taxes page
    -- (exports.gov_tax:getTaxTarget), or disappears when none is set
    ["tax.company_income"] = { from = C, to = "payee", force = true, params = { "hour", "base", "rate" } },
    ["tax.income"]         = { from = P, to = "payee", force = true, params = { "work", "key", "rate" } },
    -- VAT on top of a shop price: the buyer paid net + VAT to the shop (that money disappears or
    -- went to the shop side); gov_tax books the VAT part to the tax's account from nothing
    ["tax.vat"]            = { from = "system", to = "payee", params = { "group", "item", "net", "rate" } },
    -- property tax of an organization, every 24 online hours (biz_core)
    ["tax.property"]       = { from = C, to = "payee", force = true, params = { "count", "value", "rate" } },
    -- healthcare (gov_health, per hospital on the /gov Healthcare page): the payer (system, a state or a
    -- private company) pays the receiver (system = nobody, a state or a private company), or the
    -- patient pays it from the bank (may go into debt)
    ["health.care"]        = { from = "org", to = "org", force = true,
                               params = { "patient", "account", "hospital", "hp", "injuries", "task" } },
    ["health.patient"]     = { from = P, to = "org", force = true, params = { "hospital", "hp", "injuries" } },
    -- /gov Transfers page: state <-> state, state -> private company, collection from a private
    -- company (forced, it may go into debt)
    ["gov.transfer"]       = { from = S, to = S, force = true, params = { "note" } },
    ["gov.company_payment"] = { from = S, to = C, params = { "note" } },
    ["gov.collection"]     = { from = C, to = S, force = true, params = { "note" } },
    -- salaries of the state positions (gov_perms): from the State Treasury every online hour of the
    -- official (it may go negative, the salary is always paid); the income tax is a tax.income row
    ["salary.gov"]         = { from = S, to = P, force = true, params = { "position" } },
    -- airspace usage fees, paid by the AI flight's airline (money from nothing) to the fee's account
    ["atc.fee_takeoff"]    = { from = "system", to = "payee", params = { "callsign", "airline", "airport" } },
    ["atc.fee_landing"]    = { from = "system", to = "payee", params = { "callsign", "airline", "airport" } },
    ["atc.fee_overflight"] = { from = "system", to = "payee", params = { "callsign", "airline" } },

    -- public transport (pt_tickets + gov_transport /gov Public transport page): the passenger pays the ticket
    -- (cash or bank, the money disappears), gov_transport books the same sum from nothing to the fare
    -- receiver set for the mode (none = nobody gets it); running costs of a service (run fee per
    -- IC / RB trip, stop fee per served stop) go from the cost payer to the cost receiver
    ["pt.ticket"]          = { from = P, to = "system", params = { "line", "from", "to" } },
    ["pt.fare_income"]     = { from = "system", to = "org", params = { "mode", "line", "from", "to", "player" } },
    ["pt.run_cost"]        = { from = "org", to = "org", force = true, params = { "mode", "trip", "category" } },
    ["pt.stop_cost"]       = { from = "org", to = "org", force = true, params = { "mode", "trip", "station", "count" } },

    -- loans (eco_loan): the lender is the bank (system) or a state / company account; personal and
    -- company loans pay an installment every online hour, state loans every 24 h; after too many
    -- missed installments eco_loan takes it with the forced key (the account may go below 0)
    ["loan.payout"]             = { from = "org", to = ANY, params = { "loan" } },
    ["loan.installment"]        = { from = ANY, to = "org", params = { "loan", "n", "of" } },
    ["loan.installment_forced"] = { from = ANY, to = "org", force = true, params = { "loan", "n", "of" } },
    ["loan.extra"]              = { from = ANY, to = "org", params = { "loan" } },

    -- admin panel
    ["admin.credit"]   = { from = "system", to = ANY, admin = true, params = { "note", "admin" } },
    ["admin.debit"]    = { from = ANY, to = "system", admin = true, force = true, params = { "note", "admin" } },
    ["admin.transfer"] = { from = ANY, to = ANY, admin = true, force = true, params = { "note", "admin" } },

    -- one-time migration of the old balances (DESIGN.md 7)
    ["migration.opening"] = { from = "system", to = ANY, admin = true },
}

-- ledger filter groups of the website / admin panel: group -> key prefix
TX_GROUPS = { "cash", "transfer", "work", "salary", "fine", "shop", "biz", "tax", "health", "gov", "atc", "pt", "loan", "admin" }

--- the group of a key ("cash.deposit" -> "cash")
function txGroup(key)
    return tostring(key or ""):match("^([%w_]+)%.") or "other"
end
