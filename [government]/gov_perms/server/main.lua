-- gov_perms / server/main.lua
-- Start: schema -> wait for gov_core + v_bank -> first start (setup.lua, once) -> catalogue ->
-- groups / appointments / branches -> ready. Every RESYNC_MS: re-read, expired appointments,
-- salary stats, bank access sync. The exports at the bottom (gov_core asks them for every check).

addEvent("onGovAppointed", false)   -- (account, group code), source = gov_perms resourceRoot
addEvent("onGovDismissed", false)   -- (account, group code)

PERMS.ready = false

local function whenReady(cb)
    local bank = GOV.bank()
    if GOV.coreReady() and bank and bank:isBankReady() == true then return cb() end
    setTimer(whenReady, 2000, 1, cb)
end

addEventHandler("onResourceStart", resourceRoot, function()
    DB.start(PERMS.SCHEMA, function()
        whenReady(function()
            PERMS.setup(function()
                PERMS.rebuildCatalogue()
                PERMS.loadAll(function()
                    PERMS.loadSalaryStats()
                    PERMS.ready = true
                    PERMS.changed(false)
                    outputDebugString("[gov_perms] ready")
                end)
            end)
        end)
        setTimer(function()
            if not PERMS.ready then return end
            PERMS.loadAll(function()
                PERMS.expire()
                PERMS.loadSalaryStats()
                PERMS.syncBank()
            end)
        end, PERMS.RESYNC_MS, 0)
    end)
end)

-- gov_core restarted: it asks the modules again; the catalogue follows (onGovModulesChanged)

--------------------------------------------------------------------------------
-- exports (gov_core: every permission check; other resources)
--------------------------------------------------------------------------------

local function accountOf(who)
    if isElement(who) then return GOV.accountOf(who) end
    return type(who) == "string" and who ~= "" and who:lower() or nil
end

function isGovPermsReady() return PERMS.ready == true end

--- account (or player) has the key? (positions only; gov_core adds admins + sectors)
function hasGovPerm(who, key)
    local acc = accountOf(who)
    return acc and PERMS.ready and PERMS.has(acc, tostring(key or "")) or false
end

--- { all = true } | { [target] = true }
function getGovPermTargets(who, family)
    local acc = accountOf(who)
    if not acc or not PERMS.ready then return {} end
    return PERMS.targets(acc, family)
end

--- has the account any right at all?
function hasAnyGovPerm(who)
    local acc = accountOf(who)
    return acc and PERMS.ready and #PERMS.effective(acc) > 0 or false
end

--- for the /gov page: { super, title = highest position name, grants = { {perm, branch} } }
function getGovGrants(who)
    local acc = accountOf(who)
    if not acc or not PERMS.ready then return { super = false, title = "", grants = {} } end
    local groups = PERMS.groupsOf(acc)
    local grants = {}
    for _, g in ipairs(PERMS.effective(acc)) do grants[#grants + 1] = { perm = g.perm, branch = g.branch } end
    return { super = PERMS.isSuper(acc), title = groups[1] and groups[1].name or "", grants = grants }
end

--- { { id, code, name, rank, salary, expiresAt }, ... } of an account
function getGovPositions(account)
    local out = {}
    local acc = accountOf(account)
    if not acc then return out end
    local now = GOV.now()
    for _, m in pairs(MEMBERS) do
        local g = GROUPS[m.groupId]
        if m.account == acc and g and g.status == "active" and (m.expiresAt == 0 or m.expiresAt > now) then
            out[#out + 1] = { id = g.id, code = g.code, name = g.name, rank = g.rank, salary = g.salary, expiresAt = m.expiresAt }
        end
    end
    table.sort(out, function(a, b) return a.rank > b.rank end)
    return out
end

function getGovPermCatalogue()
    local out = {}
    for _, r in pairs(CATALOGUE) do out[#out + 1] = r end
    table.sort(out, function(a, b) return a.perm < b.perm end)
    return out
end

--- the active branches: { {code, name}, ... }
function getGovBranches()
    local out = {}
    for _, b in ipairs(BRANCHES) do
        if b.status == "active" then out[#out + 1] = { code = b.code, name = b.name } end
    end
    return out
end

function isGovSuper(who)
    local acc = accountOf(who)
    return acc and PERMS.ready and PERMS.isSuper(acc) or false
end

--- automation (the election system later): only resources in PERMS.AUTOMATION
local function automationCaller()
    local res = sourceResource and getResourceName(sourceResource)
    return res and PERMS.AUTOMATION[res] and res or nil
end

--- -> true | false, err
function appointGov(account, groupCode, expiresAt, actor)
    local res = automationCaller()
    if not res or not PERMS.ready then return false, "no_right" end
    local g = PERMS.groupByCode(tostring(groupCode))
    if not g or g.status ~= "active" then return false, "bad_group" end
    PERMS.appoint(tostring(account), g, math.max(0, math.floor(tonumber(expiresAt) or 0)), "", tostring(actor or res), function() end)
    return true
end

function dismissGov(account, groupCode, actor)
    local res = automationCaller()
    if not res or not PERMS.ready then return false, "no_right" end
    local g = PERMS.groupByCode(tostring(groupCode))
    if not g then return false, "bad_group" end
    local acc = tostring(account or ""):lower()
    for _, m in pairs(MEMBERS) do
        if m.account == acc and m.groupId == g.id then PERMS.dismiss(m, tostring(actor or res), "dismiss") end
    end
    return true
end
