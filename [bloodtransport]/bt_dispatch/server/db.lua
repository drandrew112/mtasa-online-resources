-- SQLite persistence (data/bloodtransport.db): tasks, shifts, the tasks given to a shift (also
-- handed-over ones) and the status log of every task. Date-times are "YYYY-MM-DD HH:MM:SS" text.

DB = {}

local conn

function DB.nowText()
    local t = getRealTime()
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute, t.second)
end

-- sync query -> rows (list), affected, last insert id | false
function DB.query(sql, ...)
    if not conn then return false end
    local qh = dbQuery(conn, sql, ...)
    if not qh then return false end
    return dbPoll(qh, -1)
end

local function exec(sql, ...)
    if conn then dbExec(conn, sql, ...) end
end

function DB.json(t) return toJSON(t or {}, true) end
function DB.unjson(s) return (s and s ~= "" and fromJSON(s)) or {} end

function DB.init()
    conn = dbConnect("sqlite", BTD.DB_FILE)
    if not conn then
        outputDebugString("[bt_dispatch] cannot open " .. BTD.DB_FILE, 1)
        return false
    end
    dbExec(conn, [[CREATE TABLE IF NOT EXISTS tasks (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        type          TEXT NOT NULL,
        urgency       TEXT,
        source        TEXT,
        product       TEXT,
        grp           TEXT,
        units         INTEGER,
        from_inst     TEXT,
        to_inst       TEXT,
        status        TEXT NOT NULL,
        shift_id      INTEGER,
        reserved      INTEGER DEFAULT 0,
        created_at    TEXT,
        assigned_at   TEXT,
        picked_at     TEXT,
        delivered_at  TEXT,
        cancelled_at  TEXT,
        cancel_reason TEXT
    )]])
    dbExec(conn, [[CREATE TABLE IF NOT EXISTS shifts (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        account     TEXT,
        player      TEXT,
        unit        TEXT,
        started_at  TEXT,
        ended_at    TEXT,
        end_reason  TEXT,
        delivered   INTEGER DEFAULT 0,
        in_transit  INTEGER DEFAULT 0,
        cancelled   INTEGER DEFAULT 0,
        pay         INTEGER DEFAULT 0,
        pay_items   TEXT
    )]])
    dbExec(conn, [[CREATE TABLE IF NOT EXISTS shift_tasks (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id    INTEGER NOT NULL,
        task_id     INTEGER NOT NULL,
        assigned_at TEXT,
        released_at TEXT,
        outcome     TEXT
    )]])
    dbExec(conn, [[CREATE TABLE IF NOT EXISTS task_log (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        at      TEXT,
        event   TEXT,
        info    TEXT
    )]])
    dbExec(conn, "CREATE INDEX IF NOT EXISTS idx_shift_tasks_shift ON shift_tasks (shift_id)")
    dbExec(conn, "CREATE INDEX IF NOT EXISTS idx_task_log_task ON task_log (task_id)")
    return true
end

-- Leftovers of a previous run: open tasks and shifts were lost with the volatile cargo.
-- -> the tasks that were cancelled (rows) so the stock can take their reserved units back
function DB.closeLeftovers()
    local at = DB.nowText()
    local rows = DB.query("SELECT * FROM tasks WHERE status IN ('waiting','transit')") or {}
    for _, r in ipairs(rows) do
        exec("UPDATE tasks SET status='cancelled', cancelled_at=?, cancel_reason='restart' WHERE id=?", at, r.id)
        exec("INSERT INTO task_log (task_id, at, event, info) VALUES (?,?,?,?)", r.id, at, "cancelled", "restart")
    end
    exec("UPDATE shifts SET ended_at=?, end_reason='restart' WHERE ended_at IS NULL", at)
    exec("UPDATE shift_tasks SET released_at=?, outcome='cancelled' WHERE released_at IS NULL", at)
    return rows
end

---------------------------------------------------------------- tasks

function DB.insertTask(t)
    local _, _, id = DB.query([[INSERT INTO tasks (type, urgency, source, product, grp, units, from_inst, to_inst,
        status, reserved, created_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)]],
        t.type, t.urgency, t.source, t.product, t.group, t.units, t.from, t.to, "waiting", t.reserved and 1 or 0, DB.nowText())
    return id
end

function DB.setTask(id, fields)
    local sets, args = {}, {}
    for k, v in pairs(fields) do
        sets[#sets + 1] = k .. "=?"
        args[#args + 1] = v
    end
    if #sets == 0 then return end
    args[#args + 1] = id
    exec("UPDATE tasks SET " .. table.concat(sets, ",") .. " WHERE id=?", unpack(args))
end

function DB.log(taskId, event, info)
    exec("INSERT INTO task_log (task_id, at, event, info) VALUES (?,?,?,?)", taskId, DB.nowText(), event, info and tostring(info) or nil)
end

---------------------------------------------------------------- shifts

function DB.insertShift(s)
    local _, _, id = DB.query("INSERT INTO shifts (account, player, unit, started_at) VALUES (?,?,?,?)",
        s.account, s.name, s.unit, DB.nowText())
    return id
end

function DB.endShift(id, f)
    exec("UPDATE shifts SET ended_at=?, end_reason=?, delivered=?, in_transit=?, cancelled=?, pay=?, pay_items=? WHERE id=?",
        DB.nowText(), f.reason, f.delivered, f.inTransit, f.cancelled, f.pay, DB.json(f.items), id)
end

function DB.addShiftTask(shiftId, taskId)
    exec("INSERT INTO shift_tasks (shift_id, task_id, assigned_at) VALUES (?,?,?)", shiftId, taskId, DB.nowText())
end

function DB.releaseShiftTask(shiftId, taskId, outcome)
    exec("UPDATE shift_tasks SET released_at=?, outcome=? WHERE shift_id=? AND task_id=? AND released_at IS NULL",
        DB.nowText(), outcome, shiftId, taskId)
end
