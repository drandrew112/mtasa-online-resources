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

local function rateFor(outcome)
    return Config.PAY.RATES[outcome] or Config.PAY.RATES.default
end

local function taskAmount(c)
    local rate = rateFor(c.outcome)
    return rate.base + (c.duration or 0) / 60 * rate.perMinute
end

local function taskLabel(c)
    local mins = math.floor((c.duration or 0) / 60 + 0.5)
    return string.format("#%d %s (%s, %dm)", c.id, c.title, c.outcome or "released", mins)
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
            exports.work_core:payWork(player, Config.PAY.WORK_ID, items, u.callsign .. " - shift ended")
        end
    end
end
