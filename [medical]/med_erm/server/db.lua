-- SQLite persistence (data/erm.db): tasks and shifts.
-- Date-times are stored as "YYYY-MM-DD HH:MM:SS" text; tasks also keep the
-- epoch of creation so their age survives a restart.

DB = {}

local conn

local function query(sql, ...)
    local qh = dbQuery(conn, sql, ...)
    if not qh then return false end
    return dbPoll(qh, -1)
end

local function json(t)
    return toJSON(t or {}, true)
end

local function unjson(s)
    return (s and s ~= "" and fromJSON(s)) or {}
end

function DB.init()
    conn = dbConnect("sqlite", "data/erm.db")
    if not conn then
        outputDebugString("[erm] could not open data/erm.db", 1)
        return false
    end

    dbExec(conn, [[CREATE TABLE IF NOT EXISTS tasks (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        title          TEXT NOT NULL,
        description    TEXT,
        caller         TEXT,
        pos_x          REAL,
        pos_y          REAL,
        pos_z          REAL,
        zone           TEXT,
        priority       INTEGER,
        status         TEXT NOT NULL,
        units          TEXT,
        response_log   TEXT,
        created_ts     INTEGER,
        created_at     TEXT,
        prioritized_at TEXT,
        assigned_at    TEXT,
        closed_at      TEXT,
        close_reason   TEXT,
        source         TEXT,
        meta           TEXT
    )]])

    -- columns added after the first release
    local cols = {}
    for _, c in ipairs(query("PRAGMA table_info(tasks)") or {}) do cols[c.name] = true end
    if not cols.source then dbExec(conn, "ALTER TABLE tasks ADD COLUMN source TEXT") end
    if not cols.meta then dbExec(conn, "ALTER TABLE tasks ADD COLUMN meta TEXT") end

    dbExec(conn, [[CREATE TABLE IF NOT EXISTS shifts (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        callsign     TEXT,
        unit_type    TEXT,
        plate        TEXT,
        members      TEXT,
        closed_tasks TEXT,
        started_at   TEXT NOT NULL,
        ended_at     TEXT
    )]])

    -- Which shift worked which task, from when to when and how it ended.
    dbExec(conn, [[CREATE TABLE IF NOT EXISTS shift_tasks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id    INTEGER NOT NULL,
        task_id     INTEGER NOT NULL,
        callsign    TEXT,
        assigned_at TEXT,
        released_at TEXT,
        outcome     TEXT
    )]])
    dbExec(conn, "CREATE INDEX IF NOT EXISTS idx_shift_tasks_shift ON shift_tasks (shift_id)")
    dbExec(conn, "CREATE INDEX IF NOT EXISTS idx_shift_tasks_task ON shift_tasks (task_id)")

    -- Shifts left open by a crash / restart are closed now.
    local stamp = formatDateTime(now())
    dbExec(conn, "UPDATE shifts SET ended_at = ? WHERE ended_at IS NULL", stamp)
    dbExec(conn, "UPDATE shift_tasks SET released_at = ?, outcome = 'server restart' WHERE released_at IS NULL", stamp)
    return true
end

-- Raw access for the admin panel queries (server/admin.lua).
DB.query = function(sql, ...) return query(sql, ...) end
DB.unjson = unjson

---------------------------------------------------------------- shift <-> task links

function DB.shiftTaskStart(shiftId, taskId, callsign)
    if not conn or not shiftId then return end
    dbExec(conn, "INSERT INTO shift_tasks (shift_id, task_id, callsign, assigned_at) VALUES (?, ?, ?, ?)",
        shiftId, taskId, callsign, formatDateTime(now()))
end

function DB.shiftTaskEnd(shiftId, taskId, outcome)
    if not conn or not shiftId then return end
    dbExec(conn, [[UPDATE shift_tasks SET released_at = ?, outcome = ?
        WHERE shift_id = ? AND task_id = ? AND released_at IS NULL]],
        formatDateTime(now()), outcome, shiftId, taskId)
