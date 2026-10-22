if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/actions.lua
-- What a founder does with his organization (website, office computer, ui_inac
-- menu). Every export takes the acting player first and answers
-- { ok = true, ... } or { ok = false, error = "<code>" }; the error codes are
-- listed in README.md. Asynchronous steps answer { ok = true, pending = true }
-- and finish with a notification.

ACTION = { creating = {} }

local function fail(code, extra)
    local t = { ok = false, error = code }
    if extra then for k, v in pairs(extra) do t[k] = v end end
    return t
end

local function bank() return BIZ.running("v_bank") and exports.v_bank end

local function playerName(p)
    return (getPlayerName(p):gsub("#%x%x%x%x%x%x", ""))
end

--- trimmed name or nil, error
function ACTION.cleanName(name)
    if type(name) ~= "string" then return nil, "name_invalid" end
    name = name:gsub("#%x%x%x%x%x%x", ""):gsub("[%c]", ""):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    local len = utf8 and utf8.len(name) or #name
    if not len or len < BIZ.NAME_MIN then return nil, "name_short" end
    if len > BIZ.NAME_MAX then return nil, "name_long" end
    -- letters (any script), digits, space and a few punctuation marks
    if name:find("[<>\"\\{}%[%]`|~^$]") then return nil, "name_invalid" end
    return name
end

function ACTION.defaultName(player)
    return playerName(player) .. "'s organization"
end

local function addDirtyAcc(player, key, amount)
    if amount <= 0 or not BIZ.running("v_mysql") then return end
    local old = tonumber(exports.v_mysql:getAccData(player, key)) or 0
    exports.v_mysql:setAccData(player, key, old + amount)
end
ACTION.addDirtyAcc = addDirtyAcc

--------------------------------------------------------------------------------
-- register
--------------------------------------------------------------------------------

function createCompany(player, name, officeId)
    local acc = CO.accountOf(player)
    if not acc then return fail("not_logged_in") end
    if not DB.ready then return fail("unavailable") end
    if CO.ofPlayer(player) or ACTION.creating[acc:lower()] then return fail("has_company") end
    local clean, err = ACTION.cleanName(name)
    if not clean then return fail(err) end
    if REG.nameTaken(clean) then return fail("name_taken") end
    local p = BIZ.property(officeId)
    if not p or p.kind ~= "office" then return fail("bad_office") end
    local b = bank()
    if not b then return fail("unavailable") end

    local total = BIZ.REG_FEE + p.price
    local paid = b:takeBankMoney(player, total)
    if paid ~= true then return fail("not_enough_money", { total = total }) end

    local key = acc:lower()
    ACTION.creating[key] = true
    local now = BIZ.now()

    local function refund(code)
        ACTION.creating[key] = nil
        if isElement(player) then
            b:giveBankMoney(player, total)
            NOTIFY.player(player, L.msg("biz_core.register.failed_" .. code))
        end
    end

    DB.insert(function(id, ierr)
        if not id or id == true then
            outputDebugString("[biz_core] company insert failed: " .. tostring(ierr), 2)
            return refund(tostring(ierr):lower():find("duplicate") and "taken" or "db")
        end
        DB.insert(function(unitId)
            if not unitId or unitId == true then
                DB.exec("DELETE FROM biz_companies WHERE id = ?", id)
                return refund("db")
            end
            DB.exec("UPDATE biz_companies SET hq_unit_id = ? WHERE id = ?", unitId, id)
            CO.load(acc, player, function(c)
                ACTION.creating[key] = nil
                if not c then return end
                c.hqUnit = unitId
                MONEY.apply(c, 0, 0, "founded", ("Organization founded, headquarters %s (paid by the founder: € %d)"):format(BIZ.propertyName(officeId), total), acc)
                CO.publish(c)
                REG.refresh()
                if isElement(player) then
                    NOTIFY.player(player, L.msg("biz_core.register.done", { name = c.name, office = BIZ.propertyName(officeId) }))
                    STAT.unlock(player, "biz_registered")
                    if p.tier == "executive" then STAT.unlock(player, "biz_corner_office") end
                end
            end)
        end, "INSERT INTO biz_units (company_id, property_id, price_paid, purchased_at) VALUES (?, ?, ?, ?)", id, officeId, p.price, now)
    end, "INSERT INTO biz_companies (owner_account, founder_account, name, name_key, created_at) VALUES (?, ?, ?, ?, ?)",
        acc, acc, clean, clean:lower(), now)

    return { ok = true, pending = true, total = total }
