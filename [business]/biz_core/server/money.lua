if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/money.lua
-- The company's money. Two parts:
--   clean = the company's v_bank account (v_bank DESIGN 6.3); every change is a v_bank booking
--           with a transaction key, c.clean mirrors the account (onBankBalanceChanged)
--   dirty = illegal income, kept here (balance_dirty) with its own biz_ledger rows
-- Spending takes the clean part first, so dirty money stays until it is laundered or withdrawn.
-- c.ledger (the cache the computer shows) holds both: dirty rows written here, clean rows built
-- from the v_bank changes of the account.
--
-- Server exports (loaded companies only, i.e. founder online on this instance):
--   getCompanyBalance(id)                                          -> clean, dirty | false
--   creditCompany(id, amount, category, desc, actor, dirty, ref, params)  -> true | false
--   debitCompany(id, amount, category, desc, actor, ref, params)          -> true | false, "not_enough_money"
--   queueLaunder(id, amount)  /  processLaunder(id, max, feeRatio) -> laundered, fee

MONEY = {}

addEvent("onBizBalanceChanged", false)   -- (companyId, clean, dirty)

local function amountOf(v)
    v = math.floor(tonumber(v) or 0)
    return v > 0 and v or nil
end

local function bank() return BIZ.running("v_bank") and exports.v_bank or nil end
MONEY.bank = bank

--- v_bank account id of the company (cached on the record), or nil
function MONEY.accountId(c)
    if c.bankId then return c.bankId end
    local b = bank()
    local id = b and b:getCompanyAccount(c.id)
    if id then c.bankId = id end
    return id or nil
end

--- reads the clean balance from v_bank into the record (load, account ready)
function MONEY.refreshClean(c)
    local id = MONEY.accountId(c)
    local b = bank()
    local bal = id and b and b:getBalance(id)
    if bal then c.clean = math.floor(bal) end
end

--------------------------------------------------------------------------------
-- dirty part (and marker rows like "founded")
--------------------------------------------------------------------------------

