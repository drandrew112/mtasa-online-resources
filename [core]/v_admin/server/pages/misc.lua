if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
if not MYSQL then loadstring(exports.v_mysql:importAsync())() end -- v_mysql async lib
-- ============================================================
--  v_admin / server/pages/misc.lua
--  The smaller pages:
--    dashboard     summary { }                                  -> counters + latest admin actions
--    bans          list { search, active, page } / unban { name }
--    resources     list { } / action { name, action } / updates / checkupdates / updateresources (v_main exports)
--    achievements  list { } / give { name, id }                 (v_achievements exports)
-- ============================================================

local function now() return getRealTime().timestamp end

local function strip(s) return (tostring(s or ""):gsub("#%x%x%x%x%x%x", "")) end

local function txt(actor, x)
    return strip(L.resolveFor(isWebActor(actor) and "en" or actor, x))
end

--------------------------------------------------------------------------------
-- dashboard
--------------------------------------------------------------------------------

PAGES.register("dashboard", {
    perm = "panel",
    actions = {
        summary = function(actor, args, reply)
            local d = { now = now(), online = 0, guests = 0, admins = {}, muted = 0, jailed = 0 }
            for _, p in ipairs(getElementsByType("player")) do
                d.online = d.online + 1
                if getElementData(p, "isLogged") ~= true then d.guests = d.guests + 1 end
                local muteUntil = tonumber(getElementData(p, "mute_until"))
                if muteUntil and muteUntil > d.now then d.muted = d.muted + 1 end
                if getElementData(p, "adminjail") then d.jailed = d.jailed + 1 end
                local lvl = getAdminLevel(p)
                if lvl > 0 then d.admins[#d.admins + 1] = { name = strip(getPlayerName(p)), level = lvl, id = tonumber(getElementData(p, "ID")) } end
            end
            table.sort(d.admins, function(a, b) return a.level > b.level end)
            d.maxPlayers = getMaxPlayers()
            d.reports, d.reportsWaiting = adminReportCounts()
            d.instance = INSTANCE.name()
            d.accounts = accountsSummary() or false

            -- running week
            if resourceRunning("v_weekly") then
                local ok, w = pcall(function() return exports.v_weekly:getWeeklyInfo(0) end)
                if ok and type(w) == "table" then
                    local jobs = {}
                    for _, j in ipairs(w.jobs or {}) do
                        jobs[#jobs + 1] = txt(actor, j.name) .. (j.community and " [community]" or "") .. " " .. txt(actor, j.label or "")
                    end
                    d.week = { from = w.from, to = w.to, jobs = jobs, timetrial = w.timetrial and txt(actor, w.timetrial.name) or false,
                               loginBonus = w.loginBonus or false }
                end
            end

            -- resources that failed to load
            d.failed = {}
            for _, res in ipairs(getResources()) do
                if getResourceState(res) == "failed to load" then d.failed[#d.failed + 1] = getResourceName(res) end
            end
            table.sort(d.failed)

            MYSQL.query(function(bans)
                d.activeBans = tonumber(bans and bans[1] and bans[1].n) or 0
                MYSQL.query(function(log)
                    d.log = {}
                    for i, r in ipairs(log or {}) do
                        d.log[i] = { ts = tonumber(r.ts), admin = r.admin, action = r.action, source = r.source }
                    end
                    if d.accounts then return reply(d) end
                    accountsWarm(function()
                        d.accounts = accountsSummary() or false
                        reply(d)
                    end)
                end, "SELECT ts, admin, action, source FROM `" .. ADMIN.log.table .. "` ORDER BY id DESC LIMIT 12")
            end, "SELECT COUNT(*) AS n FROM `bans` WHERE lifted_at = 0")
        end,
    },
})

--------------------------------------------------------------------------------
-- bans
--------------------------------------------------------------------------------

PAGES.register("bans", {
    perm = "panel",
    perms = { unban = "ban" },
    actions = {
        list = function(actor, args, reply)
            local where, params = {}, {}
            if args.active ~= false then where[#where + 1] = "lifted_at = 0" end
            local search = argText(args.search)
            if search ~= "" then
                where[#where + 1] = "(account_name LIKE ? OR serial LIKE ? OR admin LIKE ? OR reason LIKE ?)"
                local p = likeText(search)
                params[#params + 1], params[#params + 2], params[#params + 3], params[#params + 4] = p, p, p, p
            end
            local size = 80
            local page = math.max(0, math.floor(tonumber(args.page) or 0))
            params[#params + 1] = size + 1
            params[#params + 1] = page * size
            local showIp = getAdminLevel(actor) >= permLevel("fullEmail")
            MYSQL.query(function(rows)
                if not rows then return reply(false, L.msg("v_admin.page.database_error")) end
                local out = {}
                for i = 1, math.min(#rows, size) do
                    local r = rows[i]
                    out[i] = { id = tonumber(r.id), account = r.account_name or false, serial = r.serial or false,
                               ip = showIp and r.ip or (r.ip and "•••" or false), reason = r.reason, admin = r.admin,
                               at = tonumber(r.created_at), lifted = tonumber(r.lifted_at) or 0, liftedBy = r.lifted_by or false }
                end
                reply({ rows = out, more = #rows > size, page = page })
            end, "SELECT * FROM `bans`" .. (#where > 0 and (" WHERE " .. table.concat(where, " AND ")) or "")
                .. " ORDER BY id DESC LIMIT ? OFFSET ?", unpack(params))
        end,

        unban = function(actor, args, reply)
            local name = argText(args.name)
            if name == "" then return reply(false) end
            adminUnban(actor, name)
            reply(true)
        end,
    },
})

--------------------------------------------------------------------------------
-- resources
--------------------------------------------------------------------------------

PAGES.register("resources", {
    perm = "resources",
    actions = {
        list = function(actor, args, reply)
            if not resourceRunning("v_main") then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_main" })) end
            reply({ list = exports.v_main:listResources() or {} })
        end,

        action = function(actor, args, reply)
            if not resourceRunning("v_main") then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_main" })) end
            local name, action = argText(args.name), args.action
            if action ~= "start" and action ~= "stop" and action ~= "restart" then return reply(false) end
            local ok, message = exports.v_main:adminResourceAction(actorName(actor) .. (isWebActor(actor) and " (web)" or ""), action, name)
            if ok then adminLog(actor, ("%s resource %s"):format(action, name)) end
            reply(ok and true or false, message or nil)
        end,

        -- GitHub update check / update (v_main updater.lua, updateResources.lua)
        updates = function(actor, args, reply)
            if not resourceRunning("v_main") then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_main" })) end
            reply(exports.v_main:getUpdateReport() or {})
        end,

        checkupdates = function(actor, args, reply)
            if not resourceRunning("v_main") then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_main" })) end
            if not exports.v_main:adminCheckUpdates(actorName(actor)) then return reply(false, L.msg("v_admin.res.busy")) end
            adminLog(actor, "started an update check")
            reply(true, L.msg("v_admin.res.check_started"))
        end,

        updateresources = function(actor, args, reply)
            if not resourceRunning("v_main") then return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_main" })) end
            if not exports.v_main:adminUpdateResources(actorName(actor)) then return reply(false, L.msg("v_admin.res.busy")) end
            adminLog(actor, "started updateresources (download + apply repo changes)")
            reply(true, L.msg("v_admin.res.update_started"))
        end,
    },
})

--------------------------------------------------------------------------------
-- achievements
--------------------------------------------------------------------------------

PAGES.register("achievements", {
    perm = "panel",
    perms = { give = "achievements" },
    actions = {
        list = function(actor, args, reply)
            if not resourceRunning("v_achievements") then
                return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_achievements" }))
            end
            local out = {}
            for _, def in ipairs(exports.v_achievements:getAchievements() or {}) do
                out[#out + 1] = { id = def.id, name = txt(actor, def.name or def.id), desc = txt(actor, def.description or def.desc or ""),
                                  category = txt(actor, def.category or ""), xp = tonumber(def.xp) or 0, goal = tonumber(def.goal) or 1 }
            end
            reply({ list = out })
        end,

        give = function(actor, args, reply)
            local name, id = argText(args.name), argText(args.id)
            if name == "" or id == "" then return reply(false, L.msg("v_admin.page.enter_account")) end
            if not resourceRunning("v_achievements") then
                return reply(false, L.msg("v_admin.page.resource_missing", { name = "v_achievements" }))
            end
            if not exports.v_achievements:unlockAchievement(name, id) then return reply(false, L.msg("v_admin.page.nothing_changed")) end
            adminLog(actor, ("gave achievement %s to %s"):format(id, name), name)
            reply(true, L.msg("v_admin.page.saved"))
        end,
    },
})
