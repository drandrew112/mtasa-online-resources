-- gov_core / server/registry.lua
-- The modules of the /gov panel. Every gov_* resource registers (registerModule, through the lib's
-- GOV.module) its setting prefixes + defaults, its permissions (static keys + generated families),
-- its panel actions with the permission they need and its pages (menu category, order, page
-- script). A stopped module is dropped: its menu items go, its requests fail.
--
--   page      mta.triggerEvent("gov_core:pageCall", id, action, args)
--   client    -> "gov_core:call" (requestId, action, args)
--   gov_core  permission check -> triggerEvent("onGovAction", <module resourceRoot>, reqId, action, args, actor, player)
--   module    -> exports.gov_core:reply(reqId, result, err)
--   gov_core  -> "gov_core:reply" (requestId, result | false, errorKey) to the player
--
-- Permissions live in gov_perms (positions, their rights, appointments). gov_core asks it; while
-- gov_perms does not run only admins get in (fail closed). Admins (GOV.ADMIN_LEVEL) may do
-- everything. A sector (a public service run by a company) gives the people of that company the
-- sector's own permissions without a position.

MODULES = {}     -- [resource name] = def
ACTIONS = {}     -- [action] = { res, need = { public | panel | perm, arg } }
PAGES = {}       -- [page id] = { id, res, category, order, needs = { key, ... }, script, title }
CATEGORIES = {}  -- [id] = { id, order, key }
SECTORS = {}     -- [id] = { id, res, setting, perms = { key, ... } }
TARGETS = {}     -- [family prefix] = { res, list = { {id, name}, ... } }

local LEGACY = { viewer = true, official = true, minister = true }

addEvent("onGovModulesChanged", false)   -- source = gov_core resourceRoot (gov_perms rebuilds its catalogue)

local changeTimer
local function modulesChanged()
    if isTimer(changeTimer) then killTimer(changeTimer) end
    changeTimer = setTimer(function() triggerEvent("onGovModulesChanged", resourceRoot) end, 1000, 1)
end

local function resetCategories()
    CATEGORIES = {}
    for _, c in ipairs(GOV_CATEGORIES) do CATEGORIES[c.id] = { id = c.id, order = c.order, key = "gov_core.menu." .. c.id } end
end
resetCategories()

--- the need of an action -> { public = true } | { panel = true } | { perm, arg } | nil
--- (an old role string means the legacy.<role> permission)
local function parseNeed(need)
    if type(need) == "table" then
        if type(need.perm) == "string" then
            return { perm = need.perm, arg = type(need.arg) == "string" and need.arg or nil }
        end
        if LEGACY[need.role] then return { perm = "legacy." .. need.role } end
        return nil
    end
    if need == "public" then return { public = true } end
    if need == "panel" then return { panel = true } end
    if LEGACY[need] then return { perm = "legacy." .. need } end
    if type(need) == "string" and need:match("^[%w_%.%*]+$") then return { perm = need } end
end

local function unregister(resName)
    MODULES[resName] = nil
    for name, a in pairs(ACTIONS) do if a.res == resName then ACTIONS[name] = nil end end
    for id, p in pairs(PAGES) do if p.res == resName then PAGES[id] = nil end end
    for id, c in pairs(CATEGORIES) do if c.res == resName then CATEGORIES[id] = nil end end
    for id, sc in pairs(SECTORS) do if sc.res == resName then SECTORS[id] = nil end end
    for prefix, t in pairs(TARGETS) do if t.res == resName then TARGETS[prefix] = nil end end
    GOV.setDefaults(resName, {}, {})
    modulesChanged()
end

