-- gov_railways / server/railways.lua
-- The Railways page of /gov: the railway as a public service.
--   * operator: the company that runs the railway (setting "rail.operator": "none" |
--     "state:<code>" | "company:<id>"), picked by a minister / admin. Its members (bank access
--     to the company account) get the page and may edit the timetable, without a /gov role
--     (gov_core sector "railways").
--   * the timetable: the rows of the MySQL table `rw_timetable` (rw_timetable reads it; the
--     routes and the minutes between the stops are fixed there). A row = line + stretch (from /
--     to station) + departures (interval first..last every N min, or a single departure) + days
--     (+ an optional date, an optional fixed train number for a single one).
-- Rows are checked by rw_timetable (checkScheduleRow), written here, then rw_timetable re-reads
-- them (reloadTimetable). Every change goes to gov_log (rail.*).

loadstring(exports.gov_core:importLib())()

local A = GOV.A
local SECTOR = "railways"

GOV_DEFAULTS = {
    ["rail.operator"] = "none",     -- nobody: only ministers edit the timetable
}

local function int(v) return DB.int(v) end

local function tt()
    return isResourceRunning("rw_timetable") and exports.rw_timetable or nil
end

--- the operator spec ("none" | "state:<code>" | "company:<id>")
local function operator()
    local v = GOV.get("rail.operator")
    return type(v) == "string" and v or "none"
end

--- the row of the page as it is shown / logged
local function brief(r)
    return { line = r.line, kind = r.kind, from = r.from, to = r.to, first = r.first, last = r.last,
        headway = r.headway, days = r.days, date = r.date, number = r.number }
end

