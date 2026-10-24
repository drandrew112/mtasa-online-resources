-- gov_core / server/registry.lua
-- The modules of the /gov panel. Every gov_* resource registers (registerModule, through the lib's
-- GOV.module) its setting prefixes + defaults, its panel actions with the role they need and its
-- pages (menu category, order, page script). A stopped module is dropped: its menu items go, its
-- requests fail.
--
--   page      mta.triggerEvent("gov_core:pageCall", id, action, args)
--   client    -> "gov_core:call" (requestId, action, args)
--   gov_core  role check -> triggerEvent("onGovAction", <module resourceRoot>, reqId, action, args, actor, player)
--   module    -> exports.gov_core:reply(reqId, result, err)
--   gov_core  -> "gov_core:reply" (requestId, result | false, errorKey) to the player

MODULES = {}     -- [resource name] = def
ACTIONS = {}     -- [action] = { res, need }
PAGES = {}       -- [page id] = { id, res, category, order, need, script, title }
CATEGORIES = {}  -- [id] = { id, order, key }

local NEEDS = { viewer = true, official = true, minister = true, public = true }

local function resetCategories()
    CATEGORIES = {}
    for _, c in ipairs(GOV_CATEGORIES) do CATEGORIES[c.id] = { id = c.id, order = c.order, key = "gov_core.menu." .. c.id } end
end
resetCategories()

local function unregister(resName)
    MODULES[resName] = nil
    for name, a in pairs(ACTIONS) do if a.res == resName then ACTIONS[name] = nil end end
    for id, p in pairs(PAGES) do if p.res == resName then PAGES[id] = nil end end
    for id, c in pairs(CATEGORIES) do if c.res == resName then CATEGORIES[id] = nil end end
    GOV.setDefaults(resName, {}, {})
end

function GOV.registerModule(resName, def)
    if type(def) ~= "table" then return false end
    unregister(resName)
    MODULES[resName] = def
    local s = type(def.settings) == "table" and def.settings or {}
    GOV.setDefaults(resName, s.prefixes, s.defaults)
    for name, need in pairs(type(def.actions) == "table" and def.actions or {}) do
        name = tostring(name)
        if not NEEDS[need] then
            outputDebugString(("[gov_core] %s: action %s has an unknown role %s"):format(resName, name, tostring(need)), 2)
        elseif ACTIONS[name] then
            outputDebugString(("[gov_core] %s: action %s is taken by %s"):format(resName, name, ACTIONS[name].res), 2)
        else
            ACTIONS[name] = { res = resName, need = need }
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
                PAGES[p.id] = { id = p.id, res = resName, category = cat, order = tonumber(p.order) or 100,
                    need = GOV.ROLES[p.need] and p.need or "viewer", script = p.script,
                    title = type(p.title) == "string" and p.title or (resName .. ".page." .. p.id) }
            end
        end
    end
    return true
end

--- export: a gov_* resource registers itself (the lib calls it on start and on gov_core's start)
function registerModule(def)
    local res = sourceResource and getResourceName(sourceResource)
    if not res then return false end
    return GOV.registerModule(res, def)
end

--- the pages + categories a role sees (running modules only), for the client
function GOV.menuFor(role)
    local level = GOV.ROLES[role] or 0
    local pages, used = {}, {}
    for _, p in pairs(PAGES) do
        if level >= GOV.ROLES[p.need] and (p.res == "gov_core" or isResourceRunning(p.res)) then
            pages[#pages + 1] = { id = p.id, res = p.res, category = p.category, order = p.order, need = p.need,
                script = p.script, title = p.title }
            used[p.category] = true
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

addEvent("gov_core:call", true)
addEventHandler("gov_core:call", resourceRoot, function(requestId, action, args)
    local player = client
    if not isElement(player) then return end
    local function fail(err)
        triggerClientEvent(player, "gov_core:reply", resourceRoot, requestId, false, err)
    end
    local a = ACTIONS[tostring(action)]
    if not a then return fail("gov_core.err.unknown") end
    if not GOV.ready then return fail("v_bank.error.unavailable") end
    if a.need == "public" then
        if not GOV.accountOf(player) then return fail("gov_core.err.no_right") end
    elseif not GOV.can(player, a.need) then
        return fail("gov_core.err.no_right")
    end
    local res = getResourceFromName(a.res)
    if not res or getResourceState(res) ~= "running" then return fail("gov_core.err.module_offline") end
    seq = seq + 1
    pending[seq] = { player = player, req = requestId, res = a.res, t = getTickCount() }
    triggerEvent("onGovAction", getResourceRootElement(res), seq, tostring(action),
        type(args) == "table" and args or {}, GOV.accountOf(player) or "?", player)
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
