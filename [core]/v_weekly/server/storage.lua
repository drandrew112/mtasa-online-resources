-- weekly_schedule persistence (v_mysql). Every row is cached in memory; the
-- table is tiny (one row per configured week).
--
-- The table maintains itself:
--   * ensureTable() creates it and adds the columns older versions lack;
--   * the running week always has its own row (seeded from the inherited week
--     on boot / rollover), rows older than WEEKLY.KEEP_WEEKS are pruned;
--   * every WEEKLY.SYNC_INTERVAL the rows are re-read, so changes made by
--     another server instance (or by hand in the database) are picked up.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

STORE = {}

local rows = {}     -- rows[week_start] = data table
local raws = {}     -- raws[week_start] = stored JSON text (change detection of the sync)
local loaded = false
local writeSeq = 0  -- bumped by every local write; a sync started before it is dropped

local function sql() return exports.v_mysql end

function STORE.isLoaded() return loaded end

local function decode(s)
    if type(s) ~= "string" or s == "" then return {} end
    local ok, t = pcall(fromJSON, s)
    return (ok and type(t) == "table") and t or {}
end

local function readRows(res)
    local r, st = {}, {}
    for _, row in ipairs(res) do
        local ws = tonumber(row.week_start)
        if ws then
            r[ws] = decode(row.data)
            st[ws] = tostring(row.data or "")
        end
    end
    return r, st
end

-- true on success; false when the database is not reachable yet
function STORE.load()
    local res = sql():mysqlQuerySync("SELECT week_start, data FROM weekly_schedule")
    if not res then return false end
    rows, raws = readRows(res)
    loaded = true
    return true
end

-- columns added after the first version: name -> definition
local COLUMNS = {
    { "updated_by", "VARCHAR(50) DEFAULT NULL" },
    { "updated_at", "INT NOT NULL DEFAULT 0" },
}

function STORE.ensureTable()
    sql():mysqlQuerySync([[CREATE TABLE IF NOT EXISTS weekly_schedule (
        week_start INT NOT NULL PRIMARY KEY,
        data MEDIUMTEXT NOT NULL,
        updated_by VARCHAR(50) DEFAULT NULL,
        updated_at INT NOT NULL DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    local cols = sql():mysqlQuerySync("SHOW COLUMNS FROM weekly_schedule")
    if type(cols) ~= "table" then return end
    local have = {}
    for _, c in ipairs(cols) do have[tostring(c.Field or c.field or ""):lower()] = true end
    for _, c in ipairs(COLUMNS) do
        if not have[c[1]] then
            sql():mysqlQuerySync(("ALTER TABLE weekly_schedule ADD COLUMN `%s` %s"):format(c[1], c[2]))
            outputServerLog("[v_weekly] weekly_schedule: added column " .. c[1])
        end
    end
end

function STORE.get(ws) return rows[ws] end

-- ascending list of configured week_start values
function STORE.starts()
    local list = {}
    for ws in pairs(rows) do list[#list + 1] = ws end
    table.sort(list)
    return list
end

function STORE.set(ws, data, by)
    local json = toJSON(data, true)
    rows[ws], raws[ws] = data, json
    writeSeq = writeSeq + 1
    sql():mysqlExec(
        "REPLACE INTO weekly_schedule (week_start, data, updated_by, updated_at) VALUES (?, ?, ?, ?)",
        ws, json, tostring(by or ""):sub(1, 50), getRealTime().timestamp)
end

-- Gives the week its own row when it has none (a snapshot of the inherited
-- data). INSERT IGNORE: another instance may have written it meanwhile.
function STORE.seed(ws, data)
    if rows[ws] then return false end
    local json = toJSON(data, true)
    rows[ws], raws[ws] = data, json
    writeSeq = writeSeq + 1
    sql():mysqlExec(
        "INSERT IGNORE INTO weekly_schedule (week_start, data, updated_by, updated_at) VALUES (?, ?, ?, ?)",
        ws, json, "auto", getRealTime().timestamp)
    return true
end

function STORE.delete(ws)
    rows[ws], raws[ws] = nil, nil
    writeSeq = writeSeq + 1
    sql():mysqlExec("DELETE FROM weekly_schedule WHERE week_start = ?", ws)
end

-- Deletes the rows older than `before` (only when `keep` has its own row, so
-- nothing still inherits from them).
function STORE.prune(before, keep)
    if not rows[keep] then return end
    local any = false
    for ws in pairs(rows) do
        if ws < before then rows[ws], raws[ws], any = nil, nil, true end
    end
    if any then
        writeSeq = writeSeq + 1
        sql():mysqlExec("DELETE FROM weekly_schedule WHERE week_start < ?", before)
    end
end

-- Re-reads the table in the background; onChange() runs when another
-- instance (or a manual edit) changed, added or removed a row.
function STORE.sync(onChange)
    if not loaded then return end
    local seq = writeSeq
    MYSQL.query(function(res)
        if type(res) ~= "table" or seq ~= writeSeq then return end
        local r, st = readRows(res)
        local changed = false
        for ws, t in pairs(st) do
            if raws[ws] ~= t then changed = true break end
        end
        if not changed then
            for ws in pairs(raws) do
                if not st[ws] then changed = true break end
            end
        end
        if not changed then return end
        rows, raws = r, st
        onChange()
    end, "SELECT week_start, data FROM weekly_schedule")
end
