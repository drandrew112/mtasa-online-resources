-- gov_treasury / server/panel.lua
-- The Overview, Treasury, Transfers and Budget pages of /gov and the registration with gov_core.

local A = GOV.A

local function int(v) return DB.int(v) end

--- the last tax runs of gov_tax (empty while it does not run)
local function taxRuns(n, since)
    if not isResourceRunning("gov_tax") then return {} end
    local ok, runs = pcall(function() return exports.gov_tax:getTaxRuns(n, since) end)
    return ok and type(runs) == "table" and runs or {}
end

function A.overview(p, args, reply, actor)
    local bank = GOV.bank()
    local tid = GOV.treasuryId()
    if not tid then return reply(false, "v_bank.error.unavailable") end
    local now = GOV.now()
    GOV.bankCall("stats", { id = tid, since = now - 86400 }, actor, function(day)
        GOV.bankCall("stats", { id = tid, since = now - 7 * 86400 }, actor, function(week)
            reply({ treasury = bank:getAccountInfo(tid), day = day.stats or {}, week = week.stats or {}, runs = taxRuns(24),
                states = GOV.stateAccounts() })
        end)
    end)
end

--- the statement of the treasury or a state company: only the last GOV.HISTORY_DAYS days
function A.treasuryLedger(p, args, reply, actor)
    local id = tonumber(args.id) or GOV.treasuryId()
    if not id or not GOV.isStateAccount(id) then return reply(false, "v_bank.error.no_access") end
    GOV.bankCall("ledger", { id = id, before = tonumber(args.before), group = args.group, limit = 40,
        since = GOV.historySince() }, actor, function(r)
        if not r.ok then return reply(false, "v_bank.error." .. tostring(r.error)) end
        reply({ id = id, rows = r.rows, more = r.more, ledgerRows = true })
    end)
end

