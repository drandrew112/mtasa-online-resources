-- pt_web :: server/provider_rail.lua
-- Sunline Rail (the [railways] resources) as a pt_web provider, plus the data of the live
-- network map (map.html). Everything is read through exports, nothing here is required: a
-- stopped rw_* resource only makes the provider offline.

ProviderAdapters = ProviderAdapters or {}
local TT_RES = "rw_timetable"

-- secOfDay value of a trip -> timestamp, relative to the trip departure (trips cross midnight)
local function absTime(depTs, depSec, sec)
    if sec == nil then return nil end
    return depTs + ((sec - depSec) % 86400)
end

ProviderAdapters.rail = function()
    local P = {}

    function P.online() return Util.running(TT_RES) end

    function P.stops()
        local out = {}
        for _, s in ipairs(Util.call(TT_RES, "getStations") or {}) do
            out[#out + 1] = { id = s.id, name = s.name, city = s.city, x = s.x, y = s.y }
        end
        return out
    end

    function P.trips(t0, t1)
        local out = {}
        for _, v in ipairs(Util.call(TT_RES, "getAllServices", t0, t1) or {}) do
            local depTs, depSec = v.depTimestamp, v.dep
            local stops = {}
            for i, s in ipairs(v.stops or {}) do
                stops[i] = {
                    stop = s.station,
                    arr = i > 1 and absTime(depTs, depSec, s.arr) or nil,
                    dep = i < #v.stops and absTime(depTs, depSec, s.dep) or nil,
                    actArr = absTime(depTs, depSec, s.actArr), actDep = absTime(depTs, depSec, s.actDep),
                    state = s.state or "pending",
                }
            end
            out[#out + 1] = {
                id = v.tripId, line = v.line, number = v.id, name = v.name, headsign = v.toName,
                status = v.status == "active" and "active" or v.status, delay = tonumber(v.delay) or 0,
                stops = stops,
            }
        end
        return out
    end

    function P.board(stopId, rows)
        return Util.call(TT_RES, "getStationBoard", stopId, rows) or false
    end

    -- lines derived from the trips of the next two hours (rw_timetable has no line export)
    function P.lines()
        local now = Util.now()
        local byLine, order = {}, {}
        for _, v in ipairs(Util.call(TT_RES, "getAllServices", now - 1800, now + 7200) or {}) do
            local l = byLine[v.line]
            if not l then
                local names = {}
                for _, s in ipairs(v.stops or {}) do names[#names + 1] = s.name end
                l = { id = v.line, code = tostring(v.id):match("^(%a+)") or "", name = v.name,
                    from = v.fromName, to = v.toName, stops = names, deps = {} }
                byLine[v.line] = l
                order[#order + 1] = l
            end
            l.deps[#l.deps + 1] = v.depTimestamp
        end
        for _, l in ipairs(order) do
            table.sort(l.deps)
            l.headway = #l.deps >= 2 and math.floor((l.deps[2] - l.deps[1]) / 60 + 0.5) or false
            l.deps = nil
        end
        table.sort(order, function(a, b) return a.id < b.id end)
        return order
    end

    return P
end

---------------------------------------------------------------- live network map

RailMap = {}

-- static part: track geometry, stations, signals, switch positions
function RailMap.network()
    local geo = Util.call("rw_core", "getNetworkGeometry")
    if not geo then return { ok = false, error = "The railway network (rw_core) is not running." } end
    return Util.text({
        ok = true, company = geo.company, short = geo.short, tracks = geo.tracks, switches = geo.switches,
        stations = Util.call(TT_RES, "getStations") or {},
        signals = Util.call("rw_signals", "getSignalList") or {},
    })
end

-- moving part: trains (with their service), switch states, signal aspects, trips around now
function RailMap.state()
    local trains = Util.call("rw_core", "getNetworkTrains")
    if not trains then return { ok = false, error = "The railway network (rw_core) is not running." } end
    for _, c in ipairs(trains.consists or {}) do
        c.service = Util.call(TT_RES, "getConsistService", c.id) or false
    end
    return Util.text({
        ok = true, time = Util.secOfDay(Util.now()),
        consists = trains.consists, switches = trains.switches,
        aspects = Util.call("rw_signals", "getSignalAspects") or {},
        trips = Util.call(TT_RES, "getTripsOverview") or {},
    })
end

function RailMap.boards(rows)
    return Util.text({ ok = true, boards = Util.call(TT_RES, "getStationBoards", rows) or {} })
end
