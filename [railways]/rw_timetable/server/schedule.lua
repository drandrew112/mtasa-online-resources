-- The timetable: WHEN the trains run. It lives in the MySQL table `rw_timetable` (one row per
-- departure rule) and is edited on the /gov Railways page (gov_railways). The routes - stops,
-- the minutes between them, consist, spawn points - stay fixed in TT.LINES; a row only picks a
-- line, the stretch of it (from / to station), the departure time(s) and the days:
--   kind "interval": from first_min to last_min every headway minutes (minutes after midnight)
--   kind "single":   one departure at first_min (an extra train, e.g. one a day)
--   days:    bit mask Monday = 1, Tuesday = 2 ... Sunday = 64 (127 = every day)
--   on_date: "YYYY-MM-DD" = only on that day (NULL = every day of `days`)
--   number:  fixed train number of a single departure; else line.base + 2 * n (the n-th
--            departure of the line that day without a fixed number)
-- Two departures of the same line in the same minute = one train (a single row wins).
-- An empty table is filled with TT.SEED (the timetable before the table existed). The table is
-- re-read every TT.SCHEDULE.RELOAD s (the other instance) and on reloadTimetable() (gov_railways
-- after a change). Until the first read succeeds TT.SEED runs.

if not MYSQL then loadstring(exports.v_mysql:importAsync())() end

