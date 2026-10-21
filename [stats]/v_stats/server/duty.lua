-- Time on duty per work (STATS.DUTY_STATS): measured from the work_core duty
-- events, so the work resources need no change for it. The running duty is
-- credited every STATS.DUTY_TICK and when it ends (duty end, quit, stop).

local onDuty = {}   -- onDuty[player] = { stat = id, since = tick }

addEvent("onPlayerWorkDutyStart")
addEvent("onPlayerWorkDutyEnd")

local function credit(player)
    local d = onDuty[player]
    if not d then return end
    local now = getTickCount()
    local seconds = (now - d.since) / 1000
    d.since = now
    if seconds <= 0 then return end
    local entry = STORE.get(player)
    if entry then API_ADD(entry, d.stat, seconds) end
end

local function start(player, workId)
    local stat = STATS.DUTY_STATS[tostring(workId)]
    if stat then onDuty[player] = { stat = stat, since = getTickCount() } end
end

local function stop(player)
    credit(player)
    onDuty[player] = nil
end

addEventHandler("onPlayerWorkDutyStart", root, function(workId)
    stop(source)
    start(source, workId)
end)

addEventHandler("onPlayerWorkDutyEnd", root, function()
    stop(source)
end)

-- quit: "high" priority runs this before storage.lua drops (and writes) the entry
addEventHandler("onPlayerQuit", root, function()
    local d = onDuty[source]
    onDuty[source] = nil
    if not d then return end
    local seconds = (getTickCount() - d.since) / 1000
    local name = STORE.loggedName(source)
    if seconds > 0 and name then
        local entry = STORE.get(name)
        if entry then API_ADD(entry, d.stat, seconds) end
    end
end, true, "high")

setTimer(function()
    for player in pairs(onDuty) do
        if isElement(player) then credit(player) else onDuty[player] = nil end
    end
end, STATS.DUTY_TICK, 0)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(onDuty) do credit(player) end
    STORE.flushAll()
end, true, "high")

-- v_stats (re)started while players are on duty
addEventHandler("onResourceStart", resourceRoot, function()
    local res = getResourceFromName("work_core")
    if not res or getResourceState(res) ~= "running" then return end
    for _, player in ipairs(getElementsByType("player")) do
        local workId = exports.work_core:getPlayerWork(player)
        if workId then start(player, workId) end
    end
end)
