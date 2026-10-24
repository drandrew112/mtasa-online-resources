-- Running costs of the services (v_gov /gov Transport page, setting pt.rail): every trip pays its
-- run fee by train category (IC / RB) when it starts and the stop fee for every served stop
-- (doors open for DOOR_MIN). Who pays it to whom is set in v_gov; "from nobody to nowhere"
-- books nothing. Auto trains (rw_auto) pay the same as player-driven ones.

local charged = {}      -- [consistId] = { trip, stops = served stops already charged }

local function govRunning()
    local r = getResourceFromName("v_gov")
    return r and getResourceState(r) == "running"
end

local function charge(kind, params)
    if not govRunning() then return end
    local ok, err = pcall(function() return exports.v_gov:chargeTransportCost("rail", kind, params) end)
    if not ok then outputDebugString("[rw_timetable] running cost: " .. tostring(err), 2) end
end

local function stationName(id)
    local st = Stations[id]
    if not st then return tostring(id) end
    local ok, s = pcall(L.resolveFor, "en", st.name)     -- ledger params are plain text
    return ok and type(s) == "string" and s or id
end

local function categoryOf(trip) return trip and trip.line and trip.line.prefix or "RB" end

addEventHandler("onRailServiceStart", root, function(consistId, tripId)
    local trip = getTrip(tripId)
    if not trip then return end
    charged[consistId] = { trip = tripId, stops = 0 }
    charge("run", { trip = trip.number, category = categoryOf(trip) })
end)

addEventHandler("onRailServiceStop", root, function(consistId, tripId, k, rec)
    local c = charged[consistId]
    if not c or c.trip ~= tripId or type(rec) ~= "table" or rec.state ~= "done" then return end
    local trip = getTrip(tripId)
    if not trip then return end
    c.stops = c.stops + 1
    charge("stop", { trip = trip.number, station = stationName(trip.stops[k] and trip.stops[k].station), count = 1 })
end)

-- the final stop has no onRailServiceStop: the summary's served count includes it
addEventHandler("onRailServiceComplete", root, function(consistId, tripId, _, sum)
    local c = charged[consistId]
    charged[consistId] = nil
    if not c or c.trip ~= tripId or type(sum) ~= "table" then return end
    local trip = getTrip(tripId)
    local extra = (tonumber(sum.served) or 0) - c.stops
    if trip and extra > 0 then
        charge("stop", { trip = trip.number, station = stationName(trip.to), count = extra })
    end
end)

addEventHandler("onRailServiceCancel", root, function(consistId) charged[consistId] = nil end)
