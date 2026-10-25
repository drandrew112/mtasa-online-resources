-- gov_perms / server/salary.lua
-- Salaries (DESIGN.md 9): every position has its own salary per online hour, paid by the State
-- Treasury. Every SALARY_TICK s each instance adds the tick to salary_sec of the appointments
-- whose official is logged in HERE (a player is online on one instance only, so an hour is never
-- counted twice); at SALARY_HOUR the row is claimed (UPDATE ... WHERE salary_sec >= 3600, one
-- winner) and paid: v_bank key salary.gov from the treasury (may go negative, the salary is
-- always paid), then the income tax of the position's tax key (tax.income to the account set on
-- the Taxes page), a gov_perms_salaries row and a notification. Salary 0 = nothing booked.

addEvent("onGovSalaryPaid", false)   -- (account, group code, gross, tax), source = gov_perms resourceRoot

local function int(v) return DB.int(v) end

local function govTax() return isResourceRunning("gov_tax") and exports.gov_tax or nil end

--- income tax rate (0..1) of a tax key (gov_tax), 0 when it does not run / the key is gone
local function taxRate(key)
    local t = govTax()
    if not t then return 0 end
    local ok, keys = pcall(function() return t:getIncomeTaxKeys() end)
    local rate = ok and type(keys) == "table" and tonumber(keys[key]) or nil
    if rate == nil and ok and type(keys) == "table" then rate = tonumber(keys.standard) end
    return rate or 0
end

local function pay(player, m)
    local g = GROUPS[m.groupId]
    if not g or g.salary <= 0 or not isElement(player) then return end
    local bank = GOV.bank()
    local tid = GOV.treasuryId()
    local pid = bank and bank:getPlayerAccount(player)
    if not tid or not pid then return end
    local gross = g.salary
    local ok, err = bank:transfer(tid, pid, gross, "salary.gov", { position = g.name }, "gov_perms")
    if not ok then
        outputDebugString(("[gov_perms] salary of %s (%s) failed: %s"):format(m.account, g.code, tostring(err)), 2)
        return
    end
    local rate = taxRate(g.taxKey)
    local tax = math.floor(gross * rate)
    if tax > 0 then
        local t = govTax()
        local target = t and tonumber(t:getTaxTarget("income")) or nil
        bank:forceTakeMoney(player, tax, "tax.income", { work = g.name, key = g.taxKey, rate = math.floor(rate * 100 + 0.5) }, target)
    end
    DB.exec("INSERT INTO gov_perms_salaries (ts, account_name, group_id, gross, tax) VALUES (?, ?, ?, ?, ?)",
        GOV.now(), m.account, g.id, gross, tax)
    triggerClientEvent(player, "gov_perms:salary", resourceRoot, g.name, gross, tax)
    triggerEvent("onGovSalaryPaid", resourceRoot, m.account, g.code, gross, tax)
end

local function tick()
    if not PERMS.ready then return end
    local bank = GOV.bank()
    if not bank or bank:isBankReady() ~= true then return end
    local players, ids = {}, {}
    for _, player in ipairs(getElementsByType("player")) do
        local acc = GOV.accountOf(player)
        if acc then players[acc] = player end
    end
    local byId = {}
    for _, m in pairs(MEMBERS) do
        local g = GROUPS[m.groupId]
        if players[m.account] and g and g.status == "active" and (m.expiresAt == 0 or m.expiresAt > GOV.now()) then
            ids[#ids + 1] = m.id
            byId[m.id] = m
        end
    end
    if #ids == 0 then return end
    local marks = {}
    for i = 1, #ids do marks[i] = "?" end
    local list = table.concat(marks, ",")
    DB.exec("UPDATE gov_perms_members SET salary_sec = salary_sec + " .. PERMS.SALARY_TICK .. " WHERE id IN (" .. list .. ")", unpack(ids))
    local args = { unpack(ids) }
    args[#args + 1] = PERMS.SALARY_HOUR
    DB.query(function(rows)
        for _, r in ipairs(rows or {}) do
            local id = int(r.id)
            DB.query(function(res, affected)
                if res == false or tonumber(affected) ~= 1 then return end
                local m = byId[id]
                if m then pay(players[m.account], m) end
            end, "UPDATE gov_perms_members SET salary_sec = salary_sec - ? WHERE id = ? AND salary_sec >= ?",
                PERMS.SALARY_HOUR, id, PERMS.SALARY_HOUR)
        end
    end, "SELECT id FROM gov_perms_members WHERE id IN (" .. list .. ") AND salary_sec >= ?", unpack(args))
end

setTimer(tick, PERMS.SALARY_TICK * 1000, 0)

-- payouts older than 30 days go (GOV.HISTORY_DAYS), once an hour
setTimer(function()
    DB.exec("DELETE FROM gov_perms_salaries WHERE ts < ?", GOV.historySince())
end, 3600000, 0)

--------------------------------------------------------------------------------
-- the plan (gov_treasury Budget plan) and the 30-day sums (Permissions page)
--------------------------------------------------------------------------------

local PAID7 = {}    -- ["account|group id"] = payouts in the last 7 days
local PAID30 = {}   -- [group id] = { gross, count }, [account] = gross (key "acc:<name>")

function PERMS.loadSalaryStats(cb)
    local now = GOV.now()
    DB.query(function(rows)
        local p7, p30 = {}, {}
        for _, r in ipairs(rows or {}) do
            local acc, gid, ts, gross = tostring(r.account_name), int(r.group_id), int(r.ts), int(r.gross)
            if ts >= now - 7 * 86400 then p7[acc .. "|" .. gid] = (p7[acc .. "|" .. gid] or 0) + 1 end
            local g = p30[gid] or { gross = 0, count = 0 }
            g.gross, g.count = g.gross + gross, g.count + 1
            p30[gid] = g
            p30["acc:" .. acc] = (p30["acc:" .. acc] or 0) + gross
        end
        if rows then PAID7, PAID30 = p7, p30 end
        if cb then cb() end
    end, "SELECT ts, account_name, group_id, gross FROM gov_perms_salaries WHERE ts >= ?", GOV.historySince())
end

function PERMS.paid30(groupId) return PAID30[groupId] or { gross = 0, count = 0 } end
function PERMS.paid30Account(account) return PAID30["acc:" .. account] or 0 end

--- expected online hours per day of an appointment: the average of the last 7 days when it is
--- older than 7 days, else the setting perms.salary.plan_hours
function PERMS.planHours(m)
    local default = tonumber(GOV.get("perms.salary.plan_hours")) or PERMS.PLAN_HOURS
    if m.grantedAt > GOV.now() - 7 * 86400 then return default end
    return (PAID7[m.account .. "|" .. m.groupId] or 0) / 7
end

--- export (gov_treasury Budget plan): the salaries the treasury will pay
--- { defaultHours, rows = { { group, name, account, salary, hours, expiresAt }, ... } }
function getSalaryPlan()
    local rows = {}
    for _, m in pairs(MEMBERS) do
        local g = GROUPS[m.groupId]
        if g and g.status == "active" and g.salary > 0 then
            rows[#rows + 1] = { group = g.code, name = g.name, account = m.account, salary = g.salary,
                hours = math.floor(PERMS.planHours(m) * 100 + 0.5) / 100, expiresAt = m.expiresAt }
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    return { defaultHours = tonumber(GOV.get("perms.salary.plan_hours")) or PERMS.PLAN_HOURS, rows = rows }
end
