if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/pages.lua
--  Requests of the admin panel pages (v_admin 3.0), the same for the
--  in-game panel and the web panel:
--
--    PAGES.register(page, { perm = <ADMIN.perms key to use the page>,
--                           perms = { [action] = <perm key> },   -- stricter actions
--                           actions = { [action] = fn(actor, args, reply) } })
--
--  `actor` is a player element or a web actor (server/core.lua). A handler
--  answers exactly once with reply(result, message): result = plain data
--  (false = failed), message = L.msg(...) or nil. Handlers may answer later
--  (MySQL / other resources), the callers wait for it.
--
--  In game: client E.pageCall (requestId, page, action, args) ->
--           E.pageReply (requestId, result, message) to that client.
--  Web:     adminWebCall / adminWebResult (server/web.lua).
--
--  REMOTE.call(resource, export, cb, ...) calls an export of another
--  resource that answers later: the export gets a request id as its first
--  argument and answers with
--      triggerEvent("v_admin:remoteResult", <v_admin resource root>, id, result)
--  (the root comes from sourceResource while the export runs).
-- ============================================================

PAGES = { defs = {} }

local E = ADMIN.events

function PAGES.register(page, def)
    def.actions = def.actions or {}
    PAGES.defs[page] = def
end

function resourceRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

--- Account name of an admin (player or web actor), or nil.
function actorAccount(actor)
    if isWebActor(actor) then return actor.account end
    if isElement(actor) and resourceRunning("v_accounts") then
        return exports.v_accounts:getName(actor) or nil
    end
end

--- trimmed string of a request argument ("" when missing)
function argText(v)
    if type(v) ~= "string" and type(v) ~= "number" then return "" end
    return (tostring(v):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- LIKE pattern matching `s` anywhere
function likeText(s) return "%" .. tostring(s):gsub("[%%_\\]", "\\%0") .. "%" end

--- The level a perm key needs (unknown key = out of reach).
function permLevel(perm)
    if not perm then return 0 end
    return ADMIN.perms[perm] or 99
end

local function denied(perm)
    return L.msg("v_admin.core.you_need_at_least_admin_level", { min_level = permLevel(perm) })
end

--- Runs one page request; done(result, message) is called exactly once.
function PAGES.run(actor, page, action, args, done)
    local def = PAGES.defs[page]
    local fn = def and def.actions[action]
    if not fn then return done(false, L.msg("v_admin.page.unknown_request")) end
    if getAdminLevel(actor) < permLevel("panel") then return done(false, denied("panel")) end
    if getAdminLevel(actor) < permLevel(def.perm) then return done(false, denied(def.perm)) end
    local need = def.perms and def.perms[action]
    if need and getAdminLevel(actor) < permLevel(need) then return done(false, denied(need)) end

    local answered = false
    local function reply(result, message)
        if answered then return end
        answered = true
        done(result == nil and true or result, message)
    end
    local ok, err = pcall(fn, actor, type(args) == "table" and args or {}, reply)
    if not ok then
        outputDebugString(("[v_admin] page %s/%s: %s"):format(tostring(page), tostring(action), tostring(err)), 1)
        reply(false, L.msg("v_admin.page.request_failed"))
    end
end

--------------------------------------------------------------------------------
-- in game
--------------------------------------------------------------------------------

local budget = {}   -- [player] = { tick, count } flood guard

addEvent(E.pageCall, true)
addEventHandler(E.pageCall, resourceRoot, function(id, page, action, args)
    local player = client
    if not player then return end
    local b = budget[player]
    local now = getTickCount()
    if not b or now - b.tick > 1000 then b = { tick = now, count = 0 }; budget[player] = b end
    b.count = b.count + 1
    if b.count > 25 then return end
    if not hasAdminLevel(player, ADMIN.perms.panel) then return end

    PAGES.run(player, tostring(page), tostring(action), args, function(result, message)
        if not isElement(player) then return end
        triggerClientEvent(player, E.pageReply, resourceRoot, id,
            L.resolveDeep(result, player), message and L.resolveFor(player, message) or false)
    end)
end)

addEventHandler("onPlayerQuit", root, function() budget[source] = nil end)

--------------------------------------------------------------------------------
-- calls to other resources that answer later
--------------------------------------------------------------------------------

REMOTE = {}

local pending, seq = {}, 0

addEvent("v_admin:remoteResult")
addEventHandler("v_admin:remoteResult", resourceRoot, function(id, result)
    local p = pending[id]
    pending[id] = nil
    if p then p.cb(result) end
end)

--- cb(result | false). Every argument after cb goes to the export after the request id.
function REMOTE.call(resName, fn, cb, ...)
    local res = getResourceFromName(resName)
    if not res or getResourceState(res) ~= "running" then return cb(false) end
    seq = seq + 1
    local id = seq
    pending[id] = { cb = cb, tick = getTickCount() }
    local ok, started = pcall(call, res, fn, id, ...)
    if not ok or not started then
        if pending[id] then
            pending[id] = nil
            if not ok then outputDebugString(("[v_admin] %s:%s failed: %s"):format(resName, fn, tostring(started)), 1) end
            cb(false)
        end
    end
end

-- answers that never come (the other resource stopped)
setTimer(function()
    local now = getTickCount()
    for id, p in pairs(pending) do
        if now - p.tick > 30000 then
            pending[id] = nil
            p.cb(false)
        end
    end
end, 10000, 0)

--------------------------------------------------------------------------------
-- page commands of other resources (/weekly, /news, /mail)
--------------------------------------------------------------------------------

for page, cmd in pairs(ADMIN.pageCommands) do
    addCommandHandler(cmd, function(player)
        local def = PAGES.defs[page]
        local need = def and def.perm or "panel"
        if not hasAdminLevel(player, permLevel(need)) then return denyAccess(player, permLevel(need)) end
        openAdminPanel(player, page)
    end)
end

for page, cmd in pairs(ADMIN.pageCommands) do
    local def = PAGES.defs[page]
    CMD.register(cmd, "", permLevel(def and def.perm or "panel"), "Open the " .. page .. " page of the admin panel")
end
