if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)

function registerMenus()
    -- MAIN MENU
    registerMenu({
        id = "main",
        title = L("ui_inac.main.interaction_menu"),
        back = nil,
        items = {
            {
                label = L("ui_inac.main.fast_travel"),
                type = "select",
                value = 1,
                options = {
                    {
                        label = L("ui_inac.main.ls_airport"),
                        action = function()
                            if getPedOccupiedVehicle(localPlayer) then return uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_can_t_use_fast_travel")) end
                            setElementPosition(localPlayer, 1683.09, -2286.06, 13.5)
                        end
                    },
                    {
                        label = L("ui_inac.main.lv_airport"),
                        action = function()
                            if getPedOccupiedVehicle(localPlayer) then return uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_can_t_use_fast_travel")) end
                            setElementPosition(localPlayer, 1693.51, 1447.89, 10.76)
                        end
                    },
                    {
                        label = L("ui_inac.main.sf_airport"),
                        action = function()
                            if getPedOccupiedVehicle(localPlayer) then return uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_can_t_use_fast_travel")) end
                            setElementPosition(localPlayer, -1409.88, -304.44, 14.14)
                        end
                    }
                }
            },
            {
                label = L("ui_inac.main.vehicle"),
                type = "submenu",
                target = "vehicle"
            },
            {
                label = L("ui_inac.main.collectibles"),
                type = "submenu",
                target = "collectibles"
            },
            {
                label = L("ui_inac.main.stats"),
                type = "submenu",
                target = "stats"
            }
        }
    })

    -- VEHCILE
    registerMenu({
        id = "vehicle",
        title = L("ui_inac.main.vehicle"),
        back = "main",
        items = {
            {
                label = L("ui_inac.main.spawn_vehicle"),
                type = "submenu",
                target = "spawn_vehicle"
            },
            {
                label = L("ui_inac.main.request_personal_vehicle"),
                type = "submenu",
                target = "request_personal_vehicle",
                desc = L("ui_inac.main.summon_one_of_your_personal_vehicles"),
                onOpen = function()
                    triggerServerEvent("ui_inac:requestPersonalVehicleList", localPlayer)
                end
            },
            {
                label = L("ui_inac.main.restore_personal_vehicle"),
                type = "action",
                desc = L("ui_inac.main.store_personal_vehicle_you_currently_have"),
                action = function()
                    triggerServerEvent("ui_inac:storePersonalVehicle", localPlayer)
                end
            },
            {
                label = L("ui_inac.main.repair_vehicle"),
                type = "action",
                action = function()
                    local veh = getPedOccupiedVehicle(localPlayer)
                    if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                    else fixVehicle(veh)
                    end
                end
            },
            {
                label = L("ui_inac.main.siren_type"),
                type = "select",
                value = 1,
                options = {
                    {
                        label = L("ui_inac.main.armcom_dal_257"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "dal")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.code3_z3"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "code3_z3")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.eriston_150"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "eriston")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.federal_signal_as_320"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "fsvas320")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.hella_rtk_7"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "hella_rtk7")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.italian_ambulance"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "italy")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.premier_hazard_6009"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "premier_hazard_6009")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.premier_hazard_7109"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "premier_hazard_7109")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.soundoff_signal"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "soundoff")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.soundoff_signal_rumbler"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "rumbler")
                            end
                        end
                    },
                    {
                        label = L("ui_inac.main.standby_rsg_mcs32"),
                        action = function()
                            local veh = getPedOccupiedVehicle(localPlayer)
                            if not veh then uicore:addNotification(L("ui_inac.main.error"), L("ui_inac.main.you_need_vehicle_for_this"))
                            else setElementData(veh, "sirenType", "standby_rsg_mcs32")
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
        title = L("ui_inac.main.my_business"),
        back = "main",
        items = {
            {
                label = L("ui_inac.main.under_development"),
                type = "action",
                action = function() end
            }
        }
    })

    -- COLLECTIBLES
    registerMenu({
        id = "collectibles",
        title = L("ui_inac.main.collectibles"),
        back = "main",
        items = {
            { label = L("ui_inac.main.stunts_air"), type = "data", source = localPlayer, key = "collectibles_stuntsair" },
            { label = L("ui_inac.main.stunts_land"), type = "data", source = localPlayer, key = "collectibles_stuntsland" },
            { label = L("ui_inac.main.ufo_spaceship_parts"), type = "data", source = localPlayer, key = "collectibles_ufoshipparts" }
        }
    })

    -- STATS
    registerMenu({
        id = "stats",
        title = L("ui_inac.main.stats"),
        back = "main",
        items = {
            {
                label = L("ui_inac.main.played_time"),
                type = "data",
                source = localPlayer,
                key = "Játékidő",
            },
            {
                label = L("common.level"),
                type = "data",
                source = localPlayer,
                key = "level",
            },
        }
    })

    registerOwnvehMenu()

    exports.v_accounts:resourceReady()
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, function()
    registerMenus()
end)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then
        registerMenus()
    end
end)
