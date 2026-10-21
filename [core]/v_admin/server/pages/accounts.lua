if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- ============================================================
--  v_admin / server/pages/accounts.lua
--  Accounts page: every account (MySQL `accounts`), filtered, sorted and
--  paged here; the client only gets one page. The list is read in one go
--  (a few account_data keys through JSON_EXTRACT) and kept for
--  ADMIN.accounts.cacheTime seconds; online players' values are live.
--
--  list    { search, admin, status, registered, email, updates, conds = { { key, op, value } },
--            sort, dir, page, refresh } -> { rows, total, page, pages, now, cachedAt }
--  detail  { name }        -> the account's Overview data
--  tab     { name, tab }   -> stats | vehicles | mails | punishments | achievements | inventory | social
--  mail    { id }          -> one mail's text
--  edit    { name, what, ... } -> setlevel | money | level | xp | workxp | note | delnote |
--                                 vehgive | vehdelete | vehrestore | achgive | achreset |
--                                 ban | unban | unmute
-- ============================================================

local ACC = ADMIN.accounts

local cache = { rows = nil, tick = 0, at = 0, loading = nil }

local function now() return getRealTime().timestamp end

local function strip(s) return (tostring(s or ""):gsub("#%x%x%x%x%x%x", "")) end

--- text for the actor (message objects resolved: web = English, player = their language)
local function txt(actor, x)
    return strip(L.resolveFor(isWebActor(actor) and "en" or actor, x))
end

local function lower(s) return utf8.lower and utf8.lower(tostring(s or "")) or tostring(s or ""):lower() end

local function sameName(a, b) return a and b and tostring(a):lower() == tostring(b):lower() end

local function playerOfAccount(name)
    if not resourceRunning("acc_auth") then return nil end
    for _, p in ipairs(getElementsByType("player")) do
        if sameName(exports.acc_auth:getName(p), name) then return p end
    end
end

--- "jo•••@gmail.com" below ADMIN.perms.fullEmail
local function showEmail(actor, email)
    if type(email) ~= "string" or email == "" then return false end
    if getAdminLevel(actor) >= permLevel("fullEmail") then return email end
    local user, domain = email:match("^([^@]*)@(.*)$")
    if not user then return "•••" end
    return utf8.sub(user, 1, 2) .. "•••@" .. domain
end

-- JSON value of one account_data key (both stored shapes, see v_mysql accdata.lua)
local function jsonKey(key)
    local k = '"' .. key .. '"'
    return ("(CASE WHEN JSON_VALID(account_data) THEN COALESCE("
        .. "JSON_UNQUOTE(JSON_EXTRACT(account_data, '$.%s.v')), "
        .. "JSON_UNQUOTE(JSON_EXTRACT(account_data, '$.%s[0].v')), "
        .. "JSON_UNQUOTE(JSON_EXTRACT(account_data, '$[0].%s.v'))) END)"):format(k, k, k)
end

local LIST_SQL = "SELECT id, account_name, email, display_name, admin_level, created_at, updated_at, "
    .. jsonKey("money-BETA") .. " AS money, "
    .. jsonKey("level") .. " AS level, "
    .. jsonKey("xp") .. " AS xp, "
    .. jsonKey("Online.hours") .. " AS hours, "
    .. jsonKey("Online.minutes") .. " AS minutes, "
    .. jsonKey("last_login") .. " AS last_login, "
    .. jsonKey("receiveUpdateMails") .. " AS upd "
    .. "FROM `accounts`"

--------------------------------------------------------------------------------
-- the list (cache)
--------------------------------------------------------------------------------

