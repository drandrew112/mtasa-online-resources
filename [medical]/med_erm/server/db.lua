-- MySQL persistence through v_mysql (the shared database), two tables:
--   med_tasks   every task; `shifts` = the shifts it was given to
--   med_shifts  every shift (signed-in unit); `tasks` = the tasks given to it, `task_count` = their number
-- `shifts` / `tasks` are append-only JSON lines (one toJSON entry per line, CONCAT on the server,
-- no read-modify-write); a release line closes the latest open assignment of the same id.
-- Date-times are DATETIME columns, read back as "YYYY-MM-DD HH:MM:SS" text; tasks also keep the
-- epoch of creation so their age survives a restart.
-- med_shifts.server = the server that runs the shift (two servers may share the database): a
-- restart only closes its own leftovers, the callsign check sees every server.
-- New rows come from id pools (see below), so creating a task / shift does not block (PERF-01).

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

DB = {}

DB.ready = false   -- tables created (main.lua retries on mysql:connected)

local function sql()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql or nil
end

local function serverId()
    return string.format("%s:%d", getServerName(), getServerPort())
end

function DB.isConnected()
    local m = sql()
    return m and m:mysqlIsConnected() or false
end

-- blocking SELECT -> rows (list) | false
local function query(q, ...)
    local m = sql()
    if not m then return false end
    return m:mysqlQuerySync(q, ...)
end

local function exec(q, ...)
    local m = sql()
    if m then m:mysqlExec(q, ...) end
end

-- blocking INSERT -> new id | false
local function insert(q, ...)
    local m = sql()
    local id = m and m:mysqlInsert(q, ...)
    return type(id) == "number" and id or false
end

-- md5 tag of this server on the pool rows of med_tasks (it has no server column)
local POOL_TAG = "pool:" .. md5(serverId()):sub(1, 16)

local function json(t)
    return toJSON(t or {}, true)
end

local function unjson(s)
    return (s and s ~= "" and fromJSON(s)) or {}
end

---------------------------------------------------------------- JSON lines

local function append(tbl, col, id, entry)
    exec("UPDATE " .. tbl .. " SET " .. col .. " = CONCAT(COALESCE(" .. col .. ", ''), ?) WHERE id = ?",
        toJSON(entry, true) .. "\n", id)
end

