-- gov_tax / server/tax.lua
-- Hourly company income tax. Every full hour (+GOV.TAX_RUN_DELAY s) the hour that just ended is
-- taxed: per company account the sum of its taxable ledger rows (legal income, net) in that hour;
-- a positive base pays floor(base * rate) to the tax's state account (Taxes page; none = the
-- money disappears) (tax.company_income, may push the company below 0). Only one instance runs
-- an hour: it claims the hour in gov_tax_runs.
-- Also the income tax keys, the company tax rate and the tax targets.

addEvent("onGovTaxRun", false)        -- (periodStart, companies, total), source = gov_tax resourceRoot
addEvent("onGovCompanyTaxed", false)  -- (companyId, tax, base, periodStart), source = gov_tax resourceRoot

local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS gov_tax_runs (
        period_start INT UNSIGNED NOT NULL,
        instance VARCHAR(16) NOT NULL,
        companies INT UNSIGNED NOT NULL DEFAULT 0,
        total BIGINT NOT NULL DEFAULT 0,
        finished_at INT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (period_start)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
}

function getCompanyTaxRate()
    return tonumber(GOV.get("tax.company")) or 0
end

--- the account a tax (GOV_TAXES) goes to, or nil = it disappears
function getTaxTarget(tax) return GOV.targetAccount("tax.targets", tax) end

--- the income tax rate keys { key = rate } (gov_works reads them for getIncomeTaxRate)
function getIncomeTaxKeys() return GOV.get("tax.income_keys") or {} end

--------------------------------------------------------------------------------
-- the runs (cached for the overview of gov_treasury and gov_web)
--------------------------------------------------------------------------------

RUNS = {}                              -- newest first: { period, companies, total, instance }
RUNS_30D = { count = 0, total = 0 }    -- the runs of the last HISTORY_DAYS

local function int(v) return DB.int(v) end

function GOV.refreshRuns()
    if not DB.ready then return end
    DB.query(function(rows)
        if not rows then return end
        local list = {}
        for i, r in ipairs(rows) do
            list[i] = { period = int(r.period_start), companies = int(r.companies), total = int(r.total), instance = tostring(r.instance) }
        end
        RUNS = list
    end, "SELECT period_start, companies, total, instance FROM gov_tax_runs ORDER BY period_start DESC LIMIT 48")
    DB.query(function(rows)
        local r = rows and rows[1]
        if r then RUNS_30D = { count = int(r.n), total = int(r.total) } end
    end, "SELECT COUNT(*) AS n, COALESCE(SUM(total), 0) AS total FROM gov_tax_runs WHERE period_start >= ?", GOV.historySince())
end

--- export: the last `n` (max 48) tax runs, newest first; `since` = only from this time on
function getTaxRuns(n, since)
    n, since = tonumber(n) or 24, tonumber(since) or 0
    local out = {}
    for _, r in ipairs(RUNS) do
        if #out >= n then break end
        if r.period >= since then out[#out + 1] = r end
    end
    return out
end

--------------------------------------------------------------------------------
-- the hourly run
--------------------------------------------------------------------------------

local function hourLabel(periodStart)
    local t1, t2 = getRealTime(periodStart), getRealTime(periodStart + 3600)
    return ("%02d:00-%02d:00"):format(t1.hour, t2.hour)
end

local function runHour(periodStart, done)
    local bank = GOV.bank()
    if not bank or not bank:isBankReady() then return done(false) end
    local keys = bank:getTaxableKeys()
    if #keys == 0 then return done(false) end

    -- claim the hour (the other instance may run it at the same time)
    DB.query(function(res, affected)
        if res == false or tonumber(affected) ~= 1 then return done(false) end
        local marks, args = {}, {}
        for i = 1, #keys do marks[i], args[i] = "?", keys[i] end
        args[#args + 1] = periodStart
        args[#args + 1] = periodStart + 3600
        DB.query(function(rows)
            local rate = getCompanyTaxRate()
            local target = getTaxTarget("company")
            local companies, total = 0, 0
            for _, r in ipairs(rows or {}) do
                local base = DB.int(r.base)
                local tax = math.floor(base * rate)
                if base > 0 and tax > 0 then
                    local ok = bank:transfer(DB.int(r.account_id), target, tax, "tax.company_income",
                        { hour = hourLabel(periodStart), base = base, rate = math.floor(rate * 100 + 0.5) }, "v_gov")
                    if ok then
                        companies, total = companies + 1, total + tax
                        triggerEvent("onGovCompanyTaxed", resourceRoot, tonumber(r.owner_ref), tax, base, periodStart)
                    end
                end
            end
            DB.exec("UPDATE gov_tax_runs SET companies = ?, total = ?, finished_at = ? WHERE period_start = ?",
                companies, total, GOV.now(), periodStart)
            if companies > 0 then
                outputServerLog(("[gov_tax] company tax %s: %d companies, € %d"):format(hourLabel(periodStart), companies, total))
            end
            triggerEvent("onGovTaxRun", resourceRoot, periodStart, companies, total)
            setTimer(GOV.refreshRuns, 2000, 1)
            done(true)
        end, "SELECT l.account_id, a.owner_ref, SUM(l.amount) AS base FROM bank_ledger l "
            .. "JOIN bank_accounts a ON a.id = l.account_id AND a.kind = 'company' AND a.status <> 'closed' "
            .. "WHERE l.tx_key IN (" .. table.concat(marks, ",") .. ") AND l.ts >= ? AND l.ts < ? "
            .. "GROUP BY l.account_id, a.owner_ref", unpack(args))
    end, "INSERT IGNORE INTO gov_tax_runs (period_start, instance) VALUES (?, ?)", periodStart, DB.clip(GOV.instance(), 16))
end

local function lastFullHour()
    local now = GOV.now()
    return math.floor(now / 3600) * 3600 - 3600
end

--- every unclaimed hour of the last GOV.TAX_CATCHUP_HOURS, oldest first
local function catchUp()
    local last = lastFullHour()
    local hours = {}
    for h = GOV.TAX_CATCHUP_HOURS - 1, 0, -1 do hours[#hours + 1] = last - h * 3600 end
    local i = 0
    local function nextHour()
        i = i + 1
        if hours[i] then runHour(hours[i], nextHour) end
    end
    nextHour()
end

local function schedule()
    local now = GOV.now()
    local wait = (math.floor(now / 3600) + 1) * 3600 + GOV.TAX_RUN_DELAY - now
    setTimer(function()
        runHour(lastFullHour(), function() end)
        schedule()
    end, math.max(1000, wait * 1000), 1)
end

-- the runs start once the table, gov_core (settings) and v_bank are ready
local taxesStarted = false
local function startTaxesWhenReady()
    if taxesStarted then return end
    local bank = GOV.bank()
    if DB.ready and GOV.coreReady() and bank and bank:isBankReady() then
        taxesStarted = true
        catchUp()
        schedule()
        return
    end
    setTimer(startTaxesWhenReady, 5000, 1)
end

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start(SCHEMA, function()
        GOV.refreshRuns()
        setTimer(GOV.refreshRuns, GOV.CACHE_MS, 0)
        startTaxesWhenReady()
    end)
end)
