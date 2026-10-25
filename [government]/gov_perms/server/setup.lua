-- gov_perms / server/setup.lua
-- The first start (DESIGN.md 11), done by one instance only (the INSERT of the gov_settings row
-- perms.migrated decides which):
--   1. the branches (only into an empty gov_branches)
--   2. the default positions (by code, salaries 0)
--   3. the old gov_members roles -> the system groups legacy_viewer / legacy_official / legacy_minister
--   4. the existing v_bank access rows of the state accounts -> "<account> - <role> (migrated)"
--      positions, so nobody loses access before the Governor sorts them out (from now on the bank
--      access of a state account follows the rights, server/bank.lua)

local function int(v) return DB.int(v) end

--- runs fns one after the other (each gets `next`) -> done()
local function chain(fns, done)
    local function step(i)
        if i > #fns then return done and done() end
        fns[i](function() step(i + 1) end)
    end
    step(1)
end

--- inserts a group with its grants unless the code exists -> cb(group id | nil)
local function ensureGroup(def, cb)
    DB.query(function(rows)
        if rows and rows[1] then return cb(int(rows[1].id)) end
        local now = GOV.now()
        MYSQL.insert(function(id)
            if not id or id == true then return cb(nil) end
            id = int(id)
            for _, gr in ipairs(def.grants or {}) do
                local perm, branch = gr, ""
                if type(gr) == "table" then perm, branch = gr[1], gr[2] or "" end
                DB.exec("INSERT IGNORE INTO gov_perms_group_perms (group_id, perm, branch, granted_by, granted_at) VALUES (?, ?, ?, 'setup', ?)",
                    id, perm, branch, now)
            end
            cb(id)
        end, "INSERT INTO gov_perms_groups (code, name, description, kind, seniority, max_holders, salary, tax_key, color, status, "
            .. "created_by, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, 0, 'standard', ?, 'active', 'setup', ?, ?)",
            def.code, def.name, def.description or "", def.kind or "position", def.rank or 100, def.max or 0,
            def.color or "#888888", now, now)
    end, "SELECT id FROM gov_perms_groups WHERE code = ? LIMIT 1", def.code)
end

local function seedBranches(nextStep)
    DB.query(function(rows)
        if rows and rows[1] and int(rows[1].n) > 0 then return nextStep() end
        for _, b in ipairs(PERMS.SEED_BRANCHES) do
            DB.exec("INSERT IGNORE INTO gov_branches (code, name, sort, status) VALUES (?, ?, ?, 'active')", b[1], b[2], b[3])
        end
        nextStep()
    end, "SELECT COUNT(*) AS n FROM gov_branches")
end

local function seedGroups(nextStep)
    local fns = {}
    for _, def in ipairs(PERMS.SEED_GROUPS) do
        fns[#fns + 1] = function(n) ensureGroup(def, function() n() end) end
    end
    chain(fns, nextStep)
end

local function migrateRoles(nextStep)
    DB.query(function(rows)
        if not rows or #rows == 0 then return nextStep() end
        local ids, fns = {}, {}
        for role, def in pairs(PERMS.LEGACY_GROUPS) do
            fns[#fns + 1] = function(n)
                ensureGroup({ code = def.code, name = def.name, kind = "system", rank = def.rank, color = "#777777",
                    description = "Members of the old /gov role " .. role .. " (migrated). Move them to real positions.",
                    grants = def.grants }, function(id) ids[role] = id; n() end)
            end
        end
        chain(fns, function()
            local now = GOV.now()
            for _, r in ipairs(rows) do
                local id = ids[tostring(r.role)]
                if id then
                    DB.exec("INSERT IGNORE INTO gov_perms_members (account_name, group_id, granted_by, granted_at, note) VALUES (?, ?, ?, ?, 'migrated role')",
                        tostring(r.account_name):lower(), id, tostring(r.granted_by or "setup"), now)
                end
            end
            nextStep()
        end)
    end, "SELECT account_name, role, granted_by FROM gov_members")
end

local ROLE_PERM = { owner = "manage", manager = "pay", viewer = "view" }

local function migrateBankAccess(nextStep)
    local bank = GOV.bank()
    if not bank then return nextStep() end
    local accounts = {}   -- [bank account id] = { target, name }
    local tid = GOV.treasuryId()
    local t = tid and bank:getAccountInfo(tid)
    if t then accounts[tid] = { target = "treasury", name = t.name } end
    for _, c in ipairs(GOV.companyList()) do
        if c.accountId then accounts[c.accountId] = { target = tostring(c.id), name = c.name } end
    end
    local ids = {}
    for id in pairs(accounts) do ids[#ids + 1] = id end
    if #ids == 0 then return nextStep() end
    local marks = {}
    for i = 1, #ids do marks[i] = "?" end
    DB.query(function(rows)
        local fns = {}
        local byGroup = {}   -- [code] = { def, accounts = {} }
        for _, r in ipairs(rows or {}) do
            local a = accounts[int(r.account_id)]
            local perm = ROLE_PERM[tostring(r.role)]
            if a and perm then
                local code = DB.clip("bank_" .. a.target .. "_" .. perm, 32)
                local grp = byGroup[code]
                if not grp then
                    local grants = { "gov." .. a.target .. ".bank." .. perm }
                    if a.target ~= "treasury" then grants[#grants + 1] = "gov." .. a.target .. ".view" end
                    grp = { def = { code = code, name = DB.clip(a.name .. " - " .. perm .. " (migrated)", 64), rank = 20,
                        color = "#777777", description = "Bank access of the account before gov_perms (migrated).",
                        grants = grants }, accounts = {} }
                    byGroup[code] = grp
                end
                grp.accounts[#grp.accounts + 1] = tostring(r.account_name):lower()
            end
        end
        for _, grp in pairs(byGroup) do
            fns[#fns + 1] = function(n)
                ensureGroup(grp.def, function(id)
                    if id then
                        for _, acc in ipairs(grp.accounts) do
                            DB.exec("INSERT IGNORE INTO gov_perms_members (account_name, group_id, granted_by, granted_at, note) VALUES (?, ?, 'setup', ?, 'migrated bank access')",
                                acc, id, GOV.now())
                        end
                    end
                    n()
                end)
            end
        end
        chain(fns, nextStep)
    end, "SELECT account_id, account_name, role FROM bank_account_access WHERE account_id IN (" .. table.concat(marks, ",") .. ")", unpack(ids))
end

--- the first start, once -> cb() (also when another instance did / does it)
function PERMS.setup(cb)
    MYSQL.query(function(res, affected)
        if res == false or tonumber(affected) ~= 1 then return cb() end
        outputDebugString("[gov_perms] first start: branches, default positions, migration of the old roles and bank access")
        chain({ seedBranches, seedGroups, migrateRoles, migrateBankAccess }, function()
            GOV.log("setup", "perm.migrate", { groups = #PERMS.SEED_GROUPS })
            cb()
        end)
    end, "INSERT IGNORE INTO gov_settings (skey, value, updated_by, updated_at) VALUES ('perms.migrated', 'true', 'gov_perms', ?)", GOV.now())
end
