-- /weekly admin menu backend. The client menu sends compact requests; every one
-- re-checks the admin level here.

addEvent("weekly:adminOpen", true)
addEvent("weekly:adminEdit", true)
addEvent("weekly:adminPreview", true)

local function isAdmin(player)
    if getElementData(player, "isLogged") ~= true then return false end
    return (tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0) >= WEEKLY.ADMIN_LEVEL
end

local function reply(player, text)
    triggerClientEvent(player, "weekly:notify", player, text)
end

local function overview()
    local weeks = {}
    for off = 0, WEEKLY.ADMIN_WEEKS - 1 do
        local ws = weekStartAt(off)
        local d, inherited = SCHED.resolve(ws)
        weeks[#weeks + 1] = {
            offset = off, from = formatBudapest(ws), inherited = inherited,
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
        weeks = weeks, jobs = jobs, trials = trials, nextChange = formatBudapest(weekStartAt(1)),
        multipliers = WEEKLY.MULTIPLIERS, period = WEEKLY.LOGIN_BONUS_PERIOD,
        maxMoney = WEEKLY.LOGIN_MAX_MONEY, maxXp = WEEKLY.LOGIN_MAX_XP,
    }
end

addCommandHandler("weekly", function(player)
    if not isAdmin(player) then return reply(player, "You have no permission.") end
    if not STORE.isLoaded() then return reply(player, "Weekly system is not ready yet.") end
    triggerClientEvent(player, "weekly:openAdmin", player, overview())
end)

addEventHandler("weekly:adminPreview", root, function()
    if not isAdmin(client) then return end
    PANEL.show(client, true)
end)

-- action: "job" (offset, jobId, money, xp) | "trial" (offset, index)
--         "news" (offset, title, body) | "login" (offset, money, xp) | "reset" (offset)
addEventHandler("weekly:adminEdit", root, function(action, offset, a, b, c)
    local player = client
    if not isAdmin(player) then return end
    local ok, err
    if action == "job" then
        ok, err = setJobMultiplier(offset, a, b, c)
    elseif action == "login" then
        ok, err = setLoginBonus(offset, a, b)
    elseif action == "trial" then
        ok, err = setActiveTimetrial(offset, a)
    elseif action == "news" then
        ok, err = setWeekNews(offset, a, b)
    elseif action == "reset" then
        ok, err = clearWeek(offset)
    else
        return
    end
    outputServerLog(("[v_weekly] %s: %s week+%s %s -> %s"):format(
        tostring(getElementData(player, "accName")), action, tostring(offset), tostring(a), tostring(ok)))
    reply(player, ok and "Saved." or ("Failed: " .. tostring(err)))
    triggerClientEvent(player, "weekly:openAdmin", player, overview(), true)
end)
