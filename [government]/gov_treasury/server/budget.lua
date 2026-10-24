-- gov_treasury / server/budget.lua
-- The budget of the state: income / expense of the treasury and every state company by ledger
-- group over the last GOV.HISTORY_DAYS days (read straight from v_bank's bank_ledger), and the
-- money part of the gov_web snapshot (getPublicFinance, rebuilt every GOV.PUBLIC_REFRESH_MS).
-- Nothing older than HISTORY_DAYS is ever returned.

local function int(v) return DB.int(v) end

local function group(key) return tostring(key):match("^([%w_]+)%.") or "other" end

--- cb({ accounts = { [accountId] = { inSum, outSum, groups = { [group] = {inSum, outSum} } } },
---      daily = { {day, inSum, outSum}, ... } (treasury), treasury = id })
function GOV.budget(cb)
    local tid = GOV.treasuryId()
    local ids = { tid }
    for _, c in ipairs(GOV.companyList()) do if c.accountId then ids[#ids + 1] = c.accountId end end
    if #ids == 0 then return cb({ accounts = {}, daily = {} }) end
    local since = GOV.historySince()
    local marks, args = {}, {}
    for i = 1, #ids do marks[i], args[i] = "?", ids[i] end
    args[#args + 1] = since
    DB.query(function(rows)
        local acc = {}
        for _, id in ipairs(ids) do acc[id] = { inSum = 0, outSum = 0, groups = {} } end
        for _, r in ipairs(rows or {}) do
            local a = acc[int(r.account_id)]
            if a then
                local g = group(r.tx_key)
                a.groups[g] = a.groups[g] or { inSum = 0, outSum = 0 }
                a.groups[g].inSum = a.groups[g].inSum + int(r.in_sum)
                a.groups[g].outSum = a.groups[g].outSum + int(r.out_sum)
                a.inSum = a.inSum + int(r.in_sum)
                a.outSum = a.outSum + int(r.out_sum)
            end
        end
        if not tid then return cb({ accounts = acc, daily = {} }) end
        DB.query(function(drows)
            local daily = {}
            for i, r in ipairs(drows or {}) do
                daily[i] = { day = int(r.d) * 86400, inSum = int(r.in_sum), outSum = int(r.out_sum) }
            end
            cb({ accounts = acc, daily = daily, treasury = tid })
        end, "SELECT FLOOR(ts / 86400) AS d, SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS in_sum, "
            .. "SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS out_sum FROM bank_ledger "
            .. "WHERE account_id = ? AND ts >= ? GROUP BY d ORDER BY d", tid, since)
    end, "SELECT account_id, tx_key, SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS in_sum, "
        .. "SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS out_sum FROM bank_ledger "
        .. "WHERE account_id IN (" .. table.concat(marks, ",") .. ") AND ts >= ? GROUP BY account_id, tx_key",
        unpack(args))
end

--------------------------------------------------------------------------------
-- public part of gov_web
--------------------------------------------------------------------------------

local PUBLIC = false

local function groupList(groups)
    local out = {}
    for g, s in pairs(groups or {}) do out[#out + 1] = { group = g, inSum = s.inSum, outSum = s.outSum } end
    table.sort(out, function(a, b) return a.group < b.group end)
    return out
end

local function rebuild()
    if not GOV.coreReady() then return end
    local bank = GOV.bank()
    if not bank then return end
    GOV.budget(function(b)
        local tid = b.treasury
        local tinfo = tid and bank:getAccountInfo(tid)
        local t = tid and b.accounts[tid] or { inSum = 0, outSum = 0, groups = {} }
        local companies = {}
        for _, c in ipairs(GOV.companyList()) do
            local a = c.accountId and b.accounts[c.accountId] or { inSum = 0, outSum = 0, groups = {} }
            companies[#companies + 1] = { code = c.code, name = c.name, description = c.description, balance = c.balance,
                inSum = a.inSum, outSum = a.outSum, groups = groupList(a.groups), works = {} }
        end
        PUBLIC = {
            updated = GOV.now(), days = GOV.HISTORY_DAYS,
            treasury = { name = tinfo and tinfo.name or "State Treasury", balance = tinfo and tinfo.balance or 0,
                inSum = t.inSum, outSum = t.outSum, groups = groupList(t.groups) },
            daily = b.daily, companies = companies,
        }
    end)
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(rebuild, 5000, 1)
    setTimer(rebuild, GOV.PUBLIC_REFRESH_MS, 0)
end)

--- gov_web: { updated, days, treasury, daily, companies } (at most HISTORY_DAYS of money data, no
--- account names), or false until the first build
function getPublicFinance()
    return PUBLIC
end
