-- gov_perms / server/panel.lua
-- The Permissions page of /gov (Administration; tabs Groups, Officials, Branches, Catalogue) and
-- the registration with gov_core. Reading needs perms.view, every change perms.manage (the
-- Governor and admins only, DESIGN.md 6). System groups (the Governor, the legacy roles) are
-- changed by admins only. Every change goes to gov_log.

local A = GOV.A

local function int(v) return DB.int(v) end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function isAdmin(p)
    if not GOV.accountOf(p) then return false end
    local level = isResourceRunning("v_mysql") and tonumber(exports.v_mysql:getAccData(p, "admin_level")) or 0
    return level >= PERMS.ADMIN_LEVEL
end

local function taxKeys()
    if not isResourceRunning("gov_tax") then return { standard = 0 } end
    local ok, keys = pcall(function() return exports.gov_tax:getIncomeTaxKeys() end)
    return ok and type(keys) == "table" and keys or { standard = 0 }
end

--- may this group be changed by the player? (system groups: admins only)
local function canTouch(p, g)
    if g.kind == "system" and not isAdmin(p) then return false, "system_group" end
    return true
end

--- account -> display name (accounts.display_name, else the account name) -> cb(map)
local function displayNames(accounts, cb)
    if #accounts == 0 then return cb({}) end
    local marks = {}
    for i = 1, #accounts do marks[i] = "?" end
    DB.query(function(rows)
        local out = {}
        for _, r in ipairs(rows or {}) do
            local name = tostring(r.account_name):lower()
            local d = r.display_name
            out[name] = (type(d) == "string" and d ~= "") and d or tostring(r.account_name)
        end
        cb(out)
    end, "SELECT account_name, display_name FROM accounts WHERE account_name IN (" .. table.concat(marks, ",") .. ")", unpack(accounts))
end

--------------------------------------------------------------------------------
-- read
--------------------------------------------------------------------------------

