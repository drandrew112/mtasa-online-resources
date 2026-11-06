if not MYSQL then loadstring(exports.v_mysql:importAsync())() end
-- ER persistence (v_mysql): hosp_cases (one row per case, the full case as JSON), hosp_events (the patient
-- pathway: every event with time, kind, actor), hosp_stock (supplies per hospital).
--   * case ids continue from MAX(id) (several server instances: the id is taken at insert time too)
--   * a ped that survives a med_hospitals restart gets its whole case back (element data er.case.id)
--   * open cases whose ped is gone (server restart) are closed as "interrupted" with a partial Ambuláns lap

ERDB = { ready = false }

-- several server instances share the database: every row belongs to the instance (v_main id)
local function instance()
    local res = getResourceFromName("v_main")
    if not res or getResourceState(res) ~= "running" then return 0 end
    local ok, id = pcall(function() return exports.v_main:getServerInstanceId() end)
    return ok and tonumber(id) or 0
end

local function sql()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql or nil
end

-- non-blocking write (v_mysql mysqlExec: dbExec, no result)
local function dbx(q, ...)
    local m = sql()
    if m then m:mysqlExec(q, ...) end
end

-- the case without the runtime parts (elements, timers) as JSON
local SKIP = { ped = true, treating = true, bed = true, pending = false }
local function snapshot(c)
    local out = {}
    for k, v in pairs(c) do
        if not SKIP[k] and type(v) ~= "userdata" and type(v) ~= "function" then out[k] = v end
    end
    if type(c.pending) == "table" then
        local p = {}
        for k, v in pairs(c.pending) do if type(v) ~= "userdata" then p[k] = v end end
        out.pending = p
    end
    out.bedRef = c.bed and { kind = c.bed.ward and "ward" or "icu", ward = c.bed.ward } or nil
    return toJSON(out, true)
end

function ERDB.setup(done)
    local m = sql()
    if not m then return done and done() end
    m:mysqlExec([[CREATE TABLE IF NOT EXISTS hosp_cases (
        instance SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        id INT UNSIGNED NOT NULL,
        hospital VARCHAR(32) NOT NULL,
        name VARCHAR(96) NOT NULL DEFAULT '',
        status VARCHAR(24) NOT NULL DEFAULT '',
        outcome VARCHAR(24) NOT NULL DEFAULT '',
        triage TINYINT UNSIGNED NOT NULL DEFAULT 0,
        created_at INT UNSIGNED NOT NULL,
        closed_at INT UNSIGNED NULL,
        data MEDIUMTEXT,
        PRIMARY KEY (instance, id), KEY idx_hc_open (closed_at), KEY idx_hc_hosp (hospital)
    ) DEFAULT CHARSET=utf8mb4]])
    m:mysqlExec([[CREATE TABLE IF NOT EXISTS hosp_events (
        id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
        instance SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        case_id INT UNSIGNED NOT NULL,
        at INT UNSIGNED NOT NULL,
        kind VARCHAR(24) NOT NULL,
        actor VARCHAR(64) NOT NULL DEFAULT '',
        data TEXT,
        KEY idx_he_case (instance, case_id)
    ) DEFAULT CHARSET=utf8mb4]])
    m:mysqlExec([[CREATE TABLE IF NOT EXISTS hosp_stock (
        instance SMALLINT UNSIGNED NOT NULL DEFAULT 0,
        hospital VARCHAR(32) NOT NULL,
        data TEXT,
        updated_at INT UNSIGNED NOT NULL,
        PRIMARY KEY (instance, hospital)
    ) DEFAULT CHARSET=utf8mb4]])
    MYSQL.query(function(rows)
        local maxId = type(rows) == "table" and rows[1] and tonumber(rows[1].m) or 0
        ER.nextId = math.max(ER.nextId or 1, (maxId or 0) + 1)
        ERDB.ready = true
        if done then done() end
    end, "SELECT MAX(id) AS m FROM hosp_cases WHERE instance = ?", instance())
