-- Automatic (NPC) trains. Runs every timetable trip nobody took: the train is created
-- AUTO.SPAWN_LEAD seconds before departure (players can board the coaches; the cab stays
-- locked), drives the trip on time, stops at every station with the doors open, and is
-- removed at the terminus - or runs the next trip of its `chain` line from there.
--
-- The trains are rw_customtracks network trains under scripted control: each stop is the
-- train's destination, so the network routes it (switches reserved ahead, released behind),
-- and its ATP stops it at the platform, at red signals and behind other trains. This file
-- only keeps the timetable: a speed that arrives on time, the doors, the dwell.

-- late-bound export proxies: the other resources may (re)start after this one
local function proxy(name)
    return setmetatable({}, { __index = function(_, fn)
        return function(_, ...) return exports[name][fn](exports[name], ...) end
    end })
end
local core = proxy("rw_core")
local tt = proxy("rw_timetable")
local net = proxy("rw_customtracks")

Trains = {}             -- [consistId] = train
local handled = {}      -- [tripId] = { kind = "player" | "auto" | "skip" | consistId, dep }
local reservedTrip = {} -- [tripId] = consistId (a chained train will run it)
local waitWarned = {}
local zones = {}        -- [station] = { [track] = zone }
local states = {}       -- [id] = latest network state (onNetTrainStates)
local abs, min, max = math.abs, math.min, math.max

-- rw_core railway log (category "auto")
local function rlog(level, text, consistId)
    pcall(function() core:railLog("auto", level, text, consistId) end)
end

local function now() return getRealTime().timestamp end
local function nowMs() return getTickCount() end

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function loadZones()
    zones = {}
    for _, z in ipairs(tt:getStationZones() or {}) do
        zones[z.station] = zones[z.station] or {}
        zones[z.station][z.track] = z
    end
end

addEvent("onNetTrainStates", false)
addEventHandler("onNetTrainStates", root, function(list)
    states = {}
    for _, st in ipairs(list) do states[st.id] = st end
end)

------------------------------------------------------------------ trips

local function clearDoors(train, side)
    exports.rw_loco:setLocoState(train.id, { doors = side or "closed" })
    train.doors = side or "closed"
end

local function platformSide(train)
    local ok, side = tt:canOpenDoors(train.id)
    if ok then return side == "both" and "right" or side end
    return nil
end

-- the track a stop is served on: the stop's own track, else the line's, else the current one
local function stopTrack(train, stop)
    if stop.track and zones[stop.station] and zones[stop.station][stop.track] then return stop.track end
    if train.plan.track and zones[stop.station] and zones[stop.station][train.plan.track] then return train.plan.track end
    local info = core:getConsist(train.id)
    if info and info.track and zones[stop.station] and zones[stop.station][info.track] then return info.track end
    for track in pairs(zones[stop.station] or {}) do return track end
end

local lineCache = {}
local function lineInfo(track)
    if not lineCache[track] then
        for _, l in ipairs(net:getNetLines() or {}) do lineCache[l.id] = l end
    end
    return lineCache[track]
end
addEvent("onNetNetworkRebuilt", false)
addEventHandler("onNetNetworkRebuilt", root, function() lineCache = {} end)

-- sends the train to stop k: its destination is the stop point of that platform
local function headFor(train, k)
    local stop = train.plan.stops[k]
    local track = stopTrack(train, stop)
    local z = track and zones[stop.station][track]
    if not z then
        outputDebugString(("[rw_auto] train %d: no platform for %s"):format(train.id, tostring(stop.station)), 2)
        rlog("error", ("no platform for %s"):format(tostring(stop.station)), train.id)
        return false
    end
    local tp = z.center + train.dir * AUTO.STOP_AHEAD
    -- dead-end tracks (Cranberry 3 / 4): stop short of the buffer
    local info = lineInfo(track)
    if info and not info.closed then tp = max(AUTO.END_GAP, min(info.length - AUTO.END_GAP, tp)) end
    train.target = { track = track, tp = tp }
    local ok, err = net:setNetTrainLineDestination(train.id, track, train.target.tp, train.dir)
    if not ok then
        outputDebugString(("[rw_auto] train %d: no route to %s (%s)"):format(train.id, stop.station, tostring(err)), 2)
        rlog("warn", ("no route to %s (%s)"):format(stop.station, tostring(err)), train.id)
    end
    return ok
