-- /ermadmin: shift & task history panel (client/admin/*.lua) for admins.
-- Every query re-checks the admin level; the data comes straight from erm.db.

local PAGE = 14

local function adminLevel(player)
    local res = getResourceFromName("v_mysql")
    if res and getResourceState(res) == "running" then
        return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    end
    return tonumber(getElementData(player, "admin_level")) or 0
end

local function isAdmin(player)
    return adminLevel(player) >= Config.ADMIN_LEVEL
end

-- "YYYY-MM-DD HH:MM:SS" -> seconds (only used for differences)
local function toSeconds(s)
    local Y, M, D, h, m, sec = tostring(s or ""):match("^(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if not Y then return nil end
    Y, M, D = tonumber(Y), tonumber(M), tonumber(D)
    if M <= 2 then Y = Y - 1 end
    local era = math.floor(Y / 400)
    local yoe = Y - era * 400
    local doy = math.floor((153 * ((M + 9) % 12) + 2) / 5) + D - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return (era * 146097 + doe - 719468) * 86400 + tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(sec)
end

local function duration(from, to)
    local a, b = toSeconds(from), toSeconds(to or formatDateTime(now()))
    return (a and b) and math.max(0, b - a) or 0
end

local function like(s)
    return "%" .. trim(s):gsub("[%%_]", "") .. "%"
end

local function liveUnitOfShift(shiftId)
    for _, u in pairs(Units.list) do
        if u.shiftId == shiftId then return u end
    end
end

-- Runs "SELECT COUNT(*)" + the paged select with the same WHERE.
local function paged(countSql, selectSql, where, args, page)
    local w = #where > 0 and (" WHERE " .. table.concat(where, " AND ")) or ""
    local countRows = DB.query(countSql .. w, unpack(args)) or {}
    local total = countRows[1] and tonumber(countRows[1].n) or 0
    local pages = math.max(1, math.ceil(total / PAGE))
    page = math.min(math.max(1, page), pages)

    local qa = { unpack(args) }
    qa[#qa + 1] = PAGE
    qa[#qa + 1] = (page - 1) * PAGE
    local rows = DB.query(selectSql .. w .. " ORDER BY id DESC LIMIT ? OFFSET ?", unpack(qa)) or {}
    return rows, total, page, pages
end

local handlers = {}

---------------------------------------------------------------- shifts

function handlers.shifts(p)
    local where, args = {}, {}
    local search = trim(p.search)
    if search ~= "" then
        local l = like(search)
        where[#where + 1] = "(callsign LIKE ? OR members LIKE ? OR plate LIKE ? OR unit_type LIKE ?)"
        args = { l, l, l, l }
    end
    if p.filter == "active" then
        where[#where + 1] = "ended_at IS NULL"
    elseif p.filter == "ended" then
        where[#where + 1] = "ended_at IS NOT NULL"
    end

    local rows, total, page, pages = paged("SELECT COUNT(*) AS n FROM shifts",
        "SELECT *, (SELECT COUNT(*) FROM shift_tasks st WHERE st.shift_id = shifts.id) AS task_count FROM shifts",
        where, args, tonumber(p.page) or 1)

    local list = {}
    for _, r in ipairs(rows) do
        local closed = DB.unjson(r.closed_tasks)
        local live = liveUnitOfShift(r.id)
        list[#list + 1] = {
            id        = r.id,
            callsign  = r.callsign or "?",
            type      = r.unit_type or "",
            plate     = r.plate or "",
            members   = DB.unjson(r.members),
            startedAt = r.started_at or "",
            endedAt   = r.ended_at or "",
            duration  = duration(r.started_at, r.ended_at),
            tasks     = math.max(tonumber(r.task_count) or 0, #closed),
            closed    = #closed,
            live      = live and live.status or false,
        }
    end
    return { list = list, total = total, page = page, pages = pages }
end

function handlers.shift(p)
    local id = tonumber(p.id)
    local r = id and (DB.query("SELECT * FROM shifts WHERE id = ?", id) or {})[1]
    if not r then return { error = "Shift not found" } end

    local tasks, linked = {}, {}
    for _, l in ipairs(DB.query([[SELECT st.*, t.title, t.priority, t.status, t.zone FROM shift_tasks st
        LEFT JOIN tasks t ON t.id = st.task_id WHERE st.shift_id = ? ORDER BY st.id]], id) or {}) do
        linked[l.task_id] = true
        tasks[#tasks + 1] = {
            id = l.task_id, title = l.title or "?", priority = tonumber(l.priority) or 0,
            status = l.status or "?", zone = l.zone or "",
            assignedAt = l.assigned_at or "", releasedAt = l.released_at or "",
            outcome = l.outcome or (l.released_at and "" or "active"),
        }
    end
    -- shifts from before the link table existed only know their closed task ids
    for _, taskId in ipairs(DB.unjson(r.closed_tasks)) do
        if not linked[taskId] then
            local t = (DB.query("SELECT id, title, priority, status, zone, closed_at FROM tasks WHERE id = ?", taskId) or {})[1]
            if t then
                tasks[#tasks + 1] = {
                    id = t.id, title = t.title, priority = tonumber(t.priority) or 0, status = t.status,
                    zone = t.zone or "", assignedAt = "", releasedAt = t.closed_at or "", outcome = "closed",
                }
            end
        end
    end

    local live = liveUnitOfShift(id)
    return {
        id        = r.id,
        callsign  = r.callsign or "?",
        type      = r.unit_type or "",
        plate     = r.plate or "",
        members   = DB.unjson(r.members),
        startedAt = r.started_at or "",
        endedAt   = r.ended_at or "",
        duration  = duration(r.started_at, r.ended_at),
        closed    = #DB.unjson(r.closed_tasks),
        tasks     = tasks,
        live      = live and { status = live.status, task = live.task or 0 } or false,
    }
end

---------------------------------------------------------------- tasks

function handlers.tasks(p)
    local where, args = {}, {}
    local search = trim(p.search)
    if search ~= "" then
        local l = like(search)
        where[#where + 1] = "(title LIKE ? OR zone LIKE ? OR caller LIKE ? OR units LIKE ? OR source LIKE ? OR CAST(id AS TEXT) = ?)"
        args = { l, l, l, l, l, (search:gsub("^#", "")) }
    end
    if p.filter == "open" then
        where[#where + 1] = "status != 'closed'"
    elseif p.filter == "closed" then
        where[#where + 1] = "status = 'closed'"
    end

    local rows, total, page, pages = paged("SELECT COUNT(*) AS n FROM tasks",
        "SELECT id, title, priority, status, zone, created_at, closed_at, source, units FROM tasks",
        where, args, tonumber(p.page) or 1)

    local list = {}
    for _, r in ipairs(rows) do
        list[#list + 1] = {
            id = r.id, title = r.title or "", priority = tonumber(r.priority) or 0, status = r.status or "",
            zone = r.zone or "", createdAt = r.created_at or "", closedAt = r.closed_at or "",
            source = r.source or "", units = DB.unjson(r.units),
        }
    end
    return { list = list, total = total, page = page, pages = pages }
end

function handlers.task(p)
    local id = tonumber(p.id)
    local r = id and (DB.query("SELECT * FROM tasks WHERE id = ?", id) or {})[1]
    if not r then return { error = "Task not found" } end

    local log, total = {}, 0
    for _, e in ipairs(DB.unjson(r.response_log)) do
        local d = e.stop and duration(e.start, e.stop) or duration(e.start)
        total = total + d
        log[#log + 1] = { unit = e.unit or "?", start = e.start or "", stop = e.stop or "", duration = d }
    end

    local links = {}
    for _, l in ipairs(DB.query([[SELECT st.*, s.unit_type FROM shift_tasks st
        LEFT JOIN shifts s ON s.id = st.shift_id WHERE st.task_id = ? ORDER BY st.id]], id) or {}) do
        links[#links + 1] = {
            shift = l.shift_id, callsign = l.callsign or "?", type = l.unit_type or "",
            assignedAt = l.assigned_at or "", releasedAt = l.released_at or "",
            outcome = l.outcome or (l.released_at and "" or "active"),
        }
    end

    local meta = DB.unjson(r.meta)
    return {
        id            = r.id,
        title         = r.title or "",
        description   = r.description or "",
        caller        = r.caller or "",
        x = r.pos_x or 0, y = r.pos_y or 0, z = r.pos_z or 0,
        zone          = r.zone or "",
        priority      = tonumber(r.priority) or 0,
        status        = r.status or "",
        source        = r.source or "",
        createdAt     = r.created_at or "",
        prioritizedAt = r.prioritized_at or "",
        assignedAt    = r.assigned_at or "",
        closedAt      = r.closed_at or "",
        closeReason   = r.close_reason or "",
        unitLog       = DB.unjson(r.units),
        responseLog   = log,
        responseTotal = total,
        links         = links,
        meta          = next(meta) and toJSON(meta, true):sub(2, -2) or "",
    }
end

---------------------------------------------------------------- wiring

addCommandHandler("ermadmin", function(player)
    if not isAdmin(player) then
        triggerClientEvent(player, "erm:notify", resourceRoot, "ERM Admin",
            string.format("You need admin level %d or higher.", Config.ADMIN_LEVEL))
        return
    end
    triggerClientEvent(player, "erm:admin:open", resourceRoot)
end)

addEvent("erm:admin:query", true)
addEventHandler("erm:admin:query", resourceRoot, function(kind, params)
    local player = client
    if not isElement(player) or not handlers[kind] then return end
    if not isAdmin(player) then
        triggerClientEvent(player, "erm:admin:denied", resourceRoot)
        return
    end
    local ok, result = pcall(handlers[kind], type(params) == "table" and params or {})
    if not ok then
        outputDebugString("[erm] admin query " .. kind .. ": " .. tostring(result), 1)
        result = { error = "Query failed" }
    end
    triggerClientEvent(player, "erm:admin:result", resourceRoot, kind, result)
end)

---------------------------------------------------------------- auto dispatch switch

local function sendAutoState(player)
    triggerClientEvent(player, "erm:admin:auto", resourceRoot, AutoDispatch.state())
end

addEvent("erm:admin:autoGet", true)
addEventHandler("erm:admin:autoGet", resourceRoot, function()
    if isElement(client) and isAdmin(client) then sendAutoState(client) end
end)

addEvent("erm:admin:autoSet", true)
addEventHandler("erm:admin:autoSet", resourceRoot, function(on)
    local player = client
    if not isElement(player) then return end
    if not isAdmin(player) then
        triggerClientEvent(player, "erm:admin:denied", resourceRoot)
        return
    end
    local ok, err = AutoDispatch.set(on == true, "admin " .. accountName(player))
    if not ok then
        triggerClientEvent(player, "erm:notify", resourceRoot, "ERM Admin", tostring(err or "Failed"))
    end
    sendAutoState(player)
end)

-- Keep every open admin panel in sync (switched by another admin / resource,
-- or med_erm_auto started / stopped).
local function broadcastAutoState()
    local state = AutoDispatch.state()
    for _, p in ipairs(getElementsByType("player")) do
        if isAdmin(p) then triggerClientEvent(p, "erm:admin:auto", resourceRoot, state) end
    end
end

addEvent("onErmAutoDispatchChange", false)
addEventHandler("onErmAutoDispatchChange", root, broadcastAutoState)
addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "med_erm_auto" then broadcastAutoState() end
end)
addEventHandler("onResourceStop", root, function(res)
    if getResourceName(res) == "med_erm_auto" then setTimer(broadcastAutoState, 50, 1) end
end)
