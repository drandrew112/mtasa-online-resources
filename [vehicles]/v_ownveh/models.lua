-- v_ownveh :: custom vehicle model names
--
-- Override table for getModelName(model) (server.lua export). When a model id
-- has an entry here it wins over GTA's built-in getVehicleNameFromModel - use
-- it for modloader-replaced or otherwise renamed vehicles.
--
--   Vehicles.modelNames[<model id>] = "Display name"

Vehicles = Vehicles or {}

Vehicles.modelNames = {
    -- [596] = "LSPD Cruiser",
    -- [416] = "Rescue Ambulance",
}

-- Custom name for a model id, or nil when there is no override.
function Vehicles.customModelName(model)
    model = tonumber(model)
    if not model then return nil end
    local name = Vehicles.modelNames[model]
    if type(name) == "string" and name ~= "" then return name end
    return nil
end
