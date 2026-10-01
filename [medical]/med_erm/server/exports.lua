-- Automation API for other resources (server side).
--
-- ERM stays the interface: everything done through these exports goes through
-- the same rules as the web console (one task per unit, a priority before any
-- assignment), shows up live for the dispatcher, reaches the unit tablets and
-- is logged in the database. Events to react to are listed in server/events.lua.
--
-- Every mutating export returns   true / id   or   false, "error message".

local function callerName()
    return sourceResource and getResourceName(sourceResource) or "script"
end

---------------------------------------------------------------- tasks

-- createTask(title, description, x, y [, z [, caller [, priority [, meta]]]])
--   -> taskId | false, error
-- z: nil/0 = ground (resolved client side for the radar objective)
-- caller: shown to dispatcher/crew, default = calling resource name
-- priority: 1-4 to create it already prioritized (assignable right away)
-- meta: any table the caller wants to attach (persisted, returned by getTask)
function createTask(title, description, x, y, z, caller, priority, meta)
    local id, err = Tasks.create(title, description, x, y, z, caller or callerName(), callerName(), meta)
    if not id then return false, err end
    if priority ~= nil then
        local ok, perr = Tasks.setPriority(id, priority)
        if not ok then return id, "Task created, priority not set: " .. perr end
    end
    return id
end

-- updateTask(taskId, { title=, description=, caller=, x=, y=, z=, meta= }) -> bool, error
-- Only the given fields change; assigned crews see it live (objective moves too).
function updateTask(taskId, fields)
    return Tasks.update(taskId, fields)
end

-- setTaskPriority(taskId, 1-4) -> bool, error
function setTaskPriority(taskId, priority)
    return Tasks.setPriority(taskId, priority)
end

-- assignUnit(taskId, unitId) -> bool, error
-- Needs a priority on the task and a unit without a task.
function assignUnit(taskId, unitId)
    return Tasks.assign(taskId, unitId)
end

-- unassignUnit(taskId, unitId) -> bool, error
function unassignUnit(taskId, unitId)
    return Tasks.unassign(taskId, unitId)
end

-- closeTask(taskId [, reason]) -> bool, error   (assigned units are released)
function closeTask(taskId, reason)
    return Tasks.close(taskId, reason or ("Closed by " .. callerName()))
end

-- getTask(taskId) -> task | false   (open or recently closed)
-- { id, title, description, caller, x, y, z, zone, priority (0 = none),
--   status ("unassigned"|"prioritized"|"assigned"|"closed"),
--   units = { {id, callsign, status}, ... }, responseLog, createdAt, closedAt,
--   closedLabel, closeReason, unitLog, source, meta }
function getTask(taskId)
    local t = Tasks.find(taskId)
    return t and Tasks.public(t) or false
end

-- getTasks([status [, source]]) -> { task, ... }   open tasks only
-- status: filter by status; source: filter by creating resource name
-- (pass getResourceName(getThisResource()) to get only your own tasks)
function getTasks(status, source)
    local out = {}
    for _, t in ipairs(Tasks.publicActive()) do
        if (not status or t.status == status) and (not source or t.source == source) then
            out[#out + 1] = t
        end
    end
    return out
end

---------------------------------------------------------------- units

-- getUnits() -> { unit, ... }   (see getUnitData for the fields)
function getUnits()
    return Units.publicList()
end

-- getUnitData(unitId | player) -> unit | false
-- { id, callsign, type, plate, status, statusLabel, task (0 = none), taskTitle,
--   responding, members = {nick,...}, accounts = {account,...}, x, y, z, zone,
--   startedAt, handoverEnds, closedTasks }
function getUnitData(unitOrPlayer)
    local u
    if isElement(unitOrPlayer) then
        u = Units.ofPlayer(unitOrPlayer)
    else
        u = Units.get(unitOrPlayer)
    end
    return u and Units.public(u) or false
end

local function typeFilter(types)
    if types == nil then return nil end
    local set = {}
    for _, t in ipairs(type(types) == "table" and types or { types }) do set[tostring(t):upper()] = true end
    return set
end

-- getFreeUnits([types]) -> { unit, ... }
-- Units that can take a task now: no task and status "available".
-- types: "ALS" or { "ALS", "BLS" } to filter by unit type.
function getFreeUnits(types)
    local set = typeFilter(types)
    local out = {}
    for _, u in ipairs(Units.publicList()) do
        if u.task == 0 and u.status == "available" and (not set or set[u.type]) then
            out[#out + 1] = u
        end
    end
    return out
end

-- getNearestFreeUnit(x, y [, z [, types]]) -> unit, distance | false
function getNearestFreeUnit(x, y, z, types)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return false end
    local best, bestDist
    for _, u in ipairs(getFreeUnits(types)) do
        local d = getDistanceBetweenPoints2D(x, y, u.x, u.y)
        if not bestDist or d < bestDist then best, bestDist = u, d end
    end
    if not best then return false end
    return best, bestDist
end

-- setUnitStatus(unitId, status [, handoverTime]) -> bool, error
-- status: "available" | "enroute" | "onscene" | "handover"
-- Same effect as the tablet's status buttons:
--   enroute  -> starts the lights & siren log of the unit's task
--   onscene  -> stops it and marks the scene reached (radar objective removed,
--               Handover button enabled) - use this for automatic arrival
--   handover -> starts the hospital handover; handoverTime (ms) overrides
--               Config.HANDOVER_TIME, false / 0 = no automatic finish
--               (end it with completeHandover). onErmUnitHandoverStart fires.
--   available -> stops the log, keeps the task
function setUnitStatus(unitId, status, handoverTime)
    local u = Units.get(unitId)
    if not u then return false, "Unit not found" end
    return Units.setStatus(u, status, handoverTime)
end

-- unitCaseAction(unitId, "start" | "stop" | "onscene" | "handover") -> bool, error
-- Presses an Active Case button for the unit, with the tablet's rules
-- (e.g. "onscene" only while responding, "handover" only after the scene).
function unitCaseAction(unitId, action)
    local u = Units.get(unitId)
    if not u then return false, "Unit not found" end
    return Units.caseAction(u, action)
end

-- setHandoverTime(unitId, ms | false) -> bool, error
-- Re-times a running handover: ms from now, or false = wait for completeHandover.
function setHandoverTime(unitId, ms)
    local u = Units.get(unitId)
    if not u then return false, "Unit not found" end
    if u.status ~= "handover" then return false, "Unit is not in handover" end
    Units.scheduleHandover(u, ms)
    Units.sync(u)
    return true
end

-- completeHandover(unitId) -> bool, error
-- Ends the handover now: unit -> Available, task credited to its shift and
-- closed when it was the last unit on it (same as the timer running out).
function completeHandover(unitId)
    local u = Units.get(unitId)
    if not u then return false, "Unit not found" end
    if u.status ~= "handover" then return false, "Unit is not in handover" end
    Units.finishHandover(u)
    return true
end

---------------------------------------------------------------- messages

-- sendMessage(channel, target, text [, from]) -> messageId | false, error
-- channel: "broadcast" (target ignored), "unit" (target = unitId),
--          "task" (target = taskId, every assigned unit gets it)
-- from: sender name shown on tablet and web, default "Dispatch".
-- The message appears in the dispatcher chat as a dispatch message.
function sendMessage(channel, target, text, from)
    from = cleanText(from, 40)
    if from == "" then from = "Dispatch" end
    return Chat.post(channel, tonumber(target), from, true, text)
end
