if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/companies.lua
-- Loaded companies. A company is loaded on the instance where its founder is
-- online (login / resource start) and unloaded when the founder leaves. Only
-- loaded companies run: money is changed in memory first (synchronous exports)
-- and written to MySQL as deltas right after. The clean money is the company's
-- v_bank account (server/money.lua); balance_clean is not used any more.
--
-- Company record (CO.byId[id]):
--   id, account (owner), founderAccount, name, clean (v_bank mirror), dirty, launder, hqUnit, bankId,
--   status, activeSeconds, upkeepSeconds, valueCache, peakValue, createdAt,
--   renamedAt, founder (player element or nil), units = { [unitId] = unit },
--   ledger = { newest first }, paused, sync = { clean, dirty } (resync deltas)
-- Unit record (UNITS[id]):
--   id, companyId, propertyId, pricePaid, upgradesPaid, purchasedAt, data

CO = { byId = {}, byAccount = {}, loading = {} }
UNITS = {}

addEvent("onBizCompanyLoaded", false)     -- (companyId, founder)
addEvent("onBizCompanyUnloaded", false)   -- (companyId, reason)  reason: "quit" | "sold" | "stop"
addEvent("onBizAccessChanged", false)     -- source = player; units this player may enter changed
addEvent("onBizUnitAdded", false)         -- (unitId, propertyId, companyId)
addEvent("onBizUnitRemoved", false)       -- (unitId, propertyId, companyId, reason)
addEvent("onPlayerLoaded", false)

local int = DB.int

--------------------------------------------------------------------------------
-- accounts
--------------------------------------------------------------------------------

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end
BIZ.running = running

--- account name of a logged-in player, or nil
function CO.accountOf(player)
    if not isElement(player) or getElementType(player) ~= "player" then return nil end
    local name
    if running("acc_auth") then name = exports.acc_auth:getName(player) end
    if not name then name = getElementData(player, "accName") end
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

--- online player of an account (this instance), or nil
function CO.playerOf(account)
    if not account then return nil end
    local lower = account:lower()
    for _, p in ipairs(getElementsByType("player")) do
        local a = CO.accountOf(p)
        if a and a:lower() == lower then return p end
    end
end

--------------------------------------------------------------------------------
-- records
--------------------------------------------------------------------------------

local function unitFromRow(r)
    local data = r.data_json and r.data_json ~= "" and fromJSON(r.data_json) or nil
    return {
        id = int(r.id), companyId = int(r.company_id), propertyId = tostring(r.property_id),
        pricePaid = int(r.price_paid), upgradesPaid = int(r.upgrades_paid),
        purchasedAt = int(r.purchased_at), data = type(data) == "table" and data or {},
    }
end
CO.unitFromRow = unitFromRow

local function companyFromRow(r)
    return {
        id = int(r.id), account = r.owner_account, founderAccount = r.founder_account,
        name = tostring(r.name), clean = 0, dirty = int(r.balance_dirty),
        launder = int(r.launder_queue), hqUnit = int(r.hq_unit_id), status = tostring(r.status),
        activeSeconds = int(r.active_seconds), upkeepSeconds = int(r.upkeep_seconds), taxSeconds = int(r.tax_seconds),
        valueCache = int(r.value_cache), peakValue = int(r.peak_value),
        createdAt = int(r.created_at), renamedAt = int(r.renamed_at),
        units = {}, ledger = {}, paused = false, sync = { dirty = 0 },
    }
end
CO.companyFromRow = companyFromRow

local function ledgerFromRow(r)
    return {
        id = int(r.id), ts = int(r.ts), amount = int(r.amount), dirty = int(r.dirty) == 1,
        balance = int(r.balance_after), category = tostring(r.category),
        description = tostring(r.description or ""), actor = tostring(r.actor_account or ""),
    }
end
CO.ledgerFromRow = ledgerFromRow

function CO.balance(c) return c.clean + c.dirty end

