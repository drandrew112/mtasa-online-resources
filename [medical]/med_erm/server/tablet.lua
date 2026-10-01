-- Requests coming from the unit tablet (client).

local function reply(player, ok, err)
    if not ok and err then
        triggerClientEvent(player, "erm:notify", resourceRoot, "EMS Tablet", err)
    end
end

local function handle(name, fn)
    addEvent(name, true)
    addEventHandler(name, resourceRoot, function(...)
        if not isElement(client) then return end
        reply(client, fn(client, ...))
    end)
end

handle("erm:signIn", function(player, unitType, candidates, unitNumber)
    local u, err = Units.signIn(player, unitType, candidates, unitNumber)
    return u and true, err
end)

handle("erm:signOut", function(player)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    Units.signOut(u, "Shift ended by " .. getPlayerName(player) .. ".")
    return true
end)

handle("erm:setStatus", function(player, status)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    return Units.setStatus(u, status)
end)

handle("erm:caseAction", function(player, action)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    return Units.caseAction(u, action)
end)

handle("erm:sendMessage", function(player, text)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    local id, err = Chat.post("unit", u.id, u.callsign .. " (" .. getPlayerName(player) .. ")", false, text)
    return id and true, err
end)

addEventHandler("onPlayerQuit", root, function()
    Units.removeMember(source, "Disconnected.")
end)
