
function setCustomGamemodeName()
    outputServerLog("FreeV Gamemode started")
    setGameType("FreeV Open World")
end
addEventHandler("onResourceStart", resourceRoot, setCustomGamemodeName)