-- MySQL persistence through v_mysql (the shared database), two tables:
--   bt_tasks   every task; `log` = its status history, `shifts` = the shifts it was given to (also
--              the handed-over ones)
--   bt_shifts  every service; `tasks` = the tasks given to it, `task_count` = their number
-- `log` / `shifts` / `tasks` are append-only JSON lines (one toJSON entry per line, CONCAT on the
-- server, no read-modify-write); a release line closes the latest open assignment of the same id.
-- Date-times are DATETIME columns, read back as "YYYY-MM-DD HH:MM:SS" text.

DB = {}

DB.completed = 0   -- delivered tasks in the database when the resource (or the connection) started

local function sql()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql or nil
end

function DB.nowText()
    local t = getRealTime()
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", t.year + 1900, t.month + 1, t.monthday, t.hour, t.minute, t.second)
end

function DB.isConnected()
    local m = sql()
    return m and m:mysqlIsConnected() or false
end

-- blocking SELECT -> rows (list) | false
function DB.query(q, ...)
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

function DB.json(t) return toJSON(t or {}, true) end
function DB.unjson(s) return (s and s ~= "" and fromJSON(s)) or {} end

---------------------------------------------------------------- JSON lines

local function append(tbl, col, id, entry)
    exec("UPDATE " .. tbl .. " SET " .. col .. " = CONCAT(COALESCE(" .. col .. ", ''), ?) WHERE id = ?",
        toJSON(entry, true) .. "\n", id)
end

-- JSON lines -> list of entries
function DB.lines(s)
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
    for _, e in ipairs(DB.lines(s)) do
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

---------------------------------------------------------------- start-up

-- false while the database is not reachable (main.lua retries on mysql:connected)
function DB.init()
    if not DB.isConnected() then return false end
    exec([[CREATE TABLE IF NOT EXISTS bt_tasks (
        id            INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
        type          VARCHAR(32)  NOT NULL,
        urgency       VARCHAR(32)  DEFAULT NULL,
        source        VARCHAR(64)  DEFAULT NULL,
        product       VARCHAR(32)  DEFAULT NULL,
        grp           VARCHAR(8)   DEFAULT NULL,
        units         INT          DEFAULT NULL,
        from_inst     VARCHAR(64)  DEFAULT NULL,
        to_inst       VARCHAR(64)  DEFAULT NULL,
        status        VARCHAR(16)  NOT NULL,
        shift_id      INT          DEFAULT NULL,
        reserved      TINYINT      NOT NULL DEFAULT 0,
        created_at    DATETIME     DEFAULT NULL,
        assigned_at   DATETIME     DEFAULT NULL,
        picked_at     DATETIME     DEFAULT NULL,
        delivered_at  DATETIME     DEFAULT NULL,
        cancelled_at  DATETIME     DEFAULT NULL,
        cancel_reason VARCHAR(64)  DEFAULT NULL,
        log           MEDIUMTEXT,
        shifts        TEXT,
        KEY idx_status (status),
        KEY idx_shift (shift_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    exec([[CREATE TABLE IF NOT EXISTS bt_shifts (
        id          INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
        account     VARCHAR(64)  DEFAULT NULL,
        player      VARCHAR(64)  DEFAULT NULL,
        unit        VARCHAR(32)  DEFAULT NULL,
        started_at  DATETIME     DEFAULT NULL,
        ended_at    DATETIME     DEFAULT NULL,
        end_reason  VARCHAR(64)  DEFAULT NULL,
        delivered   INT          NOT NULL DEFAULT 0,
        in_transit  INT          NOT NULL DEFAULT 0,
        cancelled   INT          NOT NULL DEFAULT 0,
        pay         INT          NOT NULL DEFAULT 0,
        pay_items   TEXT,
        task_count  INT          NOT NULL DEFAULT 0,
        tasks       MEDIUMTEXT,
        KEY idx_ended (ended_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local rows = DB.query("SELECT COUNT(*) AS n FROM bt_tasks WHERE status = 'delivered'")
    DB.completed = rows and rows[1] and tonumber(rows[1].n) or 0
    return true
end

-- Leftovers of a previous run: open tasks and shifts were lost with the volatile cargo.
-- -> the tasks that were cancelled (rows) so the stock can take their reserved units back
function DB.closeLeftovers()
    local at = DB.nowText()
    local rows = DB.query([[SELECT id, status, reserved, product, grp, units, from_inst, shift_id FROM bt_tasks
        WHERE status IN ('waiting','transit')]]) or {}
    for _, r in ipairs(rows) do
        exec("UPDATE bt_tasks SET status='cancelled', cancelled_at=?, cancel_reason='restart' WHERE id=?", at, r.id)
        append("bt_tasks", "log", r.id, { at = at, event = "cancelled", info = "restart" })
        local shiftId = tonumber(r.shift_id)
        if shiftId then
            append("bt_tasks", "shifts", r.id, { shift = shiftId, released = at, outcome = "cancelled" })
            append("bt_shifts", "tasks", shiftId, { task = r.id, released = at, outcome = "cancelled" })
        end
    end
    exec("UPDATE bt_shifts SET ended_at=?, end_reason='restart' WHERE ended_at IS NULL", at)
    return rows
end

---------------------------------------------------------------- tasks

function DB.insertTask(t)
    return insert([[INSERT INTO bt_tasks (type, urgency, source, product, grp, units, from_inst, to_inst,
        status, reserved, created_at, log, shifts) VALUES (?,?,?,?,?,?,?,?,?,?,?,'','')]],
        t.type, t.urgency, t.source, t.product, t.group, t.units, t.from, t.to, "waiting", t.reserved and 1 or 0, DB.nowText())
end

function DB.setTask(id, fields)
    local sets, args = {}, {}
    for k, v in pairs(fields) do
        sets[#sets + 1] = k .. "=?"
        args[#args + 1] = v
    end
    if #sets == 0 then return end
    args[#args + 1] = id
    exec("UPDATE bt_tasks SET " .. table.concat(sets, ",") .. " WHERE id=?", unpack(args))
end

function DB.log(taskId, event, info)
    append("bt_tasks", "log", taskId, { at = DB.nowText(), event = event, info = info and tostring(info) or nil })
end

---------------------------------------------------------------- shifts

function DB.insertShift(s)
    return insert("INSERT INTO bt_shifts (account, player, unit, started_at, tasks) VALUES (?,?,?,?,'')",
        s.account, s.name, s.unit, DB.nowText())
end

function DB.endShift(id, f)
    exec("UPDATE bt_shifts SET ended_at=?, end_reason=?, delivered=?, in_transit=?, cancelled=?, pay=?, pay_items=? WHERE id=?",
        DB.nowText(), f.reason, f.delivered, f.inTransit, f.cancelled, f.pay, DB.json(f.items), id)
end

function DB.addShiftTask(shiftId, taskId)
    local at = DB.nowText()
    exec("UPDATE bt_shifts SET task_count = task_count + 1 WHERE id = ?", shiftId)
    append("bt_shifts", "tasks", shiftId, { task = taskId, at = at })
    append("bt_tasks", "shifts", taskId, { shift = shiftId, at = at })
end

function DB.releaseShiftTask(shiftId, taskId, outcome)
    local at = DB.nowText()
    append("bt_shifts", "tasks", shiftId, { task = taskId, released = at, outcome = outcome })
    append("bt_tasks", "shifts", taskId, { shift = shiftId, released = at, outcome = outcome })
end
