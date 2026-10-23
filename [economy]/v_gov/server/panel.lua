-- v_gov / server/panel.lua
-- /gov and the requests of the panel (client/panel.lua). Every action has a minimum gov role
-- (settings.lua getGovRole); every change goes to gov_log.
--
--   client -> "v_gov:call" (requestId, action, args)
--   server -> "v_gov:reply" (requestId, result | false, errorKey | nil)

addEvent("v_gov:call", true)

local NEED = {
    overview = "viewer", treasuryLedger = "viewer", taxes = "viewer", works = "viewer", fees = "viewer",
    health = "viewer", companies = "viewer", company = "viewer", members = "viewer", log = "viewer",
    findCompanies = "viewer",
    setCompanyTax = "minister", setTaxKey = "minister", deleteTaxKey = "minister", setWork = "minister",
    setFee = "minister", setMember = "minister", treasuryTransfer = "minister",
    setHealth = "official", createCompany = "official", renameCompany = "official", deleteCompany = "official",
    companyMember = "official", companyOverdraft = "minister",
}

local function int(v) return DB.int(v) end

local function clamp(v, r) return math.max(r[1], math.min(r[2], v)) end

--------------------------------------------------------------------------------
-- v_bank requests that answer later (bankCall)
--------------------------------------------------------------------------------

local pending, seq = {}, 0
addEvent("v_gov:remoteResult", false)
addEventHandler("v_gov:remoteResult", resourceRoot, function(id, result)
    local cb = pending[id]
    pending[id] = nil
    if cb then cb(result) end
end)

function GOV.bankCall(action, args, actor, cb)
    local bank = GOV.bank()
    if not bank then return cb({ ok = false, error = "unavailable" }) end
    seq = seq + 1
    local id = seq
    pending[id] = cb
    if not bank:bankCall(id, action, args, actor) then
        pending[id] = nil
        cb({ ok = false, error = "unavailable" })
    end
end

--------------------------------------------------------------------------------
-- data of the pages
--------------------------------------------------------------------------------

local A = {}

local function treasuryId()
    local bank = GOV.bank()
    return bank and bank:getStateAccount("treasury")
end

function A.overview(p, args, reply, actor)
    local bank = GOV.bank()
    local tid = treasuryId()
    if not tid then return reply(false, "v_bank.error.unavailable") end
    local now = GOV.now()
    GOV.bankCall("stats", { id = tid, since = now - 86400 }, actor, function(day)
        GOV.bankCall("stats", { id = tid, since = now - 7 * 86400 }, actor, function(week)
            DB.query(function(rows)
                local runs = {}
                for i, r in ipairs(rows or {}) do
                    runs[i] = { period = int(r.period_start), companies = int(r.companies), total = int(r.total), instance = tostring(r.instance) }
                end
                reply({ treasury = bank:getAccountInfo(tid), day = day.stats or {}, week = week.stats or {}, runs = runs,
                    states = bank:getStateAccounts() })
            end, "SELECT period_start, companies, total, instance FROM gov_tax_runs ORDER BY period_start DESC LIMIT 24")
        end)
    end)
end

function A.treasuryLedger(p, args, reply, actor)
    local id = tonumber(args.id) or treasuryId()
    local bank = GOV.bank()
    local info = bank and bank:getAccountInfo(id)
    if not info or info.kind ~= "state" then return reply(false, "v_bank.error.no_access") end
    GOV.bankCall("ledger", { id = id, before = tonumber(args.before), group = args.group, limit = 40 }, actor, function(r)
        if not r.ok then return reply(false, "v_bank.error." .. tostring(r.error)) end
        reply({ id = id, rows = r.rows, more = r.more })
    end)
end