--- applies a dirty delta and writes the ledger row
function MONEY.applyDirty(c, dDirty, category, desc, actor, ref, ledgerAmount)
    dDirty = math.floor(dDirty or 0)
    c.dirty = c.dirty + dDirty
    c.sync.dirty = (c.sync.dirty or 0) + dDirty
    if dDirty ~= 0 then
        DB.exec("UPDATE biz_companies SET balance_dirty = balance_dirty + ? WHERE id = ?", dDirty, c.id)
    end

    local amount = ledgerAmount or dDirty
    local row = {
        id = 0, ts = BIZ.now(), amount = amount, dirty = dDirty ~= 0, balance = CO.balance(c),
        category = DB.clip(category, 32), description = DB.clip(desc, 160), actor = DB.clip(actor, 64),
    }
    table.insert(c.ledger, 1, row)
    while #c.ledger > BIZ.LEDGER_CACHE do table.remove(c.ledger) end
    DB.exec("INSERT INTO biz_ledger (company_id, ts, amount, dirty, balance_after, category, description, actor_account, ref) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        c.id, row.ts, amount, row.dirty and 1 or 0, row.balance, row.category, row.description, row.actor, DB.clip(ref, 64))

    CO.publish(c)
    triggerEvent("onBizBalanceChanged", resourceRoot, c.id, c.clean, c.dirty)
    return true
end

--------------------------------------------------------------------------------
-- clean part (v_bank)
--------------------------------------------------------------------------------

--- clean income from outside (key: a v_bank key whose payer is "system")
function MONEY.creditClean(c, amount, key, params, actor)
    local id, b = MONEY.accountId(c), bank()
    if not id or not b then return false, "unavailable" end
    return b:credit(id, amount, key, params, actor or "")
end

--- clean spending to outside / the treasury
function MONEY.debitClean(c, amount, key, params, actor, toId)
    local id, b = MONEY.accountId(c), bank()
    if not id or not b then return false, "unavailable" end
    return b:debit(id, amount, key, params, actor or "", toId)
end

--------------------------------------------------------------------------------
-- the old API on top of both parts
--------------------------------------------------------------------------------

--- clean (key, params) or dirty (biz_ledger row with key as category + desc)
function MONEY.credit(c, amount, key, params, desc, actor, dirty)
    amount = amountOf(amount)
    if not c or not amount then return false end
    if dirty then return MONEY.applyDirty(c, amount, key, desc, actor) end
    return MONEY.creditClean(c, amount, key, params, actor)
end

--- clean part first, then dirty -> true | false, err
function MONEY.debit(c, amount, key, params, desc, actor)
    amount = amountOf(amount)
    if not c or not amount then return false, "invalid" end
    if CO.balance(c) < amount then return false, "not_enough_money" end
    local fromClean = math.min(math.max(c.clean, 0), amount)
    if fromClean > 0 then
        local ok, err = MONEY.debitClean(c, fromClean, key, params, actor)
        if not ok then return false, err end
    end
    if amount > fromClean then
        MONEY.applyDirty(c, -(amount - fromClean), key, desc, actor)
    end
    return true
end

--------------------------------------------------------------------------------
-- the ledger cache: clean rows from v_bank
--------------------------------------------------------------------------------

-- v_bank key -> the category the computer filters / labels by
local KEY_CATEGORY = {
    ["biz.deposit"] = "deposit", ["biz.withdraw"] = "withdrawal",
    ["biz.property_buy"] = "property.buy", ["biz.property_refund"] = "property.refund",
    ["biz.property_sell"] = "property.sell", ["biz.property_upgrade"] = "property.upgrade",
    ["biz.upkeep"] = "upkeep", ["biz.rename_fee"] = "rename", ["biz.launder"] = "launder",
    ["biz.casino_hour"] = "casino.hour", ["biz.casino_loss"] = "casino.hour", ["biz.weed_supply"] = "weed.supply",
    ["biz.close_payout"] = "company.sell", ["biz.write_off"] = "company.sell",
    ["tax.company_income"] = "tax", ["tax.property"] = "tax", ["transfer.account"] = "transfer",
    ["work.pay"] = "wages", ["work.deduction"] = "wages",
    ["admin.credit"] = "admin.adjust", ["admin.debit"] = "admin.adjust", ["admin.transfer"] = "admin.adjust",
    ["migration.opening"] = "opening",
}
MONEY.KEY_CATEGORY = KEY_CATEGORY

--- the v_bank text of a booking, in the founder's language (else English)
function MONEY.bankText(c, key, amount, params)
    local who = isElement(c.founder) and c.founder or "en"
    local base = "v_bank.tx." .. tostring(key)
    local dir = base .. (amount < 0 and ".out" or ".in")
    local k = L.has(dir, L.lang(who)) and dir or base
    local p = {}
    for name, v in pairs(params or {}) do p[name] = v end
    return L.forPlayer(who, k, p)
end

--- a clean row for the cache, from a bank_ledger row / a v_bank change
function MONEY.cleanRow(c, ts, amount, balanceAfter, key, params, actor)
    return {
        id = 0, ts = ts, amount = amount, dirty = false,
        balance = (balanceAfter or c.clean) + c.dirty,
        category = KEY_CATEGORY[key] or key, description = DB.clip(MONEY.bankText(c, key, amount, params), 160),
        actor = tostring(actor or ""),
    }
end

addEvent("onBankBalanceChanged", false)
addEvent("onBankAccountReady", false)

addEventHandler("onBankBalanceChanged", root, function(accountId, balance, amount, key, params)
    for _, c in pairs(CO.byId) do
        if MONEY.accountId(c) == accountId then
            c.clean = math.floor(balance)
            if key ~= "resync" and amount ~= 0 then
                table.insert(c.ledger, 1, MONEY.cleanRow(c, BIZ.now(), amount, balance, key, params))
                while #c.ledger > BIZ.LEDGER_CACHE do table.remove(c.ledger) end
            end
            CO.publish(c)
            triggerEvent("onBizBalanceChanged", resourceRoot, c.id, c.clean, c.dirty)
            return
        end
    end
end)

-- a company account created after the company was loaded (new organization)
addEventHandler("onBankAccountReady", root, function(accountId, kind, ownerRef)
    if kind ~= "company" then return end
    local c = CO.byId[tonumber(ownerRef)]
    if not c then return end
    c.bankId = accountId
    MONEY.refreshClean(c)
    CO.publish(c)
end)

--------------------------------------------------------------------------------
-- laundering: queued by the founder (casino computer), processed by biz_casino
-- once per casino hour
--------------------------------------------------------------------------------

function MONEY.setLaunder(c, value)
    local delta = value - c.launder
    c.launder = value
    c.sync.launder = (c.sync.launder or 0) + delta
    DB.exec("UPDATE biz_companies SET launder_queue = launder_queue + ? WHERE id = ?", delta, c.id)
    CO.publish(c)
end

function MONEY.queueLaunder(c, amount)
    amount = amountOf(amount)
    if not c or not amount then return false, "invalid" end
    if c.launder + amount > c.dirty then return false, "not_enough_dirty" end
    MONEY.setLaunder(c, c.launder + amount)
    return true
end

--- dirty -> clean: the dirty part leaves here, the clean part (minus the fee) enters the bank
function MONEY.processLaunder(c, max, feeRatio)
    max = math.floor(tonumber(max) or 0)
    local take = math.min(c.launder, c.dirty, max)
    if take <= 0 then
        if c.launder > c.dirty then MONEY.setLaunder(c, math.max(0, c.dirty)) end
        return 0, 0
    end
    if not MONEY.accountId(c) or not bank() then return 0, 0 end
    local fee = math.floor(take * (tonumber(feeRatio) or 0))
    MONEY.setLaunder(c, c.launder - take)
    MONEY.applyDirty(c, -take, "launder", ("Laundered € %d (fee € %d)"):format(take, fee), "")
    if take - fee > 0 then MONEY.creditClean(c, take - fee, "biz.launder", { amount = take, fee = fee }, "") end
    if isElement(c.founder) then STAT.add(c.founder, STAT.IDS.laundered, take) end
    return take, fee
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

local function loaded(id) return CO.byId[tonumber(id)] end

-- export category -> v_bank key (clean part): credit / debit
local CATEGORY_KEY = {
    ["casino.hour"] = { credit = "biz.casino_hour", debit = "biz.casino_loss" },
    ["weed.supply"] = { debit = "biz.weed_supply" },
}

function getCompanyBalance(id)
    local c = loaded(id)
    if not c then return false end
    return c.clean, c.dirty
end

function creditCompany(id, amount, category, desc, actor, dirty, ref, params)
    category = category or "other"
    if dirty then return MONEY.credit(loaded(id), amount, category, nil, desc or "", actor or "", true) end
    local k = CATEGORY_KEY[category]
    if not k or not k.credit then
        outputDebugString("[biz_core] creditCompany: no bank key for category " .. tostring(category), 2)
        return false
    end
    return MONEY.credit(loaded(id), amount, k.credit, params, desc or "", actor or "") == true
end

function debitCompany(id, amount, category, desc, actor, ref, params)
    category = category or "other"
    local k = CATEGORY_KEY[category]
    if not k or not k.debit then
        outputDebugString("[biz_core] debitCompany: no bank key for category " .. tostring(category), 2)
        return false, "bad_key"
    end
    return MONEY.debit(loaded(id), amount, k.debit, params, desc or "", actor or "")
end

function queueLaunder(id, amount)
    return MONEY.queueLaunder(loaded(id), amount)
end

function processLaunder(id, max, feeRatio)
    local c = loaded(id)
    if not c then return 0, 0 end
    return MONEY.processLaunder(c, max, feeRatio)
end

function clearLaunderQueue(id)
    local c = loaded(id)
    if not c then return false end
    MONEY.setLaunder(c, 0)
    return true
end

function getLaunderQueue(id)
    local c = loaded(id)
    return c and c.launder or 0
end

-- v_gov hourly company income tax: the founder is told (the row itself comes from v_bank)
addEvent("onGovCompanyTaxed", false)
addEventHandler("onGovCompanyTaxed", root, function(companyId, tax, base)
    local c = CO.byId[tonumber(companyId)]
    if c then NOTIFY.company(c, "founder", L.msg("biz_core.tax.paid", { amount = tax, base = base })) end
end)
