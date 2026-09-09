-- v_customs :: nitro (client)
--
-- Capacity (25/50/75/100) is bought in the workshop and persists on
-- "customs:extras".nitro; the live charge refills to capacity every time the
-- player gets in and drains while LSHIFT is held.

local veh       = nil
local capacity  = 0     -- purchased %, 0 = no nitro
local charge    = 0     -- remaining %
local boosting  = false
local lastTick  = 0
local DRAIN     = 5     -- % per second

addEvent("v_customs:nitroLevel", true)

local function bind(v)
    veh = v
    local extras = getElementData(v, "customs:extras")
    capacity = (type(extras) == "table" and tonumber(extras.nitro)) or 0
    charge   = capacity
    lastTick = getTickCount()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local v = getPedOccupiedVehicle(localPlayer)
    if v and getVehicleController(v) == localPlayer then bind(v) end
end)

addEventHandler("onClientVehicleEnter", root, function(player, seat)
    if player == localPlayer and seat == 0 then bind(source) end
end)

addEventHandler("onClientVehicleExit", root, function(player, seat)
    if player == localPlayer and seat == 0 then veh = nil end
end)

addEventHandler("v_customs:nitroLevel", root, function(v, level)
    if v ~= veh then return end
    capacity = tonumber(level) or 0
    charge   = capacity
end)

bindKey("lshift", "down", function() boosting = true end)
bindKey("lshift", "up",   function() boosting = false end)

addEventHandler("onClientRender", root, function()
    if not isElement(veh) or capacity <= 0 then return end
    if getVehicleUpgradeOnSlot(veh, 8) ~= 1010 then return end

    local now = getTickCount()
    local dt  = (now - lastTick) / 1000
    lastTick  = now

    if boosting and charge > 0 then
        setVehicleNitroLevel(veh, 1)
        setVehicleNitroActivated(veh, true)
        charge = math.max(0, charge - dt * DRAIN)
    else
        setVehicleNitroActivated(veh, false)
    end
end)
