if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / server/tick.lua
-- The online clock of a company. Runs only while its founder is online on
-- this instance: one tick per BIZ.TICK_MS, plus a partial tick when he leaves.
-- Every tick:
--   * active_seconds / upkeep_seconds grow by the elapsed online seconds
--   * every UPKEEP_INTERVAL online seconds the upkeep of every property and
--     the office is paid; without money the company pauses (no production, no
--     casino) and the payment is retried every tick
--   * every PROPERTY_TAX_INTERVAL online seconds the property tax (v_gov rate x the price of every
--     legal property) goes to the State Treasury; it is forced (the account may go negative)
--   * while not paused: onBizCompanyTick (companyId, seconds) for the activities

TICK = {}

local function upkeepOf(c)
    local sum = 0
    for _, u in pairs(c.units) do
        local p = BIZ.property(u.propertyId)
        sum = sum + (p and p.upkeep or 0)
    end
    return sum
end
TICK.upkeepOf = upkeepOf

local function payUpkeep(c)
    local total = upkeepOf(c)
    if total <= 0 then
        c.upkeepSeconds = c.upkeepSeconds - BIZ.UPKEEP_INTERVAL
        return true
    end
    local n = 0
    for _ in pairs(c.units) do n = n + 1 end
    local ok = MONEY.debit(c, total, "biz.upkeep", { count = n }, ("Upkeep of %d properties (2 h)"):format(n), "")
    if ok then
        c.upkeepSeconds = c.upkeepSeconds - BIZ.UPKEEP_INTERVAL
        NOTIFY.company(c, "founder", L.msg("biz_core.upkeep.paid", { amount = total }))
        if c.paused then
            c.paused = false
            NOTIFY.company(c, "all", L.msg("biz_core.upkeep.resumed"))
        end
        return true
    end
    c.upkeepSeconds = BIZ.UPKEEP_INTERVAL   -- retried next tick
    if not c.paused then
        c.paused = true
        NOTIFY.company(c, "all", L.msg("biz_core.upkeep.unpaid", { amount = total }))
        triggerEvent("onBizCompanyPaused", resourceRoot, c.id, true)
    end
    return false
end

addEvent("onBizCompanyPaused", false)   -- (companyId, paused)

--- the property tax of one interval -> amount, value (sum of the legal property prices), count
local function propertyTaxOf(c)
    local res = getResourceFromName("v_gov")
    local rate = res and getResourceState(res) == "running" and tonumber(exports.v_gov:getPropertyTaxRate()) or 0
    local value, n = 0, 0
    for _, u in pairs(c.units) do
        local p = BIZ.property(u.propertyId)
        if p and not p.illegal then value, n = value + p.price, n + 1 end
    end
    return math.floor(value * rate + 0.5), value, n, rate
end
TICK.propertyTaxOf = propertyTaxOf

local function payPropertyTax(c)
    c.taxSeconds = c.taxSeconds - BIZ.PROPERTY_TAX_INTERVAL
    local tax, value, n, rate = propertyTaxOf(c)
    if tax <= 0 then return end
    -- to the state account set on the /gov Taxes page (none = the money disappears)
    local res = getResourceFromName("v_gov")
    local target = res and getResourceState(res) == "running" and tonumber(exports.v_gov:getTaxTarget("property")) or nil
    local ok, err = MONEY.debitClean(c, tax, "tax.property",
        { count = n, value = value, rate = math.floor(rate * 1000 + 0.5) / 10 }, "", target)
    if not ok then
        outputDebugString(("[biz_core] property tax of company %d failed: %s"):format(c.id, tostring(err)), 2)
        return
    end
    MONEY.refreshClean(c)
    NOTIFY.company(c, "founder", L.msg("biz_core.tax.property_paid", { amount = tax, count = n }))
end

local function run(c, dt)
    if not c or CO.byId[c.id] ~= c then return end
    dt = math.max(0, math.floor(dt + 0.5))
    if dt <= 0 then return end
    c.activeSeconds = c.activeSeconds + dt
    c.upkeepSeconds = c.upkeepSeconds + dt
    c.taxSeconds = (c.taxSeconds or 0) + dt
    local wasPaused = c.paused
    if c.upkeepSeconds >= BIZ.UPKEEP_INTERVAL then payUpkeep(c) end
    if c.taxSeconds >= BIZ.PROPERTY_TAX_INTERVAL then payPropertyTax(c) end
    if wasPaused and not c.paused then triggerEvent("onBizCompanyPaused", resourceRoot, c.id, false) end
    if not c.paused then
        triggerEvent("onBizCompanyTick", resourceRoot, c.id, dt)
    end
    DB.exec("UPDATE biz_companies SET active_seconds = ?, upkeep_seconds = ?, tax_seconds = ? WHERE id = ?",
        c.activeSeconds, math.max(0, c.upkeepSeconds), math.max(0, c.taxSeconds), c.id)
    CO.saveValue(c)
    CO.publish(c)
end

function TICK.start(c)
    if isTimer(c.tickTimer) then killTimer(c.tickTimer) end
    c.lastTick = getTickCount()
    c.tickTimer = setTimer(function()
        local now = getTickCount()
        local dt = (now - (c.lastTick or now)) / 1000
        c.lastTick = now
        run(c, dt)
    end, BIZ.TICK_MS, 0)
end

--- partial tick for the seconds since the last full one (founder leaving)
function TICK.finish(c)
    if isTimer(c.tickTimer) then killTimer(c.tickTimer) end
    c.tickTimer = nil
    if c.lastTick then
        run(c, (getTickCount() - c.lastTick) / 1000)
        c.lastTick = nil
    end
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

--- founder online on this instance and upkeep paid
function isCompanyActive(companyId)
    local c = CO.byId[tonumber(companyId)]
    return c and isElement(c.founder) and not c.paused or false
end

function isCompanyPaused(companyId)
    local c = CO.byId[tonumber(companyId)]
    return c and c.paused or false
end

--- online seconds until the next property tax payment, its amount and rate
function getPropertyTaxInfo(companyId)
    local c = CO.byId[tonumber(companyId)]
    if not c then return false end
    local tax, value, n, rate = propertyTaxOf(c)
    return math.max(0, BIZ.PROPERTY_TAX_INTERVAL - (c.taxSeconds or 0)), tax, rate
end

--- online seconds until the next upkeep payment, and its amount
function getUpkeepInfo(companyId)
    local c = CO.byId[tonumber(companyId)]
    if not c then return false end
    return math.max(0, BIZ.UPKEEP_INTERVAL - c.upkeepSeconds), upkeepOf(c)
end
