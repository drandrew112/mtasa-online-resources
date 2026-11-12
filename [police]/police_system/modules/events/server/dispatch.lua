-- police_system / modules/events/server/dispatch.lua
-- Backup and the on-duty AI group. The calls (phone, scene, EMS requests), their offers and the route objectives are
-- the CalloutManager (modules/callouts/server/callouts.lua).
-- Backup (REQUEST_BACKUP): only when another unit is on duty; the nearest available one gets it (MDC message,
-- route objective, Responding) and a "backup" incident, paid when it arrived there (within 40 m).

local D = POL.module("dispatch", {})

function isOfficerOnDuty(player)
    return isElement(player) and POL.units.isOnDuty(player) or false
end

-- Exported: the callsign of the unit the officer is signed in to, or false (v_voice radio)
function getOfficerUnit(player)
    local u = isElement(player) and POL.units.of(player)
    return u and (u.callsign or u.id) or false
end

-- Exported: { callsign, status, sub } of the officer's unit, or false (v_radar unit indicator)
function getOfficerUnitInfo(player)
    local u = isElement(player) and POL.units.of(player)
    if not u then return false end
    return { callsign = u.callsign or u.id, status = u.status, sub = u.sub }
end

-- on-duty officers are in the ai_peds group "police" (the AI cops too): scene NPCs hostile only to the police
-- (v_scenemanager) attack them and nobody else
local function setAIGroup(player, on)
    if not isElement(player) or not POL.running("ai_peds") then return end
    pcall(function() exports.ai_peds:setPlayerAIGroup(player, on and "police" or false) end)
end

POL.on("units.member", function(unit, player, joined) setAIGroup(player, joined) end)
POL.on("unit.signedOff", function(unit)
    for _, p in ipairs(POL.units.members(unit)) do setAIGroup(p, false) end
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) ~= "ai_peds" then return end
    setTimer(function()
        for _, p in ipairs(POL.units.onDuty()) do setAIGroup(p, true) end
    end, 1000, 1)
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
    POL.callouts.setObjective(best, x, y, z, "police_system.dispatch.backup_objective")
    local inc = POL.events.open(best, "backup", nil)
    inc.backupFor, inc.bx, inc.by, inc.bz = unit.callsign, x, y, z
    POL.notify(POL.units.members(best), "police_system.dispatch.backup_assigned", { callsign = unit.callsign, zone = getZoneName(x, y, z) })
    POL.notify(POL.units.members(unit), "police_system.dispatch.backup_coming", { callsign = best.callsign })
    POL.events.log(unit, player, "backup_requested", { to = best.callsign })
    POL.db.stat("backups", 1)
    POL.emit("backup.requested", unit, best, x, y, z)
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
                        POL.callouts.clearObjective(u)
                        break
                    end
                end
            end
        end
    end
end

function D.start() setTimer(backupTick, 2000, 0) end
