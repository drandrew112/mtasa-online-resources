-- Airspace usage fees (v_bank DESIGN 6.5): the airline of a live AI flight pays for a takeoff from /
-- landing at a San Andreas airport and for an overflight (external -> external). Money from nothing
-- (key atc.fee_*) to the state account set for the fee on the /gov Fees page; none set (or no
-- gov_tax) = nothing is booked. Amounts: gov_tax fees airspace.<kind> (/gov), else TR.FEES.

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function feeAmount(kind)
    if running("gov_tax") then
        local v = tonumber(exports.gov_tax:getFee("airspace." .. kind))
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
    if not running("gov_tax") then return end
    local target = tonumber(exports.gov_tax:getFeeTarget("airspace." .. kind))
    if not target then return end
    exports.v_bank:credit(target, amount, "atc.fee_" .. kind,
        { callsign = callsign, airline = airlineOf(callsign), airport = icao or nil }, "avi_traffic")
end)
