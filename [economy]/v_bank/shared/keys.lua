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
--   { personal = true, company = true, state = true } - an account of these kinds
--
--   force   = the paying account may go below 0 (debt, paid off by its next income)
--   admin   = also works on frozen / closed accounts
--   taxable = legal company income for the hourly company tax (v_gov)
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
    ["fine.hospital_bay_income"] = { from = "settled", to = "treasury", params = { "player", "hospital", "count" } },

    -- shops (from the bank part of a purchase)
    ["shop.weapon"]         = { from = P, to = "system", params = { "item" } },
    ["shop.weapon_refund"]  = { from = "system", to = P, params = { "item" } },
    ["shop.vehicle"]        = { from = P, to = "system", params = { "item" } },
    ["shop.vehicle_refund"] = { from = "system", to = P, params = { "item" } },
    ["phone.service"]       = { from = P, to = "system", params = { "contact", "action" } },

    -- organizations (biz_core)
    ["biz.register_fee"]     = { from = P, to = "treasury", params = { "company" } },
    ["biz.register_refund"]  = { from = "treasury", to = P, force = true, params = { "company" } },
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
    ["biz.rename_fee"]       = { from = C, to = "system", params = { "name" } },
    ["biz.launder"]          = { from = "system", to = C, params = { "amount", "fee" } },
    ["biz.casino_hour"]      = { from = "system", to = C, taxable = true, params = { "event" } },
    ["biz.casino_loss"]      = { from = C, to = "system", force = true, taxable = true, params = { "event" } },
    ["biz.weed_supply"]      = { from = C, to = "system", params = { "units" } },
    ["biz.write_off"]        = { from = "system", to = C, admin = true, params = { "company" } },

    -- state (v_gov): every tax goes to the state account set for it on the /gov Taxes page
    -- (exports.v_gov:getTaxTarget), or disappears when none is set
    ["tax.company_income"] = { from = C, to = "payee", force = true, params = { "hour", "base", "rate" } },
    ["tax.income"]         = { from = P, to = "payee", force = true, params = { "work", "key", "rate" } },
    -- VAT on top of a shop price: the buyer paid net + VAT to the shop (that money disappears or
    -- went to the shop side); v_gov books the VAT part to the tax's account from nothing
    ["tax.vat"]            = { from = "system", to = "payee", params = { "group", "item", "net", "rate" } },
    -- property tax of an organization, every 24 online hours (biz_core)
    ["tax.property"]       = { from = C, to = "payee", force = true, params = { "count", "value", "rate" } },
    ["health.care"]        = { from = "treasury", to = "system", force = true,
                               params = { "patient", "account", "hospital", "hp", "injuries", "task" } },
    ["gov.transfer"]       = { from = S, to = S, force = true, params = { "note" } },
    -- airspace usage fees, paid by the AI flight's airline (money from nothing)
    ["atc.fee_takeoff"]    = { from = "system", to = S, params = { "callsign", "airline", "airport" } },
    ["atc.fee_landing"]    = { from = "system", to = S, params = { "callsign", "airline", "airport" } },
    ["atc.fee_overflight"] = { from = "system", to = S, params = { "callsign", "airline" } },

    -- admin panel
    ["admin.credit"]   = { from = "system", to = ANY, admin = true, params = { "note", "admin" } },
    ["admin.debit"]    = { from = ANY, to = "system", admin = true, force = true, params = { "note", "admin" } },
    ["admin.transfer"] = { from = ANY, to = ANY, admin = true, force = true, params = { "note", "admin" } },

    -- one-time migration of the old balances (DESIGN.md 7)
    ["migration.opening"] = { from = "system", to = ANY, admin = true },
}

-- ledger filter groups of the website / admin panel: group -> key prefix
TX_GROUPS = { "cash", "transfer", "work", "fine", "shop", "biz", "tax", "health", "gov", "atc", "admin" }

--- the group of a key ("cash.deposit" -> "cash")
function txGroup(key)
    return tostring(key or ""):match("^([%w_]+)%.") or "other"
end
