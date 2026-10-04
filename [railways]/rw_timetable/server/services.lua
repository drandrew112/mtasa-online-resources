-- Services: a trip (one run of a line) driven by a consist. Taking a trip, watching the
-- stops (standing in the platform zone, doors open long enough, door side), departures,
-- delays, completion. The loco timetable module talks to this through the rw:tt:* events.

local core = exports.rw_core
Services = {}           -- [consistId] = service
local taken = {}        -- [tripId] = consistId
local finished = {}     -- [tripId] = { delay, at } (station boards show "arrived")
local cancelled = {}    -- [tripId] = { reason, at } (no train will run it)
local retiring = {}     -- [consistId] = { at, reason } (service over: the train is removed)

addEvent("onRailServiceStart")      -- source: lead, (consistId, tripId, player|false)
addEvent("onRailServiceStop")       -- source: lead, (consistId, tripId, stopIndex, record)
addEvent("onRailServiceComplete")   -- source: lead, (consistId, tripId, player|false, summary)
addEvent("onRailServiceCancel")     -- source: lead|root, (consistId, tripId, reason)

local function now() return getRealTime().timestamp end

local function tell(player, text, ok)
    if isElement(player) then triggerClientEvent(player, "rw:tt:notify", resourceRoot, text, ok and true or false) end
end

local function driverOf(c) return c and isElement(c.lead) and getVehicleOccupant(c.lead, 0) or nil end

------------------------------------------------------------------ checks

local function compatible(c, line)
    local req = line.consist
    local okLoco = false
    for _, l in ipairs(req.locos) do if l == c.loco then okLoco = true end end
    if not okLoco then return false, "needs a " .. table.concat(req.locos, "/") .. " locomotive" end
    if c.passengerCars < (req.minPassenger or 0) then return false, ("needs at least %d passenger coach(es)"):format(req.minPassenger) end
    if req.maxPassenger and c.passengerCars > req.maxPassenger then return false, ("at most %d passenger coaches"):format(req.maxPassenger) end
    return true
end

-- is the consist at the trip's origin, facing the next stop
local function placed(c, trip)
    local st = Stations[trip.from]
    local z = st and st.zones[c.track]
    if not z or c.tp < z.lo or c.tp > z.hi then return false, "not at " .. (st and st.name or trip.from) end
    local nst = Stations[trip.stops[2].station]
    local nz = nst and nst.zones[c.track]
    -- a dead-end station track (Cranberry 3 / 4) has no next station: the train leaves it
    if not nz then return true end
    local towards = core:getTrackDelta(c.track, z.center, nz.center) > 0 and 1 or -1
    if towards ~= c.dir then return false, "the locomotive faces the wrong way" end
    return true
end