local function loadList(cb)
    if cache.loading then
        cache.loading[#cache.loading + 1] = cb
        return
    end
    cache.loading = { cb }
    local function finish(ok)
        local waiting = cache.loading
        cache.loading = nil
        for _, f in ipairs(waiting) do f(ok) end
    end
    MYSQL.query(function(rows)
        if not rows then return finish(false) end
        local list, byName = {}, {}
        for _, r in ipairs(rows) do
            local name = r.account_name
            if type(name) == "string" then
                local e = {
                    id = tonumber(r.id) or 0, name = name, display = r.display_name or false,
                    email = type(r.email) == "string" and r.email ~= "" and r.email or false,
                    adminLevel = tonumber(r.admin_level) or 0,
                    created = tonumber(r.created_at) or 0, updated = tonumber(r.updated_at) or 0,
                    money = tonumber(r.money) or 0, level = tonumber(r.level) or 0, xp = tonumber(r.xp) or 0,
                    playtime = (tonumber(r.hours) or 0) * 60 + (tonumber(r.minutes) or 0),
                    lastLogin = tonumber(r.last_login) or tonumber(r.updated_at) or 0,
                    updates = r.upd ~= "false",
                    vehicles = 0, banned = false,
                }
                list[#list + 1] = e
                byName[name:lower()] = e
            end
        end
        -- owned vehicles + active bans (separate: a missing table must not break the list)
        MYSQL.query(function(vrows)
            for _, v in ipairs(vrows or {}) do
                local e = byName[tostring(v.account_name or ""):lower()]
                if e then e.vehicles = tonumber(v.n) or 0 end
            end
            MYSQL.query(function(brows)
                for _, b in ipairs(brows or {}) do
                    local e = byName[tostring(b.account_name or ""):lower()]
                    if e then e.banned = true end
                end
                cache.rows, cache.byName, cache.tick, cache.at = list, byName, getTickCount(), now()
                finish(true)
            end, "SELECT DISTINCT account_name FROM `bans` WHERE lifted_at = 0 AND account_name IS NOT NULL")
        end, "SELECT account_name, COUNT(*) AS n FROM `vehicles` WHERE isDestroyed = 0 GROUP BY account_name")
    end, LIST_SQL)
end

local function withList(refresh, cb)
    if cache.rows and not refresh and getTickCount() - cache.tick < ACC.cacheTime * 1000 then return cb(true) end
    loadList(cb)
end

--- Forget the cached list (after an edit).
local function dirty() cache.tick = 0 end

-- live values of online players
local function onlineInfo()
    local out = {}
    if not resourceRunning("acc_auth") then return out end
    local t = now()
    for _, p in ipairs(getElementsByType("player")) do
        local name = exports.acc_auth:getName(p)
        if name then
            local muteUntil = tonumber(getElementData(p, "mute_until"))
            out[name:lower()] = {
                id = tonumber(getElementData(p, "ID")) or 0,
                money = getPlayerMoney(p),
                level = tonumber(getElementData(p, "level")),
                xp = tonumber(getElementData(p, "xp")),
                muted = muteUntil and muteUntil > t or false,
                jailed = getElementData(p, "adminjail") and true or false,
            }
        end
    end
    return out
end

local NUMERIC = { money = true, level = true, xp = true, playtime = true, vehicles = true, adminLevel = true, id = true }

local function compare(a, op, b)
    if op == ">=" then return a >= b end
    if op == "<=" then return a <= b end
    if op == "=" then return a == b end
    if op == ">" then return a > b end
    if op == "<" then return a < b end
    return true
end

local function buildRows(actor, args)
    local online = onlineInfo()
    local t = now()
    local search = lower(argText(args.search))
    local admin = args.admin
    local status = args.status
    local regDays = tonumber(args.registered)
    local email, updates = args.email, args.updates
    local conds = type(args.conds) == "table" and args.conds or {}

    local out = {}
    for _, e in ipairs(cache.rows) do
        local o = online[e.name:lower()]
        local r = {
            id = e.id, name = e.name, display = e.display, adminLevel = e.adminLevel, created = e.created,
            money = o and o.money or e.money, level = o and o.level or e.level, xp = o and o.xp or e.xp,
            playtime = e.playtime, vehicles = e.vehicles, lastLogin = o and t or e.lastLogin,
            online = o and o.id or false, banned = e.banned, muted = o and o.muted or false, jailed = o and o.jailed or false,
            hasEmail = e.email and true or false, updates = e.updates,
        }
        local keep = true
        if search ~= "" then
            keep = lower(e.name):find(search, 1, true) or (e.display and lower(e.display):find(search, 1, true))
                or (e.email and lower(e.email):find(search, 1, true)) or tostring(e.id) == search
        end
        if keep and admin == "admins" then keep = e.adminLevel > 0
        elseif keep and tonumber(admin) then keep = e.adminLevel == tonumber(admin) end
        if keep and status and status ~= "any" then
            if status == "online" then keep = r.online and true
            elseif status == "offline" then keep = not r.online
            elseif status == "banned" then keep = r.banned
            elseif status == "muted" then keep = r.muted
            elseif status == "jailed" then keep = r.jailed end
        end
        if keep and regDays then keep = e.created >= t - regDays * 86400 end
        if keep and email == "yes" then keep = r.hasEmail elseif keep and email == "no" then keep = not r.hasEmail end
        if keep and updates == "yes" then keep = r.hasEmail and r.updates elseif keep and updates == "no" then keep = not r.updates end
        if keep then
            for _, c in ipairs(conds) do
                if type(c) == "table" and NUMERIC[c.key] and tonumber(c.value) then
                    local v = c.key == "playtime" and r.playtime / 60 or r[c.key]
                    if not compare(tonumber(v) or 0, c.op, tonumber(c.value)) then keep = false break end
                end
            end
        end
        if keep then out[#out + 1] = r end
    end

    local key = args.sort
    if not (NUMERIC[key] or key == "name" or key == "lastLogin" or key == "created" or key == "display") then key = "name" end
    local desc = args.dir ~= "asc"
    if key == "name" or key == "display" then desc = args.dir == "desc" end
    table.sort(out, function(a, b)
        local x, y = a[key], b[key]
        if key == "name" or key == "display" then x, y = lower(x or ""), lower(y or "") else x, y = tonumber(x) or 0, tonumber(y) or 0 end
        if x == y then return a.name:lower() < b.name:lower() end
        if desc then return x > y end
        return x < y
    end)
    return out
end

--------------------------------------------------------------------------------
-- details
--------------------------------------------------------------------------------

-- account_data JSON -> { key = value } (same shapes as v_mysql)
local function decodeData(json)
    local obj = type(json) == "string" and fromJSON(json) or nil
    local out = {}
    if type(obj) == "table" and type(obj[1]) == "table" and obj[1].v == nil and #obj == 1 then obj = obj[1] end
    if type(obj) ~= "table" then return out end
    for key, rec in pairs(obj) do
        if type(rec) == "table" and rec.v == nil and type(rec[1]) == "table" then rec = rec[1] end
        if type(rec) == "table" and rec.v ~= nil then
            local v = rec.v
            if rec.t == "int" or rec.t == "float" then v = tonumber(v) elseif rec.t == "boolean" then v = v == "true" end
            out[key] = v
        end
    end
    return out
end

local function notesOf(data)
    local list = type(data[ACC.notesKey]) == "string" and fromJSON(data[ACC.notesKey]) or nil
    return type(list) == "table" and list or {}
end

local function fetchAccount(name, cb)
    MYSQL.query(function(rows)
        cb(rows and rows[1] or nil, rows ~= false and rows ~= nil)
    end, "SELECT id, account_name, email, display_name, admin_level, created_at, updated_at, account_data FROM `accounts` WHERE account_name = ? LIMIT 1", name)
end

local function workLevels(actor, name)
    if not resourceRunning("work_core") then return {} end
    local ok, t = pcall(function() return exports.work_core:getAccountWorkLevels(name) end)
    local out = {}
    for id, w in pairs(ok and type(t) == "table" and t or {}) do
        out[#out + 1] = { id = id, name = txt(actor, w.name), level = w.level, xp = w.xp, maxLevel = w.maxLevel }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function detail(actor, name, reply)
    fetchAccount(name, function(row, ok)
        if not ok then return reply(false, L.msg("v_admin.page.database_error")) end
        if not row then return reply(false, L.msg("v_admin.page.no_such_account")) end
        local data = decodeData(row.account_data)
        local acc = row.account_name
        local player = playerOfAccount(acc)
        local d = {
            id = tonumber(row.id), name = acc, display = row.display_name or false,
            email = showEmail(actor, row.email), hasEmail = type(row.email) == "string" and row.email ~= "",
            adminLevel = tonumber(row.admin_level) or 0, created = tonumber(row.created_at) or 0,
            updated = tonumber(row.updated_at) or 0,
            money = tonumber(data["money-BETA"]) or 0, level = tonumber(data.level) or 0, xp = tonumber(data.xp) or 0,
            playtime = (tonumber(data["Online.hours"]) or 0) * 60 + (tonumber(data["Online.minutes"]) or 0),
            lastLogin = tonumber(data.last_login) or false, lastSerial = data.last_serial or false, lastIp = data.last_ip or false,
            updates = data.receiveUpdateMails ~= false, skin = tonumber(data.skin) or false,
            language = data["locale.language"] or false,
            works = workLevels(actor, acc), notes = notesOf(data), now = now(),
            online = false,
        }
        if player then
            local muteUntil = tonumber(getElementData(player, "mute_until"))
            d.online = tonumber(getElementData(player, "ID")) or 0
            d.money = getPlayerMoney(player)
            d.level = tonumber(getElementData(player, "level")) or d.level
            d.xp = tonumber(getElementData(player, "xp")) or d.xp
            d.lastSerial, d.lastIp = getPlayerSerial(player), getPlayerIP(player)
            d.muted = muteUntil and muteUntil > now() or false
            d.jailed = getElementData(player, "adminjail") and true or false
            d.playtimeText = getElementData(player, "Játékidő") or false
        end
        if resourceRunning("v_achievements") then
            local ok2, s = pcall(function() return exports.v_achievements:getPlayerAchievementSummary(acc) end)
            if ok2 and type(s) == "table" then d.achievements = { done = s.done, total = s.total } end
        end
        if getAdminLevel(actor) < permLevel("fullEmail") then d.lastIp = d.lastIp and "•••" or false end
        MYSQL.query(function(bans)
            d.banned = bans and bans[1] and { reason = bans[1].reason, admin = bans[1].admin, at = tonumber(bans[1].created_at) } or false
            MYSQL.query(function(v)
                d.vehicles = tonumber(v and v[1] and v[1].n) or 0
                reply(d)
            end, "SELECT COUNT(*) AS n FROM `vehicles` WHERE account_name = ? AND isDestroyed = 0", acc)
        end, "SELECT reason, admin, created_at FROM `bans` WHERE account_name = ? AND lifted_at = 0 ORDER BY id DESC LIMIT 1", acc)
    end)
end

local TABS = {}

function TABS.stats(actor, name, reply)
    if not resourceRunning("v_stats") then return reply({ list = {} }) end
    local defs = exports.v_stats:getStatDefinitions() or {}
    local values = exports.v_stats:getStats(name) or {}
    local out = {}
    for _, def in ipairs(defs) do
        out[#out + 1] = { id = def.id, name = txt(actor, def.name or def.id),
                          category = txt(actor, def.category or ""), value = values[def.id] or 0 }
    end
    reply({ list = out })
end

function TABS.vehicles(actor, name, reply)
    if not resourceRunning("v_ownveh") then return reply({ list = {} }) end
    local out = {}
    for _, v in ipairs(exports.v_ownveh:getOwnedVehicles(name) or {}) do
        out[#out + 1] = { id = v.id, model = v.model, name = getVehicleNameFromModel(v.model) or tostring(v.model),
                          plate = v.plate or false, destroyed = v.isDestroyed, spawned = v.spawned }
    end
    reply({ list = out })
end

function TABS.mails(actor, name, reply)
    MYSQL.query(function(rows)
        if not rows then return reply({ list = {} }) end
        local out = {}
        for i, r in ipairs(rows) do
            out[i] = { id = tonumber(r.id), kind = r.kind, subject = r.subject, status = r.status, error = r.error or false,
                       sender = r.sender, ts = (tonumber(r.sent_at) or 0) > 0 and tonumber(r.sent_at) or tonumber(r.created_at) }
        end
        reply({ list = out })
    end, "SELECT id, kind, subject, status, error, sender, created_at, sent_at FROM `mails` WHERE account_name = ? ORDER BY id DESC LIMIT 200", name)
end

function TABS.punishments(actor, name, reply)
    MYSQL.query(function(bans)
        MYSQL.query(function(logs)
            local b, l = {}, {}
            for i, r in ipairs(bans or {}) do
                b[i] = { reason = r.reason, admin = r.admin, at = tonumber(r.created_at), lifted = tonumber(r.lifted_at) or 0,
                         liftedBy = r.lifted_by or false }
            end
            for i, r in ipairs(logs or {}) do
                l[i] = { ts = tonumber(r.ts), admin = r.admin, action = r.action, source = r.source }
            end
            reply({ bans = b, log = l })
        end, "SELECT ts, admin, action, source FROM `" .. ADMIN.log.table .. "` WHERE target = ? ORDER BY id DESC LIMIT 200", name)
    end, "SELECT reason, admin, created_at, lifted_at, lifted_by FROM `bans` WHERE account_name = ? ORDER BY id DESC", name)
end

function TABS.achievements(actor, name, reply)
    if not resourceRunning("v_achievements") then return reply({ list = {} }) end
    local defs = exports.v_achievements:getAchievements() or {}
    local recs = exports.v_achievements:getPlayerAchievements(name) or {}
    local out = {}
    for _, def in ipairs(defs) do
        local r = recs[def.id] or {}
        out[#out + 1] = { id = def.id, name = txt(actor, def.name or def.id), done = r.done and true or false,
                          progress = r.progress or 0, goal = r.goal or 0, at = r.unlockedAt or false }
    end
    reply({ list = out })
end

function TABS.inventory(actor, name, reply)
    local player = playerOfAccount(name)
    if not player or not resourceRunning("v_inventory") then return reply({ online = false, list = {} }) end
    local inv = exports.v_inventory
    local out = {}
    local function add(uid, depth, slot)
        local it = inv:getItem(uid)
        if not it then return end
        local def = inv:getItemDef(it.def) or {}
        out[#out + 1] = { slot = slot or false, depth = depth, name = txt(actor, def.name or it.def), amount = it.amount or 1 }
        for _, c in ipairs(it.contents or {}) do add(c, depth + 1) end
    end
    for slot, uid in pairs(inv:getPlayerSlots(player) or {}) do add(uid, 0, slot) end
    reply({ online = true, list = out })
end

function TABS.social(actor, name, reply)
    local friends = exports.v_mysql:getAccData(name, "socialpanel:friends")
    local crew = exports.v_mysql:getAccData(name, "socialpanel:crew")
    local list = {}
    for n in tostring(friends or ""):gmatch("[^\n]+") do list[#list + 1] = n end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    reply({ friends = list, crew = type(crew) == "string" and crew ~= "" and crew or false })
end

--------------------------------------------------------------------------------
-- edits
--------------------------------------------------------------------------------

local EDIT_PERM = {
    setlevel = "setLevel", money = "accountEdit", level = "accountEdit", xp = "accountEdit", workxp = "accountEdit",
    note = "notes", delnote = "notes", vehgive = "vehicles", vehdelete = "vehicles", vehrestore = "vehicles",
    achgive = "achievements", achreset = "achievements", ban = "ban", unban = "ban", unmute = "mute",
}

local function ok(msgKey, params) return true, L.msg(msgKey, params) end
local function fail(msgKey, params) return false, L.msg(msgKey, params) end

local EDIT = {}

function EDIT.setlevel(actor, name, a)
    local lvl = math.floor(tonumber(a.value) or -1)
    if lvl < 0 or lvl > ADMIN.maxLevel then return fail("v_admin.admin_manage.level_must_be_between_0_and", { max_level = ADMIN.maxLevel }) end
    local my = getAdminLevel(actor)
    if my < ADMIN.maxLevel and lvl >= my then return fail("v_admin.admin_manage.you_can_only_grant_level_lower") end
    local player = playerOfAccount(name)
    if player then
        adminSetLevel(actor, player, lvl)
        return true
    end
    local current = tonumber(exports.v_mysql:getAccData(name, "admin_level")) or 0
    if my < ADMIN.maxLevel and current >= my then return fail("v_admin.core.you_can_t_do_that_to") end
    if not exports.v_mysql:setAccData(name, "admin_level", lvl) then return fail("v_admin.page.save_failed") end
    adminLog(actor, ("set %s admin level to %d (offline)"):format(name, lvl), name)
    return ok("v_admin.page.saved")
end

function EDIT.money(actor, name, a)
    local v = math.floor(tonumber(a.value) or -1)
    if v < 0 or v > 999999999 then return fail("v_admin.page.bad_number") end
    local player = playerOfAccount(name)
    if player then setPlayerMoney(player, v)
    elseif not exports.v_mysql:setAccData(name, "money-BETA", v) then return fail("v_admin.page.save_failed") end
    adminLog(actor, ("set money of %s to %d"):format(name, v), name)
    return ok("v_admin.page.saved")
end

local function setProgress(actor, name, key, v)
    local player = playerOfAccount(name)
    if not exports.v_mysql:setAccData(player or name, key, v) then return fail("v_admin.page.save_failed") end
    if player then setElementData(player, key, v) end
    adminLog(actor, ("set %s of %s to %d"):format(key, name, v), name)
    return ok("v_admin.page.saved")
end

function EDIT.level(actor, name, a)
    local v = math.floor(tonumber(a.value) or 0)
    if v < 1 or v > 1000 then return fail("v_admin.page.bad_number") end
    return setProgress(actor, name, "level", v)
end

function EDIT.xp(actor, name, a)
    local v = math.floor(tonumber(a.value) or -1)
    if v < 0 then return fail("v_admin.page.bad_number") end
    return setProgress(actor, name, "xp", v)
end

function EDIT.workxp(actor, name, a)
    local v = math.floor(tonumber(a.value) or -1)
    if v < 0 or type(a.work) ~= "string" then return fail("v_admin.page.bad_number") end
    if not resourceRunning("work_core") then return fail("v_admin.page.resource_missing", { name = "work_core" }) end
    local done, err = exports.work_core:setAccountWorkXp(name, a.work, v)
    if not done then return false, L.msg("v_admin.page.failed_reason", { reason = tostring(err) }) end
    adminLog(actor, ("set %s work XP of %s to %d"):format(a.work, name, v), name)
    return ok("v_admin.page.saved")
end

function EDIT.note(actor, name, a)
    local text = argText(a.text)
    if text == "" then return fail("v_admin.page.write_note") end
    text = utf8.sub(text, 1, ACC.notesMax)
    local list = notesOf({ [ACC.notesKey] = exports.v_mysql:getAccData(name, ACC.notesKey) })
    table.insert(list, 1, { t = now(), admin = actorAccount(actor) or "?", text = text })
    while #list > 50 do table.remove(list) end
    if not exports.v_mysql:setAccData(name, ACC.notesKey, toJSON(list, true)) then return fail("v_admin.page.save_failed") end
    adminLog(actor, "added a note to " .. name, name)
    return ok("v_admin.page.saved")
end

function EDIT.delnote(actor, name, a)
    local list = notesOf({ [ACC.notesKey] = exports.v_mysql:getAccData(name, ACC.notesKey) })
    local i = tonumber(a.index)
    if not i or not list[i] then return fail("v_admin.page.save_failed") end
    table.remove(list, i)
    if not exports.v_mysql:setAccData(name, ACC.notesKey, toJSON(list, true)) then return fail("v_admin.page.save_failed") end
    adminLog(actor, "deleted a note of " .. name, name)
    return ok("v_admin.page.saved")
end

function EDIT.vehgive(actor, name, a)
    if not resourceRunning("v_ownveh") then return fail("v_admin.page.resource_missing", { name = "v_ownveh" }) end
    local model = tonumber(a.model)
    if not model or not getVehicleNameFromModel(model) then
        model = getVehicleModelFromName(tostring(a.model or ""))
    end
    if not model then return fail("v_admin.page.bad_model") end
    local id, err = exports.v_ownveh:giveVehicle(name, model)
    if not id then return false, L.msg("v_admin.page.failed_reason", { reason = tostring(err) }) end
    adminLog(actor, ("gave %s a %s"):format(name, getVehicleNameFromModel(model)), name)
    return ok("v_admin.page.saved")
end

local function vehicleOf(name, id)
    local d = resourceRunning("v_ownveh") and exports.v_ownveh:getVehicleData(tonumber(id))
    return d and sameName(d.account_name, name) and d or nil
end

function EDIT.vehdelete(actor, name, a)
    local d = vehicleOf(name, a.id)
    if not d then return fail("v_admin.page.no_such_vehicle") end
    local done, err = exports.v_ownveh:deleteVehicle(d.id)
    if not done then return false, L.msg("v_admin.page.failed_reason", { reason = tostring(err) }) end
    adminLog(actor, ("deleted vehicle #%d (%s) of %s"):format(d.id, getVehicleNameFromModel(d.model) or d.model, name), name)
    return ok("v_admin.page.saved")
end

function EDIT.vehrestore(actor, name, a)
    local d = vehicleOf(name, a.id)
    if not d then return fail("v_admin.page.no_such_vehicle") end
    exports.v_ownveh:setVehicleDestroyed(d.id, false)
    adminLog(actor, ("restored vehicle #%d of %s"):format(d.id, name), name)
    return ok("v_admin.page.saved")
end

function EDIT.achgive(actor, name, a)
    if not resourceRunning("v_achievements") then return fail("v_admin.page.resource_missing", { name = "v_achievements" }) end
    if not exports.v_achievements:unlockAchievement(name, tostring(a.id)) then return fail("v_admin.page.nothing_changed") end
    adminLog(actor, ("gave achievement %s to %s"):format(tostring(a.id), name), name)
    return ok("v_admin.page.saved")
end

function EDIT.achreset(actor, name, a)
    if not resourceRunning("v_achievements") then return fail("v_admin.page.resource_missing", { name = "v_achievements" }) end
    if not exports.v_achievements:resetPlayerAchievement(name, a.id and tostring(a.id) or nil) then return fail("v_admin.page.nothing_changed") end
    adminLog(actor, ("reset achievement %s of %s"):format(tostring(a.id or "all"), name), name)
    return ok("v_admin.page.saved")
end

function EDIT.ban(actor, name, a)
    local reason = argText(a.reason)
    if reason == "" then return fail("v_admin.players.enter_reason") end
    adminBan(actor, name, reason)
    return true
end

function EDIT.unban(actor, name)
    adminUnban(actor, name)
    return true
end

function EDIT.unmute(actor, name)
    local player = playerOfAccount(name)
    if not player then return fail("v_admin.admin_manage.that_player_is_not_logged_in") end
    adminUnmute(actor, player)
    return true
end

--------------------------------------------------------------------------------
-- page
--------------------------------------------------------------------------------

PAGES.register("accounts", {
    perm = "accounts",
    actions = {
        list = function(actor, args, reply)
            withList(args.refresh == true, function(loaded)
                if not loaded then return reply(false, L.msg("v_admin.page.database_error")) end
                local rows = buildRows(actor, args)
                local size = ACC.pageSize
                local pages = math.max(1, math.ceil(#rows / size))
                local page = math.max(0, math.min(pages - 1, math.floor(tonumber(args.page) or 0)))
                local out = {}
                for i = page * size + 1, math.min(#rows, (page + 1) * size) do out[#out + 1] = rows[i] end
                reply({ rows = out, total = #rows, all = #cache.rows, page = page, pages = pages, now = now(), cachedAt = cache.at })
            end)
        end,

        detail = function(actor, args, reply)
            local name = argText(args.name)
            if name == "" then return reply(false) end
            detail(actor, name, reply)
        end,

        tab = function(actor, args, reply)
            local name, fn = argText(args.name), TABS[args.tab]
            if name == "" or not fn then return reply(false) end
            fn(actor, name, reply)
        end,

        mail = function(actor, args, reply)
            MYSQL.query(function(rows)
                local r = rows and rows[1]
                if not r then return reply(false, L.msg("v_admin.page.database_error")) end
                reply({ id = tonumber(r.id), subject = r.subject or "", body = r.body or "", error = r.error or false, status = r.status })
            end, "SELECT id, subject, body, error, status FROM `mails` WHERE id = ?", tonumber(args.id) or 0)
        end,

        edit = function(actor, args, reply)
            local name, what = argText(args.name), tostring(args.what)
            local fn = EDIT[what]
            if name == "" or not fn then return reply(false) end
            local need = EDIT_PERM[what]
            if getAdminLevel(actor) < permLevel(need) then
                return reply(false, L.msg("v_admin.core.you_need_at_least_admin_level", { min_level = permLevel(need) }))
            end
            -- the real account name (case) from the cache, else as typed
            local e = cache.byName and cache.byName[name:lower()]
            if e then name = e.name end
            local done, message = fn(actor, name, args)
            if done then dirty() end
            reply(done and true or false, message)
        end,
    },
})

--- Accounts page row count etc. for the dashboard.
function accountsSummary()
    return cache.rows and #cache.rows or false
end

--- Warm the cache for the dashboard.
function accountsWarm(cb) withList(false, cb) end
