-- gov_perms / server/perms.lua
-- Groups (positions), their rights, appointments and branches, cached; the check (DESIGN.md 4).
-- Everything is re-read every RESYNC_MS (the other server instance may have changed it); the
-- instance that changes something applies it at once. Allow-only: a key nobody granted is refused.

GROUPS = {}       -- [id] = { id, code, name, description, kind, rank, maxHolders, salary, taxKey, color, status, grants = { {perm, branch} } }
MEMBERS = {}      -- [member id] = { id, account, groupId, grantedBy, grantedAt, expiresAt, note }
BRANCHES = {}     -- { { code, name, sort, status }, ... } in order
BRANCH_OF = {}    -- [company id] = branch code (gov_core state companies)

local BY_ACC = {} -- [account] = { member, ... }
local EFF = {}    -- [account] = effective grants (cache)

local function int(v) return DB.int(v) end

function PERMS.reindex()
    BY_ACC, EFF = {}, {}
    for _, m in pairs(MEMBERS) do
        local list = BY_ACC[m.account] or {}
        list[#list + 1] = m
        BY_ACC[m.account] = list
    end
end

--- the branch of every state company (from gov_core)
function PERMS.refreshBranchOf()
    local fresh = {}
    for _, c in ipairs(GOV.companyList()) do fresh[tostring(c.id)] = tostring(c.branch or "other") end
    BRANCH_OF = fresh
    EFF = {}
end

local function alive(m, now)
    return m.expiresAt == 0 or m.expiresAt > (now or GOV.now())
end

--- the active positions of an account: { group, ... } (highest rank first)
function PERMS.groupsOf(account)
    local out, now = {}, GOV.now()
    for _, m in ipairs(BY_ACC[tostring(account or ""):lower()] or {}) do
        local g = GROUPS[m.groupId]
        if g and g.status == "active" and alive(m, now) then out[#out + 1] = g end
    end
    table.sort(out, function(a, b) return a.rank > b.rank end)
    return out
end

--- { { perm, branch, group }, ... } of an account
function PERMS.effective(account)
    account = tostring(account or ""):lower()
    if EFF[account] then return EFF[account] end
    local list = {}
    for _, g in ipairs(PERMS.groupsOf(account)) do
        for _, gr in ipairs(g.grants) do list[#list + 1] = { perm = gr.perm, branch = gr.branch, group = g.id } end
    end
    EFF[account] = list
    return list
end

--- a branch-limited grant covers only gov.<company id>.… keys of companies in that branch
function PERMS.branchOk(branch, key)
    if not branch or branch == "" then return true end
    local id = tostring(key):match("^gov%.([^%.]+)%.")
    return id ~= nil and BRANCH_OF[id] == branch
end

--- the grant of an account that covers a key, or nil
function PERMS.grantFor(account, key)
    for _, g in ipairs(PERMS.effective(account)) do
        if GOV.permMatch(g.perm, key) and PERMS.branchOk(g.branch, key) then return g end
    end
end

function PERMS.isSuper(account)
    for _, g in ipairs(PERMS.effective(account)) do
        if g.perm == "*" and g.branch == "" then return true end
    end
    return false
end

function PERMS.has(account, key)
    return PERMS.grantFor(account, tostring(key or "")) ~= nil
end

--- the targets of a family an account reaches: { all = true } | { [target] = true }
function PERMS.targets(account, family)
    family = tostring(family or "")
    for _, g in ipairs(PERMS.effective(account)) do
        if g.branch == "" and GOV.permMatch(g.perm, family) then return { all = true } end
    end
    local out = {}
    for _, row in ipairs(PERMS.familyRows(family)) do
        if PERMS.has(account, row.perm) then out[row.target] = true end
    end
    return out
end

--------------------------------------------------------------------------------
-- load
--------------------------------------------------------------------------------

local function groupFromRow(r)
    return { id = int(r.id), code = tostring(r.code), name = tostring(r.name), description = tostring(r.description or ""),
        kind = tostring(r.kind), rank = int(r.seniority), maxHolders = int(r.max_holders), salary = int(r.salary),
        taxKey = tostring(r.tax_key or "standard"), color = tostring(r.color or "#888888"), status = tostring(r.status),
        createdAt = int(r.created_at), grants = {} }
end

local function memberFromRow(r)
    return { id = int(r.id), account = tostring(r.account_name):lower(), groupId = int(r.group_id),
        grantedBy = tostring(r.granted_by or ""), grantedAt = int(r.granted_at), expiresAt = int(r.expires_at),
        note = tostring(r.note or "") }
end

--- re-reads groups, rights, appointments and branches -> cb()
function PERMS.loadAll(cb)
    DB.query(function(grows)
        DB.query(function(prows)
            DB.query(function(mrows)
                DB.query(function(brows)
                    if grows and prows and mrows and brows then
                        local groups = {}
                        for _, r in ipairs(grows) do local g = groupFromRow(r); groups[g.id] = g end
                        for _, r in ipairs(prows) do
                            local g = groups[int(r.group_id)]
                            if g then g.grants[#g.grants + 1] = { perm = tostring(r.perm), branch = tostring(r.branch or "") } end
                        end
                        for _, g in pairs(groups) do
                            table.sort(g.grants, function(a, b) return a.perm .. "|" .. a.branch < b.perm .. "|" .. b.branch end)
                        end
                        local members = {}
                        for _, r in ipairs(mrows) do local m = memberFromRow(r); members[m.id] = m end
                        local branches = {}
                        for _, r in ipairs(brows) do
                            branches[#branches + 1] = { code = tostring(r.code), name = tostring(r.name), sort = int(r.sort), status = tostring(r.status) }
                        end
                        local before = PERMS.signature and PERMS.signature() or ""
                        GROUPS, MEMBERS, BRANCHES = groups, members, branches
                        PERMS.reindex()
                        PERMS.refreshBranchOf()
                        if PERMS.ready and before ~= PERMS.signature() then PERMS.changed(false) end
                    end
                    if cb then cb() end
                end, "SELECT code, name, sort, status FROM gov_branches ORDER BY sort, code")
            end, "SELECT * FROM gov_perms_members")
        end, "SELECT group_id, perm, branch FROM gov_perms_group_perms")
    end, "SELECT * FROM gov_perms_groups")
end

--- a short text of everything that decides a right (to see whether a re-read changed anything)
function PERMS.signature()
    local parts = {}
    for id, g in pairs(GROUPS) do
        local gr = {}
        for _, x in ipairs(g.grants) do gr[#gr + 1] = x.perm .. "/" .. x.branch end
        parts[#parts + 1] = id .. ":" .. g.status .. ":" .. table.concat(gr, ",")
    end
    for id, m in pairs(MEMBERS) do parts[#parts + 1] = "m" .. id .. ":" .. m.account .. ":" .. m.groupId .. ":" .. m.expiresAt end
    table.sort(parts)
    return table.concat(parts, ";")
end

--- something that decides rights changed: gov_core re-sends the open panels, the bank access is
--- synced. account = only this account changed (false = anybody)
function PERMS.changed(account)
    EFF = {}
    triggerEvent("onGovPermsChanged", resourceRoot, account or false)
    if PERMS.scheduleBankSync then PERMS.scheduleBankSync() end
end

--------------------------------------------------------------------------------
-- groups
--------------------------------------------------------------------------------

function PERMS.groupByCode(code)
    for _, g in pairs(GROUPS) do if g.code == code then return g end end
end

function PERMS.holders(groupId)
    local out, now = {}, GOV.now()
    for _, m in pairs(MEMBERS) do
        if m.groupId == groupId and alive(m, now) then out[#out + 1] = m end
    end
    return out
end

--- creates / changes a group: f = { id?, code, name, description, kind, rank, maxHolders, salary, taxKey, color }
--- -> cb(id) | cb(false, err)
function PERMS.saveGroup(f, actor, cb)
    local now = GOV.now()
    if f.id then
        local g = GROUPS[f.id]
        if not g then return cb(false, "bad_group") end
        local oldSalary = g.salary
        g.name, g.description, g.rank, g.maxHolders, g.salary, g.taxKey, g.color =
            f.name, f.description, f.rank, f.maxHolders, f.salary, f.taxKey, f.color
        DB.exec("UPDATE gov_perms_groups SET name = ?, description = ?, seniority = ?, max_holders = ?, salary = ?, tax_key = ?, "
            .. "color = ?, updated_at = ? WHERE id = ?", g.name, g.description, g.rank, g.maxHolders, g.salary, g.taxKey,
            g.color, now, g.id)
        GOV.log(actor, "perm.group.edit", { code = g.code, name = g.name })
        if oldSalary ~= g.salary then GOV.log(actor, "perm.salary", { code = g.code, old = oldSalary, new = g.salary }) end
        PERMS.changed(false)
        return cb(g.id)
    end
    if PERMS.groupByCode(f.code) then return cb(false, "code_taken") end
    MYSQL.insert(function(id, err)
        if not id or id == true then
            outputDebugString("[gov_perms] group insert failed: " .. tostring(err), 1)
            return cb(false, "db")
        end
        local g = { id = int(id), code = f.code, name = f.name, description = f.description, kind = f.kind or "position",
            rank = f.rank, maxHolders = f.maxHolders, salary = f.salary, taxKey = f.taxKey, color = f.color, status = "active",
            createdAt = now, grants = {} }
        GROUPS[g.id] = g
        GOV.log(actor, "perm.group.create", { code = g.code, name = g.name })
        PERMS.changed(false)
        cb(g.id)
    end, "INSERT INTO gov_perms_groups (code, name, description, kind, seniority, max_holders, salary, tax_key, color, status, "
        .. "created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?)",
        f.code, f.name, f.description, f.kind or "position", f.rank, f.maxHolders, f.salary, f.taxKey, f.color,
        DB.clip(actor, 64), now, now)
end

--- replaces the rights of a group: grants = { {perm, branch}, ... } (checked by the caller)
function PERMS.setGrants(g, grants, actor)
    local now = GOV.now()
    local old, new = {}, {}
    for _, x in ipairs(g.grants) do old[x.perm .. "|" .. x.branch] = x end
    for _, x in ipairs(grants) do new[x.perm .. "|" .. x.branch] = x end
    for k, x in pairs(old) do
        if not new[k] then
            DB.exec("DELETE FROM gov_perms_group_perms WHERE group_id = ? AND perm = ? AND branch = ?", g.id, x.perm, x.branch)
            GOV.log(actor, "perm.revoke", { group = g.code, perm = x.perm, branch = x.branch })
        end
    end
    for k, x in pairs(new) do
        if not old[k] then
            DB.exec("INSERT IGNORE INTO gov_perms_group_perms (group_id, perm, branch, granted_by, granted_at) VALUES (?, ?, ?, ?, ?)",
                g.id, x.perm, x.branch, DB.clip(actor, 64), now)
            GOV.log(actor, "perm.grant", { group = g.code, perm = x.perm, branch = x.branch })
        end
    end
    g.grants = {}
    for _, x in pairs(new) do g.grants[#g.grants + 1] = { perm = x.perm, branch = x.branch } end
    table.sort(g.grants, function(a, b) return a.perm .. "|" .. a.branch < b.perm .. "|" .. b.branch end)
    DB.exec("UPDATE gov_perms_groups SET updated_at = ? WHERE id = ?", now, g.id)
    PERMS.changed(false)
end

function PERMS.setGroupStatus(g, status, actor)
    g.status = status
    DB.exec("UPDATE gov_perms_groups SET status = ?, updated_at = ? WHERE id = ?", status, GOV.now(), g.id)
    GOV.log(actor, "perm.group." .. (status == "archived" and "archive" or "restore"), { code = g.code })
    PERMS.changed(false)
end

--------------------------------------------------------------------------------
-- appointments
--------------------------------------------------------------------------------

--- appoints an account to a group -> cb(member id) | cb(false, err) (rules checked by the caller)
function PERMS.appoint(account, g, expiresAt, note, actor, cb)
    account = tostring(account or ""):lower()
    for _, m in pairs(MEMBERS) do
        if m.account == account and m.groupId == g.id then return cb(false, "already_member") end
    end
    local now = GOV.now()
    MYSQL.insert(function(id, err)
        if not id or id == true then
            outputDebugString("[gov_perms] appointment failed: " .. tostring(err), 1)
            return cb(false, "db")
        end
        MEMBERS[int(id)] = { id = int(id), account = account, groupId = g.id, grantedBy = tostring(actor), grantedAt = now,
            expiresAt = expiresAt, note = note }
        PERMS.reindex()
        GOV.log(actor, "perm.member.appoint", { account = account, group = g.code, expires = expiresAt })
        triggerEvent("onGovAppointed", resourceRoot, account, g.code)
        PERMS.changed(account)
        cb(int(id))
    end, "INSERT INTO gov_perms_members (account_name, group_id, granted_by, granted_at, expires_at, note) VALUES (?, ?, ?, ?, ?, ?)",
        account, g.id, DB.clip(actor, 64), now, expiresAt, DB.clip(note, 128))
end

--- removes an appointment (logAction = "dismiss" | "expire" | "replace")
function PERMS.dismiss(m, actor, logAction)
    MEMBERS[m.id] = nil
    PERMS.reindex()
    DB.exec("DELETE FROM gov_perms_members WHERE id = ?", m.id)
    local g = GROUPS[m.groupId]
    GOV.log(actor, "perm.member." .. (logAction or "dismiss"), { account = m.account, group = g and g.code or m.groupId })
    triggerEvent("onGovDismissed", resourceRoot, m.account, g and g.code or "")
    PERMS.changed(m.account)
end

--- ends the expired appointments (both instances may run it: the DELETE decides who logs)
function PERMS.expire()
    local now = GOV.now()
    for _, m in pairs(MEMBERS) do
        if m.expiresAt > 0 and m.expiresAt <= now then
            DB.query(function(res, affected)
                if MEMBERS[m.id] then
                    MEMBERS[m.id] = nil
                    PERMS.reindex()
                    PERMS.changed(m.account)
                end
                if res ~= false and tonumber(affected) == 1 then
                    local g = GROUPS[m.groupId]
                    GOV.log("system", "perm.member.expire", { account = m.account, group = g and g.code or m.groupId })
                    triggerEvent("onGovDismissed", resourceRoot, m.account, g and g.code or "")
                end
            end, "DELETE FROM gov_perms_members WHERE id = ? AND expires_at > 0 AND expires_at <= ?", m.id, now)
        end
    end
end

--------------------------------------------------------------------------------
-- branches
--------------------------------------------------------------------------------

function PERMS.branch(code)
    for _, b in ipairs(BRANCHES) do if b.code == code then return b end end
end

function PERMS.saveBranch(code, name, sort, actor)
    local b = PERMS.branch(code)
    if b then
        b.name, b.sort = name, sort
        GOV.log(actor, "perm.branch.edit", { code = code, name = name })
    else
        BRANCHES[#BRANCHES + 1] = { code = code, name = name, sort = sort, status = "active" }
        GOV.log(actor, "perm.branch.create", { code = code, name = name })
    end
    table.sort(BRANCHES, function(a, x) if a.sort ~= x.sort then return a.sort < x.sort end return a.code < x.code end)
    DB.exec("INSERT INTO gov_branches (code, name, sort, status) VALUES (?, ?, ?, 'active') "
        .. "ON DUPLICATE KEY UPDATE name = VALUES(name), sort = VALUES(sort)", code, name, sort)
end

function PERMS.setBranchStatus(b, status, actor)
    b.status = status
    DB.exec("UPDATE gov_branches SET status = ? WHERE code = ?", status, b.code)
    GOV.log(actor, "perm.branch." .. (status == "archived" and "archive" or "restore"), { code = b.code })
end