function GOV.registerModule(resName, def)
    if type(def) ~= "table" then return false end
    unregister(resName)
    MODULES[resName] = def
    local s = type(def.settings) == "table" and def.settings or {}
    GOV.setDefaults(resName, s.prefixes, s.defaults)
    for _, sc in ipairs(type(def.sectors) == "table" and def.sectors or {}) do
        if type(sc) == "table" and type(sc.id) == "string" and type(sc.setting) == "string" then
            SECTORS[sc.id] = { id = sc.id, res = resName, setting = sc.setting, perms = type(sc.perms) == "table" and sc.perms or {} }
        end
    end
    for name, need in pairs(type(def.actions) == "table" and def.actions or {}) do
        name = tostring(name)
        local parsed = parseNeed(need)
        if not parsed then
            outputDebugString(("[gov_core] %s: action %s has an unknown need %s"):format(resName, name, tostring(need)), 2)
        elseif ACTIONS[name] then
            outputDebugString(("[gov_core] %s: action %s is taken by %s"):format(resName, name, ACTIONS[name].res), 2)
        else
            ACTIONS[name] = { res = resName, need = parsed }
        end
    end
    for _, c in ipairs(type(def.categories) == "table" and def.categories or {}) do
        if type(c) == "table" and type(c.id) == "string" and not CATEGORIES[c.id] then
            CATEGORIES[c.id] = { id = c.id, order = tonumber(c.order) or 500, key = resName .. ".menu." .. c.id, res = resName }
        end
    end
    for _, p in ipairs(type(def.pages) == "table" and def.pages or {}) do
        if type(p) == "table" and type(p.id) == "string" and type(p.script) == "string" then
            if PAGES[p.id] then
                outputDebugString(("[gov_core] %s: page %s is taken by %s"):format(resName, p.id, PAGES[p.id].res), 2)
            else
                local cat = tostring(p.category or "other")
                if not CATEGORIES[cat] then
                    outputDebugString(("[gov_core] %s: page %s has an unknown category %s (shown under other)"):format(resName, p.id, cat), 2)
                    cat = "other"
                end
                -- need: a key / family, a list of them (any), an old role, or none = the page's own action
                local needs = {}
                local list = type(p.need) == "table" and p.need or { p.need }
                for _, n in ipairs(list) do
                    local parsed = parseNeed(n)
                    if parsed and parsed.perm then needs[#needs + 1] = parsed.perm end
                end
                if #needs == 0 then
                    local a = ACTIONS[p.id]
                    if a and a.need.perm and not a.need.arg then needs[1] = a.need.perm end
                end
                PAGES[p.id] = { id = p.id, res = resName, category = cat, order = tonumber(p.order) or 100,
                    needs = needs, script = p.script,
                    title = type(p.title) == "string" and p.title or (resName .. ".page." .. p.id) }
            end
        end
    end
    modulesChanged()
    return true
end

--- export: a gov_* resource registers itself (the lib calls it on start and on gov_core's start)
function registerModule(def)
    local res = sourceResource and getResourceName(sourceResource)
    if not res then return false end
    return GOV.registerModule(res, def)
end

local function storeTargets(res, prefix, list)
    prefix = tostring(prefix or "")
    if not prefix:match("^[%w_]+$") then return false end
    local clean = {}
    for _, t in ipairs(type(list) == "table" and list or {}) do
        local id = type(t) == "table" and tostring(t.id or "") or ""
        if id:match("^[%w_]+$") then clean[#clean + 1] = { id = id, name = tostring(t.name or id) } end
    end
    local old = TARGETS[prefix]
    if old and old.res ~= res then
        outputDebugString(("[gov_core] %s: target prefix %s is taken by %s"):format(res, prefix, old.res), 2)
        return false
    end
    if old and toJSON(old.list) == toJSON(clean) then return true end
    TARGETS[prefix] = { res = res, list = clean }
    modulesChanged()
    return true
end

--- export: the targets of a module's generated permissions (lib GOV.setTargets)
function setGovTargets(prefix, list)
    local res = sourceResource and getResourceName(sourceResource)
    if not res then return false end
    return storeTargets(res, prefix, list)
end

--- gov_core's own targets (the gov.* families: treasury + state companies)
function GOV.setTargets(prefix, list) return storeTargets("gov_core", prefix, list) end

--- export (gov_perms): every running module's permissions and the target lists
function getGovPermDefs()
    local modules = {}
    for res, def in pairs(MODULES) do
        if res == "gov_core" or isResourceRunning(res) then
            modules[res] = { perms = type(def.perms) == "table" and def.perms or {},
                families = type(def.families) == "table" and def.families or {} }
        end
    end
    local targets = {}
    for prefix, t in pairs(TARGETS) do targets[prefix] = t.list end
    return { modules = modules, targets = targets }
end

--------------------------------------------------------------------------------
-- permission checks
--------------------------------------------------------------------------------

function GOV.isAdmin(player)
    if not GOV.accountOf(player) then return false end
    local level = isResourceRunning("v_mysql") and tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    return level >= GOV.ADMIN_LEVEL
end

--- gov_perms when it runs and has loaded its data
function GOV.perms()
    if not isResourceRunning("gov_perms") then return nil end
    local p = exports.gov_perms
    return p:isGovPermsReady() == true and p or nil
end

--- the sector permissions a player has through the company of a sector: { key, ... }
local function sectorPerms(player)
    local out = {}
    for id, sc in pairs(SECTORS) do
        if #sc.perms > 0 and GOV.inSector(player, id) then
            for _, k in ipairs(sc.perms) do out[#out + 1] = k end
        end
    end
    return out
end

--- may the player do this (a key, or a family "x.*.y": any target of it)?
function GOV.hasPerm(player, key)
    key = tostring(key or "")
    if GOV.isAdmin(player) then return true end
    local acc = GOV.accountOf(player)
    if not acc then return false end
    local p = GOV.perms()
    if p then
        if key:find("*", 1, true) then
            local t = p:getGovPermTargets(acc, key)
            if type(t) == "table" and next(t) then return true end
        elseif p:hasGovPerm(acc, key) then
            return true
        end
    end
    for _, k in ipairs(sectorPerms(player)) do
        if GOV.permMatch(k, key) or (key:find("*", 1, true) and GOV.permMatch(key, k)) then return true end
    end
    return false
end

--- the targets of a family a player reaches: { all = true } | { [target] = true }
function GOV.permTargets(player, family)
    if GOV.isAdmin(player) then return { all = true } end
    local acc = GOV.accountOf(player)
    local p = acc and GOV.perms()
    local t = p and p:getGovPermTargets(acc, tostring(family or "")) or {}
    return type(t) == "table" and t or {}
end

--- may the player open /gov at all? (an admin, any right, or the company of a sector)
function GOV.hasPanel(player)
    if GOV.isAdmin(player) then return true end
    local acc = GOV.accountOf(player)
    if not acc then return false end
    local p = GOV.perms()
    if p and p:hasAnyGovPerm(acc) then return true end
    return next(GOV.sectorsOf(player)) ~= nil
end

--- what the page needs to hide buttons: { super, title, grants = { {perm, branch} }, branchOf = { [company id] = branch } }
function GOV.accessOf(player)
    local branchOf = {}
    for _, c in ipairs(GOV.companyList()) do branchOf[tostring(c.id)] = c.branch end
    local out = { super = false, title = "", grants = {}, branchOf = branchOf }
    if GOV.isAdmin(player) then
        out.super, out.title = true, "admin"
        return out
    end
    local acc = GOV.accountOf(player)
    local p = acc and GOV.perms()
    local info = p and p:getGovGrants(acc)
    if type(info) == "table" then
        out.super = info.super == true
        out.title = tostring(info.title or "")
        for _, g in ipairs(type(info.grants) == "table" and info.grants or {}) do out.grants[#out.grants + 1] = g end
    end
    for _, k in ipairs(sectorPerms(player)) do out.grants[#out.grants + 1] = { perm = k, branch = "" } end
    if out.title == "" and next(GOV.sectorsOf(player)) then out.title = "sector" end
    return out
end

--- exports for the modules (lib GOV.has / GOV.targets) and other resources
function hasGovPerm(player, key) return GOV.hasPerm(player, key) end
function getGovPermTargets(player, family) return GOV.permTargets(player, family) end

-- gov_core's own copy of the lib asks itself directly
GOV.has = GOV.hasPerm
GOV.targets = GOV.permTargets

--- legacy exports (the old roles = the legacy.<role> permissions of gov_perms):
--- "viewer" | "official" | "minister" | false
function getGovRole(player)
    if GOV.isAdmin(player) then return "minister" end
    for _, r in ipairs({ "minister", "official", "viewer" }) do
        if GOV.hasPerm(player, "legacy." .. r) then return r end
    end
    return false
end

function canGov(player, need)
    if not LEGACY[need] then return false end
    return GOV.hasPerm(player, "legacy." .. need)
end

--- the pages + categories a player sees (running modules only), for the client
function GOV.menuFor(player)
    local pages, used = {}, {}
    for _, p in pairs(PAGES) do
        if p.res == "gov_core" or isResourceRunning(p.res) then
            local ok = #p.needs == 0 and GOV.hasPanel(player)
            for _, n in ipairs(p.needs) do
                if ok then break end
                ok = GOV.hasPerm(player, n)
            end
            if ok then
                pages[#pages + 1] = { id = p.id, res = p.res, category = p.category, order = p.order,
                    script = p.script, title = p.title }
                used[p.category] = true
            end
        end
    end
    table.sort(pages, function(a, b)
        local ca, cb = CATEGORIES[a.category], CATEGORIES[b.category]
        if ca.order ~= cb.order then return ca.order < cb.order end
        if a.order ~= b.order then return a.order < b.order end
        return a.id < b.id
    end)
    local cats = {}
    for id, c in pairs(CATEGORIES) do
        if used[id] then cats[#cats + 1] = { id = c.id, order = c.order, key = c.key } end
    end
    table.sort(cats, function(a, b) return a.order < b.order end)
    return pages, cats
end

--------------------------------------------------------------------------------
-- requests
--------------------------------------------------------------------------------

local pending, seq = {}, 0   -- [reqId] = { player, req, res, t }

--- the key an action needs for these args ("gov.{id}.edit" + { id = 12 } -> "gov.12.edit"), or nil
local function neededKey(need, args)
    if not need.arg then return need.perm end
    local v = tostring(args[need.arg] or "")
    if not v:match("^[%w_]+$") then return nil end
    return (need.perm:gsub("{" .. need.arg .. "}", v))
end

addEvent("gov_core:call", true)
addEventHandler("gov_core:call", resourceRoot, function(requestId, action, args)
    local player = client
    if not isElement(player) then return end
    args = type(args) == "table" and args or {}
    local function fail(err)
        triggerClientEvent(player, "gov_core:reply", resourceRoot, requestId, false, err)
    end
    local a = ACTIONS[tostring(action)]
    if not a then return fail("gov_core.err.unknown") end
    if not GOV.ready then return fail("v_bank.error.unavailable") end
    local need = a.need
    if need.public then
        if not GOV.accountOf(player) then return fail("gov_core.err.no_right") end
    elseif need.panel then
        if not GOV.hasPanel(player) then return fail("gov_core.err.no_right") end
    else
        local key = neededKey(need, args)
        if not key or not GOV.hasPerm(player, key) then return fail("gov_core.err.no_right") end
    end
    local res = getResourceFromName(a.res)
    if not res or getResourceState(res) ~= "running" then return fail("gov_core.err.module_offline") end
    seq = seq + 1
    pending[seq] = { player = player, req = requestId, res = a.res, t = getTickCount() }
    triggerEvent("onGovAction", getResourceRootElement(res), seq, tostring(action), args, GOV.accountOf(player) or "?", player)
end)

--- export: the answer of a module -> true | false (unknown / timed out request)
function reply(reqId, result, err)
    local p = pending[reqId]
    if not p then return false end
    pending[reqId] = nil
    if isElement(p.player) then
        triggerClientEvent(p.player, "gov_core:reply", resourceRoot, p.req, result, result == false and (err or "gov_core.err.unknown") or nil)
    end
    return true
end

local function failPending(match, err)
    for id, p in pairs(pending) do
        if match(p) then
            pending[id] = nil
            if isElement(p.player) then triggerClientEvent(p.player, "gov_core:reply", resourceRoot, p.req, false, err) end
        end
    end
end

setTimer(function()
    local now = getTickCount()
    failPending(function(p) return now - p.t > GOV.REQUEST_TIMEOUT end, "gov_core.err.unknown")
end, 10000, 0)

addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    if res == getThisResource() or not MODULES[name] then return end
    unregister(name)
    failPending(function(p) return p.res == name end, "gov_core.err.module_offline")
end)

function isGovReady() return GOV.ready == true end

--------------------------------------------------------------------------------
-- sectors: a public service (gov_railways: the railway) run by a company the minister picks.
-- The module keeps the company in its own setting ("state:<code>" | "company:<id>", anything
-- else = nobody); everyone with bank access to that company's account (for a state company:
-- the gov.<id>.bank.* rights of gov_perms; for a private one: its founder / managers) gets the
-- sector's permissions (sectors[].perms) without a position.
--------------------------------------------------------------------------------

function GOV.inSector(player, sector)
    local sc = SECTORS[tostring(sector)]
    if not sc or not isResourceRunning(sc.res) or not GOV.accountOf(player) then return false end
    local spec = GOV.get(sc.setting)
    if type(spec) ~= "string" or not (spec:match("^state:") or spec:match("^company:")) then return false end
    local id = tonumber(GOV.specAccount(spec))
    local bank = GOV.bank()
    if bank and id and bank:hasAccess(player, id, "view") then return true end
    -- a private company's founder, also before the company account had its access rows
    local cid = tonumber(spec:match("^company:(%d+)$"))
    if cid and isResourceRunning("biz_core") then
        local ok, mine = pcall(function() return exports.biz_core:getPlayerCompanyId(player) end)
        return ok and tonumber(mine) == cid or false
    end
    return false
end

--- { [sector id] = true } of the sectors a player runs
function GOV.sectorsOf(player)
    local out = {}
    for id in pairs(SECTORS) do
        if GOV.inSector(player, id) then out[id] = true end
    end
    return out
end

--- export: is the player a member of the company that runs this sector?
function isGovSectorMember(player, sector) return GOV.inSector(player, sector) end
