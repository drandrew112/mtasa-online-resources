-- v_gov / server/tax.lua
-- Hourly company income tax (DESIGN.md 4). Every full hour (+GOV.TAX_RUN_DELAY s) the hour that
-- just ended is taxed: per company account the sum of its taxable ledger rows (legal income, net)
-- in that hour; a positive base pays floor(base * rate) to the treasury (tax.company_income, may
-- push the company below 0). Only one instance runs an hour: it claims the hour in gov_tax_runs.

addEvent("onGovTaxRun", false)        -- (periodStart, companies, total), source = resourceRoot
addEvent("onGovCompanyTaxed", false)  -- (companyId, tax, base, periodStart), source = resourceRoot

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
            local companies, total = 0, 0
            for _, r in ipairs(rows or {}) do
                local base = DB.int(r.base)
                local tax = math.floor(base * rate)
                if base > 0 and tax > 0 then
                    local ok = bank:transfer(DB.int(r.account_id), nil, tax, "tax.company_income",
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
                outputServerLog(("[v_gov] company tax %s: %d companies, € %d"):format(hourLabel(periodStart), companies, total))
            end
            triggerEvent("onGovTaxRun", resourceRoot, periodStart, companies, total)
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

function startTaxes()
    catchUp()
    schedule()
end
