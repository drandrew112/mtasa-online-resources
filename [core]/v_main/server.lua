local mod_name = "MTA Online"
local map_name = "San Andreas Open World"

-- version.txt lives in this resource's folder; the "@" prefix keeps it private
-- so it is never transferred to clients.
function getModVersion()
    if not fileExists("@version.txt") then
        return "?"
    end

    local file = fileOpen("@version.txt", true)
    if not file then
        return "?"
    end

    local size = fileGetSize(file)
    local version = (size and size > 0) and fileRead(file, size) or ""
    fileClose(file)

    version = version:gsub("^%s*(.-)%s*$", "%1")
    if version == "" then
        return "?"
    end
    return version
end

function setCustomGamemodeName()
    local version = getModVersion()

    setGameType(mod_name .. " v" .. version)
    setMapName(map_name)
    outputConsole("Custom gamemode name set: " .. mod_name .. " v" .. version)
    outputConsole("Map name set: " .. getMapName())
end

addEventHandler("onResourceStart", resourceRoot, setCustomGamemodeName)
