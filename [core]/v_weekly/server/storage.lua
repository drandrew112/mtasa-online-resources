-- weekly_schedule persistence (v_mysql). Every row is cached in memory; the
-- table is tiny (one row per configured week).

STORE = {}

local rows = {}     -- rows[week_start] = data table
local loaded = false

local function sql() return exports.v_mysql end

function STORE.isLoaded() return loaded end

local function decode(s)
    if type(s) ~= "string" or s == "" then return {} end
    local ok, t = pcall(fromJSON, s)
    return (ok and type(t) == "table") and t or {}
end

-- true on success; false when the database is not reachable yet
function STORE.load()
    local res = sql():mysqlQuerySync("SELECT week_start, data FROM weekly_schedule")
    if not res then return false end
    rows = {}
    for _, r in ipairs(res) do
        local ws = tonumber(r.week_start)
        if ws then rows[ws] = decode(r.data) end
    end
    loaded = true
    return true
end

function STORE.ensureTable()
    sql():mysqlExec([[CREATE TABLE IF NOT EXISTS weekly_schedule (
        week_start INT NOT NULL PRIMARY KEY,
        data MEDIUMTEXT NOT NULL,
        updated_by VARCHAR(50) DEFAULT NULL,
        updated_at INT NOT NULL DEFAULT 0
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
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
    rows[ws] = data
    sql():mysqlExec(
        "REPLACE INTO weekly_schedule (week_start, data, updated_by, updated_at) VALUES (?, ?, ?, ?)",
        ws, toJSON(data, true), tostring(by or ""):sub(1, 50), getRealTime().timestamp)
end

function STORE.delete(ws)
    rows[ws] = nil
    sql():mysqlExec("DELETE FROM weekly_schedule WHERE week_start = ?", ws)
end
