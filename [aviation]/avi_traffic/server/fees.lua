-- Airspace usage fees (v_bank DESIGN 6.5): the airline of a live AI flight pays SA Control for a
-- takeoff from / landing at a San Andreas airport and for an overflight (external -> external).
-- Money from nothing (key atc.fee_*). Amounts: v_gov fees airspace.<kind> (/gov), else TR.FEES.

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function feeAmount(kind)
    if running("v_gov") then
        local v = tonumber(exports.v_gov:getFee("airspace." .. kind))
        if v then return math.floor(v) end
    end
    return TR.FEES[kind] or 0
end

local function airlineOf(callsign)
    local a = DB.airlines[tostring(callsign):sub(1, 3)]
    return a and a.name or tostring(callsign):sub(1, 3)
end

addEventHandler("onAviFlightFee", resourceRoot, function(kind, callsign, icao)
    if not running("v_bank") then return end
    local amount = feeAmount(kind)
    if amount <= 0 then return end
    local sacontrol = exports.v_bank:getStateAccount(TR.FEE_ACCOUNT)
    if not sacontrol then return end
    exports.v_bank:credit(sacontrol, amount, "atc.fee_" .. kind,
        { callsign = callsign, airline = airlineOf(callsign), airport = icao or nil }, "avi_traffic")
end)
