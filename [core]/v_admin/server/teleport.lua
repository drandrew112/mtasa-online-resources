-- ============================================================
--  v_admin / server/teleport.lua
--  Admin teleport commands.
-- ============================================================

-- ------------------------------------------------------------
--  /goto <ID>  – teleport to the given player
-- ------------------------------------------------------------
addCommandHandler("goto", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.teleport) then
        return denyAccess(player, ADMIN.perms.teleport)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    if target == player then return end

    local x, y, z = getElementPosition(target)
    local int, dim = getElementInterior(target), getElementDimension(target)

    setElementPosition(player, x + 1.5, y, z)
    setElementInterior(player, int)
    setElementDimension(player, dim)

    adminAlert(target, "#FFFF00" .. getPlayerName(player) .. " #FFFFFFteleported to you.")
    adminAlert(player, "#FFFFFFYou teleported to #FFFF00" .. getPlayerName(target))
end)

-- ------------------------------------------------------------
--  /gethere <ID>  – bring the given player to you
-- ------------------------------------------------------------
addCommandHandler("gethere", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.teleport) then
        return denyAccess(player, ADMIN.perms.teleport)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end
    if target == player then return end

    local x, y, z = getElementPosition(player)
    local int, dim = getElementInterior(player), getElementDimension(player)

    local veh = getPedOccupiedVehicle(target)
    if veh then
        setElementVelocity(veh, 0, 0, 0)
        setElementPosition(veh, x, y, z + 2.5)
        setElementInterior(veh, int)
        setElementDimension(veh, dim)
    else
        setElementPosition(target, x, y, z + 2)
    end
    setElementInterior(target, int)
    setElementDimension(target, dim)

    adminAlert(target, "#FFFF00" .. getPlayerName(player) .. " #FFFFFFteleported you to them.")
    adminAlert(player, "#FFFFFFYou brought #FFFF00" .. getPlayerName(target) .. " #FFFFFFto you.")
end)
