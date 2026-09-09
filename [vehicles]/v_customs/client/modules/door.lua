-- v_customs :: LSD / scissor doors (client)
--
-- Ported from the original SA Customs `door/sourceC.lua`. Reacts to the synced
-- "tuning.lsdDoor" element data the server sets; animates the front doors
-- upward instead of outward while they are open.

local oldDoorRatios = {}
local doorStatus    = {}
local doorTimers    = {}
local scissor       = {}   -- [veh] = true
local ANIM          = 250

local function isVehicle(v)
    return v and isElement(v) and getElementType(v) == "vehicle"
end

local function forget(veh)
    oldDoorRatios[veh] = nil
    doorStatus[veh]    = nil
    doorTimers[veh]    = nil
    scissor[veh]       = nil
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle")) do
        if isElementStreamedIn(veh) and getElementData(veh, "tuning.lsdDoor") then
            scissor[veh] = true
        end
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if isVehicle(source) then forget(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if isVehicle(source) then forget(source) end
end)

addEventHandler("onClientVehicleExplode", root, function()
    if isVehicle(source) then forget(source) end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if isVehicle(source) and getElementData(source, "tuning.lsdDoor") then
        scissor[source] = true
    end
end)

addEventHandler("onClientElementDataChange", root, function(data)
    if not isVehicle(source) or data ~= "tuning.lsdDoor" then return end
    if isElementStreamedIn(source) then
        if getElementData(source, "tuning.lsdDoor") then
            scissor[source] = true
        else
            forget(source)
            resetVehicleComponentRotation(source, "door_lf_dummy")
            resetVehicleComponentRotation(source, "door_rf_dummy")
        end
    end
end)

addEventHandler("onClientPreRender", root, function()
    for veh in pairs(scissor) do
        if not isElement(veh) then
            forget(veh)
        else
            doorTimers[veh] = doorTimers[veh] or {}

            for n = 1, 4 do
                local i = n + 1
                local ratio = getVehicleDoorOpenRatio(veh, i)
                if ratio and oldDoorRatios[veh] and oldDoorRatios[veh][i] then
                    local old = oldDoorRatios[veh][i]
                    doorStatus[veh] = doorStatus[veh] or {}
                    local prev = doorStatus[veh][i] or "closed"

                    if prev == "closed" and ratio > old then
                        doorStatus[veh][i] = "opening"
                        doorTimers[veh][i] = setTimer(function(v, k)
                            if doorStatus[v] then doorStatus[v][k] = "open" end
                            if doorTimers[v] then doorTimers[v][k] = nil end
                        end, ANIM, 1, veh, i)
                    elseif prev == "open" and ratio < old then
                        doorStatus[veh][i] = "closing"
                        doorTimers[veh][i] = setTimer(function(v, k)
                            if doorStatus[v] then doorStatus[v][k] = "closed" end
                            if doorTimers[v] then doorTimers[v][k] = nil end
                        end, ANIM, 1, veh, i)
                    end
                elseif not oldDoorRatios[veh] then
                    oldDoorRatios[veh] = {}
                end
                if ratio then
                    oldDoorRatios[veh] = oldDoorRatios[veh] or {}
                    oldDoorRatios[veh][i] = ratio
                end
            end
        end
    end

    for veh, doors in pairs(doorStatus) do
        if scissor[veh] and isElement(veh) then
            for door, status in pairs(doors) do
                local ratio = (status == "open") and 1 or 0
                local t = doorTimers[veh] and doorTimers[veh][door]
                if t and isTimer(t) then
                    ratio = getTimerDetails(t) / ANIM
                    if status == "opening" then ratio = 1 - ratio end
                end

                local dummy = (door == 2 and "door_lf_dummy") or (door == 3 and "door_rf_dummy")
                if dummy then
                    local dx, dy, dz = -72 * ratio, -25 * ratio, 0
                    if dummy:find("rf") then dy, dz = -dy, -dz end
                    setVehicleComponentRotation(veh, dummy, dx, dy, dz)
                end
            end
        end
    end
end)

addEventHandler("onClientVehicleDamage", root, function()
    if getVehicleDoorState(source, 2) == 1 then setVehicleDoorOpenRatio(source, 2, 0, 500) end
    if getVehicleDoorState(source, 3) == 1 then setVehicleDoorOpenRatio(source, 3, 0, 500) end
end)
