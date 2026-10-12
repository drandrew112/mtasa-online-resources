if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- /elseditor: fénypont szerkesztő az épp használt ELS jármű modelljéhez.
-- A szerkesztés a kliensen történik; ide csak a megnyitás és a mentés fut be.

local function adminLevel(player)
    local res = getResourceFromName("v_mysql")
    if res and getResourceState(res) == "running" then
        return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    end
    return tonumber(getElementData(player, "admin_level")) or 0
end

local function isEditor(player)
    return adminLevel(player) >= ELS_ADMIN_LEVEL
end

addCommandHandler("elseditor", function(player)
    if not isEditor(player) then
        outputChatBox(L.msg("v_els.editor.you_do_not_have_access_to"), player, 255, 80, 80)
        return
    end

    local veh = getPedOccupiedVehicle(player)
    if not isSirenVehicle(veh) or getVehicleController(veh) ~= player then
        outputChatBox(L.msg("v_els.editor.get_in_els_vehicle_as_driver"), player, 255, 200, 0)
        return
    end

    local model = getElementModel(veh)
    triggerClientEvent(player, "els:editorToggle", resourceRoot, veh, model, Layouts.get(model) or false)
end)

addEvent("els:editorSave", true)
addEventHandler("els:editorSave", resourceRoot, function(model, layout)
    if not isEditor(client) then return end
    if type(model) ~= "number" or not sirenVehicles[model] then return end

    local ok = Layouts.set(model, layout)
    local saved = Layouts.get(model)
    local message = saved
        and L.msg("v_els.editor.light_point_s_saved_for", { points = #saved.points, model = getVehicleNameFromModel(model) })
        or L.msg("v_els.editor.layout_removed_for", { model = getVehicleNameFromModel(model) })
    if not ok then
        message = L.msg("v_els.editor.could_not_write_lights_json")
    end
    triggerClientEvent(client, "els:editorSaved", resourceRoot, ok, message)
end)