--- everything of the Groups / Officials / Branches tabs + the live catalogue
function A.perms(p, args, reply)
    local groups = {}
    for _, g in pairs(GROUPS) do
        local paid = PERMS.paid30(g.id)
        groups[#groups + 1] = { id = g.id, code = g.code, name = g.name, description = g.description, kind = g.kind,
            rank = g.rank, maxHolders = g.maxHolders, salary = g.salary, taxKey = g.taxKey, color = g.color, status = g.status,
            grants = g.grants, holders = #PERMS.holders(g.id), paid30 = paid.gross }
    end
    table.sort(groups, function(a, b) if a.rank ~= b.rank then return a.rank > b.rank end return a.name < b.name end)
    local members, accounts, seen = {}, {}, {}
    for _, m in pairs(MEMBERS) do
        members[#members + 1] = { id = m.id, account = m.account, groupId = m.groupId, grantedBy = m.grantedBy,
            grantedAt = m.grantedAt, expiresAt = m.expiresAt, note = m.note }
        if not seen[m.account] then seen[m.account] = true; accounts[#accounts + 1] = m.account end
    end
    local companies, perBranch = {}, {}
    for _, c in ipairs(GOV.companyList()) do
        companies[#companies + 1] = { id = c.id, name = c.name, branch = c.branch }
        perBranch[c.branch] = (perBranch[c.branch] or 0) + 1
    end
    local branches = {}
    for _, b in ipairs(BRANCHES) do
        branches[#branches + 1] = { code = b.code, name = b.name, sort = b.sort, status = b.status, companies = perBranch[b.code] or 0 }
    end
    local catalogue = {}
    for _, r in pairs(CATALOGUE) do catalogue[#catalogue + 1] = r end
    displayNames(accounts, function(names)
        local paid = {}
        for _, acc in ipairs(accounts) do paid[acc] = PERMS.paid30Account(acc) end
        reply({ groups = groups, members = members, names = names, paid = paid, branches = branches, companies = companies,
            catalogue = catalogue, areas = PERMS.AREAS, taxKeys = taxKeys(),
            planHours = tonumber(GOV.get("perms.salary.plan_hours")) or PERMS.PLAN_HOURS,
            canManage = GOV.has(p, "perms.manage"), isAdmin = isAdmin(p), maxSalary = PERMS.MAX_SALARY })
    end)
end

--- every gov_perms row, also the inactive ones (Catalogue tab)
function A.permCatalogue(p, args, reply)
    PERMS.catalogueRows(function(list) reply({ list = list }) end)
end

--- the resolved rights of one official: { account, rows = { {perm, group} }, super }
function A.permEffective(p, args, reply)
    local acc = tostring(args.account or ""):lower()
    if acc == "" then return reply(false, "bad_member") end
    local rows = {}
    local keys = {}
    for k in pairs(CATALOGUE) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local g = PERMS.grantFor(acc, k)
        if g then rows[#rows + 1] = { perm = k, group = GROUPS[g.group] and GROUPS[g.group].name or "?" } end
    end
    local positions = {}
    for _, g in ipairs(PERMS.groupsOf(acc)) do positions[#positions + 1] = g.name end
    reply({ account = acc, rows = rows, super = PERMS.isSuper(acc), positions = positions })
end

--------------------------------------------------------------------------------
-- groups
--------------------------------------------------------------------------------

--- { id?, code, name, description, rank, maxHolders, salary, taxKey, color }
function A.saveGroup(p, args, reply, actor)
    local f = {
        id = tonumber(args.id),
        code = trim(args.code):lower(),
        name = trim(args.name),
        description = DB.clip(trim(args.description), 255),
        rank = math.max(0, math.min(9999, int(args.rank))),
        maxHolders = math.max(0, math.min(999, int(args.maxHolders))),
        salary = int(args.salary),
        taxKey = trim(args.taxKey ~= nil and args.taxKey or "standard"),
        color = trim(args.color ~= nil and args.color or "#888888"),
    }
    if f.name == "" or #f.name > 64 then return reply(false, "bad_name") end
    if f.salary < 0 or f.salary > PERMS.MAX_SALARY then return reply(false, "bad_number") end
    if not f.color:match("^#%x%x%x%x%x%x$") then f.color = "#888888" end
    if taxKeys()[f.taxKey] == nil then return reply(false, "bad_tax_key") end
    if f.id then
        local g = GROUPS[f.id]
        if not g then return reply(false, "bad_group") end
        local ok, err = canTouch(p, g)
        if not ok then return reply(false, err) end
    else
        if not f.code:match("^[a-z0-9_]+$") or #f.code < 2 or #f.code > 32 then return reply(false, "bad_code") end
        local n = 0
        for _ in pairs(GROUPS) do n = n + 1 end
        if n >= PERMS.MAX_GROUPS then return reply(false, "too_many") end
    end
    PERMS.saveGroup(f, actor, function(id, err)
        if not id then return reply(false, err) end
        reply({ id = id })
    end)
end

--- { id, grants = { {perm, branch}, ... } }: replaces the rights of a group
function A.setGroupGrants(p, args, reply, actor)
    local g = GROUPS[tonumber(args.id) or -1]
    if not g then return reply(false, "bad_group") end
    local ok, err = canTouch(p, g)
    if not ok then return reply(false, err) end
    local list, seen = {}, {}
    for _, x in ipairs(type(args.grants) == "table" and args.grants or {}) do
        local perm = trim(type(x) == "table" and x.perm or "")
        local branch = trim(type(x) == "table" and x.branch or "")
        if perm == "" or #perm > 64 or not perm:match("^[%w_%.%*]+$") then return reply(false, "bad_perm") end
        if not PERMS.known(perm) then return reply(false, "bad_perm") end
        if branch ~= "" and (not perm:match("^gov%.%*%.") or not PERMS.branch(branch)) then return reply(false, "bad_branch") end
        -- the appointing right and "everything" stay with the system groups (the Governor)
        if g.kind ~= "system" and (perm == "*" or GOV.permMatch(perm, "perms.manage")) then return reply(false, "manage_reserved") end
        local k = perm .. "|" .. branch
        if not seen[k] then
            seen[k] = true
            list[#list + 1] = { perm = perm, branch = branch }
        end
    end
    if #list > PERMS.MAX_GRANTS then return reply(false, "too_many") end
    PERMS.setGrants(g, list, actor)
    reply(true)
end

--- { id, archived }: an archived group gives no rights; only without holders
function A.setGroupStatus(p, args, reply, actor)
    local g = GROUPS[tonumber(args.id) or -1]
    if not g then return reply(false, "bad_group") end
    local ok, err = canTouch(p, g)
    if not ok then return reply(false, err) end
    if args.archived == true then
        if #PERMS.holders(g.id) > 0 then return reply(false, "group_has_members") end
        PERMS.setGroupStatus(g, "archived", actor)
    else
        PERMS.setGroupStatus(g, "active", actor)
    end
    reply(true)
end

--- { id, code, name }: a new position with the same settings and rights (not system)
function A.copyGroup(p, args, reply, actor)
    local src = GROUPS[tonumber(args.id) or -1]
    if not src then return reply(false, "bad_group") end
    local code, name = trim(args.code):lower(), trim(args.name)
    if not code:match("^[a-z0-9_]+$") or #code < 2 or #code > 32 then return reply(false, "bad_code") end
    if name == "" or #name > 64 then return reply(false, "bad_name") end
    local grants = {}
    for _, x in ipairs(src.grants) do
        if not (x.perm == "*" or GOV.permMatch(x.perm, "perms.manage")) then grants[#grants + 1] = { perm = x.perm, branch = x.branch } end
    end
    PERMS.saveGroup({ code = code, name = name, description = src.description, kind = "position", rank = src.rank,
        maxHolders = src.maxHolders, salary = src.salary, taxKey = src.taxKey, color = src.color }, actor, function(id, err)
        if not id then return reply(false, err) end
        PERMS.setGrants(GROUPS[id], grants, actor)
        reply({ id = id })
    end)
end

--------------------------------------------------------------------------------
-- appointments
--------------------------------------------------------------------------------

--- checks + appoints: { account, group, days (0 = no end), note, replace = true (single-holder: dismiss the holder) }
function A.appoint(p, args, reply, actor)
    local g = GROUPS[tonumber(args.group) or -1]
    if not g or g.status ~= "active" then return reply(false, "bad_group") end
    local ok, err = canTouch(p, g)
    if not ok then return reply(false, err) end
    local acc = trim(args.account):lower()
    if acc == "" or #acc > 64 then return reply(false, "bad_member") end
    local days = tonumber(args.days) or 0
    if days < 0 or days > 3650 then return reply(false, "bad_number") end
    local expiresAt = days > 0 and (GOV.now() + math.floor(days * 86400)) or 0
    local note = DB.clip(trim(args.note), 128)
    DB.query(function(rows)
        if not (rows and rows[1]) then return reply(false, "no_account") end
        acc = tostring(rows[1].account_name):lower()
        local holders = PERMS.holders(g.id)
        for _, m in ipairs(holders) do
            if m.account == acc then return reply(false, "already_member") end
        end
        if g.maxHolders > 0 and #holders >= g.maxHolders then
            if not (args.replace == true and g.maxHolders == 1) then return reply(false, "position_full") end
            for _, m in ipairs(holders) do PERMS.dismiss(m, actor, "replace") end
        end
        PERMS.appoint(acc, g, expiresAt, note, actor, function(id, e)
            if not id then return reply(false, e) end
            reply({ id = id })
        end)
    end, "SELECT account_name FROM accounts WHERE account_name = ? LIMIT 1", acc)
end

--- { id } (an appointment)
function A.dismiss(p, args, reply, actor)
    local m = MEMBERS[tonumber(args.id) or -1]
    if not m then return reply(false, "bad_member") end
    local g = GROUPS[m.groupId]
    if g then
        local ok, err = canTouch(p, g)
        if not ok then return reply(false, err) end
    end
    PERMS.dismiss(m, actor, "dismiss")
    reply(true)
end

--- { id, days (0 = no end) }: a new end of an appointment
function A.setExpiry(p, args, reply, actor)
    local m = MEMBERS[tonumber(args.id) or -1]
    if not m then return reply(false, "bad_member") end
    local g = GROUPS[m.groupId]
    if g then
        local ok, err = canTouch(p, g)
        if not ok then return reply(false, err) end
    end
    local days = tonumber(args.days) or 0
    if days < 0 or days > 3650 then return reply(false, "bad_number") end
    m.expiresAt = days > 0 and (GOV.now() + math.floor(days * 86400)) or 0
    DB.exec("UPDATE gov_perms_members SET expires_at = ? WHERE id = ?", m.expiresAt, m.id)
    GOV.log(actor, "perm.member.expiry", { account = m.account, group = g and g.code or m.groupId, expires = m.expiresAt })
    PERMS.changed(m.account)
    reply(true)
end

--------------------------------------------------------------------------------
-- branches, settings, catalogue
--------------------------------------------------------------------------------

--- { code, name, sort }
function A.saveBranch(p, args, reply, actor)
    local code, name = trim(args.code):lower(), trim(args.name)
    if not code:match("^[a-z0-9_]+$") or #code < 2 or #code > 24 then return reply(false, "bad_code") end
    if name == "" or #name > 64 then return reply(false, "bad_name") end
    PERMS.saveBranch(code, name, math.max(0, math.min(9999, int(args.sort or 100))), actor)
    reply(true)
end

--- { code, archived } ("other" stays: the default of every company)
function A.setBranchStatus(p, args, reply, actor)
    local b = PERMS.branch(trim(args.code))
    if not b then return reply(false, "bad_branch") end
    if b.code == "other" and args.archived == true then return reply(false, "key_protected") end
    PERMS.setBranchStatus(b, args.archived == true and "archived" or "active", actor)
    reply(true)
end

--- { value }: expected online hours per day for the salary plan
function A.setPlanHours(p, args, reply, actor)
    local v = tonumber(args.value)
    if not v or v < 0 or v > 24 then return reply(false, "bad_number") end
    GOV.set("perms.salary.plan_hours", math.floor(v * 10 + 0.5) / 10, actor)
    reply(true)
end

--- { perm }: removes an inactive catalogue row (+ its grants)
function A.purgePerm(p, args, reply, actor)
    local perm = trim(args.perm)
    if perm == "" or CATALOGUE[perm] then return reply(false, "perm_active") end
    DB.exec("DELETE FROM gov_perms WHERE perm = ? AND active = 0", perm)
    for _, g in pairs(GROUPS) do
        local keep, changed = {}, false
        for _, x in ipairs(g.grants) do
            if x.perm == perm then changed = true else keep[#keep + 1] = x end
        end
        if changed then PERMS.setGrants(g, keep, actor) end
    end
    GOV.log(actor, "perm.catalogue.purge", { perm = perm })
    reply(true)
end

--------------------------------------------------------------------------------
-- registration
--------------------------------------------------------------------------------

GOV.module({
    settings = { prefixes = { "perms." }, defaults = { ["perms.salary.plan_hours"] = PERMS.PLAN_HOURS } },
    perms = {
        { "perms.view",   "admin", 0 },
        { "perms.manage", "admin", 3 },
    },
    actions = {
        perms = "perms.view", permCatalogue = "perms.view", permEffective = "perms.view",
        saveGroup = "perms.manage", setGroupGrants = "perms.manage", setGroupStatus = "perms.manage", copyGroup = "perms.manage",
        appoint = "perms.manage", dismiss = "perms.manage", setExpiry = "perms.manage",
        saveBranch = "perms.manage", setBranchStatus = "perms.manage", setPlanHours = "perms.manage", purgePerm = "perms.manage",
    },
    pages = {
        { id = "perms", category = "admin", order = 5, script = "web/js/pages.js", need = "perms.view" },
    },
})
