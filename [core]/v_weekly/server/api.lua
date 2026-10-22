if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Exported API. `offset` = weeks from now: 0 = the running week (applied
-- immediately), 1 = next week ... Weeks that were never configured inherit the
-- latest earlier configured week.

local function caller()
    if sourceResource then return "res:" .. getResourceName(sourceResource) end
    return "server"
end

--------------------------------------------------------------------------------
-- queries
--------------------------------------------------------------------------------

-- -> weekStart, data
function getCurrentWeek()
    local ws = SCHED.currentWeek()
    local d = SCHED.resolve(ws)
    return ws, d
end

-- -> weekStart, data, inherited
function getWeek(offset)
    local ws = weekStartAt(tonumber(offset) or 0)
    local d, inherited = SCHED.resolve(ws)
    return ws, d, inherited
end

-- Everything that is "weekly" for a week, ready to display:
-- { weekStart, from, to, news = {title, body}|nil, loginBonus = {money, xp}|nil,
--   jobs = { {id, name, money, xp, label, community}, ... }, works = { {id, name, money, xp}, ... },
--   bonuses = { { id = "official"|"community"|"work"|"business", items = {...} }, ... }  (non-empty categories;
--               business items have no xp),
--   bonusCount, timetrial = {name, time, reward}|nil }
-- offset: weeks from now (default 0 = running week)
function getWeeklyInfo(offset)
    return PANEL.payload(weekStartAt(tonumber(offset) or 0))
end

function getWeekStart(offset) return weekStartAt(tonumber(offset) or 0) end

-- unix timestamp of the next Tuesday 10:00 UTC
function getNextWeekChange() return weekStartAt(1) end

-- -> money, xp, label|false  (running week)
function getJobMultiplier(jobId)
    local d = SCHED.resolve(SCHED.currentWeek())
    local m = d.jobs[jobId]
    if not m then return 1, 1, false end
    return m.money, m.xp, m.label
end

-- -> money, xp, label|false  (running week; work_core works)
function getWorkMultiplier(workId)
    local d = SCHED.resolve(SCHED.currentWeek())
    local m = d.works[workId]
    if not m then return 1, 1, false end
    return m.money, m.xp, m.label or false
end

function getActiveTimetrial()
    local d = SCHED.resolve(SCHED.currentWeek())
    return d.timetrial
end

function isTimetrialActive(index)
    return getActiveTimetrial() == tonumber(index)
end

function getWeekValue(key)
    local d = SCHED.resolve(SCHED.currentWeek())
    return d.custom[tostring(key)]
end

--------------------------------------------------------------------------------
-- changes
--------------------------------------------------------------------------------

local function allowedMultiplier(v)
    for _, m in ipairs(WEEKLY.MULTIPLIERS) do
        if m == v then return true end
    end
    return false
end

