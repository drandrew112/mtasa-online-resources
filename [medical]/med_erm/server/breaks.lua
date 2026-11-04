if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Break request (tablet Home > Requests): an available unit can ask for a 20 minute break every 2 hours
-- (Config.BREAK). Auto dispatch grants it at once, otherwise a dispatcher approves it (web console). While on
-- break the unit has the "break" status (orange), gets no cases and can end the break any time.
-- A pending request expires when the unit gets a case (Tasks.assign) - and then there is no cooldown, because
-- the cooldown only starts when a break actually starts.

Break = {}

addEvent("onErmAutoDispatchChange", false)

-- Timestamp (now()) from which the unit may request its next break; 0 = now.
function Break.nextAt(u)
    if not u.lastBreakAt then return 0 end
    return u.lastBreakAt + Config.BREAK.COOLDOWN
end

local function minutes(seconds)
    return math.max(1, math.ceil(seconds / 60))
end

local function autoDispatchOn()
    return AutoDispatch and AutoDispatch.state().enabled == true
end

local function setBreakStatus(u, status)
    local old = u.status
    u.status = status
    Units.sync(u)
    if old ~= status then Events.fire("onErmUnitStatusChange", u.id, status, old) end
end

-- Starts the break (checks done by the callers).
local function grant(u)
    u.breakRequest = nil
    u.lastBreakAt = now()
    u.breakEnds = u.lastBreakAt + Config.BREAK.DURATION
    setBreakStatus(u, "break")
    Units.notify(u, L.msg("med_erm.break.started_title"),
        L.msg("med_erm.break.started", { minutes = minutes(Config.BREAK.DURATION) }))
    Events.fire("onErmUnitBreakStart", u.id)
end

-- The unit asks for a break -> true | false, error
function Break.request(u)
    if u.status == "break" then return false, L.msg("med_erm.break.only_available") end
    if u.status ~= "available" or u.task then return false, L.msg("med_erm.break.only_available") end
    if u.breakRequest then return false, L.msg("med_erm.break.already_pending") end
    local wait = Break.nextAt(u) - now()
    if wait > 0 then return false, L.msg("med_erm.break.wait", { minutes = minutes(wait) }) end

    if autoDispatchOn() then
        grant(u)
    else
        u.breakRequest = now()
        Units.sync(u)
        Units.notify(u, L.msg("med_erm.break.requested_title"), L.msg("med_erm.break.requested"))
        Events.fire("onErmUnitBreakRequest", u.id)
    end
    return true
end

function Break.cancel(u)
    if not u.breakRequest then return false, L.msg("med_erm.break.no_request") end
    u.breakRequest = nil
    Units.sync(u)
    Units.notify(u, L.msg("med_erm.break.requested_title"), L.msg("med_erm.break.cancelled"))
    return true
end

-- Ends the break (the unit interrupts it, or it ran out) -> true | false, error
function Break.finish(u, expired)
    if u.status ~= "break" then return false, L.msg("med_erm.break.not_on_break") end
    u.breakEnds = nil
    setBreakStatus(u, "available")
    Units.notify(u, L.msg("med_erm.break.started_title"),
        L.msg(expired and "med_erm.break.ended" or "med_erm.break.interrupted"))
    return true
end

-- Dispatcher answers (web console) -> true | false, error
function Break.approve(unitId, by)
    local u = Units.get(unitId)
    if not u then return false, L.msg("med_erm.chat.unit_not_found") end
    if not u.breakRequest then return false, L.msg("med_erm.break.no_request") end
    if u.status ~= "available" or u.task then return false, L.msg("med_erm.break.only_available") end
    grant(u)
    return true
end

function Break.deny(unitId, by)
    local u = Units.get(unitId)
    if not u then return false, L.msg("med_erm.chat.unit_not_found") end
    if not u.breakRequest then return false, L.msg("med_erm.break.no_request") end
    u.breakRequest = nil
    Units.sync(u)
    Units.notify(u, L.msg("med_erm.break.requested_title"), L.msg("med_erm.break.denied"))
    return true
end

-- Breaks run out
setTimer(function()
    local t = now()
    for _, u in pairs(Units.list) do
        if u.status == "break" and u.breakEnds and t >= u.breakEnds then Break.finish(u, true) end
    end
end, 1000, 0)

-- Auto dispatch switched on: the waiting requests are granted
addEventHandler("onErmAutoDispatchChange", root, function(enabled)
    if not enabled then return end
    for _, u in pairs(Units.list) do
        if u.breakRequest and u.status == "available" and not u.task then grant(u) end
    end
end)
