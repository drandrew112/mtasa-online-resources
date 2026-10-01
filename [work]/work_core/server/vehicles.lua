-- Work vehicles requested at duty vehicle markers. One per player; removed when the player
-- goes off duty / quits, returns it at a vehicle marker, or some seconds after it explodes.
-- Only players on duty in the vehicle's work may drive it (passengers are not restricted).
--
-- Event: onWorkVehicleSpawn (player, workId, model), source = the vehicle - e.g. for liveries,
-- sirens or unit registration in the work resource.

local byPlayer = {}                -- player -> vehicle
local byVehicle = {}               -- vehicle -> { owner, work }

addEvent("onWorkVehicleSpawn")

function getPlayerWorkVehicle(player)
    local v = byPlayer[player]
    return (v and isElement(v)) and v or false
end

function getVehicleWork(vehicle)
    local d = byVehicle[vehicle]
    return d and d.work or false
end

function getWorkVehicleOwner(vehicle)
    local d = byVehicle[vehicle]
    return d and isElement(d.owner) and d.owner or false
end

function destroyPlayerWorkVehicle(player)
    local v = byPlayer[player]
    byPlayer[player] = nil
    if not v then return false end
    byVehicle[v] = nil
    if isElement(v) then destroyElement(v) end
    return true
end

local function hasOtherOccupants(vehicle, player)
    for _, occupant in pairs(getVehicleOccupants(vehicle) or {}) do
        if occupant ~= player then return true end
    end
    return false
end

local function freeSpawn(m, int, dim)
    for _, s in ipairs(m.spawns) do
        local near = getElementsWithinRange(s[1], s[2], s[3], WORK.SPAWN_CLEAR_RADIUS, "vehicle", int, dim)
        if #near == 0 then return s end
    end
    return nil
end

local function plateInUse(text)
    for _, v in ipairs(getElementsByType("vehicle")) do
        local plate = getVehiclePlateText(v)
        if plate and plate:gsub("%s+$", "") == text then return true end
    end
    return false
end

-- platePrefix + random digits, unique among the existing vehicles
local function generatePlate(prefix, digits)
    local text
    for _ = 1, 50 do
        text = prefix .. ("%0" .. digits .. "d"):format(math.random(0, 10 ^ digits - 1))
        if not plateInUse(text) then return text end
    end
    return text
end

-- -> vehicle | false, errorText
function spawnWorkVehicle(player, marker, index)
    local m = Markers[marker]
    if not m or m.kind ~= "vehicle" then return false, "Invalid vehicle point." end
    local def = m.vehicles[tonumber(index) or 0]
    if not def then return false, "Invalid vehicle." end
    if not isPlayerOnDuty(player, m.work) then return false, "You must be on duty to request a work vehicle." end
    if isPedInVehicle(player) then return false, "Leave your vehicle first." end

    local old = getPlayerWorkVehicle(player)
    if old and hasOtherOccupants(old, player) then
        return false, "Your current work vehicle is still in use."
    end
    destroyPlayerWorkVehicle(player)

    local int, dim = getElementInterior(marker), getElementDimension(marker)
    local s = freeSpawn(m, int, dim)
    if not s then return false, "The vehicle spawn point is blocked." end

    local plate = def.platePrefix and generatePlate(def.platePrefix, def.plateDigits) or def.plate
    local vehicle = createVehicle(def.model, s[1], s[2], s[3], 0, 0, s[4], plate)
    if not vehicle then return false, "The vehicle could not be created." end
    setElementInterior(vehicle, int)
    setElementDimension(vehicle, dim)
    if def.color then setVehicleColor(vehicle, unpack(def.color)) end
    if def.data then
        for k, v in pairs(def.data) do setElementData(vehicle, k, v) end
    end
    setElementData(vehicle, WORK_DATA.VEHICLE_WORK, m.work)
    setElementData(vehicle, WORK_DATA.VEHICLE_OWNER, player)

    byPlayer[player] = vehicle
    byVehicle[vehicle] = { owner = player, work = m.work }
    addEventHandler("onElementDestroy", vehicle, function()
        local d = byVehicle[source]
        byVehicle[source] = nil
        if d and byPlayer[d.owner] == source then byPlayer[d.owner] = nil end
    end, false)

    warpPedIntoVehicle(player, vehicle)
    triggerEvent("onWorkVehicleSpawn", vehicle, player, m.work, def.model)
    return vehicle
end

-- The driver returns their own work vehicle at a vehicle marker of the same work
function returnWorkVehicle(player, marker)
    local m = Markers[marker]
    local vehicle = getPedOccupiedVehicle(player)
    if not m or m.kind ~= "vehicle" or not vehicle then return false, "You are not in a work vehicle." end
    local d = byVehicle[vehicle]
    if not d or d.owner ~= player or d.work ~= m.work then return false, "This is not your work vehicle." end
    if hasOtherOccupants(vehicle, player) then return false, "Everyone has to get out first." end
    destroyPlayerWorkVehicle(player)
    return true
end

---------------------------------------------------------------- engine events

addEventHandler("onVehicleStartEnter", root, function(player, seat)
    if seat ~= 0 then return end
    local d = byVehicle[source]
    if d and not isPlayerOnDuty(player, d.work) then
        cancelEvent()
        local work = Works[d.work]
        notifyPlayer(player, work and work.name or "Work",
            "Only on-duty workers can drive this vehicle.")
    end
end)

addEventHandler("onVehicleExplode", root, function()
    if not byVehicle[source] then return end
    local vehicle = source
    setTimer(function()
        if isElement(vehicle) and byVehicle[vehicle] then destroyElement(vehicle) end
    end, WORK.EXPLODED_CLEANUP, 1)
end)
