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

--- a fee of the state (gov_tax /gov, else the config value)
local function fee(key, fallback)
    if BIZ.running("gov_tax") then
        local v = tonumber(exports.gov_tax:getFee(key))
        if v then return math.floor(v) end
    end
    return fallback
end
BIZ.fee = fee

--- v_bank account id a fee goes to (the /gov Fees page), or nil = the money disappears
local function feeTarget(key)
    if not BIZ.running("gov_tax") then return nil end
    return tonumber(exports.gov_tax:getFeeTarget(key)) or nil
end
BIZ.feeTarget = feeTarget

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

--- police_system wanted level for withdrawing dirty money. police_system only gives it in dimension 0 (the
--- office computer is in an interior), so it waits until the player is back outside.
local pendingWanted = {}

local function giveDirtyWanted(player)
    if not BIZ.running("police_system") then pendingWanted[player] = nil return end
    local ok, why = exports.police_system:addWanted(player, BIZ.DIRTY_WANTED_REASON, BIZ.DIRTY_WANTED_LEVEL)
    pendingWanted[player] = (not ok and (why == "dimension" or why == "bad_player")) or nil
end

addEventHandler("onElementDimensionChange", root, function(_, newDim)
    if getElementType(source) == "player" and pendingWanted[source] and newDim == 0 then giveDirtyWanted(source) end
end)
addEventHandler("onPlayerSpawn", root, function()
    if pendingWanted[source] and getElementDimension(source) == 0 then giveDirtyWanted(source) end
end)
addEventHandler("onPlayerQuit", root, function() pendingWanted[source] = nil end)

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

    -- the registration fee goes to its /gov account (a refund comes back from it), the office
    -- price disappears
    local regFee = fee("register", BIZ.REG_FEE)
    local regTarget = feeTarget("register")
    local gross, vat = BIZ.grossPrice(p)
    local total = regFee + gross
    if (tonumber(b:getPlayerBalance(player)) or 0) < total then return fail("not_enough_money", { total = total }) end
    local office = BIZ.propertyName(officeId)
    if regFee > 0 and b:takeBankMoney(player, regFee, "biz.register_fee", { company = clean }, regTarget) ~= true then
        return fail("not_enough_money", { total = total })
    end
    if b:takeBankMoney(player, gross, "biz.office_purchase", { property = office }) ~= true then
        if regFee > 0 then b:giveBankMoney(player, regFee, "biz.register_refund", { company = clean }, regTarget) end
        return fail("not_enough_money", { total = total })
    end

    local key = acc:lower()
    ACTION.creating[key] = true
    local now = BIZ.now()

    local function refund(code)
        ACTION.creating[key] = nil
        if isElement(player) then
            if regFee > 0 then b:giveBankMoney(player, regFee, "biz.register_refund", { company = clean }, regTarget) end
            b:giveBankMoney(player, gross, "biz.office_refund", { property = office })
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
            VAT.book("real_estate", p.price, vat, office)
            -- the bank account of the clean money; the record picks it up on onBankAccountReady
            b:createCompanyAccount(id, clean, acc)
            CO.load(acc, player, function(c)
                ACTION.creating[key] = nil
                if not c then return end
                c.hqUnit = unitId
                MONEY.applyDirty(c, 0, "founded", ("Organization founded, headquarters %s (paid by the founder: € %d)"):format(BIZ.propertyName(officeId), total), acc)
                CO.publish(c)
                REG.refresh()
                if isElement(player) then
                    NOTIFY.player(player, L.msg("biz_core.register.done", { name = c.name, office = BIZ.propertyName(officeId) }))
                    STAT.unlock(player, "biz_registered")
                    if p.tier == "exclusive" then STAT.unlock(player, "biz_corner_office") end
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
    local gross = BIZ.grossPrice(p)
    if CO.balance(c) < gross then return fail("not_enough_money", { total = gross }) end
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
        if p.tier == "exclusive" then STAT.unlock(player, "biz_corner_office") end
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
    local renameCost = fee("rename", BIZ.RENAME_COST)
    if CO.balance(c) < renameCost then return fail("not_enough_money", { total = renameCost }) end

    -- the unique key decides: rename only after MySQL accepted the new name
    local id, oldName = c.id, c.name
    DB.query(function(res, affected)
        local cur = CO.byId[id]
        if not cur then return end
        if res == false or tonumber(affected) ~= 1 then
            NOTIFY.player(player, L.msg("biz_core.rename.taken"))
            return
        end
        if renameCost > 0 and not MONEY.debit(cur, renameCost, "biz.rename_fee", { name = clean }, ("Renamed from %s"):format(oldName), cur.account, feeTarget("rename")) then
            -- spent meanwhile: keep the new name, the fee is skipped (rare race)
            outputDebugString("[biz_core] rename fee of company " .. id .. " could not be taken", 2)
        end
        cur.name = clean
        cur.renamedAt = BIZ.now()
        CO.publish(cur)
        for p in pairs(MEM.membersOf(id)) do setOwnData(p, "biz:member", { id = id, name = clean }) end
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
    local from, to = b and b:getPlayerAccount(player), MONEY.accountId(c)
    if not from or not to then return fail("unavailable") end
    local ok, err = b:transfer(from, to, amount, "biz.deposit", { company = c.name, player = playerName(player) }, c.account)
    if not ok then return fail(err == "not_enough_money" and "not_enough_money" or "unavailable", { total = amount }) end
    NOTIFY.player(player, L.msg("biz_core.money.deposited", { amount = amount }))
    return { ok = true }
end

--- part: "clean" (default, to the bank account of the founder) | "dirty" (always as cash)
function withdrawFromCompany(player, amount, part)
    local c, e = own(player)
    if not c then return e end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return fail("bad_amount") end
    part = part == "dirty" and "dirty" or "clean"
    if part == "dirty" then
        if c.dirty < amount then return fail("not_enough_money") end
        MONEY.applyDirty(c, -amount, "withdrawal", ("Withdrawal to %s (dirty, cash)"):format(playerName(player)), c.account)
        givePlayerMoney(player, amount)
        if BIZ.running("ui_core") then exports.ui_core:showMoney(player, "add", amount, "cash") end
        addDirtyAcc(player, BIZ.ACC_DIRTY_WITHDRAWN, amount)
        giveDirtyWanted(player)
    else
        local b = bank()
        local from, to = MONEY.accountId(c), b and b:getPlayerAccount(player)
        if not from or not to then return fail("unavailable") end
        local ok, err = b:transfer(from, to, amount, "biz.withdraw", { company = c.name, player = playerName(player) }, c.account)
        if not ok then return fail(err == "not_enough_money" and "not_enough_money" or "unavailable") end
    end
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
    local gross = BIZ.grossPrice(p)
    if CO.balance(c) < gross then return fail("not_enough_money", { total = gross }) end
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
    local bankId, playerAcc = MONEY.accountId(c), b and b:getPlayerAccount(player)
    if not bankId or not playerAcc then return fail("unavailable") end
    local payout, assets = CO.salePayout(c)
    local assetPart = math.floor(assets * BIZ.SALE_ASSET_RATIO)

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
    -- the dirty money is lost
    DB.exec("INSERT INTO biz_ledger (company_id, ts, amount, dirty, balance_after, category, description, actor_account) VALUES (?, ?, ?, 1, 0, 'company.sell', ?, ?)",
        c.id, BIZ.now(), -c.dirty, ("Organization sold, € %d paid to the founder (assets € %d), dirty money lost"):format(payout, assets), c.account)
    DB.exec("UPDATE biz_companies SET status = 'sold', owner_account = NULL, name_key = NULL, sold_at = ?, balance_clean = 0, balance_dirty = 0, launder_queue = 0, value_cache = 0, hq_unit_id = NULL WHERE id = ?",
        BIZ.now(), c.id)

    -- the bank account: a debt is paid from the asset part (the rest is written off), a positive
    -- clean balance goes to the founder, then the account is closed
    local name = c.name
    local clean = c.clean
    if clean < 0 then
        local cover = math.min(assetPart, -clean)
        if cover > 0 then b:credit(bankId, cover, "biz.property_sell", { property = "Liquidation" }, c.account) end
        assetPart = assetPart - cover
        if clean + cover < 0 then b:credit(bankId, -(clean + cover), "biz.write_off", { company = name }, c.account) end
    elseif clean > 0 then
        b:transfer(bankId, playerAcc, clean, "biz.close_payout", { company = name }, c.account)
    end
    if assetPart > 0 then b:giveBankMoney(player, assetPart, "biz.asset_sale", { company = name }) end
    b:closeAccount(bankId)
    payout = math.max(0, clean) + assetPart
    c.clean, c.dirty, c.launder = 0, 0, 0

    CO.unload(c, "sold")
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
    pub.renameCost, pub.renameWait = fee("rename", BIZ.RENAME_COST), math.max(0, c.renamedAt + BIZ.RENAME_COOLDOWN - BIZ.now())
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
        regFee = fee("register", BIZ.REG_FEE), nameMin = BIZ.NAME_MIN, nameMax = BIZ.NAME_MAX,
        renameCost = fee("rename", BIZ.RENAME_COST), renameCooldown = BIZ.RENAME_COOLDOWN,
        saleRatio = BIZ.SALE_ASSET_RATIO, propertySellRatio = BIZ.PROPERTY_SELL_RATIO,
        maxAssociates = BIZ.MAX_ASSOCIATES, upkeepInterval = BIZ.UPKEEP_INTERVAL,
        associateShare = BIZ.ASSOCIATE_SHARE, thiefShare = BIZ.THIEF_SHARE,
    }
end
