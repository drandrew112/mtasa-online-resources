-- v_headlights kliens
-- L gomb: a vezető ki/bekapcsolja a fényszórót.

local function toggleHeadlights()
    local veh = getPedOccupiedVehicle(localPlayer)
    if not veh then return end

    -- csak akkor, ha a vezető ülésben ülünk (0-s ülés)
    if getPedOccupiedVehicleSeat(localPlayer) ~= 0 then return end

    triggerServerEvent("headlights:toggle", localPlayer)
end

bindKey("l", "down", toggleHeadlights)

-- streamelt járművek helyi újraszinkronizálása, hogy azonnal a jó állapot látszódjon
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "vehicle" then return end

    local on = getElementData(source, "headlights:on")
    setVehicleOverrideLights(source, (on == true) and 2 or 1)
end)