function CO.unitsOfKind(c, kind)
    local out = {}
    for _, u in pairs(c.units) do
        local p = BIZ.property(u.propertyId)
        if p and (not kind or p.kind == kind) then out[#out + 1] = u end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function CO.hasProperty(c, propertyId)
    for _, u in pairs(c.units) do
        if u.propertyId == propertyId then return u end
    end
    return nil
end

function CO.office(c)
    return c.units[c.hqUnit] or CO.unitsOfKind(c, "office")[1]
end

--------------------------------------------------------------------------------
-- company value: balance + every property / upgrade price paid + stock value
--------------------------------------------------------------------------------

--- stock value of a unit, asked from its activity resource (0 without one)
function CO.stockValue(u)
    local p = BIZ.property(u.propertyId)
    local act = p and p.activity and ACT.list[p.activity]
    if not act or not act.valueFn then return 0 end
    local res = getResourceFromName(act.resource)
    if not res or getResourceState(res) ~= "running" then return 0 end
    local ok, v = pcall(call, res, act.valueFn, u.id)
    return ok and math.max(0, int(v)) or 0
end

--- assets = properties + upgrades + stock (everything but the balance)
function CO.assets(c)
    local sum = 0
    for _, u in pairs(c.units) do
        sum = sum + u.pricePaid + u.upgradesPaid + CO.stockValue(u)
    end
    return sum
end

function CO.value(c)
    return CO.balance(c) + CO.assets(c)
end

--- payout of selling the organization: the clean balance + SALE_ASSET_RATIO of the assets
--- (the dirty money is lost at a sale)
function CO.salePayout(c)
    local assets = CO.assets(c)
    return c.clean + math.floor(assets * BIZ.SALE_ASSET_RATIO), assets
end

function CO.saveValue(c)
    local v = CO.value(c)
    c.valueCache = v
    if v > c.peakValue then c.peakValue = v end
    DB.exec("UPDATE biz_companies SET value_cache = ?, peak_value = GREATEST(peak_value, ?) WHERE id = ?", v, v, c.id)
    if isElement(c.founder) then STAT.value(c.founder, v) end
    return v
end

--------------------------------------------------------------------------------
-- element data for the founder (ui_inac, phone, HUD read it) - synced to him only
--------------------------------------------------------------------------------

--- element data only this player receives ("local" on the server would sync to nobody)
function setOwnData(player, key, value)
    addElementDataSubscriber(player, key, player)
    return setElementData(player, key, value, "subscribe")
end

function CO.publish(c)
    if not c or not isElement(c.founder) then return end
    setOwnData(c.founder, "biz:company", {
        id = c.id, name = c.name, clean = c.clean, dirty = c.dirty, paused = c.paused,
        associates = MEM.count(c.id), maxAssociates = BIZ.MAX_ASSOCIATES,
        office = c.units[c.hqUnit] and c.units[c.hqUnit].propertyId or nil,
    })
end

--- copy for other resources / the web pages (no element references)
function CO.public(c)
    if not c then return false end
    local units = {}
    for _, u in ipairs(CO.unitsOfKind(c)) do units[#units + 1] = CO.unitPublic(u) end
    return {
        id = c.id, name = c.name, account = c.account, founderAccount = c.founderAccount,
        clean = c.clean, dirty = c.dirty, balance = CO.balance(c), launder = c.launder,
        hqUnit = c.hqUnit, status = c.status, paused = c.paused, online = isElement(c.founder),
        activeSeconds = c.activeSeconds, upkeepSeconds = c.upkeepSeconds,
        createdAt = c.createdAt, renamedAt = c.renamedAt, units = units,
        associates = MEM.publicList(c.id), maxAssociates = BIZ.MAX_ASSOCIATES,
    }
end

function CO.unitPublic(u)
    local p = BIZ.property(u.propertyId) or {}
    return {
        id = u.id, companyId = u.companyId, propertyId = u.propertyId, kind = p.kind,
        activity = p.activity, tier = p.tier, building = p.building, template = p.template,
        name = BIZ.propertyName(u.propertyId), pricePaid = u.pricePaid, upgradesPaid = u.upgradesPaid,
        purchasedAt = u.purchasedAt, upkeep = p.upkeep or 0, illegal = p.illegal and true or false,
        dimension = BIZ.DIM_BASE + u.id,
    }
end

--------------------------------------------------------------------------------
-- load / unload
--------------------------------------------------------------------------------

local function accessChanged(c)
    if isElement(c.founder) then triggerEvent("onBizAccessChanged", c.founder) end
    for p in pairs(MEM.membersOf(c.id)) do triggerEvent("onBizAccessChanged", p) end
end
CO.accessChanged = accessChanged

--- the company of this account becomes the running record of `player`
local function attach(c, player)
    local old = CO.byId[c.id]
    if old and old ~= c then return end
    CO.byId[c.id] = c
    CO.byAccount[c.account:lower()] = c
    c.founder = player
    for _, u in pairs(c.units) do UNITS[u.id] = u end
    TICK.start(c)
    CO.publish(c)
    triggerEvent("onBizCompanyLoaded", resourceRoot, c.id, player)
    accessChanged(c)
    CO.saveValue(c)
end

--- loads the active company of `account` (if any) and attaches it to `player`
function CO.load(account, player, cb)
    if not account or not DB.ready then if cb then cb(false) end return end
    local key = account:lower()
    if CO.byAccount[key] then
        local c = CO.byAccount[key]
        if isElement(player) and c.founder ~= player then
            c.founder = player
            CO.publish(c)
            accessChanged(c)
        end
        if cb then cb(c) end
        return
    end
    if CO.loading[key] then
        if cb then table.insert(CO.loading[key], cb) end
        return
    end
    CO.loading[key] = { cb }

    local function finish(c)
        local waiting = CO.loading[key] or {}
        CO.loading[key] = nil
        if c and isElement(player) then attach(c, player) end
        for _, f in ipairs(waiting) do if f then f(c or false) end end
    end

    DB.query(function(rows)
        if not rows or not rows[1] then return finish(nil) end
        local c = companyFromRow(rows[1])
        -- the clean money: the v_bank account (created here if it is missing)
        MONEY.refreshClean(c)
        local bankId = MONEY.accountId(c)
        local b = MONEY.bank()
        if not bankId and b and b:isBankReady() then b:createCompanyAccount(c.id, c.name, c.account) end
        DB.query(function(urows)
            for _, r in ipairs(urows or {}) do
                local u = unitFromRow(r)
                if BIZ.property(u.propertyId) then c.units[u.id] = u
                else outputDebugString("[biz_core] unit " .. u.id .. " has unknown property " .. u.propertyId, 2) end
            end
            DB.query(function(lrows)
                for _, r in ipairs(lrows or {}) do c.ledger[#c.ledger + 1] = ledgerFromRow(r) end
                local function done() finish(c) end
                if not bankId then return done() end
                -- clean rows of the bank account, merged in by time
                DB.query(function(brows)
                    for _, r in ipairs(brows or {}) do
                        local params = r.params and r.params ~= "" and fromJSON(tostring(r.params)) or {}
                        local bal = r.balance_after ~= nil and r.balance_after ~= false and tonumber(r.balance_after) or nil
                        c.ledger[#c.ledger + 1] = MONEY.cleanRow(c, int(r.ts), int(r.amount), bal, tostring(r.tx_key),
                            type(params) == "table" and params or {}, r.actor)
                    end
                    table.sort(c.ledger, function(x, y) return x.ts > y.ts end)
                    while #c.ledger > BIZ.LEDGER_CACHE do table.remove(c.ledger) end
                    done()
                end, "SELECT ts, amount, balance_after, tx_key, params, actor FROM bank_ledger WHERE account_id = ? ORDER BY id DESC LIMIT "
                    .. BIZ.LEDGER_CACHE, bankId)
            end, "SELECT * FROM biz_ledger WHERE company_id = ? ORDER BY id DESC LIMIT " .. BIZ.LEDGER_CACHE, c.id)
        end, "SELECT * FROM biz_units WHERE company_id = ?", c.id)
    end, "SELECT * FROM biz_companies WHERE owner_account = ? AND status = 'active' LIMIT 1", account)
end

--- stops a loaded company (founder left / sold / resource stop)
function CO.unload(c, reason)
    if not c or CO.byId[c.id] ~= c then return end
    TICK.finish(c)                   -- partial minute of online time
    MEM.removeAll(c.id, "founder_quit")
    triggerEvent("onBizCompanyUnloaded", resourceRoot, c.id, reason or "quit")
    if isElement(c.founder) then
        removeElementData(c.founder, "biz:company")
        triggerEvent("onBizAccessChanged", c.founder)
    end
    for id in pairs(c.units) do UNITS[id] = nil end
    CO.byId[c.id] = nil
    CO.byAccount[c.account:lower()] = nil
    c.founder = nil
end

--- company of a player as founder (loaded), or nil
function CO.ofPlayer(player)
    local acc = CO.accountOf(player)
    return acc and CO.byAccount[acc:lower()] or nil
end

--------------------------------------------------------------------------------
-- resync: dirty balance and launder queue of loaded companies re-read every
-- RESYNC_MS, so an admin change made on another instance shows up here. Local
-- deltas issued after the SELECT was sent are added on top of the answer (same
-- connection = FIFO). The clean part is re-read by v_bank itself.
--------------------------------------------------------------------------------

function CO.resync()
    for _, c in pairs(CO.byId) do
        local id = c.id
        c.sync = { dirty = 0, launder = 0 }
        DB.query(function(rows)
            local cur = CO.byId[id]
            if not cur or not rows or not rows[1] then return end
            local r = rows[1]
            if r.status ~= "active" then return end
            local dirty = int(r.balance_dirty) + (cur.sync.dirty or 0)
            local launder = int(r.launder_queue) + (cur.sync.launder or 0)
            if dirty ~= cur.dirty or launder ~= cur.launder then
                cur.dirty, cur.launder = dirty, launder
                CO.publish(cur)
            end
        end, "SELECT balance_dirty, launder_queue, status FROM biz_companies WHERE id = ?", id)
    end
end

--------------------------------------------------------------------------------
-- player events
--------------------------------------------------------------------------------

addEventHandler("onPlayerLoaded", root, function(accName)
    local player = source
    local acc = (type(accName) == "string" and accName ~= "") and accName or CO.accountOf(player)
    if acc then CO.load(acc, player) end
end)

addEventHandler("onPlayerQuit", root, function()
    for _, c in pairs(CO.byId) do
        if c.founder == source then CO.unload(c, "quit") break end
    end
end)

local function loadEveryone()
    for _, p in ipairs(getElementsByType("player")) do
        local acc = CO.accountOf(p)
        if acc then CO.load(acc, p) end
    end
end
CO.loadEveryone = loadEveryone
