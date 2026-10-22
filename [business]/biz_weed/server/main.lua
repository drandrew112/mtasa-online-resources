if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
-- biz_weed / server/main.lua
-- Weed farm state per unit (table biz_weed) and its simulation on the
-- biz_core online tick: bought supply counts down, supply turns into product.
-- Nothing happens while the founder is offline or the company is paused.
--
-- Server exports:
--   getUnitStockValue(unitId)        -> euro (company value)
--   getPanelState(unitId)            -> OrgOS Weed farm app
--   panelAction(player, unitId, action, args)  buy | upgrade | steal | sell
--   addSupply(unitId, units)         -> added (missions: stolen supply)
--   takeProduct(unitId, units)       -> taken
--   returnProduct(unitId, units)     -> returned (missions: disconnect = 50% back)
--   getWeedState(unitId)             -> copy of the state

local W = {}     -- unitId -> { unitId, companyId, supply, product, progress, pending, pendingLeft, cooldown, notified = {} }

local function core() return exports.biz_core end
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

addEvent("biz_core:ready", false)
addEvent("onBizCompanyLoaded", false)
addEvent("onBizCompanyUnloaded", false)
addEvent("onBizCompanyTick", false)
addEvent("onBizCompanyPaused", false)
addEvent("onBizUnitAdded", false)
addEvent("onBizUnitRemoved", false)
addEvent("onPlayerEnterBizUnit", false)
addEvent("onPlayerExitBizUnit", false)

