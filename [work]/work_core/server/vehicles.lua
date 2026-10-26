if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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

local function isRunning(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-- tuning (v_customs), paintjob (v_paintjobs), ELS extra and siren type (v_els) of a vehicle
-- definition; each is skipped when its resource is not running
local function applyVehicleExtras(vehicle, def)
    if def.tuning and isRunning("v_customs") then
        pcall(function() exports.v_customs:applyVehicleTuning(vehicle, def.tuning) end)
    end
    if def.paintjob and isRunning("v_paintjobs") then
        local ok, done = pcall(function() return exports.v_paintjobs:setVehicleCustomPaintjob(vehicle, def.paintjob) end)
        if not ok or not done then
            outputDebugString(("[work_core] paintjob %s not found for model %d"):format(def.paintjob, def.model), 2)
        end
    end
    if def.elsExtra and isRunning("v_els") then
        pcall(function() exports.v_els:setElsExtra(vehicle, def.elsExtra) end)
    end
    if def.sirenType and isRunning("v_els") then
        local ok, done = pcall(function() return exports.v_els:setElsSirenType(vehicle, def.sirenType) end)
        if not ok or not done then
            outputDebugString(("[work_core] siren type %s could not be set on model %d"):format(def.sirenType, def.model), 2)
        end
    end
end

-- -> vehicle | false, errorText
function spawnWorkVehicle(player, marker, index)
    local m = Markers[marker]
    if not m or m.kind ~= "vehicle" then return false, L.msg("work_core.vehicles.invalid_vehicle_point") end
    local def = m.vehicles[tonumber(index) or 0]
    if not def then return false, L.msg("work_core.vehicles.invalid_vehicle") end
    if not isPlayerOnDuty(player, m.work) then return false, L.msg("work_core.vehicles.you_must_be_on_duty_to") end
    if isPedInVehicle(player) then return false, L.msg("work_core.vehicles.leave_your_vehicle_first") end
    if def.level and def.level > 1 and getPlayerWorkLevel(player, m.work) < def.level then
        local work = Works[m.work]
        return false, L.msg("work_core.vehicles.vehicle_needs_level", { name = work and work.name or m.work, need = def.level })
    end

    local old = getPlayerWorkVehicle(player)
    if old and hasOtherOccupants(old, player) then
        return false, L.msg("work_core.vehicles.your_current_work_vehicle_is_still")
    end
    destroyPlayerWorkVehicle(player)

    local int, dim = getElementInterior(marker), getElementDimension(marker)
    local s = freeSpawn(m, int, dim)
    if not s then return false, L.msg("work_core.vehicles.vehicle_spawn_point_is_blocked") end

    local plate = def.platePrefix and generatePlate(def.platePrefix, def.plateDigits) or def.plate
    local vehicle = createVehicle(def.model, s[1], s[2], s[3], 0, 0, s[4], plate)
    if not vehicle then return false, L.msg("work_core.vehicles.vehicle_could_not_be_created") end
    setElementInterior(vehicle, int)
    setElementDimension(vehicle, dim)
    if def.color then setVehicleColor(vehicle, unpack(def.color)) end
    if def.data then
        for k, v in pairs(def.data) do setElementData(vehicle, k, v) end
    end
    applyVehicleExtras(vehicle, def)
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
    if not m or m.kind ~= "vehicle" or not vehicle then return false, L.msg("work_core.vehicles.you_are_not_in_work_vehicle") end
    local d = byVehicle[vehicle]
    if not d or d.owner ~= player or d.work ~= m.work then return false, L.msg("work_core.vehicles.this_is_not_your_work_vehicle") end
    if hasOtherOccupants(vehicle, player) then return false, L.msg("work_core.vehicles.everyone_has_to_get_out_first") end
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
        notifyPlayer(player, work and work.name or L.msg("work_core.menus.work"),
            L.msg("work_core.vehicles.only_on_duty_workers_can_drive"))
    end
end)

addEventHandler("onVehicleExplode", root, function()
    if not byVehicle[source] then return end
    local vehicle = source
    setTimer(function()
        if isElement(vehicle) and byVehicle[vehicle] then destroyElement(vehicle) end
    end, WORK.EXPLODED_CLEANUP, 1)
end)
