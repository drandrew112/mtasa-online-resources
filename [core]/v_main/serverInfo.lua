-- Identity of this server instance, read from server.json (not versioned, see
-- server.example.json): { "id": 1, "name": "Local DrAndrew112" }

local info = { id = 1, name = "Unnamed server" }

local function load()
    if not fileExists("server.json") then
        outputDebugString("[v_main] server.json missing - copy server.example.json and edit it (using id " .. info.id .. ")", 2)
        return
    end
    local file = fileOpen("server.json", true)
    if not file then return end
    local data = fromJSON(fileRead(file, fileGetSize(file)))
    fileClose(file)
    if type(data) ~= "table" then
        outputDebugString("[v_main] server.json is not valid JSON", 1)
        return
    end
    info.id = tonumber(data.id) or info.id
    info.name = type(data.name) == "string" and data.name or info.name
end
load()

function getServerInstanceId()
    return info.id
end

function getServerInstanceName()
    return info.name
end
