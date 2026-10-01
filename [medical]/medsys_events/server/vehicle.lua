-- Events reported by the clients (GTA has no damage event for them): punching a vehicle with a
-- bare fist, and vehicle crashes. The server checks every report.

addEvent("medev:punch", true)
addEvent("medev:crash", true)

-- streaks[player] = { count, tick }
local streaks = {}

addEventHandler("medev:punch", resourceRoot, function(vehicle)
    local player = client
    if not player or isPedDead(player) or isPedInVehicle(player) then return end
    if getPedWeapon(player) ~= 0 then return end -- bare fist only (brass knuckles protect)

    local factor = 1
    if vehicle then
        if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return end
        if getElementDimension(vehicle) ~= getElementDimension(player) then return end
        local px, py, pz = getElementPosition(player)
        local vx, vy, vz = getElementPosition(vehicle)
        if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > MEDEV.PUNCH_MAX_DISTANCE then
            return
        end
    elseif MEDEV.PUNCH_WORLD then
        factor = MEDEV_PUNCH.WORLD_FACTOR
    else
        return
    end
    if not checkCooldown(player, "punch", MEDEV.PUNCH_COOLDOWN * 0.8) then return end

    local now = getTickCount()
    local streak = streaks[player]
    if not streak or now - streak.tick > MEDEV_PUNCH.streakWindow then
        streak = { count = 0 }
        streaks[player] = streak
    end
    streak.count = streak.count + 1
    streak.tick = now

    local chance = math.min(MEDEV_PUNCH.maxChance,
        MEDEV_PUNCH.chance + MEDEV_PUNCH.streakBonus * (streak.count - 1)) * factor
    applyTier(player, {
        pain = MEDEV_PUNCH.pain,
        injuries = { { type = "fracture", part = "arm", chance = chance, severity = MEDEV_PUNCH.severity } },
    }, "punch")
end)

local OPEN_VEHICLES = { Bike = true, BMX = true, Quad = true }

addEventHandler("medev:crash", resourceRoot, function(vehicle, speedChange)
    local player = client
    speedChange = tonumber(speedChange)
    if not player or not speedChange or speedChange < MEDEV.CRASH_MIN_SPEED
        or speedChange > MEDEV.CRASH_MAX_SPEED then return end
    if not isElement(vehicle) or getPedOccupiedVehicle(player) ~= vehicle then return end
    -- one report per crash, whoever of the occupants sends it first
    if not checkCooldown(vehicle, "crash", MEDEV.CRASH_COOLDOWN) then return end

    if OPEN_VEHICLES[getVehicleType(vehicle)] then
        speedChange = speedChange * MEDEV.CRASH_OPEN_FACTOR
    end

    for _, occupant in pairs(getVehicleOccupants(vehicle) or {}) do
        if isMedsysTarget(occupant) and not isPedDead(occupant) then
            -- every occupant rolls separately
            applyTier(occupant, pickTier(MEDEV_RULES.crash, speedChange), "crash")
        end
    end
end)

addEventHandler("onPlayerQuit", root, function()
    streaks[source] = nil
end)