end

local function startTrip(train, plan)
    train.plan = plan
    train.k = 1                 -- stop index we are at / heading for
    train.phase = "dwell"
    train.arrivedAt = nowMs()
    handled[plan.id] = { kind = train.id, dep = plan.dep }
    reservedTrip[plan.id] = nil
    -- the train that arrives runs the next trip of its chain line from the terminus
    train.chainTrip = nil
    if plan.chain then
        for _, t in ipairs(tt:getAllServices(plan.arr, plan.arr + plan.chainWindow * 60) or {}) do
            if t.line == plan.chain and t.from == plan.to and not t.consist then
                train.chainTrip = t.tripId
                reservedTrip[t.tripId] = train.id
                break
            end
        end
    end
end

local function removeTrain(train, reason)
    Trains[train.id] = nil
    if train.chainTrip and reservedTrip[train.chainTrip] == train.id then reservedTrip[train.chainTrip] = nil end
    core:destroyConsist(train.id, reason)
end

local function spawnFor(plan)
    if not plan.auto then return false, "line has no automatic train" end
    local id, err = core:spawnConsist({ preset = plan.auto.preset, spawn = plan.auto.spawn, auto = true })
    if not id then return false, err end
    local info = core:getConsist(id)
    local train = { id = id, dir = info.dir, doors = "closed" }
    Trains[id] = train
    exports.rw_loco:setLocoState(id, { bat = true, fuel = true, eng = "running", lights = true })
    net:setNetTrainControl(id, -1, 1, false)
    local ok, why = tt:assignService(id, plan.id, false, true)
    if not ok then
        outputDebugString(("[rw_auto] %s: service not assigned (%s)"):format(plan.number, tostring(why)), 2)
        rlog("warn", ("%s: service not assigned (%s)"):format(plan.number, tostring(why)), id)
    end
    startTrip(train, plan)
    return id
end

local function schedule()
    if not running("rw_timetable") or not running("rw_loco") or not running("rw_customtracks") then return end
    local t = now()
    for _, trip in ipairs(tt:getAllServices(t - AUTO.LATE_START - 120, t + AUTO.DECIDE_LEAD) or {}) do
        local id = trip.tripId
        if not handled[id] and trip.depTimestamp - t <= AUTO.DECIDE_LEAD then
            local state = tt:getTripState(id)
            if state.taken or state.done or state.cancelled then
                handled[id] = { kind = state.auto and "auto" or "player", dep = trip.depTimestamp }
            elseif reservedTrip[id] and Trains[reservedTrip[id]] then
                -- a chained train runs it; nothing to create
            elseif trip.depTimestamp - t <= AUTO.SPAWN_LEAD then
                if trip.depTimestamp - t < -AUTO.LATE_START then
                    handled[id] = { kind = "skip", dep = trip.depTimestamp }
                    tt:cancelTrip(id, "no train available")
                    outputDebugString(("[rw_auto] %s cancelled: no train could start it in time"):format(trip.id))
                    rlog("warn", ("%s cancelled: no train could start it in time"):format(trip.id))
                else
                    local plan = tt:getTripPlan(id)
                    if plan then
                        local ok, err = spawnFor(plan)
                        if not ok and not waitWarned[id] then
                            waitWarned[id] = true
                            outputDebugString(("[rw_auto] %s waits: %s"):format(plan.number, tostring(err)))
                            rlog("warn", ("%s: automatic train cannot be created yet (%s)"):format(plan.number, tostring(err)))
                        end
                    end
                end
            end
        end
    end
    for id, h in pairs(handled) do
        if h.dep < t - 3 * 3600 then handled[id] = nil waitWarned[id] = nil end
    end
end

------------------------------------------------------------------ driving

-- cruise speed that covers `dist` metres in `T` seconds from now
local function cruiseFor(dist, T, v)
    if T <= 1 then return AUTO.VMAX end
    local vc = max(1, dist / T)
    for _ = 1, 4 do
        local t = T - vc / (2 * AUTO.DECEL) - max(0, vc - v) / (2 * AUTO.ACCEL)
        vc = dist / max(1, t)
    end
    return min(AUTO.VMAX, max(4, vc))
end

