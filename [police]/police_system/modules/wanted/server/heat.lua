-- police_system / modules/wanted/server/heat.lua
-- 2 -> 3 and the heat points: any damage to the police (AI peds, AI vehicles, officers on duty, unit vehicles)
-- = level 3 at least + HEAT.damage; a dead officer HEAT.kill; a destroyed police vehicle HEAT.vehicle. 4-6 by the
-- HEAT_LEVELS thresholds. Damage to vehicles is reported by the attacker's client (wanted:vehdmg).

local W = POL.wanted
local C = POLICE.WANTED
local lastHit = {}       -- [vehicle] = { player, tick } (who damaged a police vehicle last)
local throttle = {}      -- [player] = tick

local function culprit(el)
    if isElement(el) and getElementType(el) == "vehicle" then el = getVehicleController(el) end
    if isElement(el) and getElementType(el) == "player" then return el end
    return nil
end

local function hit(player, kind, reason)
    if not player then return end
    local now = getTickCount()
    if kind == "damage" and throttle[player] and now - throttle[player] < 1000 then return end
    throttle[player] = now
    W.heat(player, kind, reason)
end

-- officers on duty (players)
addEventHandler("onPlayerDamage", root, function(attacker)
    if not POL.units.isOnDuty(source) then return end
    local p = culprit(attacker)
    if p and p ~= source then hit(p, "damage", "shots_at_police") end
end)

addEventHandler("onPlayerWasted", root, function(_, killer)
    if not POL.units.isOnDuty(source) then return end
    local p = culprit(killer)
    if p and p ~= source then hit(p, "kill", "police_down") end
end)

-- AI officers (ai_peds events)
addEvent("onAIPedDamaged")
addEventHandler("onAIPedDamaged", root, function(attacker)
    if not POL.ai.peds[source] then return end
    hit(culprit(attacker), "damage", "shots_at_police")
end)

addEvent("onAIPedWasted")
addEventHandler("onAIPedWasted", root, function(killer)
    if not POL.ai.peds[source] then return end
    hit(culprit(killer), "kill", "police_down")
end)

-- police vehicles (AI or a unit's): the attacker's client reports
POL.net("wanted:vehdmg", function(player, veh)
    if not isElement(veh) or not POL.isPoliceVehicleOrAI(veh) then return end
    if POL.dist(player, veh) > 120 or POL.units.isOnDuty(player) then return end
    -- the driver of the police car itself does not count
    if getVehicleController(veh) == player then return end
    lastHit[veh] = { player, getTickCount() }
    hit(player, "damage", "shots_at_police")
end)

addEventHandler("onVehicleExplode", root, function()
    local h = lastHit[source]
    lastHit[source] = nil
    if h and isElement(h[1]) and getTickCount() - h[2] < 10000 and POL.isPoliceVehicleOrAI(source) then
        W.heat(h[1], "vehicle", "police_vehicle_destroyed")
    end
end)

addEventHandler("onElementDestroy", root, function()
    if lastHit[source] then lastHit[source] = nil end
end)

addEventHandler("onPlayerQuit", root, function() throttle[source] = nil end)
