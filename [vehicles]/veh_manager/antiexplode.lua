-- veh_manager :: anti-explode (server)
--
-- Vehicles never catch fire and never explode on their own:
--   * health is never allowed below MIN_HP (GTA sets a vehicle on fire under
--     FIRE_HP, and a burning vehicle explodes a few seconds later);
--   * at or below LOCK_HP (fire + 10 hp) the vehicle is "wrecked": its engine
--     is forced off until it is repaired above LOCK_HP (fixVehicle, repair
--     shops, setElementHealth by any script);
--   * an upside-down vehicle takes no damage at all.
--
-- Damage is applied by the vehicle's syncer, so the real work (cancelling
-- damage, clamping health every frame, roll-over protection) happens in
-- antiexplode_c.lua. This side keeps the wrecked state, holds the engine off
-- and clamps vehicles that have no syncer.
--
-- Wrecked state: element data "veh.wrecked" = true (synced).
-- Exports: isVehicleWrecked(vehicle)

local FIRE_HP        = 250
local MIN_HP         = FIRE_HP + 1
local LOCK_HP        = FIRE_HP + 10
local SWEEP_INTERVAL = 500 -- ms
local WRECK_KEY      = "veh.wrecked"

-- Trains are handled by the railway resources (damage proof there).
local function isProtected(vehicle)
    return isElement(vehicle) and getElementType(vehicle) == "vehicle"
        and not isVehicleBlown(vehicle) and getVehicleType(vehicle) ~= "Train"
end

function isVehicleWrecked(vehicle)
    return isElement(vehicle) and getElementData(vehicle, WRECK_KEY) == true
end

local function setWrecked(vehicle, state)
    if state then
        if getElementData(vehicle, WRECK_KEY) ~= true then
            setElementData(vehicle, WRECK_KEY, true)
        end
        if getVehicleEngineState(vehicle) then
            setVehicleEngineState(vehicle, false)
        end
    elseif getElementData(vehicle, WRECK_KEY) ~= nil then
        removeElementData(vehicle, WRECK_KEY)
    end
end

local function check(vehicle)
    if not isProtected(vehicle) then return end
    local hp = getElementHealth(vehicle)
    if hp < MIN_HP then
        setElementHealth(vehicle, MIN_HP)
        hp = MIN_HP
    end
    setWrecked(vehicle, hp <= LOCK_HP)
end

addEventHandler("onResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle")) do check(vehicle) end
    setTimer(function()
        for _, vehicle in ipairs(getElementsByType("vehicle")) do check(vehicle) end
    end, SWEEP_INTERVAL, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        if getElementData(vehicle, WRECK_KEY) ~= nil then removeElementData(vehicle, WRECK_KEY) end
    end
end)

-- Health on the server is the syncer's value after the damage; check right
-- away so the engine dies with the hit, not at the next sweep.
addEventHandler("onVehicleDamage", root, function()
    check(source)
end)

-- GTA starts the engine when a driver gets in; turn it back off after that.
addEventHandler("onVehicleEnter", root, function(_, seat)
    if seat ~= 0 or not isVehicleWrecked(source) then return end
    local vehicle = source
    setTimer(function()
        if isElement(vehicle) and isVehicleWrecked(vehicle) then
            setVehicleEngineState(vehicle, false)
        end
    end, 50, 1)
end)

addEventHandler("onVehicleRespawn", root, function()
    setWrecked(source, false)
end)
