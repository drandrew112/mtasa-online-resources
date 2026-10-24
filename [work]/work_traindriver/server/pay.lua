if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Pay for a completed rail service. rw_timetable fires onRailServiceComplete when the last stop
-- is served; the player sitting in the driver's seat at that moment (the one who closes the
-- service) is paid through work_core:payWork, which deposits it and shows the receipt.
-- No pay: rw_auto trains (no player), a driver not on duty, no stop served.

addEvent("onRailServiceComplete")

local Paid = {}        -- [tripId] = tick, guards against a double event

-- pay and XP numbers: adjustable on the /gov Works page (gov_works); TRAINDRIVER.PAY / XP are the
-- defaults. A PAY.BASE / XP.BASE line prefix gets "base_<prefix>" / "xp_base_<prefix>".
local WAGE_PARAMS = {}
do
    local P, X = TRAINDRIVER.PAY, TRAINDRIVER.XP
    local function add(key, label, default, kind)
        WAGE_PARAMS[#WAGE_PARAMS + 1] = { key = key, label = label, default = default, kind = kind }
    end
    local prefixes = {}
    for prefix in pairs(P.BASE) do prefixes[#prefixes + 1] = prefix end
    table.sort(prefixes)
    for _, prefix in ipairs(prefixes) do add("base_" .. prefix:lower(), "Base pay: " .. prefix, P.BASE[prefix]) end
    add("base_default", "Base pay: other lines", P.BASE_DEFAULT)
    add("per_stop", "Per served stop", P.PER_STOP)
    for i, tier in ipairs(P.PUNCTUAL) do add("punctual_" .. i, ("Punctuality bonus (<= %d s)"):format(tier.max), tier.amount) end
    add("skip_fine", "Fine per skipped stop", P.SKIP_FINE)
    add("early_fine", "Fine per early departure", P.EARLY_FINE)
    add("delay_fine", "Delay fine", P.DELAY_FINE)
    prefixes = {}
    for prefix in pairs(X.BASE) do prefixes[#prefixes + 1] = prefix end
    table.sort(prefixes)
    for _, prefix in ipairs(prefixes) do add("xp_base_" .. prefix:lower(), "XP: " .. prefix, X.BASE[prefix], "xp") end
    add("xp_base_default", "XP: other lines", X.BASE_DEFAULT, "xp")
    add("xp_per_stop", "XP per served stop", X.PER_STOP, "xp")
    add("xp_punctual", "XP punctuality bonus", X.PUNCTUAL_BONUS, "xp")
    add("xp_skip_penalty", "XP penalty per skipped stop", X.SKIP_PENALTY, "xp")
end
local wageDefault = {}
for _, p in ipairs(WAGE_PARAMS) do wageDefault[p.key] = p.default end

local function govRunning()
    local res = getResourceFromName("gov_works")
    return res and getResourceState(res) == "running"
end

local function wage(key)
    if govRunning() then
        local v = exports.gov_works:getWage(TRAINDRIVER.WORK_ID, key)
        if v then return v end
    end
    return wageDefault[key]
end

addEventHandler("onResourceStart", root, function(res)
    if (res == getThisResource() or getResourceName(res) == "gov_works") and govRunning() then
        exports.gov_works:registerWage(TRAINDRIVER.WORK_ID, WAGE_PARAMS)
    end
end)

--- TRAINDRIVER.PAY with the /gov values
local function currentPay()
    local P = TRAINDRIVER.PAY
    local t = { BASE = {}, BASE_DEFAULT = wage("base_default"), PER_STOP = wage("per_stop"), PUNCTUAL = {},
        SKIP_FINE = wage("skip_fine"), EARLY_FINE = wage("early_fine"),
        DELAY_FINE_FROM = P.DELAY_FINE_FROM, DELAY_FINE = wage("delay_fine") }
    for prefix in pairs(P.BASE) do t.BASE[prefix] = wage("base_" .. prefix:lower()) end
    for i, tier in ipairs(P.PUNCTUAL) do
        t.PUNCTUAL[i] = { max = tier.max, label = tier.label, amount = wage("punctual_" .. i) }
    end
    return t
end

--- TRAINDRIVER.XP with the /gov values
local function currentXp()
    local X = TRAINDRIVER.XP
    local t = { BASE = {}, BASE_DEFAULT = wage("xp_base_default"), PER_STOP = wage("xp_per_stop"),
        PUNCTUAL_BONUS = wage("xp_punctual"), SKIP_PENALTY = wage("xp_skip_penalty") }
    for prefix in pairs(X.BASE) do t.BASE[prefix] = wage("xp_base_" .. prefix:lower()) end
    return t
end

-- -> items (payWork format) | nil
function computePay(summary)
    local P = currentPay()
    local number = tostring(summary.number or "?")      -- "RB 1101" / "IC 2101"
    local base = P.BASE[number:match("^(%a+)")] or P.BASE_DEFAULT

    local items = { { label = L.msg("work_traindriver.pay.service", { number = number }), amount = base } }
    local served = summary.served or 0
    if served > 0 then items[#items + 1] = { label = L.msg("work_traindriver.pay.stops_served", { served = served }), amount = served * P.PER_STOP } end

    local delay = summary.arrivalDelay
    if delay then
        for _, tier in ipairs(P.PUNCTUAL) do
            if delay <= tier.max then items[#items + 1] = { label = tier.label, amount = tier.amount } break end
        end
    end
    if (summary.skipped or 0) > 0 then
        items[#items + 1] = { label = L.msg("work_traindriver.pay.skipped_stops", { skipped = summary.skipped }), amount = -summary.skipped * P.SKIP_FINE }
    end
    if (summary.earlyDepartures or 0) > 0 then
        items[#items + 1] = { label = L.msg("work_traindriver.pay.early_departures", { early_departures = summary.earlyDepartures }), amount = -summary.earlyDepartures * P.EARLY_FINE }
    end
    if P.DELAY_FINE_FROM and (summary.maxDelay or 0) > P.DELAY_FINE_FROM then
        items[#items + 1] = { label = L.msg("work_traindriver.pay.delay"), amount = -P.DELAY_FINE }
    end
    return items
end

-- XP for a completed service (TRAINDRIVER.XP)
function computeXp(summary)
    local X = currentXp()
    local number = tostring(summary.number or "?")
    local xp = X.BASE[number:match("^(%a+)")] or X.BASE_DEFAULT
    xp = xp + (summary.served or 0) * X.PER_STOP
    local delay = summary.arrivalDelay
    if delay then
        for _, tier in ipairs(TRAINDRIVER.PAY.PUNCTUAL) do
            if delay <= tier.max then xp = xp + X.PUNCTUAL_BONUS break end
        end
    end
    xp = xp - (summary.skipped or 0) * X.SKIP_PENALTY
    return math.max(10, xp)
end

local function total(items)
    local t = 0
    for _, i in ipairs(items) do t = t + i.amount end
    return t
end

local function pay(player, summary)
    local items = computePay(summary)
    if total(items) < 0 then items[#items + 1] = { label = L.msg("work_traindriver.pay.adjustment"), amount = -total(items) } end
    local ok, result = exports.work_core:payWork(player, TRAINDRIVER.WORK_ID, items, L.msg("work_traindriver.pay.service_completed", { number = tostring(summary.number) }))
    if ok then
        exports.work_core:giveWorkXp(player, TRAINDRIVER.WORK_ID, computeXp(summary))
        local stats = getResourceFromName("v_stats")
        if stats and getResourceState(stats) == "running" then exports.v_stats:addStat(player, "train_shifts", 1) end
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

    local ach = getResourceFromName("v_achievements")
    if ach and getResourceState(ach) == "running" then
        exports.v_achievements:addStat(driver, "train_services", 1)
    end
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
