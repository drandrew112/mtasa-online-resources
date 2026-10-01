-- Tasks (incidents). A task can hold several units, a unit holds one task.
--
-- Status is derived:  unassigned -> prioritized (P1-P4 set) -> assigned (>=1 unit)
-- and "closed" once completed / closed by the dispatcher.

Tasks = {
    list   = {},   -- [id] = task, open tasks only
    closed = {},   -- recent closed tasks, newest first
}

local function deriveStatus(t)
    if t.closedAt then return "closed" end
    if #t.units > 0 then return "assigned" end
    if t.priority then return "prioritized" end
    return "unassigned"
end

function Tasks.get(id)
    return Tasks.list[tonumber(id) or -1]
end

function Tasks.save(t)
    t.status = deriveStatus(t)
    DB.saveTask(t)
end

-- Pushes the task to every unit working it (their tablets show it live).
function Tasks.syncUnits(t)
    for _, unitId in ipairs(t.units) do
        local u = Units.get(unitId)
        if u then Units.sync(u) end
    end
end

function Tasks.load()
    local open, closed = DB.loadTasks(Config.RECENT_CLOSED)
    for _, t in ipairs(open) do
        t.status = deriveStatus(t)   -- units are gone after a restart
        DB.saveTask(t)
        Tasks.list[t.id] = t
    end
    Tasks.closed = closed
end

-- source: name of the creating resource ("" = web / dispatcher)
-- meta:   free table owned by the creator (persisted as JSON, returned by getTask)
function Tasks.create(title, description, x, y, z, caller, source, meta)
    x, y, z = tonumber(x), tonumber(y), tonumber(z) or 0
    if not x or not y then return false, "Invalid position" end
    if meta ~= nil and type(meta) ~= "table" then return false, "meta must be a table" end

    local t = {
        title       = cleanText(title, 80),
        description = cleanText(description, 500),
        caller      = cleanText(caller, 60),
        x = x, y = y, z = z,
        zone        = zoneLabel(x, y, z),
        units       = {},
        unitLog     = {},
        responseLog = {},
        createdAt   = now(),
        status      = "unassigned",
        source      = source or "",
        meta        = meta or {},
    }
    if t.title == "" then t.title = "Medical emergency" end

    t.id = DB.insertTask(t)
    if not t.id then return false, "Database error" end

    Tasks.list[t.id] = t
    Events.fire("onErmTaskCreated", t.id)
    return t.id
end

-- fields: title, description, caller, x, y, z, meta (only the given ones change)
function Tasks.update(id, fields)
    local t = Tasks.get(id)
    if not t then return false, "Task not found" end
    if type(fields) ~= "table" then return false, "fields must be a table" end

    if fields.title ~= nil then
        t.title = cleanText(fields.title, 80)
        if t.title == "" then t.title = "Medical emergency" end
    end
    if fields.description ~= nil then t.description = cleanText(fields.description, 500) end
    if fields.caller ~= nil then t.caller = cleanText(fields.caller, 60) end
    if fields.x ~= nil or fields.y ~= nil or fields.z ~= nil then
        local x, y = tonumber(fields.x or t.x), tonumber(fields.y or t.y)
        if not x or not y then return false, "Invalid position" end
        local z = t.z
        if fields.z ~= nil then z = tonumber(fields.z) or 0 elseif fields.x ~= nil or fields.y ~= nil then z = 0 end
        t.x, t.y, t.z = x, y, z
        t.zone = zoneLabel(x, y, z)
    end
    if fields.meta ~= nil then
        if type(fields.meta) ~= "table" then return false, "meta must be a table" end
        t.meta = fields.meta
    end

    Tasks.save(t)
    Tasks.syncUnits(t)
    Events.fire("onErmTaskUpdated", t.id)
    return true
end

function Tasks.setPriority(id, priority)
    local t = Tasks.get(id)
    priority = math.floor(tonumber(priority) or 0)
    if not t then return false, "Task not found" end
    if priority < 1 or priority > 4 then return false, "Invalid priority" end

    local old = t.priority
    if old == priority then return true end
    t.priority = priority
    t.prioritizedAt = t.prioritizedAt or now()
    Tasks.save(t)
    Tasks.syncUnits(t)
    Events.fire("onErmTaskPriorityChanged", t.id, priority, old or false)
    return true
end