end

function ERDB.insertCase(c)
    if not ERDB.ready then return end
    dbx("INSERT INTO hosp_cases (instance, id, hospital, name, status, outcome, triage, created_at, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)",
        instance(), c.id, c.hospital, tostring(c.name or ""), tostring(c.status or ""), tostring(c.outcome or ""), c.triage or 0, c.created or getRealTime().timestamp, snapshot(c))
end

-- writes are coalesced per case (a case changes many times a second while it is worked on)
local dirty, flushTimer = {}, nil
local function flush()
    flushTimer = nil
    if not ERDB.ready then return end
    for c in pairs(dirty) do
        dbx("UPDATE hosp_cases SET name = ?, status = ?, outcome = ?, triage = ?, data = ? WHERE instance = ? AND id = ?",
            tostring(c.name or ""), tostring(c.status or ""), tostring(c.outcome or ""), c.triage or 0, snapshot(c), instance(), c.id)
    end
    dirty = {}
end
function ERDB.saveCase(c)
    dirty[c] = true
    if not flushTimer then flushTimer = setTimer(flush, 2000, 1) end
end

function ERDB.closeCase(c, outcome)
    dirty[c] = nil
    if not ERDB.ready then return end
    dbx("UPDATE hosp_cases SET status = ?, outcome = ?, closed_at = ?, data = ? WHERE instance = ? AND id = ?",
        tostring(c.status or "closed"), tostring(outcome or c.outcome or ""), getRealTime().timestamp, snapshot(c), instance(), c.id)
end

function ERDB.event(c, kind, text, actor)
    if not ERDB.ready or not c.id then return end
    dbx("INSERT INTO hosp_events (instance, case_id, at, kind, actor, data) VALUES (?, ?, ?, ?, ?, ?)",
        instance(), c.id, getRealTime().timestamp, tostring(kind):sub(1, 24), tostring(actor or ""):sub(1, 64), toJSON({ text = text }, true))
end

-- the full case data of an open case (restore after a resource restart). cb(table | false)
function ERDB.loadCase(id, cb)
    if not ERDB.ready then return cb(false) end
    MYSQL.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        cb(r and fromJSON(r.data or "") or false)
    end, "SELECT data FROM hosp_cases WHERE instance = ? AND id = ? AND closed_at IS NULL", instance(), id)
end

-- open cases of this server whose ped no longer exists: interrupted care (K26)
function ERDB.closeOrphans(alive)
    if not ERDB.ready then return end
    MYSQL.query(function(rows)
        for _, r in ipairs(type(rows) == "table" and rows or {}) do
            local id = tonumber(r.id)
            if not alive[id] and ER.byHospital[r.hospital] then
                local c = fromJSON(r.data or "") or {}
                c.id, c.hospital = id, r.hospital
                c.status, c.outcome = "interrupted", "interrupted"
                c.events = c.events or {}
                if ER.writeAmbulatory then ER.writeAmbulatory(c, "interrupted") end
                ERDB.closeCase(c, "interrupted")
            end
        end
    end, "SELECT id, hospital, data FROM hosp_cases WHERE instance = ? AND closed_at IS NULL", instance())
end

---------------------------------------------------------------- supplies

function ERDB.loadStock(hospitalId, cb)
    if not ERDB.ready then return cb(false) end
    MYSQL.query(function(rows)
        local r = type(rows) == "table" and rows[1]
        cb(r and fromJSON(r.data or "") or false)
    end, "SELECT data FROM hosp_stock WHERE instance = ? AND hospital = ?", instance(), hospitalId)
end

function ERDB.saveStock(hospitalId, data)
    if not ERDB.ready then return end
    dbx("INSERT INTO hosp_stock (instance, hospital, data, updated_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data), updated_at = VALUES(updated_at)",
        instance(), hospitalId, toJSON(data, true), getRealTime().timestamp)
end
