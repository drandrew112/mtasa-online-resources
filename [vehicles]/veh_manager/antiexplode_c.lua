-- veh_manager :: anti-explode (client)
--
-- Runs on every client; the syncer of a vehicle is the one whose changes
-- count, so health is only written for vehicles this client syncs.
--   * damage that would take a vehicle under MIN_HP is cancelled and the
--     health set to MIN_HP (so it never reaches the GTA fire threshold);
--   * an upside-down vehicle takes no damage: hits are cancelled, and the
--     health GTA drains from a vehicle lying on its roof is restored every
--     frame;
--   * the driver of a wrecked vehicle (see antiexplode.lua) gets a notice.

local FIRE_HP       = 250
local MIN_HP        = FIRE_HP + 1
local FLIP_UP_Z     = 0.3   -- up vector z below this = rolled over (> ~72 deg)
local LIST_INTERVAL = 250   -- ms, refresh of the synced vehicle list
local WRECK_KEY     = "veh.wrecked"

local synced   = {}                         -- vehicles this client syncs
local lastHp   = setmetatable({}, { __mode = "k" })

local function isProtected(vehicle)
    return isElement(vehicle) and not isVehicleBlown(vehicle)
        and getVehicleType(vehicle) ~= "Train"
end

local function isFlipped(vehicle)
    local m = getElementMatrix(vehicle)
    return m and m[3][3] < FLIP_UP_Z
end

addEventHandler("onClientVehicleDamage", root, function(_, _, loss)
    if not isProtected(source) then return end
    if isFlipped(source) then
        cancelEvent()
        return
    end
    local hp = getElementHealth(source)
    if hp - (loss or 0) < MIN_HP then
        cancelEvent()
        if isElementSyncer(source) and hp ~= MIN_HP then
            setElementHealth(source, MIN_HP)
        end
    end
end)

local function refreshList()
    local list = {}
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        if isElementSyncer(vehicle) and isProtected(vehicle) then
            list[#list + 1] = vehicle
        end
    end
    synced = list
end

addEventHandler("onClientPreRender", root, function()
    for i = 1, #synced do
        local vehicle = synced[i]
        if isProtected(vehicle) then
            local hp = getElementHealth(vehicle)
            local last = lastHp[vehicle]
            if last and hp < last and isFlipped(vehicle) then
                setElementHealth(vehicle, last)
            elseif hp < MIN_HP then
                setElementHealth(vehicle, MIN_HP)
                lastHp[vehicle] = MIN_HP
            else
                lastHp[vehicle] = hp
            end
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    refreshList()
    setTimer(refreshList, LIST_INTERVAL, 0)
end)

local function notifyWrecked()
    pcall(function()
        exports.ui_core:addNotification("Vehicle", "The vehicle is too badly damaged to drive. Get it repaired.")
    end)
end

addEventHandler("onClientPlayerVehicleEnter", localPlayer, function(vehicle, seat)
    if seat == 0 and getElementData(vehicle, WRECK_KEY) == true then notifyWrecked() end
end)

addEventHandler("onClientElementDataChange", root, function(key, _, new)
    if key ~= WRECK_KEY or new ~= true or getElementType(source) ~= "vehicle" then return end
    if getVehicleController(source) == localPlayer then notifyWrecked() end
end)
