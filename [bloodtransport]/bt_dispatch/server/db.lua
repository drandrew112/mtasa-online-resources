-- MySQL persistence through v_mysql (the shared database), two tables:
--   bt_tasks   every task; `log` = its status history, `shifts` = the shifts it was given to (also
--              the handed-over ones)
--   bt_shifts  every service; `tasks` = the tasks given to it, `task_count` = their number
-- `log` / `shifts` / `tasks` are append-only JSON lines (one toJSON entry per line, CONCAT on the
-- server, no read-modify-write); a release line closes the latest open assignment of the same id.
-- Date-times are DATETIME columns, read back as "YYYY-MM-DD HH:MM:SS" text.
-- New rows come from id pools (see below), so creating a task / shift does not block (PERF-01).

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

DB = {}

DB.completed = 0   -- delivered tasks in the database (all servers) at the last count, see DB.refreshCompleted
DB.ready = false   -- DB.init done

-- instance id of this server (v_main), the `server` column of every row (servers share the database)
local function serverId()
    local ok, id = pcall(function() return exports.v_main:getServerInstanceId() end)
    return ok and tonumber(id) or 1
end
DB.serverId = serverId

-- name of this instance (v_main), shown in /btadmin
function DB.instanceName()
    local ok, name = pcall(function() return exports.v_main:getServerInstanceName() end)
    return ok and type(name) == "string" and name or ("#" .. serverId())
end

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

---------------------------------------------------------------- id pools (PERF-01)
-- A blocking INSERT stalls the whole server for a round trip to the remote database, but a new
-- task / shift needs its id at once (cargo, offers, events, the stock use it). So a few
-- placeholder rows are inserted ahead of time without blocking (isPool = 1, `server` = this
-- instance, hidden from every reader); a new task / shift takes one and fills it (isPool = 0)
-- with an UPDATE (always the lowest free id). An empty pool (or no connection) falls back to the blocking INSERT. Rows left
-- in a pool at a stop are taken back at the next start.

local pools = {
    task = {
        size = 2, ids = {}, inflight = 0,
        adopt = "SELECT id FROM bt_tasks WHERE isPool = 1 AND server = ? ORDER BY id",
        insert = function(cb)
            MYSQL.insert(cb, "INSERT INTO bt_tasks (server, isPool, type, status, log, shifts) VALUES (?, 1, '', 'pool', '', '')", serverId())
        end,
    },
    shift = {
        size = 2, ids = {}, inflight = 0,
        adopt = "SELECT id FROM bt_shifts WHERE isPool = 1 AND server = ? ORDER BY id",
        insert = function(cb)
            local stamp = DB.nowText()
            MYSQL.insert(cb, "INSERT INTO bt_shifts (server, isPool, started_at, ended_at, tasks) VALUES (?, 1, ?, ?, '')",
                serverId(), stamp, stamp)
        end,
    },
}

