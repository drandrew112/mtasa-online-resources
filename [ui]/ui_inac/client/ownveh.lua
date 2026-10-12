if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Personal vehicles (v_ownveh) inside the interaction menu.
--
-- The "Request personal vehicle" item in the "vehicle" menu opens this submenu; its
-- onOpen asks the server for the player's vehicles and the list below is
-- rebuilt from the reply. Every row summons that vehicle through v_ownveh.

registerMenu({
    id    = "request_personal_vehicle",
    title = L("ui_inac.main.request_personal_vehicle"),
    back  = "vehicle",
    items = {
        { label = L("common.loading"), type = "action", action = function() end },
    },
})

local function setItems(items)
    local menu = MenuRegistry:get("request_personal_vehicle")
    if not menu then return end
    menu.items = items
    if MenuState.current == "request_personal_vehicle" then
        MenuState.selected = math.max(1, math.min(MenuState.selected, #items))
    end
end

addEvent("ui_inac:personalVehicleList", true)
addEventHandler("ui_inac:personalVehicleList", root, function(list)
    local items = {}
    for _, v in ipairs(list or {}) do
        local suffix = v.spawned and L("ui_inac.ownveh.out") or (v.isDestroyed and L("ui_inac.ownveh.destroyed") or "")
        local plate  = (v.plate and v.plate ~= "") and ("  -  " .. v.plate) or ""
        items[#items + 1] = {
            label  = L("ui_inac.ownveh.id", { model_name = v.modelName, id = v.id, suffix = suffix }),
            desc   = L("ui_inac.ownveh.model", { model = v.model, plate = plate }),
            type   = "action",
            action = function()
                triggerServerEvent("ui_inac:requestPersonalVehicle", localPlayer, v.id)
            end,
        }
    end
    if #items == 0 then
        items[1] = { label = L("ui_inac.ownveh.no_personal_vehicles"), type = "action", action = function() end }
    end
    setItems(items)
end)

addEvent("ui_inac:notify", true)
addEventHandler("ui_inac:notify", root, function(title, text)
    uicore:addNotification(tostring(title), tostring(text))
end)
