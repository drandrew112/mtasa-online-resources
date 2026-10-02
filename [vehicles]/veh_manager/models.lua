-- veh_manager :: vehicle model display names
--
-- models.json holds the override table: { "<model id>": "Display name", ... }.
-- When a model id has an entry there it wins over GTA's built-in
-- getVehicleNameFromModel - use it for modloader-replaced or otherwise renamed
-- vehicles. Edit the JSON and restart the resource to apply.

local MODELS_FILE = "models.json"

local modelNames = {}

local function loadModelNames()
    modelNames = {}
    if not fileExists(MODELS_FILE) then
        outputDebugString("[veh_manager] " .. MODELS_FILE .. " not found", 2)
        return
    end
    local f = fileOpen(MODELS_FILE, true)
    if not f then return end
    local raw = fileRead(f, fileGetSize(f))
    fileClose(f)

    local data = fromJSON(raw)
    if type(data) ~= "table" then
        outputDebugString("[veh_manager] " .. MODELS_FILE .. " is not valid JSON", 1)
        return
    end
    -- JSON object keys are strings; index by numeric model id.
    local count = 0
    for k, name in pairs(data) do
        local id = tonumber(k)
        if id and type(name) == "string" and name ~= "" then
            modelNames[id] = name
            count = count + 1
        end
    end
    outputDebugString("[veh_manager] loaded " .. count .. " model name(s)")
end
addEventHandler("onResourceStart", resourceRoot, loadModelNames)

-- Human-readable name for a vehicle model id. A models.json override wins;
-- otherwise GTA's built-in name is used ("Infernus", "Sparrow", ...).
-- -> string | false
function getModelName(model)
    model = tonumber(model)
    if not model then return false end
    return modelNames[model] or getVehicleNameFromModel(model) or false
end
