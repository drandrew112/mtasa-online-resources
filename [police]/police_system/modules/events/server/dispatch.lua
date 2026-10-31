-- police_system / modules/events/server/dispatch.lua
-- Calls and backup. Calls: citizens ring the police on the phone's emergency contact (ui_phone "pd" line ->
-- export createPoliceCall); later a shared scene manager (medical + police) adds automatic ones. The MDC Calls page
-- lists them; a unit responds (route objective on v_radar, status Responding) and closes them.
-- Backup (REQUEST_BACKUP): only when another unit is on duty; the nearest available one gets it (MDC message,
-- route objective, Responding) and a "backup" incident, paid when it arrived there (within 40 m).

local D = POL.module("dispatch", { calls = {}, seq = 0, objectives = {} })

local function setObjective(unit, x, y, z, labelKey)
    for _, p in ipairs(POL.units.members(unit)) do
        if POL.running("v_radar") then
            local old = D.objectives[p]
            if old then pcall(function() exports.v_radar:removeObjective(p, old) end) end
            local ok, id = pcall(function() return exports.v_radar:addObjective(p, x, y, z, L.forPlayer(p, labelKey)) end)
            D.objectives[p] = ok and id or nil
        end
    end
end

function D.clearObjective(unit)
    for _, p in ipairs(POL.units.members(unit)) do
        local id = D.objectives[p]
        if id and POL.running("v_radar") then pcall(function() exports.v_radar:removeObjective(p, id) end) end
        D.objectives[p] = nil
    end
end

------------------------------------------------------------------------ calls

-- export: a call from a player's phone. -> id | false, reason
function createPoliceCall(caller, title, description)
    if not isElement(caller) or getElementType(caller) ~= "player" then return false, "bad_caller" end
    if #POL.units.onDuty() == 0 then return false, "no_units" end
    for _, c in pairs(D.calls) do
        if c.caller == caller and c.status ~= "closed" then return false, "open_call" end
    end
    local x, y, z = getElementPosition(caller)
    D.seq = D.seq + 1
    local c = { id = D.seq, caller = caller, name = POL.nameOf(caller), title = tostring(title or ""):sub(1, 60),
                description = tostring(description or ""):sub(1, 300), x = x, y = y, z = z,
                zone = getZoneName(x, y, z), at = POL.now(), status = "open", units = {} }
    D.calls[c.id] = c
    POL.db.stat("calls", 1)
    POL.notify(POL.units.onDuty(), "police_system.dispatch.new_call", { id = c.id, title = c.title, zone = c.zone })
    POL.emit("calls.changed")
    return c.id
end

function D.list()
    local out = {}
    for _, c in pairs(D.calls) do
        if c.status ~= "closed" or POL.now() - (c.closedAt or 0) < 900 then
            local units = {}
            for cs in pairs(c.units) do units[#units + 1] = cs end
            out[#out + 1] = { id = c.id, name = c.name, title = c.title, description = c.description, zone = c.zone,
                              at = c.at, status = c.status, units = units }
        end
    end
    table.sort(out, function(a, b) return a.id > b.id end)
    return out
end

function D.respond(player, id)
    local unit = POL.units.of(player)
    local c = D.calls[tonumber(id)]
    if not unit or not c or c.status == "closed" then return false end
    c.units[unit.callsign] = true
    c.status = "assigned"
    POL.units.setStatus(unit, "responding", player)
    setObjective(unit, c.x, c.y, c.z, "police_system.dispatch.call_objective")
    POL.events.log(unit, player, "call_respond", { call = c.id })
    if isElement(c.caller) then POL.notify(c.caller, "police_system.dispatch.call_taken", { callsign = unit.callsign }) end
    POL.emit("calls.changed")
    return true
end

function D.closeCall(player, id)
    local unit = POL.units.of(player)
    local c = D.calls[tonumber(id)]
    if not unit or not c or c.status == "closed" then return false end
    c.status, c.closedAt = "closed", POL.now()
    D.clearObjective(unit)
    POL.events.log(unit, player, "call_closed", { call = c.id })
    POL.emit("calls.changed")
    return true
end

addEventHandler("onPlayerQuit", root, function()
    for _, c in pairs(D.calls) do if c.caller == source then c.caller = nil end end
    D.objectives[source] = nil
end)

------------------------------------------------------------------------ backup

function D.requestBackup(player)
    local unit = POL.units.of(player)
    if not unit then return false, "not_in_unit" end
    local x, y, z = getElementPosition(player)
    local best, bd
    for _, u in pairs(POL.units.list) do
        if u ~= unit and u.status == "available" then
            for _, p in ipairs(POL.units.members(u)) do
                local d = POL.dist2D(p, x, y)
                if not bd or d < bd then best, bd = u, d end
            end
        end
    end
    local others = 0
    for _, u in pairs(POL.units.list) do if u ~= unit then others = others + 1 end end
    if others == 0 then return false, "no_units" end
    if not best then return false, "none_available" end
    POL.units.setStatus(best, "responding", nil)
    setObjective(best, x, y, z, "police_system.dispatch.backup_objective")
    local inc = POL.events.open(best, "backup", nil)
    inc.backupFor, inc.bx, inc.by, inc.bz = unit.callsign, x, y, z
    POL.notify(POL.units.members(best), "police_system.dispatch.backup_assigned", { callsign = unit.callsign, zone = getZoneName(x, y, z) })
    POL.notify(POL.units.members(unit), "police_system.dispatch.backup_coming", { callsign = best.callsign })
    POL.events.log(unit, player, "backup_requested", { to = best.callsign })
    POL.db.stat("backups", 1)
    return true
end

-- a backup unit that got there counts as arrived (paid at Code 4)
local function backupTick()
    for _, u in pairs(POL.units.list) do
        for inc in pairs(u.incidents) do
            if inc.type == "backup" and not inc.arrived then
                for _, p in ipairs(POL.units.members(u)) do
                    if POL.dist2D(p, inc.bx, inc.by) < 40 then
                        inc.arrived = true
                        POL.events.log(u, p, "backup_arrived", { for_unit = inc.backupFor }, inc)
                        D.clearObjective(u)
                        break
                    end
                end
            end
        end
    end
end

function D.start() setTimer(backupTick, 2000, 0) end
