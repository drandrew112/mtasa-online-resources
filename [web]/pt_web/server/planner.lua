-- pt_web :: server/planner.lua
-- Journey planner over every provider: Connection Scan (earliest arrival) on the trips of all
-- operators, with changes between trips (TRANSFER_MIN at the same stop) and footpaths between
-- stops closer than WALK_MAX (a bus stop in front of a station). Live delays are taken into
-- account: a running trip's remaining stops are expected at plan time + its delay.

Planner = {}
local C = PT.PLANNER

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

-- stops -> byId, footpaths { [stopId] = { { to, secs, dist } } }
local function footpaths(stops)
    local byId, paths = {}, {}
    for _, s in ipairs(stops) do byId[s.id] = s; paths[s.id] = {} end
    for i = 1, #stops do
        for j = i + 1, #stops do
            local a, b = stops[i], stops[j]
            local d = dist(a, b)
            if d <= C.WALK_MAX then
                local secs = math.ceil(d / C.WALK_SPEED) + C.WALK_BUFFER
                table.insert(paths[a.id], { to = b.id, secs = secs, dist = math.floor(d) })
                table.insert(paths[b.id], { to = a.id, secs = secs, dist = math.floor(d) })
            end
        end
    end
    return byId, paths
end

-- expected time of a stop event: scheduled + the trip's current delay while it runs
local function expect(trip, sched, now)
    if not sched then return nil end
    if trip.status == "active" then
        local d = tonumber(trip.delay) or 0
        local t = sched + math.max(0, d)
        return math.max(t, now)
    end
    return sched
end

