local vehicleSounds = {}
local volume_in     = 1
local volume_out    = 0.02

function updateRadio(veh)
    if not isElement(veh) then return end

    local stationId = getElementData(veh, "radiostation_id") or 0

    if vehicleSounds[veh] then
        destroyElement(vehicleSounds[veh])
        vehicleSounds[veh] = nil
    end

    if stationId == 0 then return end

    local station = RADIO_STATIONS[stationId]
    if not station then return end

    local s = playSound3D(station.url, 0, 0, 0, true)
    attachElements(s, veh)
    setSoundMaxDistance(s, 50)

    -- alapértelmezett hangerő: külső
    setSoundVolume(s, volume_out)

    -- ha pont ebben ülünk
    if getPedOccupiedVehicle(localPlayer) == veh then
        setSoundVolume(s, volume_in)
    end

    vehicleSounds[veh] = s
end


addEventHandler("onClientVehicleEnter", root,
    function(player)
        if player ~= localPlayer then return end

        if vehicleSounds[source] then
            setSoundVolume(vehicleSounds[source], volume_in)
        end
    end
)
addEventHandler("onClientVehicleExit", root,
    function(player)
        if player ~= localPlayer then return end

        if vehicleSounds[source] then
            setSoundVolume(vehicleSounds[source], volume_out)
        end
    end
)


addEventHandler("onClientElementDestroy", root,
    function ()
        if vehicleSounds[source] then
            destroyElement(vehicleSounds[source])
            vehicleSounds[source] = nil
        end
    end
)


addEventHandler("onClientElementDataChange", root,
    function (data)
        if data == "radiostation_id" then
            updateRadio(source)
        end
    end
)
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        if getElementData(veh, "radiostation_id") then
            updateRadio(veh)
        end
    end
end)

function applyStation()
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end
    triggerServerEvent("radio:setStation", localPlayer, veh, selectedStation)
end

--bindKey("q", "up", applyStation)

