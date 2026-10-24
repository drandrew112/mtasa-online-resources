if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Shift-end pay: when a unit signs out (server/units.lua Units.signOut), work_core's
-- payWork() is called once for every account that was ever part of the shift
-- (u.roster - the sign-in crew; unlike u.members it never shrinks when someone
-- leaves), with one itemised line per task the unit was credited for
-- (u.closedTasks) and an equal share of that task's amount. Rates by outcome:
-- Config.PAY (shared/config.lua).
--
-- work_core is a soft dependency, same as every other optional integration here:
-- without it running, nothing is paid. An account that cannot be resolved to a
-- live player element any more (disconnected, or reconnected as a new element)
-- is simply skipped - payWork needs one to deposit into and show the receipt.

Payment = {}

local function workCoreRunning()
    local res = getResourceFromName("work_core")
    return res and getResourceState(res) == "running"
end

-- the rates are adjustable on the /gov Works page (gov_works); Config.PAY.RATES are the defaults.
-- param keys: <outcome>.base / <outcome>.per_minute (spaces of the outcome code -> "_")
local function paramKey(outcome, field) return outcome:gsub(" ", "_") .. "." .. field end

local WAGE_PARAMS = {}
do
    local outcomes = {}
    for outcome in pairs(Config.PAY.RATES) do outcomes[#outcomes + 1] = outcome end
    table.sort(outcomes)
    for _, outcome in ipairs(outcomes) do
        local r = Config.PAY.RATES[outcome]
        WAGE_PARAMS[#WAGE_PARAMS + 1] = { key = paramKey(outcome, "base"), label = "Base pay: " .. outcome, default = r.base }
        WAGE_PARAMS[#WAGE_PARAMS + 1] = { key = paramKey(outcome, "per_minute"), label = "Per minute: " .. outcome, default = r.perMinute }
    end
end

local function govRunning()
    local res = getResourceFromName("gov_works")
    return res and getResourceState(res) == "running"
end

addEventHandler("onResourceStart", root, function(res)
    if (res == getThisResource() or getResourceName(res) == "gov_works") and govRunning() then
        exports.gov_works:registerWage(Config.PAY.WORK_ID, WAGE_PARAMS)
    end
end)

local function rateValue(outcome, field, default)
    if govRunning() then
        local v = exports.gov_works:getWage(Config.PAY.WORK_ID, paramKey(outcome, field))
        if v then return v end
    end
    return default
end

local function taskAmount(c)
    local outcome = Config.PAY.RATES[c.outcome] and c.outcome or "default"
    local rate = Config.PAY.RATES[outcome]
    local base = rateValue(outcome, "base", rate.base)
    local perMinute = rateValue(outcome, "per_minute", rate.perMinute)
    return base + (c.duration or 0) / 60 * perMinute
end

-- closedTasks outcome code -> shown word (the codes are also the Config.PAY.RATES keys)
local OUTCOME_LABEL = {
    handover          = "med_erm.outcome.handover",
    released          = "med_erm.outcome.released",
    left              = "med_erm.outcome.left",
    ["task closed"]   = "med_erm.outcome.task_closed",
    ["shift ended"]   = "med_erm.outcome.shift_ended",
}

local function taskLabel(c)
    local mins = math.floor((c.duration or 0) / 60 + 0.5)
    return L.msg("med_erm.payment.m", { id = c.id, title = c.title, outcome = L.msg(OUTCOME_LABEL[c.outcome or "released"] or "med_erm.outcome.released"), mins = mins })
end

function Payment.payUnit(u)
    if #u.closedTasks == 0 or not workCoreRunning() then return end

    local n = math.max(1, #u.roster)
    local items = {}
    for _, c in ipairs(u.closedTasks) do
        local amount = taskAmount(c) / n
        if amount ~= 0 then
            items[#items + 1] = { label = taskLabel(c), amount = amount }
        end
    end
    if #items == 0 then return end

    for _, player in ipairs(u.roster) do
        if isElement(player) and getElementType(player) == "player" then
            exports.work_core:payWork(player, Config.PAY.WORK_ID, items, L.msg("med_erm.payment.shift_ended", { callsign = u.callsign }))
        end
    end
end
