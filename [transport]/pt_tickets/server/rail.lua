-- Railway adapter (rw_passengers + rw_timetable). Boarding a coach (rw_passengers
-- onPlayerBoardTrain) needs a ticket for that trip that covers the stop the train stands at;
-- without one the boarding is refused and the ticket panel opens with the trip's remaining stops.
-- After the purchase the player boards at once (rw_passengers boardCoach).
-- The ticket holds until its last stop: when the train stands there with the doors released the
-- passenger is told, and EJECT_DELAY s later put on the platform. Leaving earlier ends the
-- ticket (except at the boarding stop while the train still stands there).

-- rw_passengers' events (it may start after this resource)
addEvent("onPlayerBoardTrain")      -- source: player, (trainId, carIndex, dim) - cancellable
addEvent("onPlayerLeftTrain")       -- source: player, (trainId, carIndex, reason)

local R = PTT.RAIL
local stations = nil    -- [id] = { x, y } (rw_timetable getStations, cached)
local warned = {}       -- [player] = eject timestamp (the "please leave" notice was shown)

local function running(name)
    local r = getResourceFromName(name)
    return r and getResourceState(r) == "running"
end

local function now() return getRealTime().timestamp end

local function tt() return exports.rw_timetable end

local function serviceOf(trainId)
    if not running("rw_timetable") then return nil end
    local ok, s = pcall(function() return tt():getConsistService(trainId) end)
    return ok and type(s) == "table" and s or nil
end

local function stationPos(id)
    if not stations and running("rw_timetable") then
        stations = {}
        for _, st in ipairs(tt():getStations() or {}) do stations[st.id] = { x = st.x, y = st.y } end
    end
    return stations and stations[id]
end

-- "IC 2101" -> "IC"
local function categoryOf(s) return tostring(s.trip or ""):match("^(%a+)") or "RB" end

-- the stops after `from` with the distance from it (km, straight lines between the stops)
local function destinations(s, from)
    local list, km = {}, 0
    local prev = stationPos(s.stops[from].station)
    for i = from + 1, #s.stops do
        local st = s.stops[i]
        local p = stationPos(st.station)
        if prev and p then km = km + getDistanceBetweenPoints2D(prev.x, prev.y, p.x, p.y) / 1000 end
        prev = p or prev
        list[#list + 1] = { index = i, name = st.name, km = km }
    end
    return list
end

-- the train stands at stop `from` of trip `ref` with the doors released
local function standsAt(s, ref, from)
    if not s or s.id ~= ref or s.nextStop ~= from then return false end
    local rec = s.stops[from]
    return rec and rec.state == "stopped" and s.doors and s.doors ~= "closed"
end

PT.ADAPTERS.rail = {
    check = function(player, offer)
        local s = serviceOf(offer.ctx.train)
        if not standsAt(s, offer.ref, offer.from) then return false, L.msg("pt_tickets.rail.train_left") end
        return true
    end,
}

------------------------------------------------------------------ boarding

addEventHandler("onPlayerBoardTrain", root, function(trainId, carIndex, dim)
    if not R.REQUIRED then return end
    local player = source
    local s = serviceOf(trainId)
    if not s then
        cancelEvent(true, "-")
        PT.tell(player, L.msg("pt_tickets.rail.not_in_service"), R.OPERATOR)
        return
    end
    local cur = tonumber(s.nextStop) or 1
    if hasValidTicket(player, "rail", s.id, cur) then return end
    cancelEvent(true, "-")
    if cur >= #s.stops then
        PT.tell(player, L.msg("pt_tickets.rail.terminates_here"), R.OPERATOR)
        return
    end
    PT.openSale(player, {
        mode = "rail", ref = s.id, line = tostring(s.trip or ""), title = s.name, category = categoryOf(s),
        operator = R.OPERATOR, from = cur, fromName = s.stops[cur].name,
        stops = destinations(s, cur), ctx = { train = trainId, dim = dim },
    })
end)

addEventHandler("onPlayerTicketBought", root, function(mode, ticket, ctx)
    if mode ~= "rail" or not ctx.dim then return end
    if running("rw_passengers") and not exports.rw_passengers:boardCoach(source, ctx.dim) then
        PT.tell(source, L.msg("pt_tickets.rail.board_now"), R.OPERATOR)
    end
end)

------------------------------------------------------------------ leaving / the last stop

addEventHandler("onPlayerLeftTrain", root, function(trainId, carIndex, reason)
    local player = source
    warned[player] = nil
    local t = PT.getTicket(player)
    if not t or t.mode ~= "rail" then return end
    -- got off again at the boarding stop before the train left: the ticket stays
    if reason == "left" and standsAt(serviceOf(trainId), t.ref, t.from) then return end
    PT.endTicket(player, reason == "ticket" and "used" or "left")
end)

addEventHandler("onPlayerQuit", root, function() warned[source] = nil end)

setTimer(function()
    if not running("rw_passengers") then return end
    local t0 = now()
    for player, t in pairs(Tickets) do
        if t.mode == "rail" and isElement(player) then
            local ride = exports.rw_passengers:getPlayerRide(player)
            local s = ride and serviceOf(ride.train)
            if s and s.id == t.ref then
                local cur = tonumber(s.nextStop) or 1
                local rec = s.stops[cur]
                -- at (or past, after a skipped stop) the last stop of the ticket, doors released
                if cur >= t.to and rec and rec.state == "stopped" and s.doors and s.doors ~= "closed" then
                    if not warned[player] then
                        warned[player] = t0 + R.EJECT_DELAY
                        PT.tell(player, L.msg("pt_tickets.rail.ticket_ends_here", { to = t.toName, s = R.EJECT_DELAY }), R.OPERATOR)
                    elseif t0 >= warned[player] then
                        warned[player] = nil
                        exports.rw_passengers:removePassenger(player, L.msg("pt_tickets.rail.put_off", { to = rec.name or t.toName }), true)
                    end
                elseif warned[player] then
                    warned[player] = nil     -- the doors closed meanwhile: wait for the next stop
                end
            end
        end
    end
end, R.TICK, 0)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "rw_timetable" then stations = nil end
end)
