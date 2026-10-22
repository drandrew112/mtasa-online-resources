if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/pages/weekly.lua
--  Weekly page (was the /weekly panel of v_weekly): the upcoming weeks'
--  bonuses (Job and Work multipliers), time trial, login bonus and weekly news.
--
--  overview {}                                   -> v_weekly:getWeeklyAdminOverview()
--  edit { action, offset, a, b, c }              -> fresh overview
--       action: job (jobId, money, xp) | work (workId, money, xp) | trial (index) | login (money, xp) | news (title, body) | reset
--  preview {}                                    shows the weekly panel to the admin in game
-- ============================================================

local function overview()
    if not resourceRunning("v_weekly") then return nil end
    local ok, data = pcall(function() return exports.v_weekly:getWeeklyAdminOverview() end)
    return ok and type(data) == "table" and data or nil
end

local SETTERS = {
    job   = function(o, a, b, c) return exports.v_weekly:setJobMultiplier(o, a, tonumber(b), tonumber(c)) end,
    work  = function(o, a, b, c) return exports.v_weekly:setWorkMultiplier(o, a, tonumber(b), tonumber(c)) end,
    trial = function(o, a)       return exports.v_weekly:setActiveTimetrial(o, tonumber(a)) end,
    login = function(o, a, b)    return exports.v_weekly:setLoginBonus(o, tonumber(a), tonumber(b)) end,
    news  = function(o, a, b)    return exports.v_weekly:setWeekNews(o, tostring(a or ""), tostring(b or "")) end,
    reset = function(o)          return exports.v_weekly:clearWeek(o) end,
}

PAGES.register("weekly", {
    perm = "weekly",
    actions = {
        overview = function(actor, args, reply)
            local data = overview()
            if not data then return reply(false, L.msg("v_admin.weekly.not_ready")) end
            reply(data)
        end,

        edit = function(actor, args, reply)
            local fn = SETTERS[args.action]
            local offset = math.max(0, math.floor(tonumber(args.offset) or 0))
            if not fn or not resourceRunning("v_weekly") then return reply(false, L.msg("v_admin.weekly.not_ready")) end
            local ok, done, err = pcall(fn, offset, args.a, args.b, args.c)
            if not ok or not done then
                return reply(overview() or false, L.msg("v_admin.page.failed_reason", { reason = tostring(ok and err or done) }))
            end
            adminLog(actor, ("weekly: %s week+%d %s %s %s"):format(args.action, offset,
                tostring(args.a or ""), tostring(args.b or ""), tostring(args.c or "")):sub(1, 250))
            reply(overview() or false, L.msg("v_admin.page.saved"))
        end,

        preview = function(actor, args, reply)
            local player = actorPlayer(actor)
            if not player then return reply(false, L.msg("v_admin.page.need_ingame")) end
            exports.v_weekly:showWeeklyPreview(player)
            reply(true)
        end,
    },
})
