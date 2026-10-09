addEvent("pausemenu_joinArenawar", true)
addEventHandler("pausemenu_joinArenawar", root, function()
    exports["v_arenawar"]:arenawarJoin(source)
end)

-- STATS tab: v_stats definitions + the player's values.
addEvent("uipause:requestStats", true)
addEventHandler("uipause:requestStats", root, function()
    local player = client
    if not isElement(player) then return end
    local res = getResourceFromName("v_stats")
    if not res or getResourceState(res) ~= "running" then
        triggerClientEvent(player, "uipause:statsData", player, false)
        return
    end
    local ok, defs, values = pcall(function()
        return exports.v_stats:getStatDefinitions(), exports.v_stats:getStats(player)
    end)
    triggerClientEvent(player, "uipause:statsData", player, ok and defs or false, ok and values or false)
end)

-- Leave Server: the client cannot run the built-in "disconnect" command from
-- Lua, so the server disconnects the player.
addEvent("uipause:leaveServer", true)
addEventHandler("uipause:leaveServer", root, function()
    if isElement(client) then
        kickPlayer(client, "You left the server.")
    end
end)
