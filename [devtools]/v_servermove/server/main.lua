-- Server list game mode while the notice runs; re-applied when another resource
-- starts (v_main sets its own), the previous value comes back on stop
local GAME_TYPE = "Server moved!"
local previousGameType

addEventHandler("onResourceStart", root, function(res)
    if res == resource then previousGameType = getGameType() end
    -- short delay so the other resource's own start handler has already run
    setTimer(function() setGameType(GAME_TYPE) end, 100, 1)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    setGameType(previousGameType or false)
end)

-- Redirect is server-side only (redirectPlayer); the client asks for it
addEvent("servermove:connect", true)
addEventHandler("servermove:connect", resourceRoot, function()
    if not client then return end
    redirectPlayer(client, CONFIG.host, CONFIG.port, CONFIG.password)
end)
