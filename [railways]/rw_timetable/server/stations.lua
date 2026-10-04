-- Stations: platform zones on every route track, "is this train standing at a station",
-- door sides, and trip generation from the lines.

local core = exports.rw_core

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

local tripCache = {}   -- [tripId] = trip (kept while referenced, pruned by age)

local function makeTrip(line, ds, k)
    local id = ("%s-%s-%d"):format(line.id, dayKey(ds + 3600), k)
    local cached = tripCache[id]
    if cached then return cached end
    local start = ds + (line.first + k * line.headway) * 60
    local stops = {}
    for i, s in ipairs(line.stops) do
        stops[i] = {
            station = s.station,
            name = Stations[s.station] and Stations[s.station].name or s.station,
            arr = s.arr and start + s.arr * 60 or nil,
            dep = s.dep and start + s.dep * 60 or nil,
        }
    end
    local trip = {
        id = id, line = line, number = line.prefix .. " " .. (line.base + 2 * k),
        name = line.name, from = line.from, to = line.to,
        dep = start, arr = stops[#stops].arr, stops = stops,
    }
    tripCache[id] = trip
    return trip
end

-- every trip departing in [t0, t1] (timestamps)
function tripsBetween(t0, t1)
    local out = {}
    for _, line in ipairs(TT.LINES) do
        local kMax = math.floor((line.last - line.first) / line.headway)
        local step = line.headway * 60
        local ds = dayStart(t0) - 86400
        while ds <= t1 do
            local base = ds + line.first * 60
            local k0 = math.max(0, math.ceil((t0 - base) / step))
            local k1 = math.min(kMax, math.floor((t1 - base) / step))
            for k = k0, k1 do out[#out + 1] = makeTrip(line, ds, k) end
            ds = ds + 86400
        end
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
