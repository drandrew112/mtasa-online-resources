local version = "0.4.0 Beta"

function setCustomGamemodeName()
    local serverIP = getServerConfigSetting("serverip")
    local namePrefix = "MTA Online"

    -- Ellenőrizzük, hogy localhost-e (auto, 127.0.0.1 vagy üres)
    if serverIP == "auto" or serverIP == "127.0.0.1" or serverIP == "" then
        namePrefix = "MTA Online DEV"
        outputServerLog("FreeV Gamemode started [DEVELOPMENT MODE]")
    else
        outputServerLog("FreeV Gamemode started [PRODUCTION MODE]")
    end

    setGameType(namePrefix .. " v" .. version)
end
addEventHandler("onResourceStart", resourceRoot, setCustomGamemodeName)