--- works of work_core + the registered pay parameters + their settings
local function workList()
    local names = {}
    if isResourceRunning("work_core") then
        for id, w in pairs(exports.work_core:getWorks() or {}) do names[id] = tostring(w.name or id) end
    end
    for id in pairs(WAGES) do names[id] = names[id] or id end
    local list = {}
    for id, name in pairs(names) do
        local w = WAGES[id]
        local params = {}
        for _, prm in ipairs(w and w.params or {}) do
            params[#params + 1] = { key = prm.key, label = prm.label, default = prm.default, kind = prm.kind,
                value = getWage(id, prm.key) }
        end
        local rate, key = getIncomeTaxRate(id)
        list[#list + 1] = { id = id, name = name, payer = GOV.payerSpec(id), multiplier = getWorkMultiplier(id),
            taxKey = key, taxRate = rate, params = params }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function payerOptions()
    local out = { { spec = "system", name = "System (money from nothing)" } }
    local bank = GOV.bank()
    for _, s in ipairs(bank and bank:getStateAccounts() or {}) do
        if s.status ~= "closed" then out[#out + 1] = { spec = "state:" .. s.ownerRef, name = s.name } end
    end
    return out
end

--- id -> name of the biz_core companies in `ids` (async)
local function companyNames(ids, cb)
    if #ids == 0 then return cb({}) end
    local marks = {}
    for i = 1, #ids do marks[i] = "?" end
    DB.query(function(rows)
        local names = {}
        for _, r in ipairs(rows or {}) do
            names[tostring(int(r.id))] = { name = tostring(r.name), active = r.status == "active" }
        end
        cb(names)
    end, "SELECT id, name, status FROM biz_companies WHERE id IN (" .. table.concat(marks, ",") .. ")", unpack(ids))
end

function A.works(p, args, reply)
    local list = workList()
    local ids, seen = {}, {}
    for _, w in ipairs(list) do
        local id = tonumber(w.payer:match("^company:(%d+)$"))
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    companyNames(ids, function(names)
        reply({ works = list, payers = payerOptions(), taxKeys = GOV.get("tax.income_keys") or {}, companies = names })
    end)
end

--- the company picker: active biz_core companies by name or id: { q } -> { list = { {id, name}, ... } }
function A.findCompanies(p, args, reply)
    local q = DB.clip(tostring(args.q or ""):gsub("^%s+", ""):gsub("%s+$", ""), 48)
    local like = "%" .. q:gsub("[\\%%_]", "\\%0") .. "%"
    DB.query(function(rows)
        local list = {}
        for i, r in ipairs(rows or {}) do list[i] = { id = int(r.id), name = tostring(r.name) } end
        reply({ list = list })
    end, "SELECT id, name FROM biz_companies WHERE status = 'active' AND (name LIKE ? OR id = ?) ORDER BY name LIMIT 25",
        like, tonumber(q) or 0)
end

function A.taxes(p, args, reply)
    local used = {}
    for _, w in ipairs(workList()) do
        used[w.taxKey] = used[w.taxKey] or {}
        table.insert(used[w.taxKey], w.name)
    end
    DB.query(function(rows)
        local runs = {}
        for i, r in ipairs(rows or {}) do
            runs[i] = { period = int(r.period_start), companies = int(r.companies), total = int(r.total) }
        end
        reply({ company = getCompanyTaxRate(), keys = GOV.get("tax.income_keys") or {}, used = used, runs = runs })
    end, "SELECT period_start, companies, total FROM gov_tax_runs ORDER BY period_start DESC LIMIT 24")
end

local FEES = { "register", "rename", "bay_fine", "airspace.takeoff", "airspace.landing", "airspace.overflight" }

function A.fees(p, args, reply)
    local list = {}
    for i, k in ipairs(FEES) do list[i] = { key = k, value = getFee(k), default = GOV_DEFAULTS["fee." .. k] } end
    reply({ fees = list })
end

function A.health(p, args, reply)
    reply({ enabled = GOV.get("health.enabled") ~= false, hpPrice = tonumber(GOV.get("health.hp_price")) or 0,
        injuries = GOV.get("health.injuries") or {} })
end

function A.companies(p, args, reply)
    local bank = GOV.bank()
    if not bank then return reply(false, "v_bank.error.unavailable") end
    local payers = {}
    for _, w in ipairs(workList()) do
        if w.payer:match("^state:") then
            local code = w.payer:sub(7)
            payers[code] = payers[code] or {}
            table.insert(payers[code], w.name)
        end
    end
    reply({ list = bank:getStateAccounts(), payers = payers })
end

function A.company(p, args, reply, actor)
    GOV.bankCall("account", { id = tonumber(args.id) }, actor, function(r)
        if not r.ok then return reply(false, "v_bank.error." .. tostring(r.error)) end
        reply({ account = r.account })
    end)
end

function A.members(p, args, reply)
    local list = {}
    for name, role in pairs(MEMBERS) do list[#list + 1] = { account = name, role = role } end
    table.sort(list, function(a, b) return a.account < b.account end)
    reply({ list = list, adminLevel = GOV.ADMIN_LEVEL })
end

function A.log(p, args, reply)
    DB.query(function(rows)
        local list = {}
        for i, r in ipairs(rows or {}) do
            list[i] = { ts = int(r.ts), actor = tostring(r.actor), action = tostring(r.action), detail = tostring(r.detail) }
        end
        reply({ list = list })
    end, "SELECT ts, actor, action, detail FROM gov_log ORDER BY id DESC LIMIT 100")
end

--------------------------------------------------------------------------------
-- changes
--------------------------------------------------------------------------------

function A.setCompanyTax(p, args, reply, actor)
    local v = tonumber(args.value)
    if not v then return reply(false, "v_gov.err.bad_number") end
    GOV.set("tax.company", clamp(v / 100, GOV_RANGE.tax), actor)
    reply(true)
end

--- add / change an income tax rate key: { key, value (%) }
function A.setTaxKey(p, args, reply, actor)
    local key = tostring(args.key or ""):lower()
    local v = tonumber(args.value)
    if not key:match("^[a-z0-9_]+$") or #key > 24 then return reply(false, "v_gov.err.bad_key") end
    if not v then return reply(false, "v_gov.err.bad_number") end
    local keys = GOV.get("tax.income_keys") or {}
    keys[key] = clamp(v / 100, GOV_RANGE.tax)
    GOV.set("tax.income_keys", keys, actor)
    reply(true)
end

function A.deleteTaxKey(p, args, reply, actor)
    local key = tostring(args.key or "")
    if key == "standard" then return reply(false, "v_gov.err.key_protected") end
    for _, w in ipairs(workList()) do
        if w.taxKey == key then return reply(false, "v_gov.err.key_in_use") end
    end
    local keys = GOV.get("tax.income_keys") or {}
    keys[key] = nil
    GOV.set("tax.income_keys", keys, actor)
    reply(true)
end

--- { work, field = payer | multiplier | taxKey | param, key, value } (value nil = default)
function A.setWork(p, args, reply, actor)
    local workId = tostring(args.work or "")
    if not workId:match("^[%w_]+$") then return reply(false, "v_gov.err.bad_work") end
    local field = args.field
    if field == "payer" then
        local spec = tostring(args.value or "system")
        if spec == "system" or spec:match("^state:[a-z0-9_]+$") then
            GOV.set("work." .. workId .. ".payer", spec, actor)
            return reply(true)
        end
        -- a private company (the picker sends its id)
        local id = tonumber(spec:match("^company:(%d+)$"))
        if not id then return reply(false, "v_gov.err.bad_payer") end
        DB.query(function(rows)
            local r = rows and rows[1]
            if not r then return reply(false, "v_gov.err.no_company") end
            GOV.set("work." .. workId .. ".payer", "company:" .. int(r.id), actor)
            reply(true)
        end, "SELECT id FROM biz_companies WHERE id = ? AND status = 'active' LIMIT 1", id)
        return
    elseif field == "multiplier" then
        local v = tonumber(args.value)
        if args.value ~= nil and not v then return reply(false, "v_gov.err.bad_number") end
        GOV.set("work." .. workId .. ".multiplier", v and clamp(v, GOV_RANGE.multiplier) or nil, actor)
    elseif field == "taxKey" then
        local keys = GOV.get("tax.income_keys") or {}
        if args.value ~= nil and keys[args.value] == nil then return reply(false, "v_gov.err.bad_key") end
        GOV.set("work." .. workId .. ".taxKey", args.value, actor)
    elseif field == "param" then
        local w = WAGES[workId]
        local prm = w and w.byKey[tostring(args.key)]
        if not prm then return reply(false, "v_gov.err.bad_param") end
        local v = tonumber(args.value)
        if args.value ~= nil then
            if not v then return reply(false, "v_gov.err.bad_number") end
            local limit = math.max(math.abs(prm.default) * GOV_RANGE.wageFactor, 1000000)
            if math.abs(v) > limit then return reply(false, "v_gov.err.out_of_range") end
        end
        GOV.set("work." .. workId .. ".p." .. prm.key, v, actor)
    else
        return reply(false, "v_gov.err.bad_field")
    end
    reply(true)
end

function A.setFee(p, args, reply, actor)
    local key = tostring(args.key or "")
    local known = false
    for _, k in ipairs(FEES) do if k == key then known = true end end
    if not known then return reply(false, "v_gov.err.bad_key") end
    local v = tonumber(args.value)
    if args.value ~= nil and not v then return reply(false, "v_gov.err.bad_number") end
    GOV.set("fee." .. key, v and math.floor(clamp(v, GOV_RANGE.fee)) or nil, actor)
    reply(true)
end

--- { field = enabled | hp_price | injury | remove_injury, type, severity, value }
function A.setHealth(p, args, reply, actor)
    if args.field == "enabled" then
        GOV.set("health.enabled", args.value == true, actor)
    elseif args.field == "hp_price" then
        local v = tonumber(args.value)
        if not v then return reply(false, "v_gov.err.bad_number") end
        GOV.set("health.hp_price", math.floor(clamp(v, GOV_RANGE.hpPrice)), actor)
    elseif args.field == "injury" then
        local t, sev, v = tostring(args.type or ""), tonumber(args.severity), tonumber(args.value)
        if not t:match("^[a-z_]+$") then return reply(false, "v_gov.err.bad_key") end
        if not v or not sev or sev < 1 or sev > 3 then return reply(false, "v_gov.err.bad_number") end
        local list = GOV.get("health.injuries") or {}
        local prices = list[t] or { 0, 0, 0 }
        prices[math.floor(sev)] = math.floor(clamp(v, GOV_RANGE.injuryPrice))
        list[t] = prices
        GOV.set("health.injuries", list, actor)
    elseif args.field == "remove_injury" then
        local t = tostring(args.type or "")
        if t == "default" then return reply(false, "v_gov.err.key_protected") end
        local list = GOV.get("health.injuries") or {}
        list[t] = nil
        GOV.set("health.injuries", list, actor)
    else
        return reply(false, "v_gov.err.bad_field")
    end
    reply(true)
end

function A.setMember(p, args, reply, actor)
    local role = args.role
    if role == "none" or role == "" then role = nil end
    if not GOV.setMember(args.account, role, actor) then return reply(false, "v_gov.err.bad_member") end
    reply(true)
end

--- money between the treasury and a state company: { id, amount, dir = "to" | "from", note }
function A.treasuryTransfer(p, args, reply, actor)
    local bank = GOV.bank()
    local tid, cid = treasuryId(), tonumber(args.id)
    local amount = math.floor(tonumber(args.amount) or 0)
    if not bank or not tid or not cid then return reply(false, "v_bank.error.unavailable") end
    if amount <= 0 then return reply(false, "v_bank.error.bad_amount") end
    local from, to = tid, cid
    if args.dir == "from" then from, to = cid, tid end
    local ok, err = bank:transfer(from, to, amount, "gov.transfer", { note = tostring(args.note or "") }, actor)
    if not ok then return reply(false, "v_bank.error." .. tostring(err)) end
    GOV.log(actor, "treasury.transfer", { company = cid, amount = amount, dir = args.dir or "to" })
    reply(true)
end

function A.createCompany(p, args, reply, actor)
    GOV.bankCall("createState", { code = args.code, name = args.name, allowNegative = args.allowNegative == true }, actor, function(r)
        if not r.ok then return reply(false, "v_gov.err." .. tostring(r.error)) end
        GOV.log(actor, "company.create", { code = args.code, name = args.name })
        reply(true)
    end)
end

function A.renameCompany(p, args, reply, actor)
    local bank = GOV.bank()
    local info = bank and bank:getAccountInfo(tonumber(args.id))
    local name = tostring(args.name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if not info or info.kind ~= "state" then return reply(false, "v_gov.err.bad_company") end
    if name == "" or #name > 64 then return reply(false, "v_gov.err.bad_name") end
    bank:renameAccount(info.id, name)
    GOV.log(actor, "company.rename", { code = info.ownerRef, name = name })
    reply(true)
end

--- closes a state company; { id, move = true } first moves its balance to the treasury
function A.deleteCompany(p, args, reply, actor)
    local bank = GOV.bank()
    local info = bank and bank:getAccountInfo(tonumber(args.id))
    if not info or info.kind ~= "state" then return reply(false, "v_gov.err.bad_company") end
    if info.ownerRef == "treasury" then return reply(false, "v_gov.err.key_protected") end
    for _, w in ipairs(workList()) do
        if w.payer == "state:" .. info.ownerRef then return reply(false, "v_gov.err.company_pays_work") end
    end
    if info.balance ~= 0 then
        if not args.move then return reply(false, "v_gov.err.company_not_empty") end
        local tid = treasuryId()
        local from, to, amount = info.id, tid, info.balance
        if amount < 0 then from, to, amount = tid, info.id, -amount end
        local ok, err = bank:transfer(from, to, amount, "gov.transfer", { note = "Company closed" }, actor)
        if not ok then return reply(false, "v_bank.error." .. tostring(err)) end
    end
    local ok, err = bank:closeAccount(info.id)
    if not ok then return reply(false, "v_gov.err." .. tostring(err)) end
    GOV.log(actor, "company.delete", { code = info.ownerRef })
    reply(true)
end

function A.companyMember(p, args, reply, actor)
    local bank = GOV.bank()
    local info = bank and bank:getAccountInfo(tonumber(args.id))
    if not info or info.kind ~= "state" then return reply(false, "v_gov.err.bad_company") end
    local role = args.role
    if role == "none" then role = nil end
    if not bank:setAccess(info.id, tostring(args.account or ""), role, actor) then return reply(false, "v_gov.err.bad_member") end
    GOV.log(actor, "company.member", { code = info.ownerRef, account = args.account, role = role or "none" })
    reply(true)
end

function A.companyOverdraft(p, args, reply, actor)
    local bank = GOV.bank()
    local info = bank and bank:getAccountInfo(tonumber(args.id))
    if not info or info.kind ~= "state" then return reply(false, "v_gov.err.bad_company") end
    bank:setAllowNegative(info.id, args.allow == true)
    GOV.log(actor, "company.overdraft", { code = info.ownerRef, allow = args.allow == true })
    reply(true)
end

--------------------------------------------------------------------------------
-- plumbing
--------------------------------------------------------------------------------

addEventHandler("v_gov:call", resourceRoot, function(requestId, action, args)
    local player = client
    if not isElement(player) then return end
    local function reply(result, err)
        if isElement(player) then triggerClientEvent(player, "v_gov:reply", resourceRoot, requestId, result, err) end
    end
    local fn, need = A[tostring(action)], NEED[tostring(action)]
    if not fn or not need then return reply(false, "v_gov.err.unknown") end
    if not GOV.ready then return reply(false, "v_bank.error.unavailable") end
    if not GOV.can(player, need) then return reply(false, "v_gov.err.no_right") end
    local ok, err = pcall(fn, player, type(args) == "table" and args or {}, reply, GOV.accountOf(player) or "?")
    if not ok then
        outputDebugString("[v_gov] " .. tostring(action) .. ": " .. tostring(err), 1)
        reply(false, "v_gov.err.unknown")
    end
end)

addCommandHandler("gov", function(player)
    local role = getGovRole(player)
    if not role then
        triggerClientEvent(player, "v_gov:denied", resourceRoot)
        return
    end
    triggerClientEvent(player, "v_gov:open", resourceRoot, role)
end)
