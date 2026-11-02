if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Requests coming from the unit tablet (client).

local function reply(player, ok, err)
    if not ok and err then
        triggerClientEvent(player, "erm:notify", resourceRoot, L.msg("med_erm.case.ems_tablet"), err)
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
    return Units.signIn(player, unitType, candidates, unitNumber, function(u, err)
        if isElement(player) then reply(player, u and true, err) end
    end)
end)

handle("erm:signOut", function(player)
    local u = Units.ofPlayer(player)
    if not u then return false, L.msg("med_erm.tablet.you_are_not_signed_in") end
    Units.signOut(u, L.msg("med_erm.tablet.shift_ended_by", { player = getPlayerName(player) }))
    return true
end)

-- Response buttons of the Active Case page. On Scene is set automatically at
-- the scene and the handover is started by the hospital (med_hospitals).
handle("erm:caseAction", function(player, action)
    local u = Units.ofPlayer(player)
    if not u then return false, L.msg("med_erm.tablet.you_are_not_signed_in") end
    if action ~= "start" and action ~= "stop" then return false, L.msg("med_erm.tablet.unknown_action") end
    return Units.caseAction(u, action)
end)

handle("erm:leaveCase", function(player)
    local u = Units.ofPlayer(player)
    if not u then return false, L.msg("med_erm.tablet.you_are_not_signed_in") end
    if not u.task then return false, L.msg("med_erm.tablet.no_active_case") end
    return Tasks.leave(u.task, u.id)
end)

-- Backup: the nearest free unit of the chosen type joins the case (server/backup.lua).
handle("erm:requestBackup", function(player, optionId)
    local u = Units.ofPlayer(player)
    if not u then return false, L.msg("med_erm.tablet.you_are_not_signed_in") end
    return Backup.request(u, optionId)
end)

-- Closing a case from the tablet (false call, broken scene, ...) needs a reason.
handle("erm:closeCase", function(player, reason)
    local u = Units.ofPlayer(player)
    if not u then return false, L.msg("med_erm.tablet.you_are_not_signed_in") end
    if not u.task then return false, L.msg("med_erm.tablet.no_active_case") end
    reason = cleanText(reason, 90)
    if #reason < 3 then return false, L.msg("med_erm.case.give_reason_for_closing_case") end
    return Tasks.close(u.task, u.callsign .. ": " .. reason)
end)

-- Request agency: the police (police_system call linked to the case, server/agency.lua)
handle("erm:requestAgency", function(player, agency, reasonId, note)
    local u = Units.ofPlayer(player)
    if not u then return false, L.msg("med_erm.tablet.you_are_not_signed_in") end
    return Agency.request(u, agency, reasonId, note)
end)

-- channel: "dispatch" (unit <-> dispatchers), "case" (every unit on the task + dispatch) or "agency" (the case's
-- units + the officers of the linked police call)
handle("erm:sendMessage", function(player, text, channel)
    local u = Units.ofPlayer(player)
    if not u then return false, L.msg("med_erm.tablet.you_are_not_signed_in") end
    if channel == "agency" then return Agency.post(u, player, text) end
    local from = u.callsign .. " (" .. getPlayerName(player) .. ")"
    local id, err
    if channel == "case" then
        if not u.task then return false, L.msg("med_erm.tablet.no_active_case") end
        id, err = Chat.post("task", u.task, from, false, text, u.id)
    else
        id, err = Chat.post("unit", u.id, from, false, text, u.id)
    end
    return id and true, err
end)

addEventHandler("onPlayerQuit", root, function()
    Units.removeMember(source, "Disconnected.")
end)

-- Losing the medsys medic role (e.g. going off duty in work_ems) leaves the unit
addEvent("onPlayerMedicChange")
addEventHandler("onPlayerMedicChange", root, function(enabled)
    if not enabled then Units.removeMember(source, L.msg("med_erm.tablet.you_are_no_longer_on_duty")) end
end)

-- The case text follows the player's language: resend it when they switch (v_locals)
addEvent("onPlayerLanguageChange")
addEventHandler("onPlayerLanguageChange", root, function()
    local u = Units.ofPlayer(source)
    if u and u.task then Units.sync(u) end
end)
