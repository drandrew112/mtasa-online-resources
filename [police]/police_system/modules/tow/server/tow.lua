-- police_system / modules/tow/server/tow.lua
-- AI tow truck (525). REQUEST_TOW: the nearest empty vehicle within REQUEST_DIST; a police car only after a
-- confirmation temp menu ("Tow your police car?"); not with someone inside. The vehicle is locked (nobody gets in),
-- the MDC shows the state. The truck appears on the road network 150-350 m from the vehicle at a point nobody sees,
-- drives next to it, hooks it up (attached, tilted, no collision) and drives to the tow point of the nearest
-- station. It disappears when nobody sees it; at the tow point it goes anyway, with the vehicle (an owned vehicle
-- is stored back in v_ownveh). Destroyed before the pick-up: failed, everything back, the caller is told.

local TW = POL.module("tow", { jobs = {} })   -- jobs[vehicle] = { truck, driver, caller, unit, state }
local C = POLICE.TOW

local function traffic() return POL.running("ai_land_traffic") and exports.ai_land_traffic or nil end

local function hasOccupant(veh)
    for _ in pairs(getVehicleOccupants(veh) or {}) do return true end
    return false
end

local function nearestEmpty(player)
    local x, y, z = getElementPosition(player)
    local own = getPedOccupiedVehicle(player)
    local best, bd
    for _, v in ipairs(getElementsWithinRange(x, y, z, C.REQUEST_DIST, "vehicle")) do
        if v ~= own and not TW.jobs[v] and not hasOccupant(v) and not POL.ai.units[v] and getVehicleType(v) ~= "Train" then
            local d = POL.dist(player, v)
            if not bd or d < bd then best, bd = v, d end
        end
    end
    return best
end

local function fail(job, key)
    local veh = job.vehicle
    TW.jobs[veh] = nil
    if isElement(veh) then setVehicleLocked(veh, false) end
    local t = traffic()
    if isElement(job.truck) and t then
        if isElement(veh) and isElementAttached(veh) then detachElements(veh, job.truck) end
        t:clearScriptedTargets(job.truck)
        t:setScriptedDespawnUnseen(job.truck, { minDist = 80 })
    end
    if isElement(job.caller) then POL.notify(job.caller, key or "police_system.tow.failed") end
end

-- veh = the vehicle picked in the interact menu (else the nearest empty one)
function TW.request(player, confirmed, veh)
    if veh then
        if not isElement(veh) or getElementType(veh) ~= "vehicle" or TW.jobs[veh] or hasOccupant(veh) or POL.ai.units[veh]
            or getVehicleType(veh) == "Train" or POL.dist(player, veh) > C.REQUEST_DIST then veh = nil end
    else
        veh = nearestEmpty(player)
    end
    if not veh then POL.notify(player, "police_system.tow.no_vehicle") return false end
    if isPoliceVehicle(veh) and not confirmed then
        POL.send(player, "tow:confirm", veh)
        return false
    end
    local t = traffic()
    if not t then POL.notify(player, "police_system.tow.unavailable") return false end
    local x, y, z = getElementPosition(veh)
    local sx, sy, sz, rot = t:findHiddenRoadSpawn(x, y, z, { minDist = C.SPAWN_MIN, maxDist = C.SPAWN_MAX, toward = veh })
    if not sx then POL.notify(player, "police_system.tow.unavailable") return false end
    local truck, driver = t:createScriptedVehicle(C.MODEL, sx, sy, sz, { heading = rot, skin = C.SKIN, profile = "truck" })
    if not truck then POL.notify(player, "police_system.tow.unavailable") return false end
    setVehicleLocked(veh, true)
    local unit = POL.units.of(player)
    local job = { vehicle = veh, truck = truck, driver = driver, caller = player, unit = unit, state = "coming",
                  at = getTickCount() }
    TW.jobs[veh] = job
    t:addScriptedStop(truck, x, y, z, { tag = "tow_pickup", hold = true, radius = 40 })
    POL.events.logFor(player, "tow_requested", { plate = getVehiclePlateText(veh) })
    POL.notify(player, "police_system.tow.coming")
    return true
end

-- nobody gets into a vehicle waiting for the tow truck
addEventHandler("onVehicleStartEnter", root, function()
    if TW.jobs[source] then cancelEvent() end
end)

local function jobOfTruck(truck)
    for _, j in pairs(TW.jobs) do if j.truck == truck then return j end end
    return nil
end

addEvent("onTrafficVehicleTargetReached")
addEventHandler("onTrafficVehicleTargetReached", root, function(truck, id, kind, tag)
    local job = jobOfTruck(truck)
    if not job then return end
    local t = traffic()
    if tag == "tow_pickup" and job.state == "coming" then
        local veh = job.vehicle
        if not isElement(veh) or isVehicleBlown(veh) then return fail(job) end
        job.state = "towing"
        setElementCollisionsEnabled(veh, false)
        attachElements(veh, truck, 0, -6.2, -0.6, 8, 0, 0)
        local x, y = getElementPosition(truck)
        local st = POL.nearestStation(x, y)
        job.station = st
        t:continueScriptedVehicle(truck)
        t:clearScriptedTargets(truck)
        t:addScriptedStop(truck, st.tow[1], st.tow[2], st.tow[3], { tag = "tow_drop", hold = true, radius = 60 })
        t:setScriptedDespawnUnseen(truck, { minDist = 60 })
        if isElement(job.caller) then POL.notify(job.caller, "police_system.tow.picked_up") end
    elseif tag == "tow_drop" then
        TW.finish(job)
    end
end)

-- the towed vehicle goes (an owned vehicle back into its owner's garage)
function TW.finish(job)
    local veh = job.vehicle
    TW.jobs[veh] = nil
    if isElement(veh) then
        local ov = tonumber(getElementData(veh, "ownveh:id"))
        if isElementAttached(veh) then detachElements(veh) end
        local stored = false
        if ov and POL.running("v_ownveh") then
            setVehicleLocked(veh, false)
            local ok = exports.v_ownveh:storeVehicle(ov)
            stored = ok == true
        end
        if not stored and isElement(veh) then destroyElement(veh) end
    end
    local t = traffic()
    if isElement(job.truck) and t then t:destroyScriptedVehicle(job.truck) end
    POL.db.stat("tows", 1)
end

addEvent("onTrafficVehicleRemoved")
addEventHandler("onTrafficVehicleRemoved", root, function(truck, reason)
    local job = jobOfTruck(truck)
    if not job then return end
    if job.state == "towing" and reason == "despawned" then
        -- went unseen with the vehicle: the vehicle goes too
        TW.finish(job)
    elseif job.state == "coming" then
        fail(job)
    end
end)

addEventHandler("onVehicleExplode", root, function()
    local job = TW.jobs[source]
    if job and job.state == "coming" then fail(job) end
end)

addEventHandler("onElementDestroy", root, function()
    local job = TW.jobs[source]
    if job and job.state == "coming" then fail(job) end
end)

POL.net("tow:confirm", function(player, veh)
    if isElement(veh) and POL.units.of(player) then TW.request(player, true, veh) end
end)

-- MDC: the tow jobs of a unit
function TW.forUnit(unit)
    local out = {}
    for veh, j in pairs(TW.jobs) do
        if j.unit == unit and isElement(veh) then
            local d = isElement(j.truck) and POL.dist(j.truck, veh) or 0
            out[#out + 1] = { plate = getVehiclePlateText(veh), state = j.state, distance = math.floor(d) }
        end
    end
    return out
end
