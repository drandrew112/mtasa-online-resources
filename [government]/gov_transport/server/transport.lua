-- gov_transport / server/transport.lua
-- Public transport money, per mode (GOV_PT_MODES; now only "rail", buses later), one setting
-- "pt.<mode>" set on the /gov Public transport page:
--   fares:  fare_km per km of the journey (straight line between the stops), at least fare_min,
--           + ic_supplement once for an IC train; the ticket money goes to fare_receiver
--   costs:  cost_ic / cost_rb per trip run (by train category), cost_stop per served stop,
--           paid by cost_payer to cost_receiver
-- Payer / receiver specs as on the Healthcare page: "system" (nobody: money from nothing / the
-- money disappears) | "state:<code>" | "company:<id>". payer system + receiver system = nothing
-- is booked ("from nobody to nowhere").
-- pt_tickets sells the tickets (getTransportFare, bookFareIncome); rw_timetable charges the
-- running costs of every service (chargeTransportCost).

loadstring(exports.gov_core:importLib())()

-- setting key -> default value
GOV_DEFAULTS = {
    -- railway (pt_tickets sells the tickets, rw_timetable charges the running costs)
    ["pt.rail"] = {
        fare_km = 100,            -- € per km of the journey (straight line between the stops)
        fare_min = 50,            -- the cheapest ticket
        ic_supplement = 500,      -- once per ticket on an IC train
        fare_receiver = "system", -- the ticket money: "system" (nobody) | "state:<code>" | "company:<id>"
        cost_ic = 2000,           -- running cost of one IC trip
        cost_rb = 800,            -- running cost of one RB (regional) trip
        cost_stop = 150,          -- per served stop
        cost_payer = "system",    -- system = nobody pays (money from nothing)
        cost_receiver = "system", -- system = nobody receives (the money disappears)
    },
}

-- the modes of the page (setting "pt.<mode>")
GOV_PT_MODES = { "rail" }
GOV_PT_NUMBERS = { "fare_km", "fare_min", "ic_supplement", "cost_ic", "cost_rb", "cost_stop" }
GOV_PT_SPECS = { "fare_receiver", "cost_payer", "cost_receiver" }

GOV_RANGE = {
    ptMoney = { 0, 1000000 },
}

--- the settings of a mode, missing fields filled from the defaults
function GOV.ptSettings(mode)
    local def = GOV_DEFAULTS["pt." .. tostring(mode)]
    if not def then return nil end
    local cur = GOV.get("pt." .. mode)
    cur = type(cur) == "table" and cur or {}
    local out = {}
    for k, v in pairs(def) do
        local x = cur[k]
        if type(v) == "number" then x = tonumber(x) end
        if type(v) == "string" and type(x) ~= "string" then x = nil end
        if x == nil then x = v end
        out[k] = x
    end
    return out
end

function getTransportSettings(mode)
    return GOV.ptSettings(mode) or false
end

--- ticket price of a journey: km (number), category "IC" | "RB" | ... -> amount, details
function getTransportFare(mode, km, category)
    local s = GOV.ptSettings(mode)
    if not s then return false end
    local base = math.floor(math.max(0, tonumber(km) or 0) * s.fare_km + 0.5)
    base = math.max(base, s.fare_min)
    local extra = tostring(category or ""):upper() == "IC" and s.ic_supplement or 0
    return base + extra, { base = base, supplement = extra, km = tonumber(km) or 0 }
end

--- the ticket of `player` was paid (the money already left the player, pt.ticket): the same sum
--- goes to the fare receiver of the mode -> true | false, err
function bookFareIncome(mode, amount, params)
    local s = GOV.ptSettings(mode)
    amount = math.floor(tonumber(amount) or 0)
    if not s or amount <= 0 then return true end
    local receiver = GOV.specAccount(s.fare_receiver)
    if receiver == false then
        outputDebugString(("[gov_transport] fare receiver %s of %s is gone, the money disappears"):format(s.fare_receiver, mode), 2)
    end
    receiver = tonumber(receiver)
    if not receiver then return true end
    local bank = GOV.bank()
    if not bank then return false, "unavailable" end
    params = type(params) == "table" and params or {}
    params.mode = mode
    local ok, err = bank:transfer(nil, receiver, amount, "pt.fare_income", params, "v_gov")
    if not ok then return false, err end
    return true
end

--- running cost of a service: kind "run" (params.category = "IC" | "RB") | "stop" (params.count,
--- default 1) -> true, amount | false, err
function chargeTransportCost(mode, kind, params)
    local s = GOV.ptSettings(mode)
    if not s then return false, "bad_mode" end
    params = type(params) == "table" and params or {}
    local amount, key
    if kind == "run" then
        amount = tonumber(s["cost_" .. tostring(params.category or ""):lower()]) or 0
        key = "pt.run_cost"
    elseif kind == "stop" then
        params.count = math.max(1, math.floor(tonumber(params.count) or 1))
        amount = s.cost_stop * params.count
        key = "pt.stop_cost"
    else
        return false, "bad_kind"
    end
    amount = math.floor(amount)
    if amount <= 0 then return true, 0 end
    local payer, receiver = GOV.specAccount(s.cost_payer), GOV.specAccount(s.cost_receiver)
    if payer == false then
        outputDebugString(("[gov_transport] %s cost payer %s is gone, paid from system"):format(mode, s.cost_payer), 2)
    end
    if receiver == false then
        outputDebugString(("[gov_transport] %s cost receiver %s is gone, the money disappears"):format(mode, s.cost_receiver), 2)
    end
    payer, receiver = tonumber(payer), tonumber(receiver)
    if not payer and not receiver then return true, amount end         -- from nobody to nowhere
    if payer and payer == receiver then return true, amount end
    local bank = GOV.bank()
    if not bank then return false, "unavailable" end
    params.mode = mode
    local ok, err = bank:transfer(payer, receiver, amount, key, params, "v_gov")
    if not ok then return false, err end
    return true, amount
end

--- the planned railway running costs of a day (the day of timestamp ts) from the rw_timetable
--- timetable and the pt.rail cost settings, every stop of every trip counted as served:
--- { trips, stops, run, stop, total, categories = { IC = { trips, run }, ... }, payer, receiver,
---   booked } | false (rw_timetable does not run). booked = false: from nobody to nowhere.
function getRailDayCosts(ts)
    local s = GOV.ptSettings("rail")
    if not s or not isResourceRunning("rw_timetable") then return false end
    local ok, deps = pcall(function() return exports.rw_timetable:getDayTimetable(ts) end)
    if not ok or type(deps) ~= "table" then return false end
    local out = { trips = #deps, stops = 0, run = 0, stop = 0, categories = {},
        payer = s.cost_payer, receiver = s.cost_receiver,
        booked = not (s.cost_payer == "system" and s.cost_receiver == "system") and s.cost_payer ~= s.cost_receiver }
    for _, d in ipairs(deps) do
        local cat = tostring(d.category or "RB"):upper()
        local fee = math.floor(tonumber(s["cost_" .. cat:lower()]) or 0)
        local c = out.categories[cat] or { trips = 0, run = 0 }
        out.categories[cat] = c
        c.trips, c.run = c.trips + 1, c.run + fee
        out.run = out.run + fee
        out.stops = out.stops + math.floor(tonumber(d.stops) or 0)
    end
    out.stop = out.stops * s.cost_stop
    out.total = out.run + out.stop
    return out
end
