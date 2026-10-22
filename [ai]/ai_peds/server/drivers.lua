-- Drivers taken over from ai_land_traffic (server). When a traffic vehicle leaves the simulation (crash, damage,
-- jacked, a player got in) ai_land_traffic hands its driver over with the export adoptTrafficDriver. The driver
-- gets out properly (behaviour "exiting", never teleported) and then is scared (flees) or an enemy (attacks the
-- player who caused it, with fists or a weapon).

Drivers = {}

local T = AIPEDS
local random = math.random

local function pickWeapon()
    local total = 0
    for _, w in ipairs(T.DRIVER_WEAPONS) do total = total + w[3] end
    local r = random() * total
    for _, w in ipairs(T.DRIVER_WEAPONS) do
        r = r - w[3]
        if r <= 0 then return w[1], w[2] end
    end
    return T.DRIVER_WEAPONS[1][1], T.DRIVER_WEAPONS[1][2]
end

-- opts: reason ("crash" | "damage" | "jacked" | "enter"), culprit (player / element that caused it),
-- behaviour ("scared" | "enemy": forced instead of the dice)
function Drivers.adopt(ped, veh, opts)
    opts = opts or {}
    if not isElement(ped) or getElementType(ped) ~= "ped" or isPedDead(ped) then return false end
    if Peds.list[ped] then return true end
    local culprit = opts.culprit
    if isElement(culprit) and getElementType(culprit) == "vehicle" then culprit = getVehicleOccupant(culprit, 0) end
    if not (isElement(culprit) and Peds.alive(culprit)) then culprit = nil end
    local jacked = opts.reason == "jacked" or opts.reason == "enter"

    local final = opts.behaviour
    if final ~= "enemy" and final ~= "scared" then
        final = "scared"
        local chance = jacked and T.DRIVER_ENEMY_CHANCE_JACKED or T.DRIVER_ENEMY_CHANCE
        if culprit and random() < chance then final = "enemy" end
    end
    if final == "enemy" and not culprit then final = "scared" end

    local p = Peds.adopt(ped, "driver", { group = "civilian" })
    p.task = { name = "wander" }   -- after calming down: back to the sidewalks (if there are any)
    local finalArgs
    if final == "enemy" then
        if random() < T.DRIVER_ARMED_CHANCE then
            local w, ammo = pickWeapon()
            Peds.giveWeapon(p, w, ammo)
        else
            Peds.giveWeapon(p, 0)
        end
        Groups.grudge(p, culprit, T.GRUDGE_TIME)
        finalArgs = { target = culprit, calmTo = "civilian" }
    else
        local x, y, z = getElementPosition(culprit or veh or ped)
        finalArgs = { threat = culprit, x = x, y = y, z = z, calmTo = "civilian" }
    end
    if isElement(veh) and getPedOccupiedVehicle(ped) == veh then
        Peds.setBehaviour(p, "exiting", { vehicle = veh, jacked = jacked, final = final, finalArgs = finalArgs })
    else
        p.outAt = getTickCount()
        Peds.setBehaviour(p, final, finalArgs)
    end
    return true
end