-- ids stay ascending: a take and a fill always use the lowest id
local function poolAdd(p, id)
    p.ids[#p.ids + 1] = id
    table.sort(p.ids)
end

-- Rows already in the table are reused, never abandoned: new placeholders are inserted only while
-- fewer than `size` (2) exist, so there is always at least one free pool, and a table that holds
-- 2 or more does not get new ones. A failed INSERT is retried at the next take.
local function poolRefill(p)
    if not DB.ready or not DB.isConnected() then return end
    for _ = 1, p.size - #p.ids - p.inflight do
        p.inflight = p.inflight + 1
        p.insert(function(id)
            p.inflight = p.inflight - 1
            if type(id) == "number" then poolAdd(p, id) end
        end)
    end
end

-- Reads the free pool rows of this instance from the table (the load check) -> list of ids
local function poolLoad(p)
    local rows = DB.query(p.adopt, serverId())
    if not rows then return p.ids end   -- query failed: keep what is known
    local ids = {}
    for _, r in ipairs(rows) do
        ids[#ids + 1] = tonumber(r.id)
    end
    table.sort(ids)
    return ids
end

-- -> lowest free pooled id | nil (empty pool or no connection: the caller inserts blocking)
local function poolTake(p)
    local id = DB.isConnected() and table.remove(p.ids, 1) or nil
    poolRefill(p)
    return id
end

---------------------------------------------------------------- start-up

-- false while the database is not reachable (main.lua retries on mysql:connected)
function DB.init()
    if not DB.isConnected() then return false end
    exec([[CREATE TABLE IF NOT EXISTS bt_tasks (
        id            INT          NOT NULL AUTO_INCREMENT PRIMARY KEY,
        server        INT          NOT NULL DEFAULT 0,
        isPool        TINYINT      NOT NULL DEFAULT 0,
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
        server      INT          NOT NULL DEFAULT 0,
        isPool      TINYINT      NOT NULL DEFAULT 0,
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
    -- tables created before the server / isPool columns: add them right after id; old pool
    -- placeholders (status / end_reason = 'pool') become isPool rows of this server
    for _, tbl in ipairs({ "bt_tasks", "bt_shifts" }) do
        local c = DB.query("SELECT COUNT(*) AS n FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = 'isPool'", tbl)
        if c and c[1] and tonumber(c[1].n) == 0 then
            DB.query("ALTER TABLE " .. tbl .. " ADD COLUMN server INT NOT NULL DEFAULT 0 AFTER id, ADD COLUMN isPool TINYINT NOT NULL DEFAULT 0 AFTER server")
            DB.query("UPDATE " .. tbl .. " SET server = ?", serverId())
            DB.query("UPDATE " .. tbl .. " SET isPool = 1 WHERE " .. (tbl == "bt_tasks" and "status" or "end_reason") .. " = 'pool'")
        end
    end
    local rows = DB.query("SELECT COUNT(*) AS n FROM bt_tasks WHERE isPool = 0 AND status = 'delivered'")
    DB.completed = rows and rows[1] and tonumber(rows[1].n) or 0
    TotalDelivered = 0

    -- load check: the free pool rows of the table are taken over as they are (a reconnect keeps
    -- the list, a row just taken may not be filled yet)
    if not DB.ready then
        for _, p in pairs(pools) do p.ids = poolLoad(p) end
        DB.ready = true
    end
    for _, p in pairs(pools) do poolRefill(p) end
    return true
end

-- Re-counts the delivered tasks of every server (the servers share the database) without blocking.
-- TotalDelivered keeps only the local deliveries made since this count was sent, so the total
-- does not jump back while the answer is on its way.
local counting = false
function DB.refreshCompleted()
    if counting or not DB.ready or not DB.isConnected() then return end
    counting = true
    local sentAt = TotalDelivered
    MYSQL.query(function(rows)
        counting = false
        local n = rows and rows[1] and tonumber(rows[1].n)
        if not n then return end
        DB.completed = n
        TotalDelivered = math.max(0, TotalDelivered - sentAt)
    end, "SELECT COUNT(*) AS n FROM bt_tasks WHERE isPool = 0 AND status = 'delivered'")
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

-- -> id | false. A pooled row is filled in the background (writes keep their order).
function DB.insertTask(t)
    local id = poolTake(pools.task)
    if id then
        exec([[UPDATE bt_tasks SET isPool=0, type=?, urgency=?, source=?, product=?, grp=?, units=?, from_inst=?, to_inst=?,
            status=?, reserved=?, created_at=?, log='', shifts='' WHERE id=?]],
            t.type, t.urgency, t.source, t.product, t.group, t.units, t.from, t.to, "waiting", t.reserved and 1 or 0, DB.nowText(), id)
        return id
    end
    return insert([[INSERT INTO bt_tasks (server, isPool, type, urgency, source, product, grp, units, from_inst, to_inst,
        status, reserved, created_at, log, shifts) VALUES (?,0,?,?,?,?,?,?,?,?,?,?,?,'','')]],
        serverId(), t.type, t.urgency, t.source, t.product, t.group, t.units, t.from, t.to, "waiting", t.reserved and 1 or 0, DB.nowText())
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

-- -> id | false (pooled like DB.insertTask)
function DB.insertShift(s)
    local id = poolTake(pools.shift)
    if id then
        exec("UPDATE bt_shifts SET isPool=0, account=?, player=?, unit=?, started_at=?, ended_at=NULL, end_reason=NULL, tasks='' WHERE id=?",
            s.account, s.name, s.unit, DB.nowText(), id)
        return id
    end
    return insert("INSERT INTO bt_shifts (server, isPool, account, player, unit, started_at, tasks) VALUES (?,0,?,?,?,?,'')",
        serverId(), s.account, s.name, s.unit, DB.nowText())
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
