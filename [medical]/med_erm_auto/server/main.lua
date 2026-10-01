-- ERM Auto Dispatch: automatic dispatcher on top of med_erm.
--
-- While enabled it watches med_erm's tasks and units and
--   1. prioritizes every task without a priority: meta.priority (1-4, set by
--      the creating resource, e.g. med_generator) or P1 by default,
--   2. sends the nearest free unit to every waiting (prioritized, no unit)
--      task - most urgent first (P1 -> P4), older tasks first within a priority.
--
-- Everything goes through med_erm's exports, so the dispatcher console, the
-- tablets and the database see the same as with a human dispatcher.
--
-- Exports:
--   getAutoDispatch()                 -> bool
--   setAutoDispatch(enabled [, by])   -> bool   (by: who switched it, for the log)
-- Event (on this resource's root):
--   onErmAutoDispatchChange (enabled, by)

local ERM = "med_erm"
local PASS_DELAY = 250     -- ms to collect a burst of events into one pass
local FALLBACK = 5000      -- ms, periodic pass in case an event was missed

local enabled = false
local passTimer

addEvent("onErmAutoDispatchChange", false)

local function ermRunning()
    local res = getResourceFromName(ERM)
    return res and getResourceState(res) == "running"
end

local function log(fmt, ...)
    outputServerLog("[med_erm_auto] " .. string.format(fmt, ...))
end

---------------------------------------------------------------- dispatching

-- meta.priority: 1-4 or "P1".."P4"; anything else -> P1.
local function priorityOf(task)
    local meta = type(task.meta) == "table" and task.meta or {}
    local p = meta.priority
    if type(p) == "string" then p = p:upper():match("^P?(%d)$") end
    p = math.floor(tonumber(p) or 1)
    if p < 1 or p > 4 then p = 1 end
    return p
end

local function nearestIndex(units, x, y)
    local best, bestDist
    for i, u in ipairs(units) do
        local d = getDistanceBetweenPoints2D(x, y, u.x, u.y)
        if not bestDist or d < bestDist then best, bestDist = i, d end
    end
    return best, bestDist
end

local function dispatch()
    if not enabled or not ermRunning() then return end
    local erm = exports[ERM]
    local tasks = erm:getTasks() or {}

    -- 1. prioritize
    for _, t in ipairs(tasks) do
        if (tonumber(t.priority) or 0) == 0 then
            local p = priorityOf(t)
            local ok, err = erm:setTaskPriority(t.id, p)
            if ok then
                t.priority = p
                if #t.units == 0 then t.status = "prioritized" end
            else
                log("could not prioritize task #%d: %s", t.id, tostring(err))
            end
        end
    end

    -- 2. waiting tasks, most urgent first
    local queue = {}
    for _, t in ipairs(tasks) do
        if t.status == "prioritized" and #t.units == 0 then queue[#queue + 1] = t end
    end
    if #queue == 0 then return end
    table.sort(queue, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        if a.createdAt ~= b.createdAt then return a.createdAt < b.createdAt end
        return a.id < b.id
    end)

    -- 3. nearest free unit for each, until the units run out
    local free = erm:getFreeUnits() or {}
    for _, t in ipairs(queue) do
        if #free == 0 then break end
        local i, dist = nearestIndex(free, t.x, t.y)
        local u = free[i]
        local ok, err = erm:assignUnit(t.id, u.id)
        if ok then
            table.remove(free, i)
            log("task #%d (P%d) -> %s (%.0f m)", t.id, t.priority, u.callsign, dist)
        else
            log("could not assign %s to task #%d: %s", u.callsign, t.id, tostring(err))
        end
    end
end

-- Several med_erm events usually arrive together; run one pass after them.
local function schedule()
    if not enabled or isTimer(passTimer) then return end
    passTimer = setTimer(function()
        passTimer = nil
        dispatch()
    end, PASS_DELAY, 1)
end

local WATCH = {
    "onErmTaskCreated", "onErmTaskUpdated", "onErmTaskPriorityChanged",
    "onErmTaskUnassigned", "onErmUnitSignIn", "onErmUnitStatusChange",
    "onErmUnitHandoverComplete",
}
for _, name in ipairs(WATCH) do
    addEvent(name, false)
    addEventHandler(name, root, schedule)
end

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == ERM then schedule() end
end)

setTimer(schedule, FALLBACK, 0)

---------------------------------------------------------------- switch

function getAutoDispatch()
    return enabled
end

function setAutoDispatch(on, by)
    on = on and true or false
    by = tostring(by or (sourceResource and getResourceName(sourceResource)) or "console")
    if on == enabled then return true end
    enabled = on
    set("enabled", on and "true" or "false")
    log("auto dispatch %s by %s", on and "ENABLED" or "DISABLED", by)
    triggerEvent("onErmAutoDispatchChange", resourceRoot, on, by)
    if on then schedule() end
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    local v = get("enabled")
    enabled = v == true or v == "true"
    log("started, auto dispatch %s", enabled and "ENABLED" or "DISABLED")
    schedule()
end)
