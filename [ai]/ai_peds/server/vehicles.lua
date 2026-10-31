-- Vehicle tasks (server): an AI ped gets into a seat (the GTA enter animation on its syncer: setPedEnterVehicle) or
-- out of its vehicle (setPedExitVehicle). While a task runs the behaviour waits. Without a syncer, or when the
-- animation does not happen (blocked door), it is placed in / out after VEH_TASK_TIMEOUT (warp fallback).
-- Events (source = the ped): onAIPedEnteredVehicle(veh, seat), onAIPedExitedVehicle(veh),
-- onAIPedVehicleTaskFailed("enter" | "exit", reason)
--
-- p.vt = { kind = "enter" | "exit", veh, seat, since, sentTo (syncer that got the command) }

VehTasks = {}

local T = AIPEDS

local function done(p, ev, ...)
    p.vt = nil
    Peds.setCmd(p, { m = "idle" })
    triggerEvent(ev, p.el, ...)
end

function VehTasks.enter(p, veh, seat)
    seat = tonumber(seat) or 0
    if getPedOccupiedVehicle(p.el) == veh then return true end
    p.vt = { kind = "enter", veh = veh, seat = seat, since = getTickCount() }
    Peds.setCmd(p, { m = "enter", veh = veh, seat = seat })
    p.vt.sentTo = p.syncer
    return true
end

function VehTasks.exit(p)
    local veh = getPedOccupiedVehicle(p.el)
    if not veh then return false end
    p.vt = { kind = "exit", veh = veh, since = getTickCount() }
    Peds.setCmd(p, { m = "exit" })
    p.vt.sentTo = p.syncer
    return true
end

-- true while the task runs
function VehTasks.update(p, now)
    local vt = p.vt
    local veh = vt.veh
    local inside = getPedOccupiedVehicle(p.el)
    if vt.kind == "enter" then
        if inside == veh then done(p, "onAIPedEnteredVehicle", veh, vt.seat); return false end
        if not isElement(veh) or isVehicleBlown(veh) or p.dead then
            p.vt = nil
            triggerEvent("onAIPedVehicleTaskFailed", p.el, "enter", "vehicle")
            return false
        end
        local occ = getVehicleOccupant(veh, vt.seat)
        if occ and occ ~= p.el then
            p.vt = nil
            triggerEvent("onAIPedVehicleTaskFailed", p.el, "enter", "seat_taken")
            return false
        end
        local wait = p.syncer and T.VEH_TASK_TIMEOUT or T.VEH_TASK_UNSYNCED
        if now - vt.since > wait then
            if inside then removePedFromVehicle(p.el) end
            warpPedIntoVehicle(p.el, veh, vt.seat)
            done(p, "onAIPedEnteredVehicle", veh, vt.seat)
            return false
        end
    else
        if not inside then done(p, "onAIPedExitedVehicle", veh); return false end
        local wait = p.syncer and T.VEH_TASK_TIMEOUT or T.VEH_TASK_UNSYNCED
        if now - vt.since > wait then
            local x, y, z = getElementPosition(inside)
            local _, _, rz = getElementRotation(inside)
            removePedFromVehicle(p.el)
            local a = math.rad(rz)
            setElementPosition(p.el, x - math.cos(a) * 2.2, y - math.sin(a) * 2.2, z + 0.3)
            done(p, "onAIPedExitedVehicle", inside)
            return false
        end
    end
    -- a new syncer has not seen the command yet
    if p.syncer ~= vt.sentTo then
        vt.sentTo = p.syncer
        Peds.updateCmd(p)
    end
    return true
end

-- syncer reports while a task runs: "exited" (out on the syncer, the server still has it seated)
function VehTasks.report(p, kind, data)
    if kind ~= "exited" or p.vt.kind ~= "exit" then return false end
    local veh = getPedOccupiedVehicle(p.el)
    if veh then
        removePedFromVehicle(p.el)
        local x, y, z = type(data) == "table" and tonumber(data[1]), tonumber(data and data[2]), tonumber(data and data[3])
        if x and y and z then setElementPosition(p.el, x, y, z) end
    end
    return true
end
