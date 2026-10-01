-- Events GTA has no damage event for, reported to the server (which checks them):
--  * a bare-fisted punch into a vehicle (or a wall, with MEDEV.PUNCH_WORLD)
--  * a vehicle crash: the speed change of the local player's vehicle in km/h

local lastPunch = 0

local function canPunch()
    if isPedDead(localPlayer) or isPedInVehicle(localPlayer) or isElementInWater(localPlayer) then return false end
    if getPedWeapon(localPlayer) ~= 0 or not isControlEnabled("fire") then return false end
    return not (isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive())
end

-- When the fist lands: is there a vehicle (or the world) right in front of the chest?
local function checkPunch()
    if not canPunch() then return end
    local x, y, z = getElementPosition(localPlayer)
    z = z + 0.45
    local matrix = getElementMatrix(localPlayer)
    local fx, fy = matrix[2][1], matrix[2][2]
    local reach = MEDEV.PUNCH_REACH
    local hit, _, _, _, element = processLineOfSight(x, y, z, x + fx * reach, y + fy * reach, z,
        MEDEV.PUNCH_WORLD, true, false, MEDEV.PUNCH_WORLD, false, false, false, false, localPlayer)
    if not hit then return end

    if element and getElementType(element) == "vehicle" then
        triggerServerEvent("medev:punch", resourceRoot, element)
    elseif MEDEV.PUNCH_WORLD and (not element or getElementType(element) == "object") then
        triggerServerEvent("medev:punch", resourceRoot, false)
    end
end

bindKey("fire", "down", function()
    local now = getTickCount()
    if now - lastPunch < MEDEV.PUNCH_COOLDOWN or not canPunch() then return end
    lastPunch = now
    setTimer(checkPunch, MEDEV.PUNCH_HIT_DELAY, 1)
end)

---------------------------------------------------------------------------
-- Crashes
---------------------------------------------------------------------------

local lastVelocity       -- velocity of the local vehicle in the previous frame
local measuring = false  -- a crash is being measured
local lastCrash = 0

addEventHandler("onClientPreRender", root, function()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle and not measuring then
        lastVelocity = { getElementVelocity(vehicle) }
    elseif not vehicle then
        lastVelocity = nil
    end
end)

addEventHandler("onClientVehicleCollision", root, function()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if source ~= vehicle or measuring or not lastVelocity then return end
    if getTickCount() - lastCrash < MEDEV.CRASH_COOLDOWN then return end

    -- the speed before the impact is the last frame's; read the speed after it a bit later
    measuring = true
    local before = lastVelocity
    setTimer(function()
        measuring = false
        if not isElement(vehicle) or getPedOccupiedVehicle(localPlayer) ~= vehicle then return end
        local vx, vy, vz = getElementVelocity(vehicle)
        local dx, dy, dz = before[1] - vx, before[2] - vy, before[3] - vz
        local change = math.sqrt(dx * dx + dy * dy + dz * dz) * 180 -- km/h
        if change >= MEDEV.CRASH_MIN_SPEED then
            lastCrash = getTickCount()
            triggerServerEvent("medev:crash", resourceRoot, vehicle, change)
        end
    end, MEDEV.CRASH_MEASURE_DELAY, 1)
end)