end

--------------------------------------------------------------------------------
-- founder actions on a loaded company
--------------------------------------------------------------------------------

local function own(player)
    local c = CO.ofPlayer(player)
    if not c or c.founder ~= player then return nil, fail("no_company") end
    return c
end

function moveHeadquarters(player, officeId)
    local c, e = own(player)
    if not c then return e end
    local p = BIZ.property(officeId)
    if not p or p.kind ~= "office" then return fail("bad_office") end
    local old = CO.office(c)
    if old and old.propertyId == officeId then return fail("already_owned") end
    if CO.balance(c) < p.price then return fail("not_enough_money", { total = p.price }) end
    local acc = c.account
    UNIT.buy(c, officeId, acc, function(u, err)
        if not u then
            NOTIFY.player(player, L.msg("biz_core.hq.failed"))
            return
        end
        c.hqUnit = u.id
        DB.exec("UPDATE biz_companies SET hq_unit_id = ? WHERE id = ?", u.id, c.id)
        if old then UNIT.remove(c, old, "moved", UNIT.refundOf(old), acc) end
        CO.publish(c)
        REG.refresh()
        NOTIFY.company(c, "founder", L.msg("biz_core.hq.moved", { office = BIZ.propertyName(officeId) }))
        if p.tier == "executive" then STAT.unlock(player, "biz_corner_office") end
    end, { office = true })
    return { ok = true, pending = true }
end

function renameCompany(player, name)
    local c, e = own(player)
    if not c then return e end
    local clean, err = ACTION.cleanName(name)
    if not clean then return fail(err) end
    if clean == c.name then return fail("name_same") end
    if REG.nameTaken(clean, c.id) then return fail("name_taken") end
    local wait = c.renamedAt + BIZ.RENAME_COOLDOWN - BIZ.now()
    if wait > 0 then return fail("rename_cooldown", { wait = wait }) end
    if CO.balance(c) < BIZ.RENAME_COST then return fail("not_enough_money", { total = BIZ.RENAME_COST }) end

    -- the unique key decides: rename only after MySQL accepted the new name
    local id, oldName = c.id, c.name
    DB.query(function(res, affected)
        local cur = CO.byId[id]
        if not cur then return end
        if res == false or tonumber(affected) ~= 1 then
            NOTIFY.player(player, L.msg("biz_core.rename.taken"))
            return
        end
        if not MONEY.debit(cur, BIZ.RENAME_COST, "rename", ("Renamed from %s"):format(oldName), cur.account) then
            -- spent meanwhile: keep the new name, the fee is skipped (rare race)
            outputDebugString("[biz_core] rename fee of company " .. id .. " could not be taken", 2)
        end
        cur.name = clean
        cur.renamedAt = BIZ.now()
        CO.publish(cur)
        for p in pairs(MEM.membersOf(id)) do setElementData(p, "biz:member", { id = id, name = clean }, "local") end
        REG.refresh()
        NOTIFY.company(cur, "all", L.msg("biz_core.rename.done", { name = clean }))
    end, "UPDATE biz_companies SET name = ?, name_key = ?, renamed_at = ? WHERE id = ? AND status = 'active'",
        clean, clean:lower(), BIZ.now(), id)
    return { ok = true, pending = true }
end

function depositToCompany(player, amount)
    local c, e = own(player)
    if not c then return e end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return fail("bad_amount") end
    local b = bank()
    if not b then return fail("unavailable") end
    if b:takeBankMoney(player, amount) ~= true then return fail("not_enough_money", { total = amount }) end
    MONEY.credit(c, amount, "deposit", ("Deposit from %s"):format(playerName(player)), c.account)
    NOTIFY.player(player, L.msg("biz_core.money.deposited", { amount = amount }))
    return { ok = true }
end