local ready = false
local SCHEMA = [[CREATE TABLE IF NOT EXISTS biz_weed (
    unit_id INT UNSIGNED NOT NULL,
    supply INT UNSIGNED NOT NULL DEFAULT 0,
    product INT UNSIGNED NOT NULL DEFAULT 0,
    progress_seconds INT UNSIGNED NOT NULL DEFAULT 0,
    pending_supply INT UNSIGNED NOT NULL DEFAULT 0,
    pending_seconds_left INT UNSIGNED NOT NULL DEFAULT 0,
    cooldown_seconds INT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (unit_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

local function exec(sql, ...)
    if running("v_mysql") then exports.v_mysql:mysqlExec(sql, ...) end
end

--------------------------------------------------------------------------------
-- state helpers
--------------------------------------------------------------------------------

local function flag(unitId, key)
    return running("biz_core") and core():getUnitData(unitId, key) == true
end

local function capacity(st)
    return flag(st.unitId, "capacity") and WEED.UPGRADES.capacity.capacity or WEED.BASE_CAPACITY
end

local function unitSeconds(st)
    return flag(st.unitId, "staff") and WEED.UPGRADES.staff.unitSeconds or WEED.UNIT_SECONDS
end

local function save(st)
    exec([[INSERT INTO biz_weed (unit_id, supply, product, progress_seconds, pending_supply, pending_seconds_left, cooldown_seconds)
           VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE supply = VALUES(supply), product = VALUES(product),
           progress_seconds = VALUES(progress_seconds), pending_supply = VALUES(pending_supply),
           pending_seconds_left = VALUES(pending_seconds_left), cooldown_seconds = VALUES(cooldown_seconds)]],
        st.unitId, st.supply, st.product, math.floor(st.progress), st.pending, math.floor(st.pendingLeft), math.floor(st.cooldown))
end

local function value(st)
    return st.product * WEED.PRODUCT_VALUE + st.supply * WEED.SUPPLY_VALUE
end

local function notify(st, key, params, scope)
    if running("biz_core") then core():notifyCompany(st.companyId, scope or "all", L.msg(key, params)) end
end

--------------------------------------------------------------------------------
-- HUD of the players inside (ui_core stat trackers, client/hud.lua)
--------------------------------------------------------------------------------

local inside = {}   -- player -> unitId

local function hudData(st)
    local cap = capacity(st)
    return { supply = st.supply, product = st.product, capacity = cap, value = st.product * WEED.PRODUCT_VALUE,
             pending = st.pending, pendingLeft = st.pendingLeft }
end

local function pushHud(st)
    local data
    for p, unitId in pairs(inside) do
        if unitId == st.unitId and isElement(p) then
            data = data or hudData(st)
            triggerClientEvent(p, "bizweed:hud", resourceRoot, data)
        end
    end
end

addEventHandler("onPlayerEnterBizUnit", root, function(unitId, propertyId, kind)
    if kind ~= "weed" then return end
    local st = W[unitId]
    if not st then return end
    inside[source] = unitId
    triggerClientEvent(source, "bizweed:hud", resourceRoot, hudData(st))
end)

addEventHandler("onPlayerExitBizUnit", root, function()
    if inside[source] then
        inside[source] = nil
        triggerClientEvent(source, "bizweed:hud", resourceRoot, false)
    end
end)

addEventHandler("onPlayerQuit", root, function() inside[source] = nil end)

--------------------------------------------------------------------------------
-- simulation (online tick)
--------------------------------------------------------------------------------

local function simulate(st, dt)
    local changed = false
    if st.cooldown > 0 then st.cooldown = math.max(0, st.cooldown - dt) end

    if st.pending > 0 then
        st.pendingLeft = st.pendingLeft - dt
        if st.pendingLeft <= 0 then
            local add = math.min(st.pending, capacity(st) - st.supply)
            st.supply = st.supply + math.max(0, add)
            notify(st, "biz_weed.supply_arrived", { units = st.pending })
            st.pending, st.pendingLeft = 0, 0
            st.notified.empty = false
            changed = true
        end
    end

    local cap, per = capacity(st), unitSeconds(st)
    if st.supply > 0 and st.product < cap then
        st.progress = st.progress + dt
        while st.progress >= per and st.supply > 0 and st.product < cap do
            st.progress = st.progress - per
            st.supply = st.supply - 1
            st.product = st.product + 1
            changed = true
        end
        if st.product >= cap then st.progress = 0 end
    else
        st.progress = 0
    end

    if st.supply == 0 and st.pending == 0 and not st.notified.empty then
        st.notified.empty = true
        notify(st, "biz_weed.supply_empty", nil, "founder")
    end
    if st.product >= cap and not st.notified.full then
        st.notified.full = true
        notify(st, "biz_weed.product_full", nil, "founder")
    elseif st.product < cap then
        st.notified.full = false
    end
    return changed
end

addEventHandler("onBizCompanyTick", root, function(companyId, dt)
    for _, st in pairs(W) do
        if st.companyId == companyId then
            simulate(st, dt)
            save(st)
            pushHud(st)
        end
    end
end)

--------------------------------------------------------------------------------
-- load / unload
--------------------------------------------------------------------------------

local function loadUnit(unitId, companyId)
    if W[unitId] then return end
    local st = { unitId = unitId, companyId = companyId, supply = 0, product = 0, progress = 0,
                 pending = 0, pendingLeft = 0, cooldown = 0, notified = {}, loading = true }
    W[unitId] = st
    MYSQL.query(function(rows)
        local r = rows and rows[1]
        if r then
            st.supply, st.product = tonumber(r.supply) or 0, tonumber(r.product) or 0
            st.progress = tonumber(r.progress_seconds) or 0
            st.pending, st.pendingLeft = tonumber(r.pending_supply) or 0, tonumber(r.pending_seconds_left) or 0
            st.cooldown = tonumber(r.cooldown_seconds) or 0
        else
            save(st)
        end
        st.loading = nil
        -- no reminder right after a login for a state that was already reported
        st.notified.empty = st.supply == 0 and st.pending == 0
        st.notified.full = st.product >= capacity(st)
        pushHud(st)
    end, "SELECT * FROM biz_weed WHERE unit_id = ?", unitId)
end

local function loadCompany(companyId)
    if not running("biz_core") then return end
    for _, u in ipairs(core():getCompanyUnits(companyId, "weed") or {}) do loadUnit(u.id, companyId) end
end

addEventHandler("onBizCompanyLoaded", root, function(companyId) loadCompany(companyId) end)

addEventHandler("onBizCompanyUnloaded", root, function(companyId)
    for id, st in pairs(W) do
        if st.companyId == companyId then
            save(st)
            W[id] = nil
        end
    end
end)

addEventHandler("onBizUnitAdded", root, function(unitId, propertyId, companyId)
    local p = core():getProperty(propertyId)
    if p and p.activity == "weed" then loadUnit(unitId, companyId) end
end)

addEventHandler("onBizUnitRemoved", root, function(unitId)
    if not W[unitId] then return end
    W[unitId] = nil
    exec("DELETE FROM biz_weed WHERE unit_id = ?", unitId)
end)

--------------------------------------------------------------------------------
-- exports for missions / value
--------------------------------------------------------------------------------

function getUnitStockValue(unitId)
    local st = W[tonumber(unitId)]
    return st and value(st) or 0
end

function getWeedState(unitId)
    local st = W[tonumber(unitId)]
    if not st then return false end
    return { unitId = st.unitId, companyId = st.companyId, supply = st.supply, product = st.product,
             capacity = capacity(st), unitSeconds = unitSeconds(st), pending = st.pending, cooldown = st.cooldown }
end

function addSupply(unitId, units)
    local st = W[tonumber(unitId)]
    units = math.floor(tonumber(units) or 0)
    if not st or units <= 0 then return 0 end
    local add = math.max(0, math.min(units, capacity(st) - st.supply))
    st.supply = st.supply + add
    st.notified.empty = false
    save(st)
    pushHud(st)
    return add
end

function takeProduct(unitId, units)
    local st = W[tonumber(unitId)]
    units = math.floor(tonumber(units) or 0)
    if not st or units <= 0 then return 0 end
    local take = math.min(units, st.product)
    st.product = st.product - take
    save(st)
    pushHud(st)
    return take
end

function returnProduct(unitId, units)
    local st = W[tonumber(unitId)]
    units = math.floor(tonumber(units) or 0)
    if units <= 0 then return 0 end
    if not st then
        -- the company stopped first (founder left): straight into the table, capped at the biggest capacity
        exec("UPDATE biz_weed SET product = LEAST(product + ?, ?) WHERE unit_id = ?", units, WEED.UPGRADES.capacity.capacity, tonumber(unitId))
        return units
    end
    local back = math.max(0, math.min(units, capacity(st) - st.product))
    st.product = st.product + back
    save(st)
    pushHud(st)
    return back
end

function setMissionCooldown(unitId, seconds)
    local st = W[tonumber(unitId)]
    if not st then return false end
    st.cooldown = math.max(0, tonumber(seconds) or WEED.MISSION_COOLDOWN)
    save(st)
    return true
end

--------------------------------------------------------------------------------
-- OrgOS app (biz_pc)
--------------------------------------------------------------------------------

local function mission(unitId)
    if not running("biz_missions") then return false end
    return exports.biz_missions:getUnitMission(unitId) or false
end

function getPanelState(unitId)
    local st = W[tonumber(unitId)]
    if not st then return false end
    local associates = core():getAssociateCount(st.companyId) or 0
    local packs = {}
    for _, p in ipairs(WEED.PACKS) do packs[#packs + 1] = { id = p.id, units = p.units, price = p.price, seconds = p.seconds } end
    return {
        kind = "weed",
        supply = st.supply, product = st.product, capacity = capacity(st), unitSeconds = unitSeconds(st),
        pendingSupply = st.pending, pendingLeft = st.pendingLeft, productValue = st.product * WEED.PRODUCT_VALUE,
        packs = packs, stealUnits = WEED.STEAL_UNITS, cooldown = st.cooldown,
        mission = mission(st.unitId), perVehicle = WEED.PER_VEHICLE, associates = associates,
        maxSell = WEED.PER_VEHICLE * (1 + associates), multiplier = core():getSaleMultiplier("weed") or 1,
        paused = core():isCompanyPaused(st.companyId),
        upgrades = {
            { id = "capacity", label = "Bigger grow room", desc = ("Supply and product capacity %d → %d."):format(WEED.BASE_CAPACITY, WEED.UPGRADES.capacity.capacity),
              price = WEED.UPGRADES.capacity.price, owned = flag(st.unitId, "capacity") },
            { id = "staff", label = "Hire staff", desc = ("One unit every %d s instead of %d s."):format(WEED.UPGRADES.staff.unitSeconds, WEED.UNIT_SECONDS),
              price = WEED.UPGRADES.staff.price, owned = flag(st.unitId, "staff") },
        },
    }
end

local ACTIONS = {}

function ACTIONS.buy(player, st, args)
    local pack
    for _, p in ipairs(WEED.PACKS) do if p.id == args.pack then pack = p end end
    if not pack then return { ok = false, error = "bad_amount" } end
    if st.pending > 0 then return { ok = false, error = "pending" } end
    if st.supply + pack.units > capacity(st) then return { ok = false, error = "no_space" } end
    local ok, err = core():debitCompany(st.companyId, pack.price, "weed.supply", ("Supply order: %d units"):format(pack.units), "")
    if not ok then return { ok = false, error = err } end
    st.pending, st.pendingLeft = pack.units, pack.seconds
    save(st)
    pushHud(st)
    core():addBizStat(player, "biz_supply_bought", pack.units)
    notify(st, "biz_weed.supply_ordered", { units = pack.units, minutes = math.floor(pack.seconds / 60) }, "founder")
    return { ok = true }
end

function ACTIONS.upgrade(player, st, args)
    local up = WEED.UPGRADES[args.id]
    if not up then return { ok = false, error = "unknown_upgrade" } end
    if flag(st.unitId, args.id) then return { ok = false, error = "already_owned" } end
    local label = args.id == "capacity" and "Bigger grow room" or "Hire staff"
    local ok, err = core():buyUnitUpgrade(st.unitId, up.price, label, "")
    if not ok then return { ok = false, error = err } end
    core():setUnitData(st.unitId, args.id, true)
    if running("biz_int") then exports.biz_int:refreshUnitProps(st.unitId) end
    pushHud(st)
    notify(st, "biz_weed.upgrade_done", { name = label }, "founder")
    if flag(st.unitId, "capacity") and flag(st.unitId, "staff") then core():unlockBizAchievement(player, "biz_fully_equipped") end
    return { ok = true }
end

function ACTIONS.steal(player, st)
    if not running("biz_missions") then return { ok = false, error = "activity_offline" } end
    if core():isCompanyPaused(st.companyId) then return { ok = false, error = "paused" } end
    if mission(st.unitId) then return { ok = false, error = "mission_running" } end
    if st.cooldown > 0 then return { ok = false, error = "mission_cooldown" } end
    if st.supply >= capacity(st) then return { ok = false, error = "no_space" } end
    local ok, err = exports.biz_missions:startSupplyMission(player, st.unitId)
    if not ok then return { ok = false, error = err or "failed" } end
    return { ok = true }
end

function ACTIONS.sell(player, st, args)
    if not running("biz_missions") then return { ok = false, error = "activity_offline" } end
    if core():isCompanyPaused(st.companyId) then return { ok = false, error = "paused" } end
    if mission(st.unitId) then return { ok = false, error = "mission_running" } end
    if st.cooldown > 0 then return { ok = false, error = "mission_cooldown" } end
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount <= 0 or st.product <= 0 then return { ok = false, error = "no_product" } end
    if amount > st.product then return { ok = false, error = "not_enough_product" } end
    local max = WEED.PER_VEHICLE * (1 + (core():getAssociateCount(st.companyId) or 0))
    if amount > max then return { ok = false, error = "too_many" } end
    local taken = takeProduct(st.unitId, amount)
    local ok, err = exports.biz_missions:startSellMission(player, st.unitId, taken, WEED.PRODUCT_VALUE, WEED.PER_VEHICLE)
    if not ok then
        returnProduct(st.unitId, taken)
        return { ok = false, error = err or "failed" }
    end
    return { ok = true }
end

function panelAction(player, unitId, action, args)
    local st = W[tonumber(unitId)]
    if not st or st.loading then return { ok = false, error = "activity_offline" } end
    local fn = ACTIONS[action]
    if not fn then return { ok = false, error = "unknown_action" } end
    return fn(player, st, type(args) == "table" and args or {})
end

--------------------------------------------------------------------------------

local function register()
    if not running("biz_core") then return end
    core():registerActivity("weed", { kind = "supply_deliver", valueFn = "getUnitStockValue" })
    for _, p in ipairs(getElementsByType("player")) do
        local id = core():getPlayerCompanyId(p)
        if id then loadCompany(id) end
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    MYSQL.query(function(ok, err)
        if ok == false then outputDebugString("[biz_weed] schema failed: " .. tostring(err), 1) end
        ready = true
        register()
    end, SCHEMA)
end)
addEventHandler("biz_core:ready", root, function() if ready then register() end end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, st in pairs(W) do save(st) end
end)
