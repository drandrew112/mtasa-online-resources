-- biztonság: csak engedélyezett járművek
local function isAllowedVehicle(veh)
    if not isElement(veh) then return false end
    return sirenVehicles[getElementModel(veh)] == true
end

addEvent("siren:setData", true)
addEventHandler("siren:setData", resourceRoot,
    function(veh, key, value)
        if not isAllowedVehicle(veh) then return end

        -- minimális whitelist, nehogy bármit írjanak
        if key ~= "mkjState"
        and key ~= "sirenState"
        and key ~= "sirenIndex"
        and key ~= "sirenHorn"
        and key ~= "sirenType" then
            return
        end

        setElementData(veh, key, value, true)

        -- ha mkjState változik, kapcsoljuk a built-in szirénát/fényt
        if key == "mkjState" then
            --setVehicleSirens(veh, value)
            setVehicleSirensOn(veh, value)
        end
    end
)

-- default értékek jármű belépéskor (spawn / stream)
addEventHandler("onVehicleEnter", root, function(player, seat)
    if seat ~= 0 then return end
    if not isAllowedVehicle(source) then return end

    setElementData(source, "mkjState",    getElementData(source, "mkjState")    or false, true)
    setElementData(source, "sirenState",  getElementData(source, "sirenState")  or false, true)
    setElementData(source, "sirenIndex",  getElementData(source, "sirenIndex")  or 1,     true)
    setElementData(source, "sirenHorn",   false, true)
    setElementData(source, "sirenType",   getElementData(source, "sirenType")   or "fsvas320", true)
end)

-- set siren type

addCommandHandler("stso", function (player)
    local veh = getPedOccupiedVehicle(player)
    if veh then
        setElementData(veh, "sirenType", "soundoff", true)
    end
end)

addCommandHandler("stfs", function (player)
    local veh = getPedOccupiedVehicle(player)
    if veh then
        setElementData(veh, "sirenType", "fsvas320", true)
    end
end)

addCommandHandler("strtk", function (player)
    local veh = getPedOccupiedVehicle(player)
    if veh then
        setElementData(veh, "sirenType", "hella_rtk7", true)
    end
end)

addCommandHandler("stitaly", function (player)
    local veh = getPedOccupiedVehicle(player)
    if veh then
        setElementData(veh, "sirenType", "italy", true)
    end
end)

addCommandHandler("eriston", function (player)
    local veh = getPedOccupiedVehicle(player)
    if veh then
        setElementData(veh, "sirenType", "eriston", true)
    end
end)

addCommandHandler("dal", function (player)
    local veh = getPedOccupiedVehicle(player)
    if veh then
        setElementData(veh, "sirenType", "dal", true)
    end
end)