--- { day = 0..6 }: lines, timetable rows, the departures of that day (0 = today), operator, the
--- planned running costs of the next 7 days
function A.railways(p, args, reply)
    local spec = operator()
    local ids = {}
    for _, x in ipairs({ spec, (GOV.get("pt.rail") or {}).cost_payer, (GOV.get("pt.rail") or {}).cost_receiver }) do
        local cid = tonumber(tostring(x):match("^company:(%d+)$"))
        if cid then ids[#ids + 1] = cid end
    end
    GOV.companyNames(ids, function(names)
        local out = { operator = spec, payers = GOV.payerOptions(), companies = names, online = false }
        local r = tt()
        if r then
            local day = math.max(0, math.min(6, math.floor(tonumber(args.day) or 0)))
            local rows, loaded = r:getScheduleRows()
            out.online = true
            out.loaded = loaded == true
            out.lines = r:getTimetableLines()
            out.stations = r:getStations()
            out.rows = rows
            out.day = day
            out.dayTs = GOV.now() + day * 86400
            out.departures = r:getDayTimetable(out.dayTs)
            -- the planned running costs of today .. +6 days (gov_transport cost settings)
            if isResourceRunning("gov_transport") then
                out.costs = {}
                for k = 0, 6 do
                    local ts = GOV.now() + k * 86400
                    local ok, c = pcall(function() return exports.gov_transport:getRailDayCosts(ts) end)
                    local t = getRealTime(ts)
                    out.costs[k + 1] = { day = k, weekday = (t.weekday + 6) % 7 + 1, cost = ok and type(c) == "table" and c or false }
                end
            end
        end
        reply(out)
    end)
end

--- { id?, row = { line, kind, from, to, first, last, headway, days, date, number, note } }:
--- a new row (no id) or a changed one
function A.saveRailRow(p, args, reply, actor)
    local r = tt()
    if not r then return reply(false, "tt_offline") end
    local row, err = r:checkScheduleRow(type(args.row) == "table" and args.row or {})
    if not row then return reply(false, err) end
    local id = tonumber(args.id)
    local function done(ok, e)
        if ok == false then
            outputDebugString("[gov_railways] timetable row write failed: " .. tostring(e), 1)
            return reply(false, "db")
        end
        r:reloadTimetable()
        local detail = brief(row)
        detail.id = id or (tonumber(ok) or nil)
        GOV.log(actor, id and "rail.row.update" or "rail.row.create", detail)
        reply(true)
    end
    -- the optional columns: "?" + the value, or NULL in the SQL (no nil placeholders)
    local cols = { "line", "kind", "from_station", "to_station", "first_min", "last_min", "headway", "days",
        "on_date", "number", "note", "updated_at", "updated_by" }
    local vals = { row.line, row.kind, row.from, row.to, row.first, row.last, row.headway, row.days,
        row.date or false, row.number or false, row.note, GOV.now(), DB.clip(actor, 64) }
    local marks, params = {}, {}
    for i = 1, #cols do
        if vals[i] == false then marks[i] = "NULL"
        else marks[i] = "?"; params[#params + 1] = vals[i] end
    end
    if id then
        local set = {}
        for i, c in ipairs(cols) do set[i] = c .. " = " .. marks[i] end
        params[#params + 1] = id
        DB.query(function(ok, e) done(ok, e) end,
            "UPDATE rw_timetable SET " .. table.concat(set, ", ") .. " WHERE id = ?", unpack(params))
    else
        MYSQL.insert(function(newId, e) done(newId or false, e) end,
            "INSERT INTO rw_timetable (" .. table.concat(cols, ", ") .. ", active) VALUES (" .. table.concat(marks, ", ") .. ", 1)",
            unpack(params))
    end
end

--- { id, active }: pauses / resumes a row
function A.toggleRailRow(p, args, reply, actor)
    local r = tt()
    local id = tonumber(args.id)
    if not r then return reply(false, "tt_offline") end
    if not id then return reply(false, "bad_row") end
    local on = args.active == true
    DB.query(function(ok, e)
        if ok == false then return reply(false, "db") end
        r:reloadTimetable()
        GOV.log(actor, "rail.row.toggle", { id = id, active = on })
        reply(true)
    end, "UPDATE rw_timetable SET active = ?, updated_at = ?, updated_by = ? WHERE id = ?", on and 1 or 0, GOV.now(), DB.clip(actor, 64), id)
end

function A.deleteRailRow(p, args, reply, actor)
    local r = tt()
    local id = tonumber(args.id)
    if not r then return reply(false, "tt_offline") end
    if not id then return reply(false, "bad_row") end
    local old
    for _, x in ipairs(r:getScheduleRows() or {}) do if x.id == id then old = x end end
    DB.query(function(ok, e)
        if ok == false then return reply(false, "db") end
        r:reloadTimetable()
        local detail = old and brief(old) or {}
        detail.id = id
        GOV.log(actor, "rail.row.delete", detail)
        reply(true)
    end, "DELETE FROM rw_timetable WHERE id = ?", id)
end

--- { spec = "none" | "state:<code>" | "company:<id>" }: who runs the railway (minister)
function A.setRailOperator(p, args, reply, actor)
    local spec = tostring(args.spec or "none")
    local function store(v)
        GOV.set("rail.operator", v ~= "none" and v or nil, actor)
        GOV.log(actor, "rail.operator", { operator = v })
        reply(true)
    end
    if spec == "none" then return store("none") end
    if spec == "state:treasury" then return reply(false, "bad_operator") end
    GOV.checkSpec(spec, false, function(ok, err)
        if not ok or ok == "system" then return reply(false, err or "bad_operator") end
        store(ok)
    end)
end

--- export: the company that runs the railway: "none" | "state:<code>" | "company:<id>"
function getRailOperator() return operator() end

GOV.module({
    settings = { prefixes = { "rail." }, defaults = GOV_DEFAULTS },
    perms = {
        { "rail.view",             "services", 0 },
        { "rail.timetable.edit",   "services", 1 },
        { "rail.timetable.toggle", "services", 1 },
        { "rail.operator.set",     "services", 2 },
    },
    -- the people of the operator company get these without a position (gov_core sectors)
    sectors = { { id = SECTOR, setting = "rail.operator", perms = { "rail.view", "rail.timetable.edit", "rail.timetable.toggle" } } },
    actions = {
        railways = "rail.view",
        saveRailRow = "rail.timetable.edit",
        toggleRailRow = "rail.timetable.toggle",
        deleteRailRow = "rail.timetable.edit",
        setRailOperator = "rail.operator.set",
    },
    pages = {
        { id = "railways", category = "services", order = 25, script = "web/js/pages.js", need = "rail.view" },
    },
})
