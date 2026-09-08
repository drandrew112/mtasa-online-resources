
-- MAIN MENU
registerMenu({
    id = "main",
    title = "INTERACTION MENU",
    back = nil,
    items = {
        {
            label = "Fast Travel",
            type = "select",
            value = 1,
            options = {
                {
                    label = "LS Airport",
                    action = function()
                        if getPedOccupiedVehicle(localPlayer) then return uicore:addNotification("Error", "You can't use fast travel in a vehicle") end
                        setElementPosition(localPlayer, 1683.09, -2286.06, 13.5)
                    end
                },
                {
                    label = "LV Airport",
                    action = function()
                        if getPedOccupiedVehicle(localPlayer) then return uicore:addNotification("Error", "You can't use fast travel in a vehicle") end
                        setElementPosition(localPlayer, 1693.51, 1447.89, 10.76)
                    end
                },
                {
                    label = "SF Airport",
                    action = function()
                        if getPedOccupiedVehicle(localPlayer) then return uicore:addNotification("Error", "You can't use fast travel in a vehicle") end
                        setElementPosition(localPlayer, -1409.88, -304.44, 14.14)
                    end
                }
            }
        },
        {
            label = "Vehicle",
            type = "submenu",
            target = "vehicle"
        },
        {
            label = "Collectibles",
            type = "submenu",
            target = "collectibles"
        },
        {
            label = "Stats",
            type = "submenu",
            target = "stats"
        }
    }
})

-- VEHCILE
registerMenu({
    id = "vehicle",
    title = "Vehicle",
    back = "main",
    items = {
        {
            label = "Spawn vehicle",
            type = "submenu",
            target = "spawn_vehicle"
        },
        {
            label = "Request vehicle",
            type = "submenu",
            target = "request_personal_vehicle",
            desc = "Summon one of your personal vehicles",
            onOpen = function()
                triggerServerEvent("ui_inac:requestPersonalVehicleList", localPlayer)
            end
        },
        {
            label = "Restore personal vehicle",
            type = "action",
            desc = "Store the personal vehicle you currently have out",
            action = function()
                triggerServerEvent("ui_inac:storePersonalVehicle", localPlayer)
            end
        },
        {
            label = "Repair vehicle",
            type = "action",
            action = function()
                local veh = getPedOccupiedVehicle(localPlayer)
                if not veh then uicore:addNotification("Error", "You need a vehicle for this")
                else fixVehicle(veh)
                end
            end
        },
        {
            label = "Siren Type",
            type = "select",
            value = 1,
            options = {
                {
                    label = "Federal signal AS-320",
                    action = function()
                        local veh = getPedOccupiedVehicle(localPlayer)
                        if not veh then uicore:addNotification("Error", "You need a vehicle for this")
                        else setElementData(veh, "sirenType", "fsvas320")
                        end
                    end
                },
                {
                    label = "Soundoff Signal",
                    action = function()
                        local veh = getPedOccupiedVehicle(localPlayer)
                        if not veh then uicore:addNotification("Error", "You need a vehicle for this")
                        else setElementData(veh, "sirenType", "soundoff")
                        end
                    end
                },
                {
                    label = "Soundoff Signal Rumbler",
                    action = function()
                        local veh = getPedOccupiedVehicle(localPlayer)
                        if not veh then uicore:addNotification("Error", "You need a vehicle for this")
                        else setElementData(veh, "sirenType", "rumbler")
                        end
                    end
                },
                {
                    label = "Hella RTK-7",
                    action = function()
                        local veh = getPedOccupiedVehicle(localPlayer)
                        if not veh then uicore:addNotification("Error", "You need a vehicle for this")
                        else setElementData(veh, "sirenType", "hella_rtk7")
                        end
                    end
                },
                {
                    label = "Italian ambulance",
                    action = function()
                        local veh = getPedOccupiedVehicle(localPlayer)
                        if not veh then uicore:addNotification("Error", "You need a vehicle for this")
                        else setElementData(veh, "sirenType", "italy")
                        end
                    end
                },
                {
                    label = "Eriston 150",
                    action = function()
                        local veh = getPedOccupiedVehicle(localPlayer)
                        if not veh then uicore:addNotification("Error", "You need a vehicle for this")
                        else setElementData(veh, "sirenType", "eriston")
                        end
                    end
                },
            }
        },
    }
})

-- BUSINESS
registerMenu({
    id = "business",
    title = "My Business",
    back = "main",
    items = {
        {
            label = "Under development :(",
            type = "action",
            action = function() end
        }
    }
})

-- COLLECTIBLES
registerMenu({
    id = "collectibles",
    title = "Collectibles",
    back = "main",
    items = {
        { label = "Stunts (Air)", type = "data", source = localPlayer, key = "collectibles_stuntsair" },
        { label = "Stunts (Land)", type = "data", source = localPlayer, key = "collectibles_stuntsland" },
        { label = "UFO spaceship parts", type = "data", source = localPlayer, key = "collectibles_ufoshipparts" }
    }
})

-- STATS
registerMenu({
    id = "stats",
    title = "Stats",
    back = "main",
    items = {
        {
            label = "Played Time",
            type = "data",
            source = localPlayer,
            key = "Játékidő",
        },
        {
            label = "Level",
            type = "data",
            source = localPlayer,
            key = "level",
        },
    }
})
