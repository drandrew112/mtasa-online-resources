-- gov_treasury / server/plan.lua
-- The Budget plan page: a 24-hour plan for every day of the week (the next 7 days, shown
-- Monday..Sunday), for the whole state and separately for the State Treasury and every state
-- company. Rows:
--   * plan items (setting "plan.items", minister): { id, account = state code, name,
--     kind = income | expense, amounts = { Mon .. Sun }, note } - whatever is expected per day
--     (an item without account belongs to the treasury)
--   * railway running costs: gov_transport getRailDayCosts (the rw_timetable timetable of that
--     day × the pt.rail cost settings) - an expense of the paying state account, an income of the
--     receiving one
--   * salaries of the state positions (gov_perms getSalaryPlan): an expense of the treasury,
--     salary x the official's expected online hours per day (last 7 days, else the plan default)
--   * standing orders: every order with the amount that falls on each day; state <-> state is an
--     expense of the sender and an income of the receiver (the whole-state plan shows it apart,
--     not counted: the money stays inside the state)

local A = GOV.A

local function int(v) return DB.int(v) end

GOV_PLAN = {
    MAX_ITEMS = 60,
    MAX_AMOUNT = 1000000000,
}

local function dayStart(ts)
    local t = getRealTime(ts)
    return ts - (t.hour * 3600 + t.minute * 60 + t.second)
end

--- Monday = 1 .. Sunday = 7
local function weekdayOf(ts) return (getRealTime(ts).weekday + 6) % 7 + 1 end