-- every trip in the take window with ok / reason for this consist
local function tripsFor(c)
    local t = now()
    local out = {}
    for _, trip in ipairs(tripsBetween(t + TT.TAKE_LEAD, t + TT.TAKE_BEFORE)) do
        local ok, reason = true, nil
        if taken[trip.id] then ok, reason = false, "already running"
        elseif finished[trip.id] then ok, reason = false, "already done" end
        if ok and cancelled[trip.id] then ok, reason = false, "cancelled" end
        if ok then ok, reason = compatible(c, trip.line) end
        if ok then ok, reason = placed(c, trip) end
        out[#out + 1] = { trip = trip, ok = ok, reason = reason }
    end
    return out
end

------------------------------------------------------------------ sync

local function stopView(trip, s)
    local view = {}
    for i, st in ipairs(trip.stops) do
        local r = s and s.stops[i] or {}
        view[i] = {
            station = st.station, name = st.name,
            arr = st.arr and secOfDay(st.arr) or nil, dep = st.dep and secOfDay(st.dep) or nil,
            actArr = r.actArr and secOfDay(r.actArr) or nil, actDep = r.actDep and secOfDay(r.actDep) or nil,
            state = r.state or "pending",
        }
    end
    return view
end

local function serviceView(s)
    local trip = s.trip
    local rec = s.stops[s.next]
    return {
        trip = trip.number, id = trip.id, name = trip.name, line = trip.line.id,
        from = trip.from, to = trip.to,
        fromName = Stations[trip.from].name, toName = Stations[trip.to].name,
        status = s.status, delay = s.delay, nextStop = s.next,
        stops = stopView(trip, s),
        doorTime = rec and math.floor(rec.doorTime or 0) or 0, doorMin = TT.DOOR_MIN,
        auto = s.auto or false,
        side = rec and rec.side or false,
        t = secOfDay(now()),
    }
end

local function sync(s, c)
    s.lastSync = getTickCount()
    c = c or core:getConsist(s.consist)
    if c and isElement(c.lead) then setElementData(c.lead, "rw.service", serviceView(s)) end
end

local function clearData(c)
    if c and isElement(c.lead) then removeElementData(c.lead, "rw.service") end
end

------------------------------------------------------------------ take / end

-- -> true | false, reason. player: role + driver are checked when given.
-- force (rw_auto): no take window, the trip only has to be free and the train fit + placed.
function assignService(consistId, tripId, player, force)
    if Services[consistId] then return false, "the train already runs a service" end
    local c = core:getConsist(consistId)
    if not c then return false, "no such train" end
    if player then
        if not core:hasRailwayAccess(player) then return false, "railway staff only" end
    end
    local trip = getTrip(tripId)
    if not trip then
        for _, e in ipairs(tripsFor(c)) do if e.trip.id == tripId then trip = e.trip end end
    end
    if not trip then return false, "unknown trip" end
    local ok, reason = false, "not available now"
    if force then
        ok, reason = true, nil
        if taken[trip.id] then ok, reason = false, "already running"
        elseif finished[trip.id] then ok, reason = false, "already done" end
        if ok then ok, reason = compatible(c, trip.line) end
        if ok then ok, reason = placed(c, trip) end
    else
        for _, e in ipairs(tripsFor(c)) do
            if e.trip == trip then ok, reason = e.ok, e.reason end
        end
    end
    if not ok then return false, reason end

    local s = { consist = consistId, trip = trip, player = player or driverOf(c), started = now(),
        next = 1, stops = {}, delay = 0, status = "running", auto = (force and not player) or nil }
    for i = 1, #trip.stops do s.stops[i] = { state = "pending", doorTime = 0 } end
    local first = s.stops[1]
    first.state, first.actArr = "stopped", now()
    first.side = platformSide(Stations[trip.from], c.track, c.tp, c.dir)
    Services[consistId] = s
    taken[trip.id] = consistId
    sync(s, c)
    triggerEvent("onRailServiceStart", c.lead, consistId, trip.id, player or false)
    return true
end

local function finish(s, c, status, reason)
    Services[s.consist] = nil
    taken[s.trip.id] = nil
    s.status = status
    if c then
        if status == "completed" then
            setElementData(c.lead, "rw.service", serviceView(s))
            local id = s.consist
            setTimer(function()
                if Services[id] then return end
                local cc = core:getConsist(id)
                clearData(cc)
            end, 20000, 1)
        else
            clearData(c)
        end
    end
    if status ~= "completed" then
        triggerEvent("onRailServiceCancel", c and c.lead or root, s.consist, s.trip.id, reason or status)
    end
end

function cancelService(consistId, reason)
    local s = Services[consistId]
    if not s then return false end
    finish(s, core:getConsist(consistId), "cancelled", reason)
    return true
end

local function summary(s)
    local served, skipped, early, maxDelay = 0, 0, 0, 0
    for i, r in ipairs(s.stops) do
        if r.state == "done" then served = served + 1 elseif r.state == "skipped" then skipped = skipped + 1 end
        if r.early then early = early + 1 end
        local st = s.trip.stops[i]
        local d = (r.actDep and st.dep and r.actDep - st.dep) or (r.actArr and st.arr and r.actArr - st.arr) or 0
        if d > maxDelay then maxDelay = d end
    end
    local last = s.stops[#s.stops]
    return {
        trip = s.trip.id, number = s.trip.number, line = s.trip.line.id,
        served = served, skipped = skipped, earlyDepartures = early,
        arrivalDelay = last.actArr and (last.actArr - s.trip.arr) or nil,
        maxDelay = maxDelay, started = s.started, finished = now(),
    }
end

------------------------------------------------------------------ removal

-- A train whose service is over leaves the network: player-spawned ones too. It goes once it
-- stands, REMOVE_AFTER s later; a new service in the meantime (rw_auto chain) keeps it.
local function retire(consistId, reason)
    retiring[consistId] = { at = now() + TT.REMOVE_AFTER, reason = reason }
end

local EXIT_LATERAL = 3.0    -- m from the car's centre line

-- destroys the consist; at a platform the driver / riders end up beside their car on the
-- platform side (rw_customtracks would drop them on the right hand side, maybe onto a track)
local function removeTrain(id, c, reason)
    local st = stationAt(c.track, c.tp)
    local p = st and st.def.platform and st.def.platform[c.track]
    local place = {}
    local net = getResourceFromName("rw_customtracks")
    local info = p and net and getResourceState(net) == "running" and exports.rw_customtracks:getNetTrain(id)
    if info then
        local function add(player, k)
            local car = info.cars[k] and info.cars[k].element
            if not isElement(player) or not isElement(car) then return end
            local m = getElementMatrix(car)
            local x, y, z = getElementPosition(car)
            local rx, ry = m[1][1], m[1][2]
            local sign = ((p.x - x) * rx + (p.y - y) * ry) > 0 and 1 or -1
            place[#place + 1] = { player, x + rx * sign * EXIT_LATERAL, y + ry * sign * EXIT_LATERAL, z + 0.5 }
        end
        if info.driver then add(info.driver, 1) end
        for _, r in ipairs(info.riders or {}) do add(r.player, r.car) end
    end
    core:destroyConsist(id, reason)
    for _, e in ipairs(place) do
        if isElement(e[1]) and not getPedOccupiedVehicle(e[1]) then setElementPosition(e[1], e[2], e[3], e[4]) end
    end
end

local function retireTick()
    local t = now()
    for id, r in pairs(retiring) do
        local c = core:getConsist(id)
        if not c or Services[id] then
            retiring[id] = nil
        elseif t >= r.at and not c.building and c.speed < TT.STOP_SPEED then
            retiring[id] = nil
            removeTrain(id, c, r.reason)
        end
    end
end

------------------------------------------------------------------ monitor

local function delayOf(s)
    local d = 0
    local t = now()
    for i, r in ipairs(s.stops) do
        local st = s.trip.stops[i]
        if r.actDep and st.dep then d = r.actDep - st.dep
        elseif r.actArr and st.arr then d = r.actArr - st.arr end
    end
    -- running late for what comes next
    local r, st = s.stops[s.next], s.trip.stops[s.next]
    if r and st then
        if r.state == "pending" and st.arr and t > st.arr then d = math.max(d, t - st.arr) end
        if r.state == "stopped" and st.dep and s.next < #s.stops and t > st.dep then d = math.max(d, t - st.dep) end
    end
    return d
end

local lastTick = getTickCount()
local function tick()
    local dt = (getTickCount() - lastTick) / 1000
    lastTick = getTickCount()
    retireTick()
    local t = now()
    for id, s in pairs(Services) do
        local c = core:getConsist(id)
        if not c then
            finish(s, nil, "cancelled", "train removed")
        elseif not c.building then
            local changed = false
            local k = s.next
            local stop, rec = s.trip.stops[k], s.stops[k]
            local st = Stations[stop.station]
            local z = st.zones[c.track]
            local inZone = z and c.tp >= z.lo and c.tp <= z.hi
            local standing = c.speed < TT.STOP_SPEED
            local doors = isElement(c.lead) and getElementData(c.lead, "rw.doors") or "closed"
            local driver = driverOf(c)

            if rec.state == "pending" then
                if inZone and standing then
                    rec.state, rec.actArr = "stopped", t
                    rec.side = platformSide(st, c.track, c.tp, c.dir)
                    changed = true
                elseif inZone then
                    rec.passing = true
                elseif rec.passing then
                    rec.state = "skipped"
                    s.next = k + 1
                    tell(driver, ("%s passed without stopping - stop not served."):format(st.name))
                    triggerEvent("onRailServiceStop", c.lead, id, s.trip.id, k, rec)
                    changed = true
                end
            elseif rec.state == "stopped" then
                -- the departure time is when the train starts moving (not when it leaves the zone)
                if not standing and not rec.moveAt then rec.moveAt = t end
                if standing then rec.moveAt = nil end
                if doors ~= "closed" and standing then
                    if rec.side and doors ~= rec.side and doors ~= "both" then
                        if not rec.wrongSide then
                            rec.wrongSide = true
                            tell(driver, "The platform is on the " .. rec.side .. " - wrong doors released!")
                        end
                    else
                        rec.doorTime = rec.doorTime + dt
                    end
                end
                if k == #s.stops then
                    if rec.doorTime >= TT.DOOR_MIN or t - rec.actArr >= TT.FINAL_WAIT then
                        rec.state = rec.doorTime >= TT.DOOR_MIN and "done" or "skipped"
                        s.delay = delayOf(s)
                        local sum = summary(s)
                        finished[s.trip.id] = { delay = sum.arrivalDelay or 0, at = t }
                        local lead = c.lead
                        finish(s, c, "completed")
                        retire(id, "service " .. s.trip.number .. " completed")
                        triggerEvent("onRailServiceComplete", lead, id, s.trip.id, s.player or false, sum)
                        local d = sum.arrivalDelay or 0
                        tell(driver, ("%s completed. Arrival %s, %d stop(s) served. The train is taken out of service in %d s."):format(
                            s.trip.number, d >= 60 and ("+" .. math.floor(d / 60) .. " min late") or "on time", sum.served,
                            TT.REMOVE_AFTER), true)
                    end
                elseif not inZone then
                    rec.actDep = rec.moveAt or t
                    rec.state = rec.doorTime >= TT.DOOR_MIN and "done" or "skipped"
                    if stop.dep and t < stop.dep - TT.EARLY_DEP then
                        rec.early = true
                        tell(driver, ("Early departure from %s!"):format(st.name))
                    end
                    if rec.state == "skipped" then
                        tell(driver, ("%s: doors were not open for %d s - stop not served."):format(st.name, TT.DOOR_MIN))
                    end
                    triggerEvent("onRailServiceStop", c.lead, id, s.trip.id, k, rec)
                    s.next = k + 1
                    changed = true
                end
            end

            if Services[id] then
                local d = delayOf(s)
                if math.floor(d / 60) ~= math.floor(s.delay / 60) then changed = true end
                s.delay = d
                if changed or getTickCount() - (s.lastSync or 0) > TT.SYNC_EVERY * 1000 then sync(s, c) end
            end
        end
    end
end

------------------------------------------------------------------ exports

local function tripView(trip)
    local id = taken[trip.id]
    local s = id and Services[id]
    local status, delay = "scheduled", 0
    if s then status, delay = "active", s.delay
    elseif finished[trip.id] then status, delay = "done", finished[trip.id].delay
    elseif cancelled[trip.id] then status = "cancelled" end
    local req = trip.line.consist
    return {
        id = trip.number, tripId = trip.id, line = trip.line.id, name = trip.name,
        from = trip.from, to = trip.to, dep = secOfDay(trip.dep), arr = secOfDay(trip.arr),
        status = status, delay = delay, consist = id or false,
        stops = stopView(trip, s), auto = s and s.auto or false,
        requires = { locos = { unpack(req.locos) }, minPassenger = req.minPassenger, maxPassenger = req.maxPassenger },
    }
end

-- running service | nil, finish record { delay, at } | nil of a trip (station displays)
function tripRuntime(tripId)
    local id = taken[tripId]
    return id and Services[id] or nil, finished[tripId]
end

-- state of a trip: { taken, consist, auto, done } (rw_auto asks before creating a train)
-- A trip no train will run (rw_auto could not start it in time). Boards show "Cancelled".
function cancelTrip(tripId, reason)
    if taken[tripId] or finished[tripId] then return false end
    cancelled[tripId] = { reason = reason or "cancelled", at = now() }
    return true
end

function isTripCancelled(tripId)
    return cancelled[tripId] ~= nil
end

function getTripState(tripId)
    local id = taken[tripId]
    local s = id and Services[id]
    return { taken = id ~= nil, consist = id or false, auto = s and s.auto or false, done = finished[tripId] ~= nil,
        cancelled = cancelled[tripId] ~= nil }
end

-- platform zones: { { station, name, track, lo, hi, center, platform } }
function getStationZones()
    local out = {}
    for _, st in ipairs(StationList) do
        for track, z in pairs(st.zones) do
            local p = st.def.platform and st.def.platform[track]
            out[#out + 1] = { station = st.id, name = st.name, track = track, lo = z.lo, hi = z.hi, center = z.center,
                platform = p and { x = p.x, y = p.y } or false }
        end
    end
    return out
end

-- the trip plan rw_auto drives (absolute timestamps)
function getTripPlan(tripId)
    local trip = getTrip(tripId)
    if not trip then return false end
    local stops = {}
    local line = trip.line
    for i, st in ipairs(trip.stops) do
        stops[i] = { station = st.station, arr = st.arr, dep = st.dep, track = line.stops[i] and line.stops[i].track or nil }
    end
    return { id = trip.id, number = trip.number, line = line.id, from = trip.from, to = trip.to, dep = trip.dep, arr = trip.arr,
        track = line.track,
        stops = stops, chain = line.chain or false, chainWindow = line.chainWindow or 0,
        auto = line.auto and { preset = line.auto.preset, spawn = line.auto.spawn } or false }
end

-- trips around now for the web map (station boards)
function getTripsOverview()
    local t = now()
    local out = {}
    for _, trip in ipairs(tripsBetween(t - 15 * 60, t + 30 * 60)) do out[#out + 1] = tripView(trip) end
    return out
end

-- Every service (trip) in a time window with the consist it needs and whether it is taken.
-- For work_traindriver: pick one, spawn a matching consist at `from`, then the driver still
-- has to take it in the loco timetable module (or call assignService).
-- t0 / t1: timestamps, default now .. now + 60 min
function getAllServices(t0, t1)
    local t = now()
    local out = {}
    for _, trip in ipairs(tripsBetween(t0 or t, t1 or (t + 3600))) do
        local v = tripView(trip)
        v.depTimestamp = trip.dep
        v.fromName = Stations[trip.from].name
        v.toName = Stations[trip.to].name
        out[#out + 1] = v
    end
    return out
end

-- trips this consist could take now -> list of { tripId, number, ..., ok, reason }
function getServicesForConsist(consistId)
    local c = core:getConsist(consistId)
    if not c then return {} end
    local out = {}
    for _, e in ipairs(tripsFor(c)) do
        local v = tripView(e.trip)
        v.ok, v.reason = e.ok, e.reason
        out[#out + 1] = v
    end
    return out
end

function getConsistService(consistId)
    local s = Services[consistId]
    if not s then return false end
    local v = serviceView(s)
    local c = core:getConsist(consistId)
    v.doors = c and isElement(c.lead) and getElementData(c.lead, "rw.doors") or nil
    return v
end

-- may the doors be released: standing inside a station zone -> true, side | false, reason
function canOpenDoors(consistId)
    local c = core:getConsist(consistId)
    if not c then return false, "no such train" end
    if c.speed >= TT.STOP_SPEED then return false, "the train is moving" end
    local st = stationAt(c.track, c.tp)
    if not st then return false, "not at a platform" end
    return true, platformSide(st, c.track, c.tp, c.dir) or "both"
end

------------------------------------------------------------------ loco timetable module

local function consistOfDriver(player)
    local id = core:getConsistByDriver(player)
    return id or nil
end

addEvent("rw:tt:list", true)
addEventHandler("rw:tt:list", resourceRoot, function()
    local player = client
    local id = consistOfDriver(player)
    if not id then return end
    local list = {}
    if core:hasRailwayAccess(player) then
        for _, v in ipairs(getServicesForConsist(id)) do
            if v.ok then list[#list + 1] = { tripId = v.tripId, number = v.id, name = v.name, from = v.from, to = v.to,
                toName = Stations[v.to] and Stations[v.to].name or v.to,
                dep = v.dep, arr = v.arr, ok = v.ok, reason = v.reason } end
        end
    end
    triggerClientEvent(player, "rw:tt:listResult", resourceRoot, list, core:hasRailwayAccess(player), secOfDay(now()))
end)

-- server clock (seconds of the day) for the cab clock
addEvent("rw:tt:time", true)
addEventHandler("rw:tt:time", resourceRoot, function()
    triggerClientEvent(client, "rw:tt:timeResult", resourceRoot, secOfDay(now()))
end)

addEvent("rw:tt:take", true)
addEventHandler("rw:tt:take", resourceRoot, function(tripId)
    local player = client
    local id = consistOfDriver(player)
    if not id then return end
    local ok, err = assignService(id, tostring(tripId), player)
    if ok then
        local trip = getTrip(tostring(tripId))
        tell(player, ("Service %s to %s started. Have a good trip!"):format(trip.number, Stations[trip.to].name), true)
    else
        tell(player, "Cannot take the service: " .. tostring(err))
    end
end)

addEvent("rw:tt:end", true)
addEventHandler("rw:tt:end", resourceRoot, function()
    local player = client
    local id = consistOfDriver(player)
    if id and Services[id] then
        cancelService(id, "ended by the driver")
        retire(id, "service ended by the driver")
        tell(player, "Service ended. The train is taken out of service once it stands.")
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(tick, TT.TICK, 0)
    setTimer(function()
        pruneTrips(function(tid) return taken[tid] ~= nil end)
        local limit = now() - 2 * 3600
        for tid, f in pairs(finished) do if f.at < limit then finished[tid] = nil end end
    end, 10 * 60 * 1000, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for id in pairs(Services) do clearData(core:getConsist(id)) end
end)

-- a destroyed consist ends its service
addEventHandler("onRailConsistDestroy", root, function(id)
    retiring[id] = nil
    local s = Services[id]
    if s then finish(s, nil, "cancelled", "train removed") end
end)

-- keep the driver name fresh for summaries
addEventHandler("onVehicleEnter", root, function(player, seat)
    if seat ~= 0 then return end
    local id = core:getVehicleConsist(source)
    local s = id and Services[id]
    if s and not s.player then s.player = player end
end)

