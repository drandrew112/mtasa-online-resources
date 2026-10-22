if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
-- biz_casino / server/main.lua
-- Casino operation: legal, passive income. One result per hour of the
-- founder's ONLINE time (biz_core tick), with random swings and rare events.
-- The same hour launders queued dirty money (biz_core queueLaunder).
-- The upkeep is paid by biz_core every 2 online hours, like every property.
--
-- Tables: biz_casino_state (hour progress per unit), biz_casino_hours (history).

local CFG = {
    BASE         = 22000,     -- average result of an hour (before upkeep)
    SIGMA        = 0.25,      -- relative spread
    EVENING      = 1.2,       -- 18:00-24:00 server time
    EVENT_CHANCE = 0.08,
    EVENTS = {
        { id = "jackpot",    label = "Jackpot payout", min = -25000, max = -10000, weight = 4 },
        { id = "whale",      label = "High roller",    min = 20000,  max = 45000,  weight = 4 },
        { id = "inspection", label = "Inspection",     min = -5000,  max = -5000,  weight = 2 },
    },
    LAUNDER_PER_HOUR = 40000,
    LAUNDER_FEE      = 0.12,
    HISTORY          = 48,    -- hours kept in memory per unit
}
local HOUR = 3600

local ST = {}      -- unitId -> { unitId, companyId, hourSeconds, hours = { {ts, result, event} } }

local function core() return exports.biz_core end
local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

addEvent("biz_core:ready", false)
addEvent("onBizCompanyLoaded", false)
addEvent("onBizCompanyUnloaded", false)
addEvent("onBizCompanyTick", false)
addEvent("onBizUnitAdded", false)
addEvent("onBizUnitRemoved", false)

local function exec(sql, ...)
    if running("v_mysql") then exports.v_mysql:mysqlExec(sql, ...) end