local function defaultLabel(money, xp)
    local parts = {}
    if money > 1 then parts[#parts + 1] = L.msg("v_weekly.api.x_money", { money = money }) end
    if xp > 1 then parts[#parts + 1] = L.msg("v_weekly.api.x_xp", { xp = xp }) end
    return table.concat(parts, " & ")
end

-- money / xp must be one of WEEKLY.MULTIPLIERS (1x, 2x, 3x); 1 and 1 removes the entry
function setJobMultiplier(offset, jobId, money, xp, label)
    return SCHED.edit(offset, function(d)
        if type(jobId) ~= "string" or jobId == "" then return false, "bad job id" end
        money, xp = tonumber(money) or 1, tonumber(xp) or 1
        if not allowedMultiplier(money) or not allowedMultiplier(xp) then
            return false, "multiplier must be one of the allowed values"
        end
        if money == 1 and xp == 1 then
            d.jobs[jobId] = nil
        else
            label = (type(label) == "string" and label ~= "") and label:sub(1, 40) or defaultLabel(money, xp)
            d.jobs[jobId] = { money = money, xp = xp, label = label }
        end
    end, caller())
end

-- Multiplier of a work_core work (payWork money / giveWorkXp XP). Same values
-- as the Jobs; 1 and 1 removes the entry. label: optional receipt text (work_core
-- shows "Weekly bonus (2x)" without one).
function setWorkMultiplier(offset, workId, money, xp, label)
    return SCHED.edit(offset, function(d)
        if type(workId) ~= "string" or workId == "" then return false, "bad work id" end
        money, xp = tonumber(money) or 1, tonumber(xp) or 1
        if not allowedMultiplier(money) or not allowedMultiplier(xp) then
            return false, "multiplier must be one of the allowed values"
        end
        if money == 1 and xp == 1 then
            d.works[workId] = nil
        else
            d.works[workId] = { money = money, xp = xp,
                label = (type(label) == "string" and label ~= "") and label:sub(1, 40) or nil }
        end
    end, caller())
end

-- Business bonus: sale multiplier of an organization activity (biz_core, supply/deliver
-- activities only - the casino has none). 1 removes it. Values: WEEKLY.BUSINESS_MULTIPLIERS.
local function allowedBusiness(v)
    for _, m in ipairs(WEEKLY.BUSINESS_MULTIPLIERS) do if m == v then return true end end
    return false
end

function setBusinessMultiplier(offset, activity, money, label)
    return SCHED.edit(offset, function(d)
        if type(activity) ~= "string" or activity == "" then return false, "bad activity" end
        money = tonumber(money) or 1
        if not allowedBusiness(money) then return false, "multiplier must be one of the allowed values" end
        if money == 1 then
            d.business[activity] = nil
        else
            d.business[activity] = { money = money,
                label = (type(label) == "string" and label ~= "") and label:sub(1, 40) or nil }
        end
    end, caller())
end

function clearBusinessMultipliers(offset)
    return SCHED.edit(offset, function(d) d.business = {} end, caller())
end

-- -> multiplier of the running week (1 = none)
function getBusinessMultiplier(activity)
    local d = SCHED.resolve(SCHED.currentWeek())
    local m = d.business[activity]
    return m and m.money or 1
end

function clearWorkMultiplier(offset, workId)
    return SCHED.edit(offset, function(d) d.works[workId] = nil end, caller())
end

function clearWorkMultipliers(offset)
    return SCHED.edit(offset, function(d) d.works = {} end, caller())
end

-- Login bonus paid to every player who logs in (see server/login.lua).
-- money / xp are whole numbers, 0 = none; both 0 removes the bonus.
function setLoginBonus(offset, money, xp)
    return SCHED.edit(offset, function(d)
        money, xp = math.floor(tonumber(money) or 0), math.floor(tonumber(xp) or 0)
        if money < 0 or xp < 0 or money > WEEKLY.LOGIN_MAX_MONEY or xp > WEEKLY.LOGIN_MAX_XP then
            return false, "login bonus out of range"
        end
        d.loginBonus = (money > 0 or xp > 0) and { money = money, xp = xp } or nil
    end, caller())
end

-- -> money, xp (running week)
function getLoginBonus()
    local d = SCHED.resolve(SCHED.currentWeek())
    local b = d.loginBonus
    return b and b.money or 0, b and b.xp or 0
end

function clearJobMultiplier(offset, jobId)
    return SCHED.edit(offset, function(d) d.jobs[jobId] = nil end, caller())
end

function clearJobMultipliers(offset)
    return SCHED.edit(offset, function(d) d.jobs = {} end, caller())
end

function setActiveTimetrial(offset, index)
    return SCHED.edit(offset, function(d)
        index = tonumber(index)
        if not index or index ~= math.floor(index) or index < 1 then return false, "bad timetrial index" end
        local res = getResourceFromName("v_timetrial")
        if res and getResourceState(res) == "running" then
            local list = exports.v_timetrial:getTimetrials()
            if type(list) == "table" and not list[index] then return false, "unknown timetrial" end
        end
        d.timetrial = index
    end, caller())
end

function setWeekValue(offset, key, value)
    return SCHED.edit(offset, function(d)
        if type(key) ~= "string" or key == "" then return false, "bad key" end
        d.custom[key] = value
    end, caller())
end

function setWeekNews(offset, title, body)
    return SCHED.edit(offset, function(d)
        title = type(title) == "string" and title:sub(1, 60) or ""
        body = type(body) == "string" and body:sub(1, 600) or ""
        if title == "" and body == "" then d.news = nil else d.news = { title = title, body = body } end
    end, caller())
end

-- replaces the whole week: { jobs, works, timetrial, custom, news, loginBonus }
function setWeek(offset, data)
    if type(data) ~= "table" then return false, "bad data" end
    return SCHED.edit(offset, function(d)
        d.jobs, d.works, d.custom, d.news = {}, {}, {}, nil
        d.business = {}
        for activity, m in pairs(type(data.business) == "table" and data.business or {}) do
            local money = type(m) == "table" and tonumber(m.money) or nil
            if type(activity) == "string" and money and allowedBusiness(money) and money ~= 1 then
                d.business[activity] = { money = money, label = type(m.label) == "string" and m.label:sub(1, 40) or nil }
            end
        end
        d.timetrial = tonumber(data.timetrial) or d.timetrial
        for jobId, m in pairs(type(data.jobs) == "table" and data.jobs or {}) do
            if type(jobId) == "string" and type(m) == "table" then
                local money, xp = tonumber(m.money) or 1, tonumber(m.xp) or 1
                if not allowedMultiplier(money) then money = 1 end
                if not allowedMultiplier(xp) then xp = 1 end
                if money > 1 or xp > 1 then
                    d.jobs[jobId] = {
                        money = money, xp = xp,
                        label = type(m.label) == "string" and m.label:sub(1, 40) or defaultLabel(money, xp),
                    }
                end
            end
        end
        for workId, m in pairs(type(data.works) == "table" and data.works or {}) do
            if type(workId) == "string" and type(m) == "table" then
                local money, xp = tonumber(m.money) or 1, tonumber(m.xp) or 1
                if not allowedMultiplier(money) then money = 1 end
                if not allowedMultiplier(xp) then xp = 1 end
                if money > 1 or xp > 1 then
                    d.works[workId] = { money = money, xp = xp,
                        label = type(m.label) == "string" and m.label ~= "" and m.label:sub(1, 40) or nil }
                end
            end
        end
        if type(data.custom) == "table" then d.custom = SCHED.copy(data.custom) end
        if type(data.news) == "table" then d.news = SCHED.copy(data.news) end
        d.loginBonus = nil
        if type(data.loginBonus) == "table" then
            local money = math.floor(math.max(0, math.min(WEEKLY.LOGIN_MAX_MONEY, tonumber(data.loginBonus.money) or 0)))
            local xp = math.floor(math.max(0, math.min(WEEKLY.LOGIN_MAX_XP, tonumber(data.loginBonus.xp) or 0)))
            if money > 0 or xp > 0 then d.loginBonus = { money = money, xp = xp } end
        end
    end, caller())
end

-- removes the week's own row again (it inherits the previous week)
function clearWeek(offset)
    return SCHED.clear(offset, caller())
end

function reapplyWeek()
    SCHED.apply()
    return true
end
