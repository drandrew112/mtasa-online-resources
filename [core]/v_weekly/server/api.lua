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

function getWeekStart(offset) return weekStartAt(tonumber(offset) or 0) end

-- unix timestamp of the next Tuesday 10:00 (Budapest)
function getNextWeekChange() return weekStartAt(1) end

-- -> money, xp, label|false  (running week)
function getJobMultiplier(jobId)
    local d = SCHED.resolve(SCHED.currentWeek())
    local m = d.jobs[jobId]
    if not m then return 1, 1, false end
    return m.money, m.xp, m.label
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
    if money > 1 then parts[#parts + 1] = money .. "x money" end
    if xp > 1 then parts[#parts + 1] = xp .. "x XP" end
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

-- replaces the whole week: { jobs, timetrial, custom, news }
function setWeek(offset, data)
    if type(data) ~= "table" then return false, "bad data" end
    return SCHED.edit(offset, function(d)
        d.jobs, d.custom, d.news = {}, {}, nil
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
