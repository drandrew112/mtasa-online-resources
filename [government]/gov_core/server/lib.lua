-- gov_core / server/lib.lua
-- The helper lib of every gov_* resource. A module imports it as the first thing after v_locals:
--   loadstring(exports.gov_core:importLib())()
-- It gives the module DB helpers, the gov_core settings / log / state company wrappers, the
-- payer / receiver / target spec helpers, v_bank's answer-later calls (bankCall) and the panel
-- plumbing (GOV.module + GOV.A action handlers). gov_core runs the same source and then replaces
-- the wrappers with its local implementations.

local LIB = [==[
GOV = GOV or {}
GOV.RES = getResourceName(getThisResource())
GOV.HISTORY_DAYS = 30     -- financial rows / sums are shown at most this far back (/gov + gov_web)
GOV.ROLES = { viewer = 1, official = 2, minister = 3 }
GOV.A = GOV.A or {}       -- panel actions of this resource: [name] = function(player, args, reply, actor)

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

-- gov_core's events (source = gov_core resourceRoot; listen on root); added here too so the
-- handlers of a module can be attached whether or not gov_core runs
addEvent("onGovSettingChanged", false)   -- (key, value)
addEvent("onGovSettingsSynced", false)   -- after every re-read of gov_core

function isResourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running" or false
end

--------------------------------------------------------------------------------
-- DB
--------------------------------------------------------------------------------

DB = DB or { ready = false }

--- runs the CREATE TABLE statements in order, then DB.ready = true and cb()
function DB.start(schema, cb)
    local function run(i)
        if i > #schema then
            DB.ready = true
            if cb then cb() end
            return
        end
        MYSQL.query(function(ok, err)
            if ok == false then
                outputDebugString(("[%s] schema %d failed: %s"):format(GOV.RES, i, tostring(err)), 1)
                setTimer(run, 10000, 1, i)
                return
            end
            run(i + 1)
        end, schema[i])
    end
    run(1)
end

function DB.exec(sql, ...)
    if not isResourceRunning("v_mysql") then return false end
    return exports.v_mysql:mysqlExec(sql, ...)
end

function DB.query(cb, sql, ...) return MYSQL.query(cb, sql, ...) end

function DB.int(v) return math.floor(tonumber(v) or 0) end

function DB.clip(s, n)
    s = tostring(s or "")
    if #s > n then s = s:sub(1, n) end
    return s
end

--------------------------------------------------------------------------------
-- basics
--------------------------------------------------------------------------------

function GOV.now() return getRealTime().timestamp end

function GOV.historySince() return GOV.now() - GOV.HISTORY_DAYS * 86400 end

function GOV.instance()
    if not isResourceRunning("v_main") then return "" end
    return tostring(exports.v_main:getServerInstanceId() or "")
end

--- account name of a logged-in player (lower-case), or nil
function GOV.accountOf(player)
    if not isElement(player) or getElementType(player) ~= "player" then return nil end
    if getElementData(player, "isLogged") ~= true then return nil end
    local name = getElementData(player, "accName")
    if type(name) ~= "string" or name == "" then return nil end
    return name:lower()
end

function GOV.bank()
    return isResourceRunning("v_bank") and exports.v_bank or nil
end

function GOV.core()
    return isResourceRunning("gov_core") and exports.gov_core or nil
end

--- gov_core has loaded its settings, members and state companies
function GOV.coreReady()
    local c = GOV.core()
    return c and c:isGovReady() == true or false
end

--- an error key of a reply: a full key stays, else <resource>.err.<k> when this resource has it,
--- else gov_core.err.<k>
function GOV.err(k)
    k = tostring(k or "unknown")
    if k:find(".", 1, true) then return k end
    local own = GOV.RES .. ".err." .. k
    if L and L.has and L.has(own) then return own end
    return "gov_core.err." .. k
end

--------------------------------------------------------------------------------
-- settings, log, state companies (gov_core)
--------------------------------------------------------------------------------

--- a setting: stored, else the default its owner registered, else nil
function GOV.get(key)
    local c = GOV.core()
    if not c then return nil end
    return c:getSetting(key)
end

--- stores a setting of this resource (value nil = back to the default)
function GOV.set(key, value, actor)
    local c = GOV.core()
    return c and c:setSetting(key, value, actor) or false
end

function GOV.log(actor, action, detail)
    local c = GOV.core()
    if c then c:log(actor, action, detail) end
end

--- active state companies with bank info: { {id, code, name, description, accountId, balance, number, allowNegative, createdAt}, ... }
function GOV.companyList()
    local c = GOV.core()
    return c and c:getStateCompanies() or {}
end

function GOV.companyByCode(code)
    local c = GOV.core()
    return c and c:getStateCompany(tostring(code or "")) or nil
end

function GOV.companyById(id)
    local c = GOV.core()
    return c and c:getStateCompanyById(tonumber(id)) or nil
end

function GOV.treasuryId()
    local bank = GOV.bank()
    return bank and bank:getStateAccount("treasury")
end

--- the treasury, then every state company (bank info, name = the company name)
function GOV.stateAccounts()
    local bank = GOV.bank()
    local out = {}
    local tid = GOV.treasuryId()
    local t = bank and tid and bank:getAccountInfo(tid)
    if t then out[1] = t end
    for _, c in ipairs(GOV.companyList()) do
        local info = bank and c.accountId and bank:getAccountInfo(c.accountId)
        if info and info.status ~= "closed" then
            info.name = c.name
            out[#out + 1] = info
        end
    end
    return out
end

function GOV.isStateAccount(id)
    for _, a in ipairs(GOV.stateAccounts()) do if a.id == id then return a end end
end

--------------------------------------------------------------------------------
-- payer / receiver / target specs
--------------------------------------------------------------------------------

--- v_bank account id of a payer / receiver spec ("system" | "state:<code>" | "company:<id>"):
--- the id, "system", or false (the account does not exist / is closed)
function GOV.specAccount(spec)
    local bank = GOV.bank()
    if spec == "system" or not bank then return "system" end
    local kind, ref = tostring(spec):match("^(%a+):(.+)$")
    local id
    if kind == "state" then id = bank:getStateAccount(ref)
    elseif kind == "company" then id = bank:getCompanyAccount(ref) end
    local info = id and bank:getAccountInfo(id)
    if not info or info.status == "closed" then return false end
    return id
end

--- where the money of a tax / fee goes: setting = { key -> state account code }; the code or nil
function GOV.targetCode(setting, key)
    local code = (GOV.get(setting) or {})[tostring(key)]
    return type(code) == "string" and code ~= "" and code or nil
end

--- v_bank account id of a target, or nil (none set, or the account is gone / not active)
function GOV.targetAccount(setting, key)
    local code = GOV.targetCode(setting, key)
    local bank = GOV.bank()
    if not code or not bank then return nil end
    local id = bank:getStateAccount(code)
    local info = id and bank:getAccountInfo(id)
    if not info or info.status ~= "active" then return nil end
    return id
end

--- the payer options of the pickers: system, the treasury, every state company
function GOV.payerOptions()
    local out = { { spec = "system", name = "System (money from nothing)" } }
    local bank = GOV.bank()
    local tid = GOV.treasuryId()
    local t = bank and tid and bank:getAccountInfo(tid)
    out[2] = { spec = "state:treasury", name = t and t.name or "State Treasury" }
    for _, c in ipairs(GOV.companyList()) do out[#out + 1] = { spec = "state:" .. c.code, name = c.name } end
    return out
end

--- the state accounts a tax / fee may go to: { {code, name}, ... } (the treasury first)
function GOV.targetOptions()
    local bank = GOV.bank()
    local tid = GOV.treasuryId()
    local t = bank and tid and bank:getAccountInfo(tid)
    local options = {}
    if t then options[1] = { code = "treasury", name = t.name } end
    for _, c in ipairs(GOV.companyList()) do options[#options + 1] = { code = c.code, name = c.name } end
    return options
end

--- id -> { name, active } of the biz_core companies in `ids` (async)
function GOV.companyNames(ids, cb)
    if #ids == 0 then return cb({}) end
    local marks = {}
    for i = 1, #ids do marks[i] = "?" end
    DB.query(function(rows)
        local names = {}
        for _, r in ipairs(rows or {}) do
            names[tostring(DB.int(r.id))] = { name = tostring(r.name), active = r.status == "active" }
        end
        cb(names)
    end, "SELECT id, name, status FROM biz_companies WHERE id IN (" .. table.concat(marks, ",") .. ")", unpack(ids))
end

--- checks a payer / receiver spec from the panel -> cb(spec) | cb(nil, errKey)
--- "system" | "player" (allowPlayer) | "state:<code>" (treasury or a state company) |
--- "company:<id>" (an active biz_core company)
function GOV.checkSpec(spec, allowPlayer, cb)
    spec = tostring(spec)
    if spec == "system" or (spec == "player" and allowPlayer) then return cb(spec) end
    local code = spec:match("^state:([a-z0-9_]+)$")
    if code then
        if code ~= "treasury" and not GOV.companyByCode(code) then return cb(nil, "bad_company") end
        return cb(spec)
    end
    local cid = tonumber(spec:match("^company:(%d+)$"))
    if not cid then return cb(nil, "bad_payer") end
    DB.query(function(rows)
        if not (rows and rows[1]) then return cb(nil, "no_company") end
        cb("company:" .. DB.int(rows[1].id))
    end, "SELECT id FROM biz_companies WHERE id = ? AND status = 'active' LIMIT 1", cid)
end

--------------------------------------------------------------------------------
-- v_bank requests that answer later (v_bank answers "<caller resource>:remoteResult")
--------------------------------------------------------------------------------

local bankPending, bankSeq = {}, 0
addEvent(GOV.RES .. ":remoteResult", false)
addEventHandler(GOV.RES .. ":remoteResult", resourceRoot, function(id, result)
    local cb = bankPending[id]
    bankPending[id] = nil
    if cb then cb(result) end
end)

function GOV.bankCall(action, args, actor, cb)
    local bank = GOV.bank()
    if not bank then return cb({ ok = false, error = "unavailable" }) end
    bankSeq = bankSeq + 1
    local id = bankSeq
    bankPending[id] = cb
    if not bank:bankCall(id, action, args, actor) then
        bankPending[id] = nil
        cb({ ok = false, error = "unavailable" })
    end
end

--------------------------------------------------------------------------------
-- the module: settings defaults, panel actions + pages (registered with gov_core now and again
-- whenever gov_core starts)
--------------------------------------------------------------------------------

local MOD

--- def = { settings = { prefixes = {...}, defaults = { key = value } },
---         actions = { name = "viewer" | "official" | "minister" | "public" | { role, sector } },
---         pages = { { id, category, order, need, script, sector? }, ... }, categories = { {id, order}, ... },
---         sectors = { { id, setting }, ... } }   (gov_core README "Sectors")
--- the handlers of the actions are GOV.A[name]
function GOV.module(def)
    MOD = def
    GOV.register()
end

function GOV.register()
    local c = GOV.core()
    if not MOD or not c then return end
    c:registerModule(MOD)
end

addEventHandler("onResourceStart", root, function(res)
    if res ~= getThisResource() and getResourceName(res) == "gov_core" then GOV.register() end
end)

addEvent("onGovAction", false)
addEventHandler("onGovAction", resourceRoot, function(reqId, action, args, actor, player)
    local function reply(result, err)
        local c = GOV.core()
        if c then c:reply(reqId, result, result == false and GOV.err(err) or nil) end
    end
    local fn = GOV.A[tostring(action)]
    if not fn then return reply(false, "unknown") end
    local ok, e = pcall(fn, player, type(args) == "table" and args or {}, reply, actor)
    if not ok then
        outputDebugString(("[%s] %s: %s"):format(GOV.RES, tostring(action), tostring(e)), 1)
        reply(false, "unknown")
    end
end)
]==]

function importLib() return LIB end

-- gov_core runs the lib itself (its own scripts then replace the gov_core wrappers)
loadstring(LIB)()
