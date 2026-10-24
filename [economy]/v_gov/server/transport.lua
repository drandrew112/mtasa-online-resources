-- v_gov / server/transport.lua
-- Public transport money (DESIGN.md 11), per mode (GOV_PT_MODES; now only "rail", buses later),
-- one setting "pt.<mode>" set on the /gov Transport page:
--   fares:  fare_km per km of the journey (straight line between the stops), at least fare_min,
--           + ic_supplement once for an IC train; the ticket money goes to fare_receiver
--   costs:  cost_ic / cost_rb per trip run (by train category), cost_stop per served stop,
--           paid by cost_payer to cost_receiver
-- Payer / receiver specs as on the Healthcare page: "system" (nobody: money from nothing / the
-- money disappears) | "state:<code>" | "company:<id>". payer system + receiver system = nothing
-- is booked ("from nobody to nowhere").
-- pt_tickets sells the tickets (getTransportFare, bookFareIncome); rw_timetable charges the
-- running costs of every service (chargeTransportCost).

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
        outputDebugString(("[v_gov] fare receiver %s of %s is gone, the money disappears"):format(s.fare_receiver, mode), 2)
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
        outputDebugString(("[v_gov] %s cost payer %s is gone, paid from system"):format(mode, s.cost_payer), 2)
    end
    if receiver == false then
        outputDebugString(("[v_gov] %s cost receiver %s is gone, the money disappears"):format(mode, s.cost_receiver), 2)
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
