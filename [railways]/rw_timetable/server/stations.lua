-- Stations: platform zones on every route track, "is this train standing at a station",
-- door sides, and trip generation from the lines.

-- looked up on every call: a reloaded rw_core is a new resource and a cached exports table
-- would keep calling the old one (everything froze after rw_core reloaded)
local core = setmetatable({}, { __index = function(_, fn) return function(_, ...) return exports.rw_core[fn](nil, ...) end end })

Stations = {}          -- [id] = { def, zones = { [track] = { lo, hi, center } } }
StationList = {}

local function buildStations()
    for _, def in ipairs(TT.STATIONS) do
        local st = { id = def.id, name = def.name, city = def.city, x = def.x, y = def.y, def = def, zones = {} }
        for _, track in ipairs(TT.ROUTE_TRACKS) do
            local t, tp = core:projectToTrack(def.x, def.y, track, 40)
            if t then
                st.zones[track] = { center = tp, lo = tp - def.length / 2, hi = tp + def.length / 2 }
            end
        end
        Stations[def.id] = st
        StationList[#StationList + 1] = st
    end
end

-- station whose zone holds track position tp on track -> station | nil
function stationAt(track, tp)
    for _, st in ipairs(StationList) do
        local z = st.zones[track]
        if z and tp >= z.lo and tp <= z.hi then return st end
    end
end

-- which side of the train (facing dirSign along the track) the platform is on:
-- "left" | "right" | nil (both / unknown)
function platformSide(st, track, tp, dirSign)
    local p = st.def.platform and st.def.platform[track]
    if not p then return nil end
    local x, y, _, dx, dy = core:getTrackPoint(track, tp)
    local fx, fy = dx * dirSign, dy * dirSign
    local cross = fx * (p.y - y) - fy * (p.x - x)     -- > 0: platform on the left
    return cross > 0 and "left" or "right"
end

------------------------------------------------------------------ trips
-- One trip = one departure of the timetable (server/schedule.lua departuresOfDay): a line run
-- from `from` to `to` (the whole line or a stretch of it), times from the fixed minutes of the
-- line's stops.

local function dayStart(ts)
    local t = getRealTime(ts)
    return ts - (t.hour * 3600 + t.minute * 60 + t.second)
end

local function dayKey(ts)
    local t = getRealTime(ts)
    return ("%04d%02d%02d"):format(t.year + 1900, t.month + 1, t.monthday)
end

-- seconds of the day of a timestamp (what the web / panels show)
function secOfDay(ts)
    local t = getRealTime(ts)
    return t.hour * 3600 + t.minute * 60 + t.second
end

--- the timestamp of the wall-clock time `min` (minutes after midnight) of the day starting at ds
--- (on a daylight saving day ds + min * 60 is an hour off after the change)
function wallTs(ds, min)
    local ts = ds + min * 60
    local t = getRealTime(ts)
    local diff = (t.hour * 60 + t.minute) - min
    if diff > 720 then diff = diff - 1440 elseif diff < -720 then diff = diff + 1440 end
    return ts - diff * 60
end

--- "SL1-20261024-0615": line, service day, departure time
function tripIdOf(line, ds, min)
    return ("%s-%s-%02d%02d"):format(line.id, dayKey(ds + 3600), math.floor(min / 60), min % 60)
end

local tripCache = {}   -- [tripId] = trip (kept while referenced, pruned by age)

local function makeTrip(e, ds)
    local line = e.line
    local id = tripIdOf(line, ds, e.min)
    local sig = ("%s|%s|%s|%d"):format(e.from, e.to, e.number, e.row.id)
    local cached = tripCache[id]
    -- a changed timetable builds the trip again, unless a train already runs it
    if cached and (cached.sig == sig or tripInUse(id)) then return cached end
    local i, j = lineSpan(line, e.from, e.to)
    local start = wallTs(ds, e.min)
    local off = line.stops[i].dep
    local stops = {}
    for k = i, j do
        local s = line.stops[k]
        stops[#stops + 1] = {
            station = s.station,
            name = Stations[s.station] and Stations[s.station].name or s.station,
            arr = k > i and s.arr and start + (s.arr - off) * 60 or nil,
            dep = k < j and s.dep and start + (s.dep - off) * 60 or nil,
            track = s.track,
        }
    end
    local trip = {
        id = id, line = line, number = line.prefix .. " " .. e.number, sig = sig,
        name = line.name, from = e.from, to = e.to, row = e.row.id, extra = e.row.kind == "single",
        dep = start, arr = stops[#stops].arr, stops = stops,
        auto = line.auto and { preset = line.auto.preset, spawn = lineSpawn(line, e.from) } or false,
    }
    tripCache[id] = trip
    return trip
end

-- every trip departing in [t0, t1] (timestamps)
function tripsBetween(t0, t1)
    local out = {}
    local ds = dayStart(dayStart(t0) - 43200)     -- the day before (its trips may still run)
    while ds <= t1 do
        for _, e in ipairs(departuresOfDay(ds)) do
            local dep = wallTs(ds, e.min)
            if dep >= t0 and dep <= t1 then out[#out + 1] = makeTrip(e, ds) end
        end
        ds = dayStart(ds + 86400 + 7200)     -- the next local midnight (a DST day is 23 / 25 h)
    end
    table.sort(out, function(a, b) return a.dep < b.dep end)
    return out
end

function getTrip(id)
    return tripCache[id]
end

-- drop cached trips that ended long ago and are not running
function pruneTrips(isActive)
    local limit = getRealTime().timestamp - 3 * 3600
    for id, t in pairs(tripCache) do
        if t.arr < limit and not isActive(id) then tripCache[id] = nil end
    end
end

------------------------------------------------------------------ exports

function getStations()
    local t = {}
    for _, st in ipairs(StationList) do
        t[#t + 1] = { id = st.id, name = st.name, city = st.city, x = st.x, y = st.y }
    end
    return t
end

-- -> stationId, name | false
function isConsistAtStation(consistId)
    local c = core:getConsist(consistId)
    if not c then return false end
    local st = stationAt(c.track, c.tp)
    if st then return st.id, st.name end
    return false
end

addEventHandler("onResourceStart", resourceRoot, buildStations)
