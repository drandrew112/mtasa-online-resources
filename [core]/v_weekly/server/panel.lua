if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Weekly news panel: shown on a week rollover and for admin preview. The
-- login-screen display (next to login/register) is handled by v_accounts via exports.v_weekly:getWeeklyInfo.

PANEL = {}

addEvent("onPlayerLoaded")

local function jobNames()
    local names = {}
    local res = getResourceFromName("v_jobmanager")
    if res and getResourceState(res) == "running" then
        local ok, list = pcall(function() return exports.v_jobmanager:jobmanagerOfficialList() end)
        if ok and type(list) == "table" then
            for _, g in ipairs(list) do names[g.id] = g.name end
        end
    end
    return names
end

local function timetrialInfo(index)
    local res = getResourceFromName("v_timetrial")
    if not index or not res or getResourceState(res) ~= "running" then return nil end
    local list = exports.v_timetrial:getTimetrials()
    local t = type(list) == "table" and list[index]
    if not t then return nil end
    return { name = t.name, time = t.time, reward = t.reward }
end

function PANEL.payload(ws)
    local data = SCHED.resolve(ws)
    local names = jobNames()
    local jobs = {}
    for jobId, m in pairs(data.jobs) do
        jobs[#jobs + 1] = { id = jobId, name = names[jobId] or jobId, money = m.money, xp = m.xp, label = m.label }
    end
    table.sort(jobs, function(a, b) return a.name < b.name end)
    return {
        weekStart = ws,
        from = formatUtc(ws),
        to = formatUtc(weekStartAt(1, ws + 3.5 * 86400)),
        news = data.news,
        loginBonus = data.loginBonus and {
            money = data.loginBonus.money, xp = data.loginBonus.xp, period = WEEKLY.LOGIN_BONUS_PERIOD,
        } or nil,
        jobs = jobs,
        timetrial = timetrialInfo(data.timetrial),
    }
end

local function accName(player)
    local n = getElementData(player, "accName")
    return (getElementData(player, "isLogged") == true and type(n) == "string" and n ~= "") and n or nil
end

-- force = ignore the "already seen" mark (admin preview)
function PANEL.show(player, force)
    if not isElement(player) then return end
    local name = accName(player)
    if not name then return end
    local ws = SCHED.currentWeek()
    if not force then
        local seen = tonumber(exports.v_mysql:getAccData(name, WEEKLY.SEEN_KEY)) or 0
        if seen >= ws then return end
        exports.v_mysql:setAccData(name, WEEKLY.SEEN_KEY, ws)
    end
    triggerClientEvent(player, "weekly:showPanel", player, PANEL.payload(ws))
end

addEventHandler("onPlayerLoaded", root, function()
    local player = source
    setTimer(function()
        if not isElement(player) or not STORE.isLoaded() then return end
        local money, xp = LOGIN.claim(player)
        if money then
            local parts = {}
            if money > 0 then parts[#parts + 1] = "€" .. money end
            if xp > 0 then parts[#parts + 1] = xp .. " XP" end
            triggerClientEvent(player, "weekly:notify", player, L.msg("v_weekly.panel.login_bonus_2", { parts = table.concat(parts, " + ") }), L.msg("v_weekly.admin.login_bonus"))
        end
    end, WEEKLY.PANEL_DELAY, 1)
end)

-- a rollover while players are online: show it to everybody who is logged in
function PANEL.weekChanged()
    for _, p in ipairs(getElementsByType("player")) do PANEL.show(p) end
end
