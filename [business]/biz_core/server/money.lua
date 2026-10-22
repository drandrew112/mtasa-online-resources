if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/money.lua
-- The company account. Two parts: clean and dirty (illegal income). Spending
-- takes the clean part first, so dirty money stays until it is laundered or
-- withdrawn. Every change writes one ledger row.
--
-- Server exports (loaded companies only, i.e. founder online on this instance):
--   getCompanyBalance(id)                                   -> clean, dirty | false
--   creditCompany(id, amount, category, desc, actor, dirty, ref)  -> true | false
--   debitCompany(id, amount, category, desc, actor, ref)          -> true | false, "not_enough_money"
--   queueLaunder(id, amount)  /  processLaunder(id, max, feeRatio) -> laundered, fee

MONEY = {}

addEvent("onBizBalanceChanged", false)   -- (companyId, clean, dirty)

local function amountOf(v)
    v = math.floor(tonumber(v) or 0)
    return v > 0 and v or nil
end

--- applies a delta to both parts and writes the ledger row
function MONEY.apply(c, dClean, dDirty, category, desc, actor, ref, ledgerAmount)
    dClean, dDirty = math.floor(dClean or 0), math.floor(dDirty or 0)
    c.clean = c.clean + dClean
    c.dirty = c.dirty + dDirty
    c.sync.clean = (c.sync.clean or 0) + dClean
    c.sync.dirty = (c.sync.dirty or 0) + dDirty
    DB.exec("UPDATE biz_companies SET balance_clean = balance_clean + ?, balance_dirty = balance_dirty + ? WHERE id = ?",
        dClean, dDirty, c.id)

    local amount = ledgerAmount or (dClean + dDirty)
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

function MONEY.credit(c, amount, category, desc, actor, dirty, ref)
    amount = amountOf(amount)
    if not c or not amount then return false end
    if dirty then return MONEY.apply(c, 0, amount, category, desc, actor, ref) end
    return MONEY.apply(c, amount, 0, category, desc, actor, ref)
end

--- clean part first, then dirty
function MONEY.debit(c, amount, category, desc, actor, ref)
    amount = amountOf(amount)
    if not c or not amount then return false, "invalid" end
    if CO.balance(c) < amount then return false, "not_enough_money" end
    local fromClean = math.min(c.clean, amount)
    return MONEY.apply(c, -fromClean, -(amount - fromClean), category, desc, actor, ref)
end

--- takes only from one part ("clean" | "dirty"), for withdrawals
function MONEY.debitPart(c, part, amount, category, desc, actor)
    amount = amountOf(amount)
    if not c or not amount then return false, "invalid" end
    if part == "dirty" then
        if c.dirty < amount then return false, "not_enough_money" end
        return MONEY.apply(c, 0, -amount, category, desc, actor)
    end
    if c.clean < amount then return false, "not_enough_money" end
    return MONEY.apply(c, -amount, 0, category, desc, actor)
end

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

function MONEY.processLaunder(c, max, feeRatio)
    max = math.floor(tonumber(max) or 0)
    local take = math.min(c.launder, c.dirty, max)
    if take <= 0 then
        if c.launder > c.dirty then MONEY.setLaunder(c, math.max(0, c.dirty)) end
        return 0, 0
    end
    local fee = math.floor(take * (tonumber(feeRatio) or 0))
    MONEY.setLaunder(c, c.launder - take)
    MONEY.apply(c, take - fee, -take, "launder", ("Laundered € %d (fee € %d)"):format(take, fee), "", nil, -fee)
    if isElement(c.founder) then STAT.add(c.founder, STAT.IDS.laundered, take) end
    return take, fee
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

local function loaded(id) return CO.byId[tonumber(id)] end

function getCompanyBalance(id)
    local c = loaded(id)
    if not c then return false end
    return c.clean, c.dirty
end

function creditCompany(id, amount, category, desc, actor, dirty, ref)
    return MONEY.credit(loaded(id), amount, category or "other", desc or "", actor or "", dirty and true or false, ref)
end

function debitCompany(id, amount, category, desc, actor, ref)
    return MONEY.debit(loaded(id), amount, category or "other", desc or "", actor or "", ref)
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
