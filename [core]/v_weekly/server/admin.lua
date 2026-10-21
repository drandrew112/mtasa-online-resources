if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Admin backend of the weekly schedule. The editor is the Weekly page of the
-- v_admin panel (v_admin 3.0, /weekly opens it there); it reads
-- getWeeklyAdminOverview() and changes weeks through the setter exports
-- (server/api.lua). The admin level is checked by v_admin (ADMIN.perms.weekly).

local function overview()
    local weeks = {}
    for off = 0, WEEKLY.ADMIN_WEEKS - 1 do
        local ws = weekStartAt(off)
        local d, inherited = SCHED.resolve(ws)
        weeks[#weeks + 1] = {
            offset = off, from = formatUtc(ws), inherited = inherited,
            jobs = d.jobs, timetrial = d.timetrial, news = d.news, loginBonus = d.loginBonus,
        }
    end

    local jobs = {}
    local res = getResourceFromName("v_jobmanager")
    if res and getResourceState(res) == "running" then
        for _, g in ipairs(exports.v_jobmanager:jobmanagerOfficialList() or {}) do
            jobs[#jobs + 1] = { id = g.id, name = g.name }
        end
    end
    local trials = {}
    res = getResourceFromName("v_timetrial")
    if res and getResourceState(res) == "running" then
        for i, t in ipairs(exports.v_timetrial:getTimetrials() or {}) do
            trials[i] = { name = t.name, reward = t.reward, time = t.time }
        end
    end
    return {
        weeks = weeks, jobs = jobs, trials = trials, nextChange = formatUtc(weekStartAt(1)),
        multipliers = WEEKLY.MULTIPLIERS, period = WEEKLY.LOGIN_BONUS_PERIOD,
        maxMoney = WEEKLY.LOGIN_MAX_MONEY, maxXp = WEEKLY.LOGIN_MAX_XP,
    }
end

--- The Weekly page of the v_admin panel (the /weekly command opens it there):
--- every configurable week with the lists the editor needs.
function getWeeklyAdminOverview()
    if not STORE.isLoaded() then return false end
    return overview()
end

--- Shows a player the weekly panel of the running week, as on login (v_admin "Preview").
function showWeeklyPreview(player)
    if not isElement(player) then return false end
    PANEL.show(player, true)
    return true
end
