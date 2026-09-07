local version = "0.1.0"

function setCustomGamemodeName()
    outputServerLog("FreeV Gamemode started")
    setGameType("MTA Online v" .. version)
end
addEventHandler("onResourceStart", resourceRoot, setCustomGamemodeName)