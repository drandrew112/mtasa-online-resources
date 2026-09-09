local mod_name = "MTA Online"
local version = "0.6.2 Beta"

function setCustomGamemodeName()
    local serverIP = getServerConfigSetting("serverip")
    setGameType(mod_name .. " v" .. version)
end
addEventHandler("onResourceStart", resourceRoot, setCustomGamemodeName)