--- income / expense of the treasury and every state company in the last HISTORY_DAYS days
function A.budget(p, args, reply)
    GOV.budget(function(b)
        local rows = {}
        local function add(name, code, accountId, balance)
            local a = b.accounts[accountId] or { inSum = 0, outSum = 0, groups = {} }
            local groups = {}
            for g, x in pairs(a.groups) do groups[#groups + 1] = { group = g, inSum = x.inSum, outSum = x.outSum } end
            table.sort(groups, function(x, y) return x.group < y.group end)
            rows[#rows + 1] = { name = name, code = code, balance = balance, inSum = a.inSum, outSum = a.outSum, groups = groups }
        end
        local bank = GOV.bank()
        local t = b.treasury and bank and bank:getAccountInfo(b.treasury)
        if t then add(t.name, "treasury", t.id, t.balance) end
        for _, c in ipairs(GOV.companyList()) do add(c.name, c.code, c.accountId, c.balance) end
        reply({ days = GOV.HISTORY_DAYS, rows = rows, daily = b.daily })
    end)
end

--- money between the treasury and a state company: { id (bank account), amount, dir = "to" | "from", note }
function A.treasuryTransfer(p, args, reply, actor)
    local bank = GOV.bank()
    local tid, cid = GOV.treasuryId(), tonumber(args.id)
    local amount = math.floor(tonumber(args.amount) or 0)
    if not bank or not tid or not cid then return reply(false, "v_bank.error.unavailable") end
    if cid == tid or not GOV.isStateAccount(cid) then return reply(false, "bad_company") end
    if amount <= 0 then return reply(false, "v_bank.error.bad_amount") end
    local from, to = tid, cid
    if args.dir == "from" then from, to = cid, tid end
    local ok, err = bank:transfer(from, to, amount, "gov.transfer", { note = tostring(args.note or "") }, actor)
    if not ok then return reply(false, "v_bank.error." .. tostring(err)) end
    -- the same log row as a state transfer of the Transfers page
    local fromInfo, toInfo = GOV.isStateAccount(from), GOV.isStateAccount(to)
    GOV.log(actor, "transfer.state", { from = fromInfo and fromInfo.name or from, to = toInfo and toInfo.name or to,
        amount = amount, note = DB.clip(tostring(args.note or ""), 48) })
    reply(true)
end

--------------------------------------------------------------------------------
-- Transfers page: state <-> state, state -> private company, collection from a private company
--------------------------------------------------------------------------------

--- the transfer rows of gov_core's change log (last HISTORY_DAYS) + the standing orders
function A.transfers(p, args, reply)
    DB.query(function(rows)
        local list = {}
        for i, r in ipairs(rows or {}) do
            list[i] = { ts = int(r.ts), actor = tostring(r.actor), action = tostring(r.action), detail = fromJSON(tostring(r.detail)) or {} }
        end
        GOV.standingList(function(orders)
            reply({ states = GOV.stateAccounts(), list = list, orders = orders })
        end)
    end, "SELECT ts, actor, action, detail FROM gov_log WHERE action LIKE 'transfer.%' AND ts >= ? ORDER BY id DESC LIMIT 50",
        GOV.historySince())
end

local function stateOf(id)
    local a = GOV.isStateAccount(tonumber(id))
    return a and a.status ~= "closed" and a or nil
end

--- { kind = state | pay | collect, from, to, amount, note }
---   state:   from / to = state bank account ids (treasury or state company)
---   pay:     from = state account id, to = biz_core company id (gov.company_payment, needs the money)
---   collect: from = biz_core company id, to = state account id (gov.collection, forced: may go into debt)
function A.moneyTransfer(p, args, reply, actor)
    local bank = GOV.bank()
    if not bank then return reply(false, "v_bank.error.unavailable") end
    local amount = math.floor(tonumber(args.amount) or 0)
    if amount <= 0 then return reply(false, "v_bank.error.bad_amount") end
    local note = DB.clip(tostring(args.note or ""), 48)
    local kind = args.kind
    local function book(fromId, toId, key, detail)
        local ok, err = bank:transfer(fromId, toId, amount, key, { note = note }, actor)
        if not ok then return reply(false, "v_bank.error." .. tostring(err)) end
        detail.amount, detail.note = amount, note
        GOV.log(actor, "transfer." .. kind, detail)
        reply(true)
    end
    if kind == "state" then
        local from, to = stateOf(args.from), stateOf(args.to)
        if not from or not to then return reply(false, "bad_company") end
        if from.id == to.id then return reply(false, "v_bank.error.same_account") end
        return book(from.id, to.id, "gov.transfer", { from = from.name, to = to.name })
    end
    if kind ~= "pay" and kind ~= "collect" then return reply(false, "bad_field") end
    local state = stateOf(kind == "pay" and args.from or args.to)
    if not state then return reply(false, "bad_company") end
    local cid = tonumber(kind == "pay" and args.to or args.from)
    if not cid then return reply(false, "no_company") end
    DB.query(function(rows)
        local r = rows and rows[1]
        if not r then return reply(false, "no_company") end
        local accId = bank:getCompanyAccount(int(r.id))
        if not accId then return reply(false, "no_company") end
        local name = tostring(r.name) .. " #" .. int(r.id)
        if kind == "pay" then
            book(state.id, accId, "gov.company_payment", { from = state.name, to = name })
        else
            book(accId, state.id, "gov.collection", { from = name, to = state.name })
        end
    end, "SELECT id, name FROM biz_companies WHERE id = ? AND status = 'active' LIMIT 1", cid)
end

--- standing order (recurring transfer): { kind = state | pay | collect, from, to, amount, interval (s), note }
--- ids as in moneyTransfer (state side = state bank account id, private side = biz_core company id)
--- with args.id an existing order is edited instead (updateStanding)
local function saveStanding(args, reply, actor)
    local kind = args.kind
    local function done(ok, err) if not ok then return reply(false, err) end reply(true) end
    local d = { kind = kind, amount = args.amount, interval = args.interval, note = DB.clip(tostring(args.note or ""), 48) }
    local function save()
        if args.id then return GOV.standingUpdate(args.id, d, actor, done) end
        GOV.standingCreate(d, actor, done)
    end
    if kind == "state" then
        local from, to = stateOf(args.from), stateOf(args.to)
        if not from or not to then return reply(false, "bad_company") end
        if from.id == to.id then return reply(false, "v_bank.error.same_account") end
        d.from, d.to, d.fromName, d.toName = from.id, to.id, from.name, to.name
        return save()
    end
    if kind ~= "pay" and kind ~= "collect" then return reply(false, "bad_field") end
    local state = stateOf(kind == "pay" and args.from or args.to)
    if not state then return reply(false, "bad_company") end
    local cid = tonumber(kind == "pay" and args.to or args.from)
    if not cid then return reply(false, "no_company") end
    DB.query(function(rows)
        local r = rows and rows[1]
        if not r then return reply(false, "no_company") end
        local name = tostring(r.name) .. " #" .. int(r.id)
        if kind == "pay" then
            d.from, d.to, d.fromName, d.toName = state.id, int(r.id), state.name, name
        else
            d.from, d.to, d.fromName, d.toName = int(r.id), state.id, name, state.name
        end
        save()
    end, "SELECT id, name FROM biz_companies WHERE id = ? AND status = 'active' LIMIT 1", cid)
end

function A.createStanding(p, args, reply, actor)
    args.id = nil
    saveStanding(args, reply, actor)
end

function A.updateStanding(p, args, reply, actor)
    if not tonumber(args.id) then return reply(false, "bad_field") end
    saveStanding(args, reply, actor)
end

function A.toggleStanding(p, args, reply, actor)
    GOV.standingSetEnabled(args.id, args.enabled == true, actor, function(ok, err) reply(ok or false, err) end)
end

function A.deleteStanding(p, args, reply, actor)
    GOV.standingDelete(args.id, actor, function(ok, err) reply(ok or false, err) end)
end

GOV.module({
    actions = {
        overview = "viewer", treasuryLedger = "viewer", budget = "viewer", transfers = "viewer",
        treasuryTransfer = "minister", moneyTransfer = "minister",
        createStanding = "minister", updateStanding = "minister", toggleStanding = "minister", deleteStanding = "minister",
    },
    pages = {
        { id = "overview",  category = "top",     order = 10, script = "web/js/pages.js" },
        { id = "treasury",  category = "economy", order = 10, script = "web/js/pages.js" },
        { id = "transfers", category = "economy", order = 20, script = "web/js/pages.js" },
        { id = "budget",    category = "economy", order = 30, script = "web/js/pages.js" },
    },
})