function Tasks.assign(id, unitId)
    local t, u = Tasks.get(id), Units.get(unitId)
    if not t then return false, "Task not found" end
    if not u then return false, "Unit not found" end
    if not t.priority then return false, "Set a priority (P1-P4) first" end
    if u.task == t.id then return false, u.callsign .. " is already on this task" end
    if u.task then return false, u.callsign .. " already has task #" .. u.task end

    t.units[#t.units + 1] = u.id
    if not hasValue(t.unitLog, u.callsign) then t.unitLog[#t.unitLog + 1] = u.callsign end
    t.assignedAt = t.assignedAt or now()

    u.task = t.id
    u.reachedScene = false
    DB.shiftTaskStart(u.shiftId, t.id, u.callsign)
    Tasks.save(t)
    Tasks.syncUnits(t)
    Units.notify(u, "New case assigned", string.format("#%d P%d - %s (%s)", t.id, t.priority, t.title, t.zone), true)
    Events.fire("onErmTaskAssigned", t.id, u.id)
    return true
end

-- Detaches a unit from its task. The task itself stays open.
-- outcome: stored on the shift <-> task link ("released", "handover", ...)
function Tasks.unassign(id, unitId, silent, outcome)
    local t, u = Tasks.get(id), Units.get(unitId)
    if not t then return false, "Task not found" end
    if not removeValue(t.units, tonumber(unitId)) then return false, "Unit is not on this task" end

    if u then
        DB.shiftTaskEnd(u.shiftId, t.id, outcome or "released")
        Units.releaseTask(u)
        if not silent then
            Units.notify(u, "Case released", string.format("You were released from case #%d.", t.id))
        end
    end
    Tasks.save(t)
    Tasks.syncUnits(t)
    Events.fire("onErmTaskUnassigned", t.id, tonumber(unitId))
    return true
end

-- A unit leaves its task on its own (tablet). At least one unit has to stay;
-- the leaving unit gets the task credited to its shift.
function Tasks.leave(id, unitId)
    local t, u = Tasks.get(id), Units.get(unitId)
    if not t or not u or u.task ~= t.id then return false, "Your unit is not on this case." end
    if #t.units < 2 then return false, "The last unit cannot leave the case. Close it instead." end
    if u.status == "handover" then return false, "Handover in progress." end

    Units.creditTask(u, t)
    Tasks.unassign(t.id, u.id, true, "left")
    Units.notify(u, "Case left", string.format("You left case #%d.", t.id))
    for _, otherId in ipairs(t.units) do
        local o = Units.get(otherId)
        if o then Units.notify(o, "Unit left", string.format("%s left case #%d.", u.callsign, t.id)) end
    end
    return true
end

function Tasks.close(id, reason)
    local t = Tasks.get(id)
    if not t then return false, "Task not found" end

    local units = t.units
    t.units = {}
    t.closedAt = now()
    t.closedLabel = formatDateTime(t.closedAt)
    t.closeReason = cleanText(reason, 120)
    if t.closeReason == "" then t.closeReason = "Closed" end

    for _, unitId in ipairs(units) do
        local u = Units.get(unitId)
        if u then
            DB.shiftTaskEnd(u.shiftId, t.id, "task closed")
            Units.creditTask(u, t)
            Units.releaseTask(u)
            Units.notify(u, "Case closed", string.format("Case #%d has been closed.", t.id))
        end
    end

    Tasks.save(t)
    Tasks.list[t.id] = nil
    table.insert(Tasks.closed, 1, t)
    while #Tasks.closed > Config.RECENT_CLOSED do table.remove(Tasks.closed) end
    Events.fire("onErmTaskClosed", t.id, t.closeReason)
    return true
end

-- Response (lights & siren) log -------------------------------------------

function Tasks.startResponse(t, u)
    local entry = { unit = u.callsign, start = now() }
    t.responseLog[#t.responseLog + 1] = entry
    DB.saveTask(t)
    return entry
end

function Tasks.stopResponse(t, entry)
    entry.stop = now()
    DB.saveTask(t)
end

-- Public (network / export) representation --------------------------------

function Tasks.public(t)
    local units = {}
    for _, unitId in ipairs(t.units) do
        local u = Units.get(unitId)
        if u then
            units[#units + 1] = { id = u.id, callsign = u.callsign, status = u.status }
        end
    end
    local log = {}
    for _, e in ipairs(t.responseLog) do
        log[#log + 1] = { unit = e.unit, start = e.start, stop = e.stop or 0 }
    end
    return {
        id          = t.id,
        title       = t.title,
        description = t.description,
        caller      = t.caller,
        x = t.x, y = t.y, z = t.z,
        zone        = t.zone,
        priority    = t.priority or 0,
        status      = t.status,
        units       = units,
        responseLog = log,
        createdAt   = t.createdAt,
        closedAt    = t.closedAt or 0,
        closedLabel = t.closedLabel or "",
        closeReason = t.closeReason or "",
        unitLog     = { unpack(t.unitLog) },
        source      = t.source or "",
        meta        = t.meta or {},
    }
end

function Tasks.publicActive()
    local out = {}
    for _, t in pairs(Tasks.list) do out[#out + 1] = Tasks.public(t) end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Open task by id, or one of the recently closed ones.
function Tasks.find(id)
    id = tonumber(id)
    if Tasks.list[id or -1] then return Tasks.list[id] end
    for _, t in ipairs(Tasks.closed) do
        if t.id == id then return t end
    end
end

function Tasks.publicClosed()
    local out = {}
    for _, t in ipairs(Tasks.closed) do out[#out + 1] = Tasks.public(t) end
    return out
end