end

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS biz_casino_state (
        unit_id INT UNSIGNED NOT NULL,
        hour_seconds INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (unit_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS biz_casino_hours (
        id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        unit_id INT UNSIGNED NOT NULL,
        ts INT UNSIGNED NOT NULL,
        revenue BIGINT NOT NULL,
        laundered BIGINT NOT NULL DEFAULT 0,
        event VARCHAR(32) NOT NULL DEFAULT '',
        PRIMARY KEY (id),
        KEY idx_unit_ts (unit_id, ts)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}
local ready = false

--------------------------------------------------------------------------------
-- simulation
--------------------------------------------------------------------------------

local function gauss()
    local u1, u2 = math.max(1e-9, math.random()), math.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end

local function pickEvent()
    if math.random() >= CFG.EVENT_CHANCE then return nil end
    local total = 0
    for _, e in ipairs(CFG.EVENTS) do total = total + e.weight end
    local r = math.random() * total
    for _, e in ipairs(CFG.EVENTS) do
        r = r - e.weight
        if r <= 0 then return e end
    end
end

--- one casino hour: result (euro, may be negative) and the event or nil
function simulateHour()
    local h = getRealTime().hour
    local mult = (h >= 18) and CFG.EVENING or 1
    local result = CFG.BASE * mult * math.max(0, 1 + gauss() * CFG.SIGMA)
    local e = pickEvent()
    if e then result = result + math.random(e.min, e.max) end
    return math.floor(result + 0.5), e
end

local function pushHour(st, row)
    table.insert(st.hours, row)
    while #st.hours > CFG.HISTORY do table.remove(st.hours, 1) end
end

local function runHour(st)
    local cid = st.companyId
    local result, e = simulateHour()
    local label = e and e.label or ""
    if result > 0 then
        core():creditCompany(cid, result, "casino.hour", "The Casino: hour result" .. (e and (" (" .. label .. ")") or ""), "")
    elseif result < 0 then
        -- a losing hour takes what the account has
        local clean, dirty = core():getCompanyBalance(cid)
        local take = math.min(-result, (clean or 0) + (dirty or 0))
        if take > 0 then core():debitCompany(cid, take, "casino.hour", "The Casino: losing hour" .. (e and (" (" .. label .. ")") or ""), "") end
    end
    local laundered = core():processLaunder(cid, CFG.LAUNDER_PER_HOUR, CFG.LAUNDER_FEE) or 0
    local ts = getRealTime().timestamp
    pushHour(st, { ts = ts, result = result, event = label })
    exec("INSERT INTO biz_casino_hours (unit_id, ts, revenue, laundered, event) VALUES (?, ?, ?, ?, ?)", st.unitId, ts, result, laundered, e and e.id or "")

    local founder = core():getCompanyFounder(cid)
    if founder then
        if result > 0 then core():addBizStat(founder, "biz_casino_income", result) end
        local key = result >= 0 and "biz_casino.hour_plus" or "biz_casino.hour_minus"
        core():notifyCompany(cid, "founder", L.msg(key, { amount = math.abs(result) }))
        if e then core():notifyCompany(cid, "founder", L.msg("biz_casino.event_" .. e.id, { amount = math.abs(result) })) end
        if laundered > 0 then
            core():notifyCompany(cid, "founder", L.msg("biz_casino.laundered", { amount = laundered, fee = math.floor(laundered * CFG.LAUNDER_FEE) }))
        end
    end
end

addEventHandler("onBizCompanyTick", root, function(companyId, dt)
    for _, st in pairs(ST) do
        if st.companyId == companyId then
            st.hourSeconds = st.hourSeconds + dt
            while st.hourSeconds >= HOUR do
                st.hourSeconds = st.hourSeconds - HOUR
                runHour(st)
            end
            exec("INSERT INTO biz_casino_state (unit_id, hour_seconds) VALUES (?, ?) ON DUPLICATE KEY UPDATE hour_seconds = VALUES(hour_seconds)",
                st.unitId, st.hourSeconds)
        end
    end
end)

--------------------------------------------------------------------------------
-- load / unload with the companies
--------------------------------------------------------------------------------

local function loadUnit(unitId, companyId)
    if ST[unitId] then return end
    local st = { unitId = unitId, companyId = companyId, hourSeconds = 0, hours = {} }
    ST[unitId] = st
    MYSQL.query(function(rows)
        if rows and rows[1] then st.hourSeconds = tonumber(rows[1].hour_seconds) or 0 end
    end, "SELECT hour_seconds FROM biz_casino_state WHERE unit_id = ?", unitId)
    MYSQL.query(function(rows)
        for i = #(rows or {}), 1, -1 do
            local r = rows[i]
            local ev = tostring(r.event or "")
            local label = ""
            for _, e in ipairs(CFG.EVENTS) do if e.id == ev then label = e.label end end
            pushHour(st, { ts = tonumber(r.ts) or 0, result = tonumber(r.revenue) or 0, event = label })
        end
    end, "SELECT ts, revenue, event FROM biz_casino_hours WHERE unit_id = ? ORDER BY id DESC LIMIT " .. CFG.HISTORY, unitId)
end

local function loadCompany(companyId)
    if not running("biz_core") then return end
    for _, u in ipairs(core():getCompanyUnits(companyId, "casino") or {}) do loadUnit(u.id, companyId) end
end

local function unloadCompany(companyId)
    for id, st in pairs(ST) do if st.companyId == companyId then ST[id] = nil end end
end

addEventHandler("onBizCompanyLoaded", root, function(companyId) loadCompany(companyId) end)
addEventHandler("onBizCompanyUnloaded", root, function(companyId) unloadCompany(companyId) end)

addEventHandler("onBizUnitAdded", root, function(unitId, propertyId, companyId)
    local p = core():getProperty(propertyId)
    if p and p.activity == "casino" then loadUnit(unitId, companyId) end
end)

addEventHandler("onBizUnitRemoved", root, function(unitId)
    if not ST[unitId] then return end
    ST[unitId] = nil
    exec("DELETE FROM biz_casino_state WHERE unit_id = ?", unitId)
end)

--------------------------------------------------------------------------------
-- OrgOS app (biz_pc)
--------------------------------------------------------------------------------

function getPanelState(unitId)
    local st = ST[tonumber(unitId)]
    if not st then return false end
    local sum, n = 0, 0
    local since = getRealTime().timestamp - 86400
    for _, h in ipairs(st.hours) do
        if h.ts >= since then sum, n = sum + h.result, n + 1 end
    end
    return {
        kind = "casino",
        hourLeft = HOUR - st.hourSeconds,
        hours = st.hours,
        average = n > 0 and math.floor(sum / n) or 0,
        launderQueue = core():getLaunderQueue(st.companyId) or 0,
        launderPerHour = CFG.LAUNDER_PER_HOUR, launderFee = CFG.LAUNDER_FEE,
        paused = core():isCompanyPaused(st.companyId),
    }
end

function panelAction(player, unitId, action, args)
    local st = ST[tonumber(unitId)]
    if not st then return { ok = false, error = "activity_offline" } end
    if action == "launder" then
        local ok, err = core():queueLaunder(st.companyId, math.floor(tonumber(args and args.amount) or 0))
        if not ok then return { ok = false, error = err == "invalid" and "bad_amount" or err } end
        return { ok = true }
    elseif action == "clear" then
        core():clearLaunderQueue(st.companyId)
        return { ok = true }
    end
    return { ok = false, error = "unknown_action" }
end

--------------------------------------------------------------------------------

local function register()
    if not running("biz_core") then return end
    core():registerActivity("casino", { kind = "passive" })
    for _, p in ipairs(getElementsByType("player")) do
        local id = core():getPlayerCompanyId(p)
        if id then loadCompany(id) end
    end
end

local function schema(i)
    i = i or 1
    if i > #SCHEMA then ready = true; return register() end
    MYSQL.query(function(ok, err)
        if ok == false then
            outputDebugString("[biz_casino] schema failed: " .. tostring(err), 1)
            return setTimer(schema, 10000, 1, i)
        end
        schema(i + 1)
    end, SCHEMA[i])
end

addEventHandler("onResourceStart", resourceRoot, function()
    math.randomseed(getTickCount())
    schema(1)
end)
addEventHandler("biz_core:ready", root, function() if ready then register() end end)
