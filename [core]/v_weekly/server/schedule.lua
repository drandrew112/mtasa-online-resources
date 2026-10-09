-- Week resolution, application to the other resources and the change timer.
--
-- A week's data:
--   { jobs = { [jobId] = { money, xp, label } }, timetrial = <index>,
--     custom = { [key] = value }, news = { title, body } }
-- A week without its own row inherits the latest earlier row (news excluded).

SCHED = {}

local currentWeek = nil

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
SCHED.copy = copy

local function blank()
    return { jobs = {}, timetrial = WEEKLY.DEFAULT_TIMETRIAL, custom = {} }
end

-- -> data (a copy), inherited (bool), sourceWeek|nil
function SCHED.resolve(ws)
    local own = STORE.get(ws)
    if own then
        local d = copy(own)
        d.jobs, d.custom = d.jobs or {}, d.custom or {}
        return d, false, ws
    end
    local src
    for _, s in ipairs(STORE.starts()) do
        if s < ws then src = s else break end
    end
    local d = src and copy(STORE.get(src)) or blank()
    d.jobs, d.custom = d.jobs or {}, d.custom or {}
    d.news = nil
    return d, true, src
end

function SCHED.currentWeek() return currentWeek or weekStartFor(getRealTime().timestamp) end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- Pushes the current week to v_jobmanager / v_timetrial.
function SCHED.apply()
    local ws = SCHED.currentWeek()
    local data = SCHED.resolve(ws)

    if running("v_jobmanager") then
        local jm = exports.v_jobmanager
        jm:jobmanagerClearMultipliers()
        for jobId, m in pairs(data.jobs) do
            jm:jobmanagerSetMultiplier(jobId, m.money, m.xp, m.label)
        end
    end
    if running("v_timetrial") and data.timetrial then
        exports.v_timetrial:setActiveTimetrial(data.timetrial)
    end

    triggerEvent("onWeeklyChanged", resourceRoot, ws, copy(data))
end

-- Detects a week rollover; returns true when a new week began.
function SCHED.check()
    if not STORE.isLoaded() then return false end
    local ws = weekStartFor(getRealTime().timestamp)
    if ws == currentWeek then return false end
    local first = currentWeek == nil
    currentWeek = ws
    SCHED.apply()
    if not first then
        outputServerLog("[v_weekly] new week started: " .. formatBudapest(ws))
        PANEL.weekChanged()
    end
    return true
end

--------------------------------------------------------------------------------
-- editing
--------------------------------------------------------------------------------

-- Runs fn(data) on the (seeded) row of the week `offset` weeks from now and
-- saves it. Returns true, or false + reason.
function SCHED.edit(offset, fn, by)
    offset = tonumber(offset)
    if not offset or offset ~= math.floor(offset) or offset < 0 or offset > 52 then
        return false, "bad week offset"
    end
    if not STORE.isLoaded() then return false, "database not ready" end
    local ws = weekStartAt(offset)
    local data = STORE.get(ws)
    if not data then data = SCHED.resolve(ws) end -- seed from the inherited week
    data = copy(data)
    data.jobs, data.custom = data.jobs or {}, data.custom or {}
    local ok, err = fn(data)
    if ok == false then return false, err or "rejected" end
    STORE.set(ws, data, by)
    if ws == SCHED.currentWeek() then SCHED.apply() end
    return true
end

function SCHED.clear(offset, by)
    offset = tonumber(offset)
    if not offset or offset < 0 then return false, "bad week offset" end
    local ws = weekStartAt(offset)
    if not STORE.get(ws) then return true end
    STORE.delete(ws)
    if ws == SCHED.currentWeek() then SCHED.apply() end
    return true
end

--------------------------------------------------------------------------------
-- startup
--------------------------------------------------------------------------------

addEvent("onWeeklyChanged")

-- v_mysql connects asynchronously: poll until the table can be read.
local bootTimer
local function boot()
    if not exports.v_mysql:mysqlIsConnected() then return end
    STORE.ensureTable()
    if not STORE.load() then return end
    killTimer(bootTimer)
    SCHED.check()
    setTimer(SCHED.check, WEEKLY.CHECK_INTERVAL, 0)
    outputServerLog("[v_weekly] ready, week of " .. formatBudapest(SCHED.currentWeek()))
end

addEventHandler("onResourceStart", resourceRoot, function()
    bootTimer = setTimer(boot, 1000, 0)
end)

-- the consumers lose their runtime state when restarted
addEventHandler("onResourceStart", root, function(res)
    local name = getResourceName(res)
    if (name == "v_jobmanager" or name == "v_timetrial") and currentWeek then
        setTimer(SCHED.apply, 1000, 1)
    end
end)
