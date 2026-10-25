-- gov_core / server/panel.lua
-- /gov and the panel pages of gov_core itself: State companies, Log, and the private company
-- search of the pickers (findCompanies). Every change goes to gov_log. The officials and their
-- rights are on gov_perms' Permissions page (the old Members page is gone).

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

--- the branches of gov_perms: { {code, name}, ... } (only "other" while gov_perms does not run)
local function branches()
    if isResourceRunning("gov_perms") then
        local ok, list = pcall(function() return exports.gov_perms:getGovBranches() end)
        if ok and type(list) == "table" and #list > 0 then return list end
    end
    return { { code = "other", name = "Other" } }
end

local function isBranch(code)
    for _, b in ipairs(branches()) do if b.code == code then return true end end
    return false
end

--- the companies the player may see (gov.<id>.view)
function A.companies(p, args, reply)
    if not GOV.bank() then return reply(false, "v_bank.error.unavailable") end
    local reach = GOV.permTargets(p, "gov.*.view")
    local list = {}
    for _, c in ipairs(GOV.companyList()) do
        if GOV.reach(reach, c.id) then list[#list + 1] = c end
    end
    reply({ list = list, payers = statePayerWorks() or {}, branches = branches() })
end

--- one state company (gov_companies id) with its bank account and the bank access list (the
--- access follows the gov.<id>.bank.* rights of the positions, gov_perms)
function A.company(p, args, reply, actor)
    local c = GOV.companyById(args.id)
    if not c then return reply(false, "bad_company") end
    GOV.bankCall("account", { id = c.accountId }, actor, function(r)
        if not r.ok then return reply(false, "v_bank.error." .. tostring(r.error)) end
        local a = r.account
        reply({ company = { id = c.id, code = c.code, name = c.name, description = c.description, branch = c.branch,
            accountId = c.accountId, number = a.number, balance = a.balance, allowNegative = a.allowNegative,
            access = a.access or {}, createdAt = c.createdAt, createdBy = c.createdBy } })
    end)
end

--- { code, name, description, branch }: a branch other than "other" only by the Governor / an
--- admin (perms.manage): the branch decides which minister reaches the company
function A.createCompany(p, args, reply, actor)
    local branch = "other"
    if args.branch and args.branch ~= "other" then
        if not GOV.hasPerm(p, "perms.manage") then return reply(false, "no_right") end
        if not isBranch(args.branch) then return reply(false, "bad_branch") end
        branch = args.branch
    end
    GOV.createCompany(args.code, args.name, args.description, args.allowNegative == true, actor, function(ok, err)
        if not ok then return reply(false, err) end
        reply(true)
    end, branch)
end

--- { id, branch }: the Governor / an admin (perms.manage) attaches a company to a branch; the
--- ministers whose rights cover that branch (gov.*.… + branch) reach it at once
function A.setCompanyBranch(p, args, reply, actor)
    local c = GOV.companyById(args.id)
    if not c then return reply(false, "bad_company") end
    local branch = tostring(args.branch or "")
    if not isBranch(branch) then return reply(false, "bad_branch") end
    GOV.setCompanyBranch(c, branch, actor)
    reply(true)
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

function A.companyOverdraft(p, args, reply, actor)
    local bank = GOV.bank()
    local c = GOV.companyById(args.id)
    if not bank or not c or not c.accountId then return reply(false, "bad_company") end
    bank:setAllowNegative(c.accountId, args.allow == true)
    GOV.log(actor, "company.overdraft", { code = c.code, allow = args.allow == true })
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
    perms = {
        { "panel.log",         "admin",         0 },
        { "office.edit",       "admin",         1 },
        { "companies.create",  "organizations", 2 },
        -- the old roles (gov_perms migrated the gov_members rows into the legacy_* positions)
        { "legacy.viewer",     "admin",         0 },
        { "legacy.official",   "admin",         1 },
        { "legacy.minister",   "admin",         3 },
    },
    -- targets: "treasury" + every state company id (server/companies.lua)
    families = {
        { "gov.*.view",        "organizations", 0 },
        { "gov.*.edit",        "organizations", 1, exclude = { "treasury" } },
        { "gov.*.close",       "organizations", 3, exclude = { "treasury" } },
        { "gov.*.bank.view",   "organizations", 0 },
        { "gov.*.bank.pay",    "organizations", 2 },
        { "gov.*.bank.manage", "organizations", 3 },
        { "gov.*.overdraft",   "organizations", 3, exclude = { "treasury" } },
    },
    actions = {
        findCompanies = "panel", log = "panel.log",
        companies = "gov.*.view",
        company = { perm = "gov.{id}.view", arg = "id" },
        createCompany = "companies.create",
        setCompanyBranch = "perms.manage",   -- the Governor / admins only (gov_perms)
        renameCompany = { perm = "gov.{id}.edit", arg = "id" },
        describeCompany = { perm = "gov.{id}.edit", arg = "id" },
        deleteCompany = { perm = "gov.{id}.close", arg = "id" },
        companyOverdraft = { perm = "gov.{id}.overdraft", arg = "id" },
    },
    pages = {
        { id = "companies", category = "organizations", order = 10, script = "web/js/pages.js", need = "gov.*.view" },
        { id = "log",       category = "admin",         order = 20, script = "web/js/pages.js", need = "panel.log" },
    },
})

--------------------------------------------------------------------------------
-- /gov
--------------------------------------------------------------------------------

--- export: opens (or closes, when open) the /gov panel of a player; also used by the
--- gov_office computers. Without any right the player gets the "no right" notification.
function openGovPanel(player)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if not GOV.hasPanel(player) then
        triggerClientEvent(player, "gov_core:denied", resourceRoot)
        return false
    end
    local pages, categories = GOV.menuFor(player)
    local list = {}
    for id in pairs(GOV.sectorsOf(player)) do list[#list + 1] = id end
    triggerClientEvent(player, "gov_core:open", resourceRoot, GOV.accessOf(player), pages, categories, list)
    return true
end

--- positions / rights changed (gov_perms): the menu and rights again (the client keeps them for
--- an open panel only); account = only that official, false = everybody
addEventHandler("onGovPermsChanged", root, function(account)
    for _, player in ipairs(getElementsByType("player")) do
        local acc = GOV.accountOf(player)
        if acc and (not account or account == acc) then
            local pages, categories = GOV.menuFor(player)
            triggerClientEvent(player, "gov_core:access", resourceRoot, GOV.accessOf(player), pages, categories)
        end
    end
end)

addCommandHandler("gov", function(player) openGovPanel(player) end)
