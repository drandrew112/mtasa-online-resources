-- gov_core / server/panel.lua
-- /gov and the panel pages of gov_core itself: State companies, Members, Log, and the private
-- company search of the pickers (findCompanies). Every change goes to gov_log.

local A = GOV.A

local function int(v) return DB.int(v) end

--- the works a state company pays (gov_works): { [code] = { work name, ... } }, or nil when
--- gov_works does not run
local function statePayerWorks()
    if not isResourceRunning("gov_works") then return nil end
    local ok, list = pcall(function() return exports.gov_works:getStatePayerWorks() end)
    return ok and type(list) == "table" and list or nil
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

function A.companies(p, args, reply)
    if not GOV.bank() then return reply(false, "v_bank.error.unavailable") end
    reply({ list = GOV.companyList(), payers = statePayerWorks() or {} })
end

--- one state company (gov_companies id) with its bank account and the bank access list
function A.company(p, args, reply, actor)
    local c = GOV.companyById(args.id)
    if not c then return reply(false, "bad_company") end
    GOV.bankCall("account", { id = c.accountId }, actor, function(r)
        if not r.ok then return reply(false, "v_bank.error." .. tostring(r.error)) end
        local a = r.account
        reply({ company = { id = c.id, code = c.code, name = c.name, description = c.description, accountId = c.accountId,
            number = a.number, balance = a.balance, allowNegative = a.allowNegative, access = a.access or {},
            createdAt = c.createdAt, createdBy = c.createdBy } })
    end)
end

function A.createCompany(p, args, reply, actor)
    GOV.createCompany(args.code, args.name, args.description, args.allowNegative == true, actor, function(ok, err)
        if not ok then return reply(false, err) end
        reply(true)
    end)
end

function A.renameCompany(p, args, reply, actor)
    local c = GOV.companyById(args.id)
    if not c then return reply(false, "bad_company") end
    local ok, err = GOV.renameCompany(c, args.name, actor)
    if not ok then return reply(false, err) end
    reply(true)
end

function A.describeCompany(p, args, reply, actor)
    local c = GOV.companyById(args.id)
    if not c then return reply(false, "bad_company") end
    GOV.describeCompany(c, args.description, actor)
    reply(true)
end

--- closes a state company; { id, move = true } first moves its balance to the treasury
function A.deleteCompany(p, args, reply, actor)
    local bank = GOV.bank()
    local c = GOV.companyById(args.id)
    if not bank or not c then return reply(false, "bad_company") end
    local payers = statePayerWorks()
    if not payers then return reply(false, "works_offline") end
    if payers[c.code] and #payers[c.code] > 0 then return reply(false, "company_pays_work") end
    local info = c.accountId and bank:getAccountInfo(c.accountId)
    if info and info.balance ~= 0 then
        if not args.move then return reply(false, "company_not_empty") end
        local tid = GOV.treasuryId()
        local from, to, amount = info.id, tid, info.balance
        if amount < 0 then from, to, amount = tid, info.id, -amount end
        local ok, err = bank:transfer(from, to, amount, "gov.transfer", { note = "Company closed" }, actor)
        if not ok then return reply(false, "v_bank.error." .. tostring(err)) end
    end
    local ok, err = GOV.closeCompany(c, actor)
    if not ok then return reply(false, err) end
    reply(true)
end

function A.companyMember(p, args, reply, actor)
    local bank = GOV.bank()
    local c = GOV.companyById(args.id)
    if not bank or not c or not c.accountId then return reply(false, "bad_company") end
    local role = args.role
    if role == "none" then role = nil end
    if not bank:setAccess(c.accountId, tostring(args.account or ""), role, actor) then return reply(false, "bad_member") end
    GOV.log(actor, "company.member", { code = c.code, account = args.account, role = role or "none" })
    reply(true)
end

function A.companyOverdraft(p, args, reply, actor)
    local bank = GOV.bank()
    local c = GOV.companyById(args.id)
    if not bank or not c or not c.accountId then return reply(false, "bad_company") end
    bank:setAllowNegative(c.accountId, args.allow == true)
    GOV.log(actor, "company.overdraft", { code = c.code, allow = args.allow == true })
    reply(true)
end

function A.members(p, args, reply)
    local list = {}
    for name, role in pairs(MEMBERS) do list[#list + 1] = { account = name, role = role } end
    table.sort(list, function(a, b) return a.account < b.account end)
    reply({ list = list, adminLevel = GOV.ADMIN_LEVEL })
end

function A.setMember(p, args, reply, actor)
    local role = args.role
    if role == "none" or role == "" then role = nil end
    if not GOV.setMember(args.account, role, actor) then return reply(false, "bad_member") end
    reply(true)
end

--- the last 100 rows of the change log
function A.log(p, args, reply)
    DB.query(function(rows)
        local list = {}
        for i, r in ipairs(rows or {}) do
            list[i] = { ts = int(r.ts), actor = tostring(r.actor), action = tostring(r.action), detail = tostring(r.detail) }
        end
        reply({ list = list })
    end, "SELECT ts, actor, action, detail FROM gov_log ORDER BY id DESC LIMIT 100")
end

GOV.registerModule("gov_core", {
    actions = {
        findCompanies = "viewer", companies = "viewer", company = "viewer", members = "viewer", log = "viewer",
        createCompany = "official", renameCompany = "official", describeCompany = "official", deleteCompany = "official",
        companyMember = "official", companyOverdraft = "minister", setMember = "minister",
    },
    pages = {
        { id = "companies", category = "organizations", order = 10, script = "web/js/pages.js" },
        { id = "members",   category = "admin",         order = 10, script = "web/js/pages.js" },
        { id = "log",       category = "admin",         order = 20, script = "web/js/pages.js" },
    },
})

--------------------------------------------------------------------------------
-- /gov
--------------------------------------------------------------------------------

--- export: opens (or closes, when open) the /gov panel of a player; also used by the
--- gov_office computers. Without a role the player gets the "no right" notification - unless
--- they are a member of a company that runs a sector (role "sector": only those pages).
function openGovPanel(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local role = getGovRole(player)
    local sectors = GOV.sectorsOf(player)
    if not role and not next(sectors) then
        triggerClientEvent(player, "gov_core:denied", resourceRoot)
        return false
    end
    local pages, categories = GOV.menuFor(role or "sector", sectors)
    local list = {}
    for id in pairs(sectors) do list[#list + 1] = id end
    triggerClientEvent(player, "gov_core:open", resourceRoot, role or "sector", pages, categories, list)
    return true
end

addCommandHandler("gov", function(player) openGovPanel(player) end)