local function items()
    local v = GOV.get("plan.items")
    local out = {}
    for _, it in ipairs(type(v) == "table" and v or {}) do
        if type(it) == "table" and tonumber(it.id) then out[#out + 1] = it end
    end
    return out
end

--- how many times a standing order books in [t0, t1)
local function runsIn(o, t0, t1)
    if not o.enabled or o.interval <= 0 or o.nextRun >= t1 then return 0 end
    local first = o.nextRun
    if first < t0 then first = first + math.ceil((t0 - first) / o.interval) * o.interval end
    if first >= t1 then return 0 end
    return math.floor((t1 - 1 - first) / o.interval) + 1
end

--- the salaries of a day: { total, groups = { [position name] = amount } } | false (gov_perms off)
local function salaries(plan, dayTs)
    if not plan then return false end
    local out = { total = 0, groups = {} }
    for _, r in ipairs(plan.rows or {}) do
        if r.expiresAt == 0 or r.expiresAt > dayTs then
            local amount = math.floor(r.salary * r.hours + 0.5)
            out.groups[r.name] = (out.groups[r.name] or 0) + amount
            out.total = out.total + amount
        end
    end
    return out
end

local function salaryPlan()
    if not isResourceRunning("gov_perms") then return false end
    local ok, r = pcall(function() return exports.gov_perms:getSalaryPlan() end)
    return ok and type(r) == "table" and r or false
end

local function railCosts(ts)
    if not isResourceRunning("gov_transport") then return false end
    local ok, r = pcall(function() return exports.gov_transport:getRailDayCosts(ts) end)
    return ok and type(r) == "table" and r or false
end

--- the plans: the treasury + every state company: { code, name }
local function planAccounts()
    local bank = GOV.bank()
    local tid = GOV.treasuryId()
    local t = bank and tid and bank:getAccountInfo(tid)
    local out = { { code = "treasury", name = t and t.name or "State Treasury", accountId = tid } }
    for _, c in ipairs(GOV.companyList()) do out[#out + 1] = { code = c.code, name = c.name, accountId = c.accountId } end
    return out
end

--- the next 7 days (today first): { ts, weekday, date, rail, orders = { [order id] = amount } },
--- the plan accounts, the plan items, the enabled standing orders (fromCode / toCode = the state
--- side), payer names
function A.budgetPlan(p, args, reply)
    GOV.standingList(function(orders)
        local accounts = planAccounts()
        local codeOf = {}
        for _, a in ipairs(accounts) do if a.accountId then codeOf[a.accountId] = a.code end end
        local list = {}
        for _, o in ipairs(orders or {}) do
            if o.enabled then
                list[#list + 1] = { id = o.id, kind = o.kind, amount = o.amount, interval = o.interval,
                    fromName = o.fromName, toName = o.toName, note = o.note,
                    fromCode = o.kind ~= "collect" and codeOf[o.from] or false,
                    toCode = o.kind ~= "pay" and codeOf[o.to] or false }
            end
        end
        local days, ids = {}, {}
        local ds = dayStart(GOV.now())
        local sPlan = salaryPlan()
        for k = 1, 7 do
            local t = getRealTime(ds)
            local d = { ts = ds, weekday = weekdayOf(ds),
                date = ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday),
                rail = railCosts(ds + 12 * 3600), salary = salaries(sPlan, ds), orders = {} }
            local nextDs = dayStart(ds + 86400 + 7200)
            for _, o in ipairs(orders or {}) do
                local n = runsIn(o, ds, nextDs)
                if n > 0 then d.orders[tostring(o.id)] = n * o.amount end
            end
            days[k] = d
            ds = nextDs
        end
        local rail = days[1].rail
        for _, spec in ipairs(rail and { rail.payer, rail.receiver } or {}) do
            local id = tonumber(tostring(spec):match("^company:(%d+)$"))
            if id then ids[#ids + 1] = id end
        end
        for _, a in ipairs(accounts) do a.accountId = nil end
        GOV.companyNames(ids, function(names)
            reply({ days = days, accounts = accounts, items = items(), orders = list, payers = GOV.payerOptions(), companies = names })
        end)
    end)
end

--- { id?, account = state code, name, kind = income | expense, amounts = { Mon .. Sun }, note }
function A.savePlanItem(p, args, reply, actor)
    local account = tostring(args.account or "treasury")
    if account ~= "treasury" and not GOV.companyByCode(account) then return reply(false, "bad_company") end
    local name = DB.clip(tostring(args.name or ""):gsub("^%s+", ""):gsub("%s+$", ""), 48)
    if name == "" then return reply(false, "bad_name") end
    local kind = args.kind == "income" and "income" or (args.kind == "expense" and "expense" or nil)
    if not kind then return reply(false, "bad_plan_kind") end
    local amounts = {}
    local src = type(args.amounts) == "table" and args.amounts or {}
    for k = 1, 7 do
        local v = tonumber(src[k] or 0)
        if not v or v < 0 or v > GOV_PLAN.MAX_AMOUNT then return reply(false, "bad_number") end
        amounts[k] = math.floor(v)
    end
    local list = items()
    local id = tonumber(args.id)
    local item = { id = id, account = account, name = name, kind = kind, amounts = amounts, note = DB.clip(tostring(args.note or ""), 64) }
    if id then
        local found = false
        for i, it in ipairs(list) do
            if tonumber(it.id) == id then list[i] = item; found = true end
        end
        if not found then return reply(false, "bad_plan_item") end
    else
        if #list >= GOV_PLAN.MAX_ITEMS then return reply(false, "plan_full") end
        local maxId = 0
        for _, it in ipairs(list) do maxId = math.max(maxId, int(it.id)) end
        item.id = maxId + 1
        list[#list + 1] = item
    end
    GOV.set("plan.items", list, actor)
    GOV.log(actor, id and "plan.update" or "plan.create", { id = item.id, account = account, name = name, kind = kind })
    reply(true)
end

function A.deletePlanItem(p, args, reply, actor)
    local id = tonumber(args.id)
    local list, out, name = items(), {}, nil
    for _, it in ipairs(list) do
        if tonumber(it.id) == id then name = it.name else out[#out + 1] = it end
    end
    if not name then return reply(false, "bad_plan_item") end
    GOV.set("plan.items", #out > 0 and out or nil, actor)
    GOV.log(actor, "plan.delete", { id = id, name = name })
    reply(true)
end