local function stepTrain(train)
    local st = states[train.id]
    if not st then return end
    local plan = train.plan
    local t = now()
    local sinceArrive = (nowMs() - train.arrivedAt) / 1000

    if train.phase == "dwell" or train.phase == "end" then
        net:setNetTrainControl(train.id, -0.6, nil, false)
        local stop = plan.stops[train.k]
        local closeAt = stop.dep and (stop.dep - AUTO.DOOR_CLOSE) or math.huge
        if train.doors == "closed" or not train.doors then
            if sinceArrive >= AUTO.DOOR_OPEN and t < closeAt then clearDoors(train, platformSide(train) or "right") end
        elseif t >= closeAt then
            clearDoors(train, "closed")
        end
        if train.phase == "end" then
            if train.chainTrip and not tt:getTripState(plan.id).taken then
                local state = tt:getTripState(train.chainTrip)
                local plan2 = (not state.taken and not state.done) and tt:getTripPlan(train.chainTrip)
                if plan2 and tt:assignService(train.id, plan2.id, false, true) then
                    local arrived = train.arrivedAt
                    startTrip(train, plan2)
                    train.arrivedAt = arrived
                    return
                end
                train.chainTrip = nil
            end
            if sinceArrive >= AUTO.DESPAWN_AFTER then removeTrain(train, "automatic train finished its trip") end
            return
        end
        if stop.dep and t >= stop.dep and train.doors == "closed" then
            train.k = train.k + 1
            if headFor(train, train.k) then train.phase = "run" else train.phase = "end" end
        end
        return
    end

    -- running towards stop k: the network stops it at the platform (destination)
    if st.arrived and abs(st.speed) < 0.1 then
        train.phase = (train.k >= #plan.stops or train.orphan) and "end" or "dwell"
        train.arrivedAt = nowMs()
        return
    end
    local stop = plan.stops[train.k]
    local dist = (st.authority and st.authority.reason == "destination" and st.authority.remaining) or 2000
    local vt = max(AUTO.VLINE, cruiseFor(max(0, dist), (stop.arr or t) - t, abs(st.speed)))
    local v = abs(st.speed)
    local c
    if v < vt - 0.5 then c = min(1, 0.35 + (vt - v) * 0.15)
    elseif v > vt + 1.5 then c = -min(0.8, (v - vt) * 0.15)
    else c = 0 end
    net:setNetTrainControl(train.id, c, 1, false)
end

local function tick()
    if not running("rw_timetable") or not running("rw_loco") or not running("rw_customtracks") then return end
    for _, train in pairs(Trains) do
        local ok, err = pcall(stepTrain, train)
        if not ok then
            outputDebugString("[rw_auto] train " .. train.id .. ": " .. tostring(err), 1)
            if train.lastErr ~= err then rlog("error", "script error: " .. tostring(err), train.id) end
            train.lastErr = err
        end
    end
end

addEventHandler("onRailConsistDestroy", root, function(id)
    Trains[id] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if running("rw_timetable") then pcall(loadZones) end
    setTimer(tick, AUTO.TICK, 0)
    setTimer(schedule, AUTO.SCHEDULE, 0)
end)

-- a restarted rw_timetable has lost the services of our trains: without one they would run
-- "not in service" for ever (nothing retires them). Each ends at its next stop instead.
local function orphan(train)
    if train.orphan then return end
    train.orphan = true
    if train.chainTrip and reservedTrip[train.chainTrip] == train.id then reservedTrip[train.chainTrip] = nil end
    train.chainTrip = nil
    if train.phase == "dwell" then
        train.phase, train.arrivedAt = "end", nowMs()
    end
    rlog("warn", "service lost (rw_timetable restarted) - the train is taken out of service at its next stop", train.id)
end

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "rw_timetable" then
        for _, train in pairs(Trains) do orphan(train) end
        setTimer(function() pcall(loadZones) end, 1000, 1)
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, train in pairs(Trains) do removeTrain(train, "rw_auto stopped") end
end)

-- web / other resources
function getAutoTrains()
    local t = {}
    for id, train in pairs(Trains) do
        local st = states[id]
        t[#t + 1] = { id = id, trip = train.plan and train.plan.id, number = train.plan and train.plan.number,
            phase = train.phase, stop = train.k, speed = st and abs(st.speed) * 3.6 or 0 }
    end
    return t
end
