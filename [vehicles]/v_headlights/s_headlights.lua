-- v_headlights
-- Letiltja a játék automatikus fényszóró kezelését (nem kapcsol be sötétedéskor),
-- és kézi vezérlést ad: a vezető az L gombbal kapcsolja ki/be a fényszórót.
--
-- setVehicleOverrideLights:
--   1 = mindig kikapcsolva  -> ezzel tiltjuk az automatikus kezelést
--   2 = mindig bekapcsolva

-- alkalmazza a fényszóró állapotát a járműre (és letiltja az auto kezelést)
local function applyHeadlights(veh)
    if not isElement(veh) then return end

    local on = getElementData(veh, "headlights:on")
    if on == nil then
        on = false
        setElementData(veh, "headlights:on", false)
    end

    setVehicleOverrideLights(veh, on and 2 or 1)
end

-- meglévő járművek indításkor
addEventHandler("onResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle")) do
        applyHeadlights(veh)
    end
end)

-- új / éppen belépett járművek
addEventHandler("onVehicleEnter", root, function()
    applyHeadlights(source)
end)

-- kézi kapcsolás a vezetőtől (kliens L gomb)
addEvent("headlights:toggle", true)
addEventHandler("headlights:toggle", root, function()
    local player = client
    if not isElement(player) then return end

    local veh = getPedOccupiedVehicle(player)
    if not veh then return end

    -- csak a vezető (0-s ülés) kapcsolhat
    if getVehicleController(veh) ~= player then return end

    local on = not (getElementData(veh, "headlights:on") == true)
    setElementData(veh, "headlights:on", on)
    setVehicleOverrideLights(veh, on and 2 or 1)
end)
