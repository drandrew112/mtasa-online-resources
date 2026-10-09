-- Pay for a completed rail service. rw_timetable fires onRailServiceComplete when the last stop
-- is served; the player sitting in the driver's seat at that moment (the one who closes the
-- service) is paid through work_core:payWork, which deposits it and shows the receipt.
-- No pay: rw_auto trains (no player), a driver not on duty, no stop served.

addEvent("onRailServiceComplete")

local Paid = {}        -- [tripId] = tick, guards against a double event

-- -> items (payWork format) | nil
function computePay(summary)
    local P = TRAINDRIVER.PAY
    local number = tostring(summary.number or "?")      -- "RB 1101" / "IC 2101"
    local base = P.BASE[number:match("^(%a+)")] or P.BASE_DEFAULT

    local items = { { label = "Service " .. number, amount = base } }
    local served = summary.served or 0
    if served > 0 then items[#items + 1] = { label = ("Stops served (%d)"):format(served), amount = served * P.PER_STOP } end

    local delay = summary.arrivalDelay
    if delay then
        for _, tier in ipairs(P.PUNCTUAL) do
            if delay <= tier.max then items[#items + 1] = { label = tier.label, amount = tier.amount } break end
        end
    end
    if (summary.skipped or 0) > 0 then
        items[#items + 1] = { label = ("Skipped stops (%d)"):format(summary.skipped), amount = -summary.skipped * P.SKIP_FINE }
    end
    if (summary.earlyDepartures or 0) > 0 then
        items[#items + 1] = { label = ("Early departures (%d)"):format(summary.earlyDepartures), amount = -summary.earlyDepartures * P.EARLY_FINE }
    end
    if P.DELAY_FINE_FROM and (summary.maxDelay or 0) > P.DELAY_FINE_FROM then
        items[#items + 1] = { label = "Delay", amount = -P.DELAY_FINE }
    end
    return items
end

local function total(items)
    local t = 0
    for _, i in ipairs(items) do t = t + i.amount end
    return t
end

local function pay(player, summary)
    local items = computePay(summary)
    if total(items) < 0 then items[#items + 1] = { label = "Adjustment", amount = -total(items) } end
    local ok, result = exports.work_core:payWork(player, TRAINDRIVER.WORK_ID, items, "Service " .. tostring(summary.number) .. " completed")
    if ok then
        outputServerLog(("[work_traindriver] %s paid %d for %s"):format(getPlayerName(player), result, tostring(summary.number)))
    else
        outputServerLog(("[work_traindriver] payment for %s failed: %s"):format(getPlayerName(player), tostring(result)))
        outputDebugString("work_traindriver: payWork failed: " .. tostring(result), 2)
    end
    return ok, result
end

addEventHandler("onRailServiceComplete", root, function(consistId, tripId, startedBy, summary)
    if type(summary) ~= "table" or (summary.served or 0) <= 0 then return end
    if Paid[tripId] then return end
    local resource = getResourceFromName("work_core")
    if not resource or getResourceState(resource) ~= "running" then return end

    local driver = isElement(source) and getVehicleOccupant(source, 0) or nil
    if not isElement(driver) or getElementType(driver) ~= "player" then return end   -- nobody closed it / rw_auto
    if not isPlayerTrainDriver(driver) then return end
    Paid[tripId] = getTickCount()
    pay(driver, summary)
end)

setTimer(function()
    local limit = getTickCount() - 3 * 3600 * 1000
    for id, at in pairs(Paid) do if at < limit then Paid[id] = nil end end
end, 30 * 60 * 1000, 0)

-- /testtraindriverpay [RB|IC]: admins only; pays a made-up summary (real deposit) to check the receipt
addCommandHandler("testtraindriverpay", function(player, _, kind)
    local ok, level = pcall(function() return exports.v_mysql:getAccData(player, "admin_level") end)
    if not ok or (tonumber(level) or 0) < 3 then return end
    local ic = kind and kind:upper() == "IC"
    pay(player, { number = ic and "IC 2101" or "RB 1101", line = ic and "SL3" or "SL1", served = ic and 5 or 3,
        skipped = 1, earlyDepartures = 1, arrivalDelay = 90, maxDelay = 120 })
end)