--- part: "clean" (default) | "dirty"
function withdrawFromCompany(player, amount, part)
    local c, e = own(player)
    if not c then return e end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return fail("bad_amount") end
    part = part == "dirty" and "dirty" or "clean"
    local b = bank()
    if not b then return fail("unavailable") end
    local ok, err = MONEY.debitPart(c, part, amount, "withdrawal",
        ("Withdrawal to %s (%s)"):format(playerName(player), part), c.account)
    if not ok then return fail(err) end
    b:giveBankMoney(player, amount)
    if part == "dirty" then addDirtyAcc(player, BIZ.ACC_DIRTY_WITHDRAWN, amount) end
    NOTIFY.player(player, L.msg(part == "dirty" and "biz_core.money.withdrawn_dirty" or "biz_core.money.withdrawn", { amount = amount }))
    return { ok = true }
end

function buyProperty(player, propertyId)
    local c, e = own(player)
    if not c then return e end
    local p = BIZ.property(propertyId)
    if not p then return fail("unknown_property") end
    if p.kind == "office" then return fail("use_move_hq") end
    if CO.hasProperty(c, propertyId) then return fail("already_owned") end
    if p.activity and not ACT.list[p.activity] then return fail("activity_offline") end
    if CO.balance(c) < p.price then return fail("not_enough_money", { total = p.price }) end
    UNIT.buy(c, propertyId, c.account, function(u, err)
        if not u then
            NOTIFY.player(player, L.msg("biz_core.property.buy_failed"))
            return
        end
        REG.refresh()
        NOTIFY.company(c, "founder", L.msg("biz_core.property.bought", { name = BIZ.propertyName(propertyId) }))
        if p.kind == "casino" then STAT.unlock(player, "biz_house_wins") end
    end)
    return { ok = true, pending = true }
end

function sellProperty(player, unitId)
    local c, e = own(player)
    if not c then return e end
    local u = c.units[tonumber(unitId) or -1]
    if not u then return fail("unknown_unit") end
    if u.id == c.hqUnit then return fail("cannot_sell_hq") end
    local refund = UNIT.refundOf(u)
    UNIT.remove(c, u, "sold", refund, c.account)
    REG.refresh()
    NOTIFY.player(player, L.msg("biz_core.property.sold", { name = BIZ.propertyName(u.propertyId), amount = refund }))
    return { ok = true, refund = refund }
end

--- what selling the organization pays right now
function getCompanySaleQuote(player)
    local c, e = own(player)
    if not c then return e end
    local payout, assets = CO.salePayout(c)
    return { ok = true, payout = payout, balance = CO.balance(c), assets = assets, ratio = BIZ.SALE_ASSET_RATIO }
end

