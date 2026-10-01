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
        outputChatBox("Nincs jogosultságod az ELS szerkesztőhöz.", player, 255, 80, 80)
        return
    end

    local veh = getPedOccupiedVehicle(player)
    if not isSirenVehicle(veh) or getVehicleController(veh) ~= player then
        outputChatBox("Ülj be sofőrként egy ELS-es járműbe a szerkesztéshez.", player, 255, 200, 0)
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
        and ("%d light point(s) saved for %s."):format(#saved.points, getVehicleNameFromModel(model))
        or ("Layout removed for %s."):format(getVehicleNameFromModel(model))
    if not ok then
        message = "Could not write lights.json!"
    end
    triggerClientEvent(client, "els:editorSaved", resourceRoot, ok, message)
end)
