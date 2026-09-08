local version = "0.4.0 Beta"

function setCustomGamemodeName()
    local serverIP = getServerConfigSetting("serverip")
    local namePrefix = "MTA Online"
    setGameType(namePrefix .. " v" .. version)
end
addEventHandler("onResourceStart", resourceRoot, setCustomGamemodeName)