--- sells (closes) the organization: full balance + SALE_ASSET_RATIO of the assets
function sellCompany(player, confirmName)
    local c, e = own(player)
    if not c then return e end
    if confirmName ~= nil and tostring(confirmName) ~= c.name then return fail("confirm_mismatch") end
    local b = bank()
    if not b then return fail("unavailable") end
    local payout, assets = CO.salePayout(c)
    local dirty = c.dirty

    -- no partial tick after this point: the company ends now
    if isTimer(c.tickTimer) then killTimer(c.tickTimer) end
    c.tickTimer, c.lastTick = nil, nil
    MEM.removeAll(c.id, "sold")

    local ids = {}
    for id, u in pairs(c.units) do ids[#ids + 1] = u end
    for _, u in ipairs(ids) do
        c.units[u.id] = nil
        UNITS[u.id] = nil
        triggerEvent("onBizUnitRemoved", resourceRoot, u.id, u.propertyId, c.id, "company_sold")
    end
    DB.exec("DELETE FROM biz_units WHERE company_id = ?", c.id)
    DB.exec("INSERT INTO biz_ledger (company_id, ts, amount, dirty, balance_after, category, description, actor_account) VALUES (?, ?, ?, 0, 0, 'company.sell', ?, ?)",
        c.id, BIZ.now(), -CO.balance(c), ("Organization sold, € %d paid to the founder (assets € %d)"):format(payout, assets), c.account)
    DB.exec("UPDATE biz_companies SET status = 'sold', owner_account = NULL, name_key = NULL, sold_at = ?, balance_clean = 0, balance_dirty = 0, launder_queue = 0, value_cache = 0, hq_unit_id = NULL WHERE id = ?",
        BIZ.now(), c.id)
    c.clean, c.dirty, c.launder = 0, 0, 0

    local name = c.name
    CO.unload(c, "sold")
    if payout > 0 then b:giveBankMoney(player, payout) end
    addDirtyAcc(player, BIZ.ACC_DIRTY_WITHDRAWN, dirty)
    REG.refresh()
    NOTIFY.player(player, L.msg("biz_core.sell.done", { name = name, amount = payout }))
    return { ok = true, payout = payout }
end

--------------------------------------------------------------------------------
-- reads for the web pages / computer
--------------------------------------------------------------------------------

--- the player's own organization (as founder) or false
function getMyOrganization(player)
    local c = CO.ofPlayer(player)
    if not c or c.founder ~= player then
        local acc = CO.accountOf(player)
        return { ok = true, company = false, creating = acc and ACTION.creating[acc:lower()] or false,
                 defaultName = isElement(player) and ACTION.defaultName(player) or "" }
    end
    local pub = CO.public(c)
    pub.value = CO.value(c)
    local payout, assets = CO.salePayout(c)
    pub.salePayout, pub.assets = payout, assets
    local left, upkeep = getUpkeepInfo(c.id)
    pub.upkeepIn, pub.upkeepAmount = left, upkeep
    pub.renameCost, pub.renameWait = BIZ.RENAME_COST, math.max(0, c.renamedAt + BIZ.RENAME_COOLDOWN - BIZ.now())
    for _, u in ipairs(pub.units) do
        u.stockValue = CO.stockValue(c.units[u.id])
        u.refund = UNIT.refundOf(c.units[u.id])
    end
    return { ok = true, company = pub }
end

--- newest ledger rows (cache of the last BIZ.LEDGER_CACHE), optional category prefix
function getCompanyLedger(player, category, limit)
    local c = CO.ofPlayer(player)
    if not c or c.founder ~= player then return fail("no_company") end
    limit = math.min(math.max(tonumber(limit) or 50, 1), BIZ.LEDGER_CACHE)
    category = type(category) == "string" and category ~= "" and category or nil
    local out = {}
    for _, row in ipairs(c.ledger) do
        if not category or row.category:sub(1, #category) == category then
            out[#out + 1] = row
            if #out >= limit then break end
        end
    end
    return { ok = true, rows = out }
end

--- income / expenses of the last `days` days from the cached ledger
function getCompanySummary(player, days)
    local c = CO.ofPlayer(player)
    if not c or c.founder ~= player then return fail("no_company") end
    local since = BIZ.now() - (tonumber(days) or 7) * 86400
    local income, expenses = 0, 0
    for _, row in ipairs(c.ledger) do
        if row.ts < since then break end
        if row.category ~= "launder" and row.category ~= "deposit" and row.category ~= "withdrawal" then
            if row.amount > 0 then income = income + row.amount else expenses = expenses - row.amount end
        end
    end
    return { ok = true, income = income, expenses = expenses }
end

--- company of a player as founder (id) or false
function getPlayerCompanyId(player)
    local c = CO.ofPlayer(player)
    return c and c.founder == player and c.id or false
end

function getPlayerCompany(player)
    local c = CO.ofPlayer(player)
    return c and c.founder == player and CO.public(c) or false
end

function getCompany(companyId)
    return CO.public(CO.byId[tonumber(companyId)])
end

function getCompanyFounder(companyId)
    local c = CO.byId[tonumber(companyId)]
    return c and isElement(c.founder) and c.founder or false
end

function getCompanyValue(companyId)
    local c = CO.byId[tonumber(companyId)]
    return c and CO.value(c) or false
end

--- numbers the web pages / computer show
function getBizConfig()
    return {
        regFee = BIZ.REG_FEE, nameMin = BIZ.NAME_MIN, nameMax = BIZ.NAME_MAX,
        renameCost = BIZ.RENAME_COST, renameCooldown = BIZ.RENAME_COOLDOWN,
        saleRatio = BIZ.SALE_ASSET_RATIO, propertySellRatio = BIZ.PROPERTY_SELL_RATIO,
        maxAssociates = BIZ.MAX_ASSOCIATES, upkeepInterval = BIZ.UPKEEP_INTERVAL,
        associateShare = BIZ.ASSOCIATE_SHARE, thiefShare = BIZ.THIEF_SHARE,
    }
end
