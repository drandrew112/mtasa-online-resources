-- veh_manager :: client copy of the vehicle model display names (override table comes from the server)

local modelNames = {}

addEvent("veh_manager:names", true)
addEventHandler("veh_manager:names", resourceRoot, function(names)
    modelNames = {}
    for id, name in pairs(names or {}) do modelNames[tonumber(id)] = name end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("veh_manager:requestNames", resourceRoot)
end)

-- -> string | false
function getModelName(model)
    model = tonumber(model)
    if not model then return false end
    return modelNames[model] or getVehicleNameFromModel(model) or false
end