end

---------------------------------------------------------------- tasks

local function responseLogRows(task)
    local rows = {}
    for _, e in ipairs(task.responseLog) do
        rows[#rows + 1] = {
            unit  = e.unit,
            start = formatDateTime(e.start),
            stop  = e.stop and formatDateTime(e.stop) or false,
        }
    end
    return rows
end

function DB.insertTask(t)
    local _, _, id = query([[INSERT INTO tasks
        (title, description, caller, pos_x, pos_y, pos_z, zone, status, units, response_log, created_ts, created_at, source, meta)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        t.title, t.description, t.caller, t.x, t.y, t.z, t.zone, t.status,
        json(t.unitLog), json({}), t.createdAt, formatDateTime(t.createdAt), t.source, json(t.meta))
    return id
end

function DB.saveTask(t)
    if not conn then return end
    dbExec(conn, [[UPDATE tasks SET title = ?, description = ?, caller = ?, pos_x = ?, pos_y = ?, pos_z = ?,
        zone = ?, priority = ?, status = ?, units = ?, response_log = ?,
        prioritized_at = ?, assigned_at = ?, closed_at = ?, close_reason = ?, meta = ? WHERE id = ?]],
        t.title, t.description, t.caller, t.x, t.y, t.z, t.zone,
        t.priority, t.status, json(t.unitLog), json(responseLogRows(t)),
        formatDateTime(t.prioritizedAt), formatDateTime(t.assignedAt),
        formatDateTime(t.closedAt), t.closeReason, json(t.meta), t.id)
end

local function rowToTask(r)
    return {
        id          = r.id,
        title       = r.title,
        description = r.description or "",
        caller      = r.caller or "",
        x = r.pos_x or 0, y = r.pos_y or 0, z = r.pos_z or 0,
        zone        = r.zone or "",
        priority    = r.priority,
        status      = r.status,
        units       = {},
        unitLog     = unjson(r.units),
        responseLog = {},            -- epochs are not restored; rows stay in the DB
        createdAt   = r.created_ts or now(),
        closedLabel = r.closed_at,
        closeReason = r.close_reason,
        source      = r.source or "",
        meta        = unjson(r.meta),
    }
end

-- Open tasks (reloaded on start) and the most recent closed ones.
function DB.loadTasks(recentClosed)
    local open, closed = {}, {}
    for _, r in ipairs(query("SELECT * FROM tasks WHERE status != 'closed' ORDER BY id") or {}) do
        open[#open + 1] = rowToTask(r)
    end
    for _, r in ipairs(query("SELECT * FROM tasks WHERE status = 'closed' ORDER BY id DESC LIMIT ?", recentClosed) or {}) do
        local t = rowToTask(r)
        t.closedAt = t.createdAt   -- only used for sorting / display fallback
        closed[#closed + 1] = t
    end
    return open, closed
end

---------------------------------------------------------------- shifts

function DB.startShift(unit)
    local _, _, id = query([[INSERT INTO shifts (callsign, unit_type, plate, members, closed_tasks, started_at)
        VALUES (?, ?, ?, ?, ?, ?)]],
        unit.callsign, unit.type, unit.plate, json(unit.accounts), json({}), formatDateTime(unit.startedAt))
    return id
end

function DB.updateShift(unit)
    if not conn or not unit.shiftId then return end
    local ids = {}
    for _, c in ipairs(unit.closedTasks) do ids[#ids + 1] = c.id end
    dbExec(conn, "UPDATE shifts SET members = ?, closed_tasks = ? WHERE id = ?",
        json(unit.accounts), json(ids), unit.shiftId)
end

function DB.endShift(unit)
    DB.updateShift(unit)
    if not conn or not unit.shiftId then return end
    dbExec(conn, "UPDATE shifts SET ended_at = ? WHERE id = ?", formatDateTime(now()), unit.shiftId)
end
