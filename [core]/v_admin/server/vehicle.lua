-- ============================================================
--  v_admin / server/vehicle.lua
--  Vehicle commands: fix, flip, getout.
--  Without an ID it affects your own vehicle, with an ID the target's.
-- ============================================================

--- Returns: vehicle, target(player)  or  false + error alert.
local function getTargetVehicle(player, idArg)
    if idArg then
        local target = getPlayerFromId(idArg)
        if not target then
            adminAlert(player, "Player not found (valid ID required).", 255, 90, 90)
            return false
        end
        return getPedOccupiedVehicle(target), target
    end
    return getPedOccupiedVehicle(player), player
end

-- ------------------------------------------------------------
--  /fixveh [ID]
-- ------------------------------------------------------------
addCommandHandler("fixveh", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end

    local veh, target = getTargetVehicle(player, idArg)
    if veh == false then return end
    if not veh then
        return adminAlert(player, "No vehicle.", 255, 90, 90)
    end

    fixVehicle(veh)

    if target and target ~= player then
        adminAlert(target, "#FFFF00" .. getPlayerName(player) .. " #FFFFFFrepaired your vehicle.")
        adminAlert(player, "#FFFFFFYou repaired #FFFF00" .. getPlayerName(target) .. "#FFFFFF's vehicle.")
    else
        adminAlert(player, "#FFFFFFVehicle repaired.")
    end
end)

-- ------------------------------------------------------------
--  /flipveh [ID]
-- ------------------------------------------------------------
addCommandHandler("flipveh", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end

    local veh, target = getTargetVehicle(player, idArg)
    if veh == false then return end
    if not veh then
        return adminAlert(player, "No vehicle.", 255, 90, 90)
    end

    local rx, _, rz = getElementRotation(veh)
    -- if it is upside down, rotate 180 degrees, otherwise keep the heading
    setElementRotation(veh, 0, 0, (rx > 90 and rx < 270) and (rz + 180) or rz)

    if target and target ~= player then
        adminAlert(target, "#FFFF00" .. getPlayerName(player) .. " #FFFFFFflipped your vehicle back.")
        adminAlert(player, "#FFFFFFYou flipped #FFFF00" .. getPlayerName(target) .. "#FFFFFF's vehicle back.")
    else
        adminAlert(player, "#FFFFFFVehicle flipped back.")
    end
end)

-- ------------------------------------------------------------
--  /getout <ID>  – pull the given player out of their vehicle
-- ------------------------------------------------------------
addCommandHandler("getout", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end

    local target = resolveTarget(player, idArg)
    if not target then return end

    local veh = getPedOccupiedVehicle(target)
    if not veh then
        return adminAlert(player, "#FFFF00" .. getPlayerName(target) .. " #FFFFFFis not in a vehicle.", 255, 90, 90)
    end

    removePedFromVehicle(target)

    if target ~= player then
        adminAlert(target, "#FFFF00" .. getPlayerName(player) .. " #FFFFFFpulled you out of your vehicle.")
        adminAlert(player, "#FFFFFFYou pulled #FFFF00" .. getPlayerName(target) .. " #FFFFFFout of their vehicle.")
    else
        adminAlert(player, "#FFFFFFYou left your vehicle.")
    end
end)