-- trips -> connections sorted by departure: { trip, i (boarding stop index), from, to, dep, arr }
local function connections(trips, now)
    local list = {}
    for ti, trip in ipairs(trips) do
        local stops = trip.stops or {}
        for i = 1, #stops - 1 do
            local a, b = stops[i], stops[i + 1]
            local gone = a.state == "done" or a.state == "skipped"
            if not gone and a.dep and b.arr and b.state ~= "skipped" then
                local dep = expect(trip, a.dep, now)
                local arr = math.max(expect(trip, b.arr, now), dep)
                list[#list + 1] = { trip = ti, i = i, from = a.stop, to = b.stop, dep = dep, arr = arr }
            end
        end
    end
    table.sort(list, function(x, y)
        if x.dep ~= y.dep then return x.dep < y.dep end
        if x.trip ~= y.trip then return x.trip < y.trip end
        return x.i < y.i
    end)
    return list
end

-- one earliest-arrival search -> legs (raw) | nil
local function scan(conns, paths, from, to, when)
    local arrive, ready, legIn, boarded = {}, {}, {}, {}
    arrive[from], ready[from] = when, when
    for _, fp in ipairs(paths[from] or {}) do
        arrive[fp.to] = when + fp.secs
        ready[fp.to] = when + fp.secs
        legIn[fp.to] = { kind = "walk", from = from, dep = when, arr = when + fp.secs, dist = fp.dist }
    end
    for k, c in ipairs(conns) do
        if c.dep >= when then
            if arrive[to] and c.dep > arrive[to] then break end
            local b = boarded[c.trip]
            if not b and ready[c.from] and ready[c.from] <= c.dep and c.from ~= to then
                b = k
                boarded[c.trip] = k
            end
            if b and (not arrive[c.to] or c.arr < arrive[c.to]) then
                arrive[c.to] = c.arr
                legIn[c.to] = { kind = "ride", board = b, alight = k }
                local r = c.arr + C.TRANSFER_MIN
                if not ready[c.to] or r < ready[c.to] then ready[c.to] = r end
                for _, fp in ipairs(paths[c.to] or {}) do
                    local t = c.arr + fp.secs
                    if fp.to ~= from and (not arrive[fp.to] or t < arrive[fp.to]) then
                        arrive[fp.to] = t
                        legIn[fp.to] = { kind = "walk", from = c.to, dep = c.arr, arr = t, dist = fp.dist }
                        if not ready[fp.to] or t < ready[fp.to] then ready[fp.to] = t end
                    end
                end
            end
        end
    end
    if not legIn[to] then return nil end

    local legs, s, guard = {}, to, 0
    while s ~= from do
        guard = guard + 1
        if guard > 50 then return nil end
        local l = legIn[s]
        if not l then return nil end
        if l.kind == "ride" then
            local cb, ca = conns[l.board], conns[l.alight]
            table.insert(legs, 1, { kind = "ride", trip = cb.trip, i = cb.i, j = ca.i + 1, from = cb.from, to = ca.to, dep = cb.dep, arr = ca.arr })
            s = cb.from
        else
            table.insert(legs, 1, { kind = "walk", from = l.from, to = s, dep = l.dep, arr = l.arr, dist = l.dist })
            s = l.from
        end
    end
    return legs
end

local function stopRef(byId, id)
    local s = byId[id]
    return { id = id, name = s and s.name or id, city = s and s.city or "", mode = s and s.mode or "", x = s and s.x or 0, y = s and s.y or 0 }
end

local function timeView(ts) return { ts = ts, sec = Util.secOfDay(ts) } end

-- raw legs -> the journey sent to the page
local function journeyView(legs, trips, byId, providers)
    local out = { legs = {}, transfers = -1 }
    for n, l in ipairs(legs) do
        local v = { kind = l.kind, from = stopRef(byId, l.from), to = stopRef(byId, l.to), dep = timeView(l.dep), arr = timeView(l.arr) }
        if l.kind == "walk" then
            -- a walk to the first ride starts as late as possible
            local nextLeg = legs[n + 1]
            if n == 1 and nextLeg then
                local dur = l.arr - l.dep
                v.arr = timeView(nextLeg.dep)
                v.dep = timeView(nextLeg.dep - dur)
            end
            v.dist = l.dist
            v.minutes = math.max(1, math.ceil((l.arr - l.dep) / 60))
        else
            local trip = trips[l.trip]
            local p = providers[trip.provider] or {}
            out.transfers = out.transfers + 1
            local a, b = trip.stops[l.i], trip.stops[l.j]
            v.provider, v.operator, v.mode, v.color = trip.provider, p.name, trip.mode, p.color
            v.line, v.number, v.name, v.headsign = trip.line, trip.number, trip.name, trip.headsign
            v.status = trip.status
            v.delay = trip.status == "active" and math.max(0, tonumber(trip.delay) or 0) or 0
            v.schedDep, v.schedArr = timeView(a.dep), timeView(b.arr)
            v.via = {}
            for k = l.i + 1, l.j - 1 do
                local st = trip.stops[k]
                local ref = stopRef(byId, st.stop)
                ref.arr = st.arr and timeView(st.arr) or false
                v.via[#v.via + 1] = ref
            end
            v.stops = l.j - l.i
        end
        out.legs[#out.legs + 1] = v
    end
    out.transfers = math.max(0, out.transfers)
    out.dep = out.legs[1].dep
    out.arr = out.legs[#out.legs].arr
    out.minutes = math.ceil((out.arr.ts - out.dep.ts) / 60)
    -- a change shorter than the delay of the arriving trip may be missed
    for n = 2, #out.legs do
        local prev, cur = out.legs[n - 1], out.legs[n]
        if cur.kind == "ride" and prev.kind == "ride" then
            cur.changeMinutes = math.floor((cur.dep.ts - prev.arr.ts) / 60)
        end
    end
    local sig = {}
    for _, l in ipairs(legs) do sig[#sig + 1] = (l.kind == "ride" and trips[l.trip].gid or "walk") .. "@" .. l.from end
    out.key = table.concat(sig, "|")
    return out
end

-- from / to: global stop ids, when: timestamp -> { journeys } | nil, error
function Planner.search(from, to, when, count)
    count = math.min(tonumber(count) or C.RESULTS, 10)
    local stops = Providers.stops()
    local byId, paths = footpaths(stops)
    if not byId[from] then return nil, "Unknown departure stop." end
    if not byId[to] then return nil, "Unknown destination stop." end
    if from == to then return nil, "Departure and destination are the same stop." end

    local now = Util.now()
    local t0 = math.floor((when - C.LOOK_BACK) / 60) * 60
    local t1 = math.ceil((when + C.HORIZON) / 60) * 60
    local trips = Providers.trips(t0, t1)
    local conns = connections(trips, now)
    local providers = {}
    for _, p in ipairs(Providers.list) do providers[p.id] = p end

    local journeys, seen, t = {}, {}, when
    for _ = 1, count * 2 + 2 do
        if #journeys >= count + 3 then break end      -- a few extra: some get filtered below
        local legs = scan(conns, paths, from, to, t)
        if not legs or #legs == 0 then break end
        local firstRide
        for _, l in ipairs(legs) do if l.kind == "ride" then firstRide = l break end end
        if not firstRide then break end           -- walking only
        local j = journeyView(legs, trips, byId, providers)
        if not seen[j.key] then
            seen[j.key] = true
            j.key = nil
            journeys[#journeys + 1] = j
        end
        t = firstRide.dep + 1
    end
    -- drop journeys another one beats: leaves no earlier, arrives no later, and is better in
    -- one of departure / arrival / changes (an early train only to wait at the change)
    local kept = {}
    for _, j in ipairs(journeys) do
        local beaten = false
        for _, k in ipairs(journeys) do
            if k ~= j and k.dep.ts >= j.dep.ts and k.arr.ts <= j.arr.ts and k.transfers <= j.transfers
                and (k.dep.ts > j.dep.ts or k.arr.ts < j.arr.ts or k.transfers < j.transfers) then
                beaten = true
                break
            end
        end
        if not beaten and #kept < count then kept[#kept + 1] = j end
    end
    journeys = kept
    return { from = stopRef(byId, from), to = stopRef(byId, to), when = timeView(when), journeys = journeys }
end
