-- Server side player count source for the Discord rich presence

local function broadcast(quitting)
    local count = getPlayerCount()
    if quitting then count = math.max(0, count - 1) end
    triggerClientEvent(root, "discord:serverInfo", resourceRoot, count, getMaxPlayers())
end

addEvent("discord:requestServerInfo", true)
addEventHandler("discord:requestServerInfo", resourceRoot, function()
    if not client then return end
    triggerClientEvent(client, "discord:serverInfo", resourceRoot, getPlayerCount(), getMaxPlayers())
end)

addEventHandler("onPlayerJoin", root, function() setTimer(broadcast, 500, 1, false) end)
-- onPlayerQuit fires before the player is removed from the count
addEventHandler("onPlayerQuit", root, function() broadcast(true) end)
