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

-- Response buttons of the Active Case page. On Scene is set automatically at
-- the scene and the handover is started by the hospital (med_hospitals).
handle("erm:caseAction", function(player, action)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    if action ~= "start" and action ~= "stop" then return false, "Unknown action" end
    return Units.caseAction(u, action)
end)

handle("erm:leaveCase", function(player)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    if not u.task then return false, "No active case." end
    return Tasks.leave(u.task, u.id)
end)

-- Closing a case from the tablet (false call, broken scene, ...) needs a reason.
handle("erm:closeCase", function(player, reason)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    if not u.task then return false, "No active case." end
    reason = cleanText(reason, 90)
    if #reason < 3 then return false, "Give a reason for closing the case." end
    return Tasks.close(u.task, u.callsign .. ": " .. reason)
end)

-- channel: "dispatch" (unit <-> dispatchers) or "case" (every unit on the task + dispatch)
handle("erm:sendMessage", function(player, text, channel)
    local u = Units.ofPlayer(player)
    if not u then return false, "You are not signed in." end
    local from = u.callsign .. " (" .. getPlayerName(player) .. ")"
    local id, err
    if channel == "case" then
        if not u.task then return false, "No active case." end
        id, err = Chat.post("task", u.task, from, false, text, u.id)
    else
        id, err = Chat.post("unit", u.id, from, false, text, u.id)
    end
    return id and true, err
end)

addEventHandler("onPlayerQuit", root, function()
    Units.removeMember(source, "Disconnected.")
end)
