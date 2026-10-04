-- Station displays: departure / arrival boards for passengers. The server builds a board per
-- station (scheduled time, train, destination / origin, track, remark); clients near a
-- display ask for it every few seconds and draw it on the wall (client/displays.lua).

-- looked up on every call: a reloaded rw_core is a new resource and a cached exports table
-- would keep calling the old one (everything froze after rw_core reloaded)
local core = setmetatable({}, { __index = function(_, fn) return function(_, ...) return exports.rw_core[fn](nil, ...) end end })
local B = TT.BOARD

local function now() return getRealTime().timestamp end

-- the track a trip normally uses at stop i
local function plannedTrack(line, i)
    local stop = line.stops[i]
    if stop and stop.track then return stop.track end
    return line.track or TT.ROUTE_TRACKS[1]
end

local function trackLabel(st, track)
    local labels = st.def.tracks
    return labels and labels[track] or tostring(track)
end

-- names of the stops between a and b (exclusive), short ("Market", not "Market Station")
local function via(trip, a, b)
    local t = {}
    for i = a + 1, b - 1 do
        t[#t + 1] = (trip.stops[i].name:gsub(" Station$", ""))
    end
    return t
end

-- estimated delay (s) of a stop that has not happened yet
local function expected(s, sched, t)
    local d = s and s.delay or 0
    if t > sched then d = math.max(d, t - sched) end
    return d
end

-- -> board { station, name, t, departures = {...}, arrivals = {...} } | false
-- rows: rows per column (default TT.BOARD.ROWS; the web map shows more)
function getStationBoard(stationId, rows)
    local st = Stations[stationId]
    if not st then return false end
    local t = now()
    local deps, arrs = {}, {}
    for _, trip in ipairs(tripsBetween(t - 2 * 3600, t + B.AHEAD * 60)) do
        for i, stop in ipairs(trip.stops) do
            if stop.station == stationId then
                local s, fin = tripRuntime(trip.id)
                local rec = s and s.stops[i]
                local track = plannedTrack(trip.line, i)
                -- a train of this trip standing in the station: its real track
                if s then
                    local c = core:getConsist(s.consist)
                    if c and c.track and st.zones[c.track] and stationAt(c.track, c.tp) == st then track = c.track end
                end
                local base = { train = trip.number, line = trip.line.id, name = trip.name, track = trackLabel(st, track) }

                -- departure (every stop but the last)
                if stop.dep and i < #trip.stops and stop.dep <= t + B.AHEAD * 60 then
                    local e = { time = secOfDay(stop.dep), to = Stations[trip.to].name, via = via(trip, i, #trip.stops) }
                    for k, v in pairs(base) do e[k] = v end
                    local show = true
                    if fin or (s and s.next > i) or (rec and (rec.state == "done" or rec.state == "skipped")) then
                        local at = rec and rec.actDep or (fin and fin.at) or stop.dep
                        e.state, e.delay = "departed", math.max(0, at - stop.dep)
                        show = t - at <= B.PAST_DEP
                    elseif rec and rec.state == "stopped" then
                        e.state, e.delay = "boarding", expected(s, stop.dep, t)
                    elseif s then
                        e.state, e.delay = "expected", expected(s, stop.dep, t)
                    elseif isTripCancelled(trip.id) or t > stop.dep + B.CANCEL_AFTER then
                        e.state, e.delay = "cancelled", 0
                        show = t - stop.dep <= B.CANCEL_AFTER + 300
                    else
                        e.state, e.delay = "scheduled", 0     -- no train yet: no delay estimate
                    end
                    if show then e.sort = stop.dep; deps[#deps + 1] = e end
                end

                -- arrival (every stop but the first)
                if stop.arr and i > 1 and stop.arr <= t + B.AHEAD * 60 then
                    local e = { time = secOfDay(stop.arr), from = Stations[trip.from].name, via = via(trip, 1, i) }
                    for k, v in pairs(base) do e[k] = v end
                    local show = true
                    local last = i == #trip.stops
                    if last and fin then
                        e.state, e.delay = "arrived", math.max(0, fin.delay or 0)
                        show = t - fin.at <= B.PAST_ARR
                    elseif rec and rec.state == "stopped" then
                        e.state, e.delay = last and "arrived" or "platform", math.max(0, rec.actArr - stop.arr)
                    elseif fin or (s and s.next > i) or (rec and rec.state ~= "pending") then
                        show = false        -- already gone (or ran through)
                    elseif s then
                        e.state, e.delay = "expected", expected(s, stop.arr, t)
                    elseif isTripCancelled(trip.id) or t > stop.arr + B.CANCEL_AFTER then
                        e.state, e.delay = "cancelled", 0
                        show = t - stop.arr <= B.CANCEL_AFTER + 300
                    else
                        e.state, e.delay = "scheduled", 0
                    end
                    if show then e.sort = stop.arr; arrs[#arrs + 1] = e end
                end
            end
        end
    end
    local function byTime(a, b) return a.sort < b.sort end
    table.sort(deps, byTime)
    table.sort(arrs, byTime)
    local function cut(list)
        local out = {}
        for i = 1, math.min(#list, tonumber(rows) or B.ROWS) do list[i].sort = nil; out[i] = list[i] end
        return out
    end
    return { station = st.id, name = st.name, city = st.city, t = secOfDay(t), departures = cut(deps), arrivals = cut(arrs) }
end

-- every station's board -> { [stationId] = board } (rw_core web map)
function getStationBoards(rows)
    local out = {}
    for _, st in ipairs(StationList) do out[st.id] = getStationBoard(st.id, rows) end
    return out
end

-- clients near a display: stationIds -> { [id] = board }
local lastAsk = {}
addEvent("rw:tt:boards", true)
addEventHandler("rw:tt:boards", resourceRoot, function(ids)
    if type(ids) ~= "table" then return end
    if lastAsk[client] and getTickCount() - lastAsk[client] < 1000 then return end
    lastAsk[client] = getTickCount()
    local out, n = {}, 0
    for _, id in ipairs(ids) do
        if n >= #TT.STATIONS then break end
        if type(id) == "string" and Stations[id] and not out[id] then
            out[id] = getStationBoard(id)
            n = n + 1
        end
    end
    triggerClientEvent(client, "rw:tt:boardsResult", resourceRoot, out)
end)

addEventHandler("onPlayerQuit", root, function() lastAsk[source] = nil end)