local function lines(s)
    local list = {}
    for line in tostring(s or ""):gmatch("[^\n]+") do
        local ok, e = pcall(fromJSON, line)
        if ok and type(e) == "table" then list[#list + 1] = e end
    end
    return list
end

-- Assignment lines ({ [key] = id, at } / { [key] = id, released, outcome }) -> list of
-- { id, assignedAt, releasedAt, outcome } in assignment order
function DB.assignments(s, key)
    local list, open = {}, {}
    for _, e in ipairs(lines(s)) do
        local id = tonumber(e[key])
        if id then
            if e.released then
                local a = open[id]
                if a then a.releasedAt, a.outcome, open[id] = e.released, e.outcome, nil end
            else
                local a = { id = id, assignedAt = e.at }
                list[#list + 1], open[id] = a, a
            end
        end
    end
    return list
end

---------------------------------------------------------------- id pools (PERF-01)
-- A blocking INSERT stalls the whole server for a round trip to the remote database, but a new
-- task / shift needs its id at once (it is its identity everywhere). So a few placeholder rows
-- are inserted ahead of time without blocking (status / end_reason = 'pool', tagged with this
-- server, hidden from every reader); a new task / shift takes one and fills it with an UPDATE.
-- An empty pool (or no connection) falls back to the blocking INSERT. Rows left in a pool at a
-- stop are taken back at the next start.

local pools = {
    task = {
        size = 3, ids = {}, inflight = 0,
        adopt = "SELECT id FROM med_tasks WHERE status = 'pool' AND source = ? ORDER BY id",
        adoptArg = function() return POOL_TAG end,
        insert = function(cb)
            MYSQL.insert(cb, "INSERT INTO med_tasks (title, status, source, shifts) VALUES ('', 'pool', ?, '')", POOL_TAG)
        end,
    },
    shift = {
        size = 2, ids = {}, inflight = 0,
        adopt = "SELECT id FROM med_shifts WHERE server = ? AND end_reason = 'pool' ORDER BY id",
        adoptArg = serverId,
        insert = function(cb)
            local stamp = formatDateTime(now())
            MYSQL.insert(cb, [[INSERT INTO med_shifts (server, started_at, ended_at, end_reason, tasks)
                VALUES (?, ?, ?, 'pool', '')]], serverId(), stamp, stamp)
        end,
    },
}

-- Tops the pool up with non-blocking INSERTs; a failed one is retried at the next take.
local function poolRefill(p)
    if not DB.ready or not DB.isConnected() then return end
    for _ = 1, p.size - #p.ids - p.inflight do
        p.inflight = p.inflight + 1
        p.insert(function(id)
            p.inflight = p.inflight - 1
            if type(id) == "number" then p.ids[#p.ids + 1] = id end
        end)
    end
end

-- -> pooled id | nil (empty pool or no connection: the caller inserts blocking)
local function poolTake(p)
    local id = DB.isConnected() and table.remove(p.ids, 1) or nil
    poolRefill(p)
    return id
end

---------------------------------------------------------------- start-up

-- false while the database is not reachable
function DB.init()
    if DB.ready then return true end
    if not DB.isConnected() then return false end

    exec([[CREATE TABLE IF NOT EXISTS med_tasks (
        id             INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
        title          VARCHAR(255) NOT NULL,
        description    TEXT,
        caller         VARCHAR(128) DEFAULT NULL,
        pos_x          FLOAT        DEFAULT NULL,
        pos_y          FLOAT        DEFAULT NULL,
        pos_z          FLOAT        DEFAULT NULL,
        zone           VARCHAR(64)  DEFAULT NULL,
        priority       INT          DEFAULT NULL,
        status         VARCHAR(16)  NOT NULL,
        units          TEXT,
        response_log   TEXT,
        created_ts     INT          DEFAULT NULL,
        created_at     DATETIME     DEFAULT NULL,
        prioritized_at DATETIME     DEFAULT NULL,
        assigned_at    DATETIME     DEFAULT NULL,
        closed_at      DATETIME     DEFAULT NULL,
        close_reason   TEXT,
        source         VARCHAR(64)  DEFAULT NULL,
        meta           TEXT,
        shifts         TEXT,
        KEY idx_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    exec([[CREATE TABLE IF NOT EXISTS med_shifts (
        id           INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
        server       VARCHAR(96)  DEFAULT NULL,
        callsign     VARCHAR(16)  DEFAULT NULL,
        unit_type    VARCHAR(16)  DEFAULT NULL,
        plate        VARCHAR(16)  DEFAULT NULL,
        members      TEXT,
        closed_tasks TEXT,
        started_at   DATETIME     NOT NULL,
        ended_at     DATETIME     DEFAULT NULL,
        end_reason   VARCHAR(64)  DEFAULT NULL,
        task_count   INT          NOT NULL DEFAULT 0,
        tasks        MEDIUMTEXT,
        KEY idx_open (ended_at, callsign),
        KEY idx_server (server, ended_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])

    -- Shifts of this server left open by a crash / restart are closed now, with their task links.
    local stamp = formatDateTime(now())
    for _, r in ipairs(query("SELECT id, tasks FROM med_shifts WHERE server = ? AND ended_at IS NULL", serverId()) or {}) do
        for _, a in ipairs(DB.assignments(r.tasks, "task")) do
            if not a.releasedAt then
                append("med_shifts", "tasks", r.id, { task = a.id, released = stamp, outcome = "server restart" })
                append("med_tasks", "shifts", a.id, { shift = r.id, released = stamp, outcome = "server restart" })
            end
        end
    end
    exec("UPDATE med_shifts SET ended_at = ?, end_reason = 'restart' WHERE server = ? AND ended_at IS NULL", stamp, serverId())

    -- pool rows of the last run are reused
    for _, p in pairs(pools) do
        for _, r in ipairs(query(p.adopt, p.adoptArg()) or {}) do
            p.ids[#p.ids + 1] = tonumber(r.id)
        end
    end
    DB.ready = true
    for _, p in pairs(pools) do poolRefill(p) end
    return true
end

-- Raw access for the admin panel queries (server/admin.lua).
DB.query = function(q, ...) return query(q, ...) end
DB.unjson = unjson

---------------------------------------------------------------- callsigns

-- Callsigns of the open shifts in the database (every server), non-blocking:
-- cb(set | false)  (false = database unreachable; cb may run before this returns)
function DB.openCallsigns(unitType, cb)
    if not DB.ready then return cb(false) end
    MYSQL.query(function(rows)
        if not rows then return cb(false) end
        local used = {}
        for _, r in ipairs(rows) do
            if r.callsign then used[r.callsign] = true end
        end
        cb(used)
    end, "SELECT callsign FROM med_shifts WHERE ended_at IS NULL AND unit_type = ?", unitType)
end

---------------------------------------------------------------- shift <-> task links

function DB.shiftTaskStart(shiftId, taskId)
    if not DB.ready or not shiftId then return end
    local at = formatDateTime(now())
    exec("UPDATE med_shifts SET task_count = task_count + 1 WHERE id = ?", shiftId)
    append("med_shifts", "tasks", shiftId, { task = taskId, at = at })
    append("med_tasks", "shifts", taskId, { shift = shiftId, at = at })
end

function DB.shiftTaskEnd(shiftId, taskId, outcome)
    if not DB.ready or not shiftId then return end
    local at = formatDateTime(now())
    append("med_shifts", "tasks", shiftId, { task = taskId, released = at, outcome = outcome })
    append("med_tasks", "shifts", taskId, { shift = shiftId, released = at, outcome = outcome })
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

-- -> id | false. A pooled row is filled in the background (writes keep their order).
function DB.insertTask(t)
    if not DB.ready then return false end
    local id = poolTake(pools.task)
    if id then
        exec([[UPDATE med_tasks SET title = ?, description = ?, caller = ?, pos_x = ?, pos_y = ?, pos_z = ?,
            zone = ?, status = ?, units = ?, response_log = ?, created_ts = ?, created_at = ?, source = ?,
            meta = ?, shifts = '' WHERE id = ?]],
            t.title, t.description, t.caller, t.x, t.y, t.z, t.zone, t.status,
            json(t.unitLog), json({}), t.createdAt, formatDateTime(t.createdAt), t.source, json(t.meta), id)
        return id
    end
    return insert([[INSERT INTO med_tasks
        (title, description, caller, pos_x, pos_y, pos_z, zone, status, units, response_log, created_ts, created_at, source, meta, shifts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '')]],
        t.title, t.description, t.caller, t.x, t.y, t.z, t.zone, t.status,
        json(t.unitLog), json({}), t.createdAt, formatDateTime(t.createdAt), t.source, json(t.meta))
end

function DB.saveTask(t)
    if not DB.ready then return end
    exec([[UPDATE med_tasks SET title = ?, description = ?, caller = ?, pos_x = ?, pos_y = ?, pos_z = ?,
        zone = ?, priority = ?, status = ?, units = ?, response_log = ?,
        prioritized_at = ?, assigned_at = ?, closed_at = ?, close_reason = ?, meta = ? WHERE id = ?]],
        t.title, t.description, t.caller, t.x, t.y, t.z, t.zone,
        t.priority, t.status, json(t.unitLog), json(responseLogRows(t)),
        formatDateTime(t.prioritizedAt), formatDateTime(t.assignedAt),
        formatDateTime(t.closedAt), t.closeReason, json(t.meta), t.id)
end

local function rowToTask(r)
    return {
        id          = tonumber(r.id),
        title       = r.title,
        description = r.description or "",
        caller      = r.caller or "",
        x = tonumber(r.pos_x) or 0, y = tonumber(r.pos_y) or 0, z = tonumber(r.pos_z) or 0,
        zone        = r.zone or "",
        priority    = tonumber(r.priority),
        status      = r.status,
        units       = {},
        unitLog     = unjson(r.units),
        responseLog = {},            -- epochs are not restored; rows stay in the DB
        createdAt   = tonumber(r.created_ts) or now(),
        closedLabel = r.closed_at,
        closeReason = r.close_reason,
        source      = r.source or "",
        meta        = unjson(r.meta),
    }
end

-- Open tasks (reloaded on start) and the most recent closed ones.
function DB.loadTasks(recentClosed)
    local open, closed = {}, {}
    for _, r in ipairs(query("SELECT * FROM med_tasks WHERE status NOT IN ('closed', 'pool') ORDER BY id") or {}) do
        open[#open + 1] = rowToTask(r)
    end
    for _, r in ipairs(query("SELECT * FROM med_tasks WHERE status = 'closed' ORDER BY id DESC LIMIT ?", recentClosed) or {}) do
        local t = rowToTask(r)
        t.closedAt = t.createdAt   -- only used for sorting / display fallback
        closed[#closed + 1] = t
    end
    return open, closed
end

---------------------------------------------------------------- shifts

-- -> id | false (pooled like DB.insertTask)
function DB.startShift(unit)
    if not DB.ready then return false end
    local id = poolTake(pools.shift)
    if id then
        exec([[UPDATE med_shifts SET server = ?, callsign = ?, unit_type = ?, plate = ?, members = ?, closed_tasks = ?,
            started_at = ?, ended_at = NULL, end_reason = NULL, task_count = 0, tasks = '' WHERE id = ?]],
            serverId(), unit.callsign, unit.type, unit.plate, json(unit.accounts), json({}),
            formatDateTime(unit.startedAt), id)
        return id
    end
    return insert([[INSERT INTO med_shifts (server, callsign, unit_type, plate, members, closed_tasks, started_at, tasks)
        VALUES (?, ?, ?, ?, ?, ?, ?, '')]],
        serverId(), unit.callsign, unit.type, unit.plate, json(unit.accounts), json({}), formatDateTime(unit.startedAt))
end

function DB.updateShift(unit)
    if not DB.ready or not unit.shiftId then return end
    local ids = {}
    for _, c in ipairs(unit.closedTasks) do ids[#ids + 1] = c.id end
    exec("UPDATE med_shifts SET members = ?, closed_tasks = ? WHERE id = ?",
        json(unit.accounts), json(ids), unit.shiftId)
end

function DB.endShift(unit, reason)
    DB.updateShift(unit)
    if not DB.ready or not unit.shiftId then return end
    exec("UPDATE med_shifts SET ended_at = ?, end_reason = ? WHERE id = ?",
        formatDateTime(now()), reason and tostring(reason):sub(1, 64) or nil, unit.shiftId)
end
