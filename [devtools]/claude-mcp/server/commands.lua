-- In-game / console commands:
--   /mcp            status
--   /mcp probe      make yourself the probe client
--   /mcp clear      destroy every workspace entity
--   /mcp overlay    toggle the entity overlay

local function say(player, text)
    if isElement(player) and getElementType(player) == "player" then
        outputChatBox("#7aa2ff[MCP] #ffffff" .. text, player, 255, 255, 255, true)
    else
        outputServerLog("[claude-mcp] " .. text)
    end
end

addCommandHandler("mcp", function(player, _, sub)
    sub = sub or "status"
    if sub == "probe" then
        if getElementType(player) ~= "player" then return say(player, "Only players can be the probe.") end
        if not Probe.clients[player] then return say(player, "Your client part of claude-mcp is not ready yet.") end
        Probe.preferred = player
        say(player, "You are the probe client now.")
        Overlay.push()
    elseif sub == "clear" then
        local n = 0
        for _, name in ipairs(Util.copy(Registry.order)) do
            local ws = Registry.workspaces[name]
            if ws then n = n + #Registry.clearWorkspace(ws, false) end
        end
        Overlay.push()
        say(player, n .. " workspace entities destroyed.")
    elseif sub == "overlay" then
        Overlay.state.enabled = not Overlay.state.enabled
        Overlay.push()
        say(player, "Overlay " .. (Overlay.state.enabled and "on" or "off") .. ".")
    else
        local p = Probe.get()
        say(player, string.format("instance %s | probe: %s | workspaces: %d | entities: %d | requests: %d (%d errors)",
            Api.instance(), p and getPlayerName(p) or "none", #Registry.order, Registry.count(), Api.stats.requests, Api.stats.errors))
    end
end)
