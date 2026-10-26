if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/spectate.lua
--  Spectate (Online players page, /spec <ID>, /specoff): the admin's camera
--  follows the target (interior too); the admin's own ped stays frozen where
--  it was. Ends on /specoff, the panel button, or when either one leaves.
--  The admin's client gets "v_admin:spectating" (target name | false) for the
--  HUD line and the panel's "Stop spectating" button.
-- ============================================================

local spectating = {}   -- [admin] = target

local function stop(admin, silent)
    local target = spectating[admin]
    spectating[admin] = nil
    if not isElement(admin) then return end
    setCameraTarget(admin, admin)
    setCameraInterior(admin, getElementInterior(admin))
    setElementFrozen(admin, false)
    triggerClientEvent(admin, "v_admin:spectating", resourceRoot, false)
    if not silent then
        adminAlert(admin, L.msg("v_admin.spectate.stopped"))
    end
    return target
end

--- Start spectating `target` (player element). admin = player element or web actor.
function adminSpectate(admin, target)
    if not hasAdminLevel(admin, ADMIN.perms.spectate) then return denyAccess(admin, ADMIN.perms.spectate) end
    local player = actorPlayer(admin)
    if not player then return adminAlert(admin, L.msg("v_admin.page.need_ingame"), 255, 90, 90) end
    if not isElement(target) or target == player then
        return adminAlert(admin, L.msg("v_admin.spectate.cant_spectate"), 255, 90, 90)
    end
    if spectating[player] then stop(player, true) end
    spectating[player] = target
    setElementFrozen(player, true)
    setCameraInterior(player, getElementInterior(target))
    setCameraTarget(player, target)
    local name = getPlayerName(target):gsub("#%x%x%x%x%x%x", "")
    triggerClientEvent(player, "v_admin:spectating", resourceRoot, name)
    adminAlert(admin, L.msg("v_admin.spectate.started", { name = name }))
    adminLog(admin, "started spectating " .. name, target)
end

function adminSpectateStop(admin)
    local player = actorPlayer(admin)
    if player and spectating[player] then stop(player) end
end

addCommandHandler("spec", function(player, _, id)
    if not hasAdminLevel(player, ADMIN.perms.spectate) then return denyAccess(player, ADMIN.perms.spectate) end
    local target = resolveTarget(player, id)
    if target then adminSpectate(player, target) end
end)

addCommandHandler("specoff", function(player)
    if spectating[player] then stop(player) end
end)

-- follow the target into interiors; the target left -> back to the admin
setTimer(function()
    for admin, target in pairs(spectating) do
        if not isElement(admin) then
            spectating[admin] = nil
        elseif not isElement(target) then
            stop(admin)
        else
            setCameraInterior(admin, getElementInterior(target))
        end
    end
end, 1000, 0)

addEventHandler("onPlayerQuit", root, function()
    spectating[source] = nil
    for admin, target in pairs(spectating) do
        if target == source then stop(admin) end
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for admin in pairs(spectating) do stop(admin, true) end
end)

-- chat command database (v_chat)
CMD.register("spec", "<id>", ADMIN.perms.spectate, "Spectate a player")
CMD.register("specoff", "", ADMIN.perms.spectate, "Stop spectating")