local S = TT.SCHEDULE
local SCHEMA = [[CREATE TABLE IF NOT EXISTS rw_timetable (
    id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    line VARCHAR(16) NOT NULL,
    kind VARCHAR(8) NOT NULL DEFAULT 'interval',
    from_station VARCHAR(24) NOT NULL,
    to_station VARCHAR(24) NOT NULL,
    first_min SMALLINT NOT NULL DEFAULT 0,
    last_min SMALLINT NOT NULL DEFAULT 0,
    headway SMALLINT NOT NULL DEFAULT 0,
    days TINYINT NOT NULL DEFAULT 127,
    on_date VARCHAR(10) NULL DEFAULT NULL,
    number INT NULL DEFAULT NULL,
    active TINYINT NOT NULL DEFAULT 1,
    note VARCHAR(128) NOT NULL DEFAULT '',
    updated_at INT NOT NULL DEFAULT 0,
    updated_by VARCHAR(64) NOT NULL DEFAULT ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]]

LineById = {}
for _, line in ipairs(TT.LINES) do LineById[line.id] = line end

SCHED = { rows = {}, version = 0, loaded = false, sig = "" }

local function int(v) return math.floor(tonumber(v) or 0) end

------------------------------------------------------------------ routes

--- the spawn point of a line at a station (rw_core SPAWNS id) or nil: a trip can only start where
--- rw_auto / the depots can create its train
function lineSpawn(line, station)
    if station == line.from and line.auto then return line.auto.spawn end
    return line.origins and line.origins[station] or nil
end

--- the stop indices of a stretch: the first stop of `from` that has a departure, the last stop
--- of `to` after it -> i, j | nil
function lineSpan(line, from, to)
    for i, s in ipairs(line.stops) do
        if s.station == from and s.dep then
            for j = #line.stops, i + 1, -1 do
                local e = line.stops[j]
                if e.station == to and e.arr then return i, j end
            end
            return nil
        end
    end
end

------------------------------------------------------------------ rows

local function fromDb(r)
    return {
        id = int(r.id), line = tostring(r.line), kind = tostring(r.kind),
        from = tostring(r.from_station), to = tostring(r.to_station),
        first = int(r.first_min), last = int(r.last_min), headway = int(r.headway), days = int(r.days),
        date = type(r.on_date) == "string" and r.on_date ~= "" and r.on_date or nil,
        number = tonumber(r.number) and int(r.number) or nil,
        active = int(r.active) == 1, note = tostring(r.note or ""),
        updatedAt = int(r.updated_at), updatedBy = tostring(r.updated_by or ""),
    }
end

--- the seed rows (TT.SEED) with ids 1..n
local function seedRows()
    local out = {}
    for i, e in ipairs(TT.SEED) do
        local line = LineById[e.line]
        out[i] = { id = i, line = e.line, kind = e.kind or "interval", from = e.from or line.from, to = e.to or line.to,
            first = e.first, last = e.last or 0, headway = e.headway or 0, days = e.days or 127, date = nil,
            number = e.number, active = true, note = e.note or "", updatedAt = 0, updatedBy = "seed" }
    end
    return out
end

local function signature(rows)
    local t = {}
    for i, r in ipairs(rows) do
        t[i] = table.concat({ r.id, r.line, r.kind, r.from, r.to, r.first, r.last, r.headway, r.days,
            r.date or "", r.number or "", r.active and 1 or 0 }, "|")
    end
    return table.concat(t, ";")
end

local function setRows(rows)
    local sig = signature(rows)
    SCHED.rows = rows
    if sig ~= SCHED.sig then
        SCHED.sig = sig
        SCHED.version = SCHED.version + 1
        dayCache = {}
    end
end

--- checks a timetable row of the /gov page (gov_railways) -> the clean row | false, error key
--- row = { line, kind, from, to, first, last, headway, days, date, number, note } (minutes)
function checkScheduleRow(row)
    if type(row) ~= "table" then return false, "bad_row" end
    local line = LineById[tostring(row.line or "")]
    if not line then return false, "bad_line" end
    local kind = row.kind == "single" and "single" or (row.kind == "interval" and "interval" or nil)
    if not kind then return false, "bad_kind" end
    local from, to = tostring(row.from or line.from), tostring(row.to or line.to)
    if not lineSpan(line, from, to) then return false, "bad_stretch" end
    if not lineSpawn(line, from) then return false, "no_spawn" end
    local first = tonumber(row.first)
    if not first or first < 0 or first > 1439 or first % 1 ~= 0 then return false, "bad_time" end
    local out = { line = line.id, kind = kind, from = from, to = to, first = first, last = 0, headway = 0,
        days = 127, date = nil, number = nil, note = tostring(row.note or ""):sub(1, 128) }
    if kind == "interval" then
        local last, hw = tonumber(row.last), tonumber(row.headway)
        if not last or last < first or last > 1439 or last % 1 ~= 0 then return false, "bad_last" end
        if not hw or hw < S.MIN_HEADWAY or hw > 1440 or hw % 1 ~= 0 then return false, "bad_headway" end
        out.last, out.headway = last, hw
    end
    local days = tonumber(row.days or 127)
    if not days or days < 1 or days > 127 or days % 1 ~= 0 then return false, "bad_days" end
    out.days = days
    if row.date ~= nil and row.date ~= "" and row.date ~= false then
        local y, m, d = tostring(row.date):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        if not y or tonumber(m) < 1 or tonumber(m) > 12 or tonumber(d) < 1 or tonumber(d) > 31 then return false, "bad_date" end
        out.date = ("%s-%s-%s"):format(y, m, d)
    end
    if row.number ~= nil and row.number ~= "" and row.number ~= false then
        local n = tonumber(row.number)
        if kind ~= "single" or not n or n < 1 or n > 99999 or n % 1 ~= 0 then return false, "bad_number" end
        out.number = n
    end
    return out
end

------------------------------------------------------------------ the departures of a day

dayCache = {}    -- [dayKey] = { version, list = { entry, ... } }

local function onDay(days, weekday)          -- weekday: getRealTime (0 = Sunday)
    local idx = (weekday + 6) % 7              -- Monday = 0
    return math.floor(days / 2 ^ idx) % 2 == 1
end

--- the departures of the service day starting at ds (local midnight):
--- { { line, row, min, from, to, number|nil }, ... } by line, then minute
function departuresOfDay(ds)
    local t = getRealTime(ds + 3600)
    local key = ("%04d%02d%02d"):format(t.year + 1900, t.month + 1, t.monthday)
    local c = dayCache[key]
    if c and c.version == SCHED.version then return c.list end
    local date = ("%04d-%02d-%02d"):format(t.year + 1900, t.month + 1, t.monthday)

    local perLine = {}                          -- [line] = { [min] = entry }
    local function add(r, m)
        local map = perLine[r.line] or {}
        perLine[r.line] = map
        local cur = map[m]
        if cur and cur.row.kind == "single" and r.kind ~= "single" then return end
        map[m] = { line = LineById[r.line], row = r, min = m, from = r.from, to = r.to,
            number = r.kind == "single" and r.number or nil }
    end
    for _, r in ipairs(SCHED.rows) do
        if r.active and LineById[r.line] and onDay(r.days, t.weekday) and (not r.date or r.date == date)
            and lineSpan(LineById[r.line], r.from, r.to) then
            if r.kind == "single" then add(r, r.first)
            elseif r.headway > 0 then
                for m = r.first, r.last, r.headway do add(r, m) end
            end
        end
    end

    local list = {}
    for _, line in ipairs(TT.LINES) do
        local map = perLine[line.id]
        if map then
            local mins = {}
            for m in pairs(map) do mins[#mins + 1] = m end
            table.sort(mins)
            local n = 0
            for _, m in ipairs(mins) do
                local e = map[m]
                if not e.number then
                    e.number = line.base + 2 * n
                    n = n + 1
                end
                list[#list + 1] = e
            end
        end
    end
    dayCache[key] = { version = SCHED.version, list = list }
    return list
end

------------------------------------------------------------------ loading

local function load(cb)
    MYSQL.query(function(rows)
        if rows then
            local out = {}
            for i, r in ipairs(rows) do out[i] = fromDb(r) end
            setRows(out)
            if not SCHED.loaded then
                outputDebugString(("[rw_timetable] timetable loaded: %d rows"):format(#out))
            end
            SCHED.loaded = true
        end
        if cb then cb(rows ~= false) end
    end, "SELECT * FROM rw_timetable ORDER BY id")
end

--- fills an empty table with TT.SEED (fixed ids: two instances starting together insert once)
local function seed(cb)
    MYSQL.query(function(rows)
        if not rows then return cb(false) end
        if int(rows[1] and rows[1].n) > 0 then return cb(true) end
        local vals, args = {}, {}
        for _, r in ipairs(seedRows()) do
            vals[#vals + 1] = "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            for _, v in ipairs({ r.id, r.line, r.kind, r.from, r.to, r.first, r.last, r.headway, r.days, r.note,
                getRealTime().timestamp, "seed", 1 }) do args[#args + 1] = v end
        end
        MYSQL.query(function(ok, err)
            if ok == false then outputDebugString("[rw_timetable] seeding the timetable failed: " .. tostring(err), 1)
            else outputDebugString(("[rw_timetable] empty timetable table filled with the %d seed rows"):format(#vals)) end
            cb(ok ~= false)
        end, "INSERT IGNORE INTO rw_timetable (id, line, kind, from_station, to_station, first_min, last_min, headway, days, note, updated_at, updated_by, active) VALUES "
            .. table.concat(vals, ", "), unpack(args))
    end, "SELECT COUNT(*) AS n FROM rw_timetable")
end

local function start()
    MYSQL.query(function(ok, err)
        if ok == false then
            outputDebugString("[rw_timetable] timetable table: " .. tostring(err) .. " (the seed timetable runs, retry in 30 s)", 1)
            return setTimer(start, 30000, 1)
        end
        seed(function() load() end)
    end, SCHEMA)
end

--- export: re-reads the table now (gov_railways after a change)
function reloadTimetable()
    load()
    return true
end

--- export: the stored rows (as the /gov page edits them) + whether they come from the table
function getScheduleRows()
    local out = {}
    for i, r in ipairs(SCHED.rows) do
        out[i] = { id = r.id, line = r.line, kind = r.kind, from = r.from, to = r.to, first = r.first, last = r.last,
            headway = r.headway, days = r.days, date = r.date or false, number = r.number or false, active = r.active,
            note = r.note, updatedAt = r.updatedAt, updatedBy = r.updatedBy }
    end
    return out, SCHED.loaded
end

--- export: the routes a row may use: { id, prefix, name, base, track, from, to, stops = { {station,
--- name, arr, dep} }, origins = { station, ... } }
function getTimetableLines()
    local out = {}
    for i, line in ipairs(TT.LINES) do
        local stops, origins, seen = {}, {}, {}
        for k, s in ipairs(line.stops) do
            stops[k] = { station = s.station, name = Stations[s.station] and Stations[s.station].name or s.station,
                arr = s.arr or false, dep = s.dep or false }
            if s.dep and not seen[s.station] and lineSpawn(line, s.station) then
                seen[s.station] = true
                origins[#origins + 1] = s.station
            end
        end
        out[i] = { id = line.id, prefix = line.prefix, name = line.name, base = line.base, track = line.track,
            from = line.from, to = line.to, stops = stops, origins = origins }
    end
    return out
end

--- export: the departures of a day (the day of timestamp ts, default today), as the trains run:
--- { { tripId, line, number, category (IC / RB), stops (count), from, to, dep, arr (minutes of the
--- day; arr may pass 1440), row, single } }
function getDayTimetable(ts)
    local t = tonumber(ts) or getRealTime().timestamp
    local tt = getRealTime(t)
    local ds = t - (tt.hour * 3600 + tt.minute * 60 + tt.second)
    local out = {}
    for _, e in ipairs(departuresOfDay(ds)) do
        local i, j = lineSpan(e.line, e.from, e.to)
        local off = e.line.stops[i].dep
        out[#out + 1] = { line = e.line.id, number = e.line.prefix .. " " .. e.number, from = e.from, to = e.to,
            category = e.line.prefix, stops = j - i + 1,
            dep = e.min, arr = e.min + (e.line.stops[j].arr - off), row = e.row.id, single = e.row.kind == "single",
            tripId = tripIdOf(e.line, ds, e.min) }
    end
    table.sort(out, function(a, b) if a.dep ~= b.dep then return a.dep < b.dep end return a.line < b.line end)
    return out
end

SCHED.rows = seedRows()
SCHED.sig = signature(SCHED.rows)
addEventHandler("onResourceStart", resourceRoot, function()
    start()
    setTimer(function() if SCHED.loaded then load() end end, S.RELOAD * 1000, 0)
end)
