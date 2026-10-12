if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- ============================================================
--  v_admin / server/vehicle.lua
--  Vehicle commands: fix, flip, getout.
--  Without an ID it affects your own vehicle, with an ID the target's.
--  adminFixVeh / adminFlipVeh / adminGetOut are shared with the
--  admin panel (target = the player whose vehicle it is).
-- ============================================================

--- Returns: vehicle, target(player)  or  false + error alert.
local function getTargetVehicle(player, idArg)
    if idArg then
        local target = getPlayerFromId(idArg)
        if not target then
            adminAlert(player, L.msg("v_admin.core.player_not_found_valid_id_required"), 255, 90, 90)
            return false
        end
        return getPedOccupiedVehicle(target), target
    end
    return getPedOccupiedVehicle(player), player
end

-- ------------------------------------------------------------
--  /fixveh [ID]
-- ------------------------------------------------------------
function adminFixVeh(player, target)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end
    if not isElement(target) then return end

    local veh = getPedOccupiedVehicle(target)
    if not veh then
        return adminAlert(player, L.msg("v_admin.vehicle.no_vehicle"), 255, 90, 90)
    end

    fixVehicle(veh)

    if target and target ~= player then
        adminAlert(target, L.msg("v_admin.vehicle.repaired_your_vehicle", { player = getPlayerName(player) }))
        adminAlert(player, L.msg("v_admin.vehicle.you_repaired_s_vehicle", { player = getPlayerName(target) }))
    else
        adminAlert(player, L.msg("v_admin.vehicle.vehicle_repaired"))
    end
end

addCommandHandler("fixveh", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end
    local veh, target = getTargetVehicle(player, idArg)
    if veh == false then return end
    adminFixVeh(player, target)
end)

-- ------------------------------------------------------------
--  /flipveh [ID]
-- ------------------------------------------------------------
function adminFlipVeh(player, target)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end
    if not isElement(target) then return end

    local veh = getPedOccupiedVehicle(target)
    if not veh then
        return adminAlert(player, L.msg("v_admin.vehicle.no_vehicle"), 255, 90, 90)
    end

    local rx, _, rz = getElementRotation(veh)
    -- if it is upside down, rotate 180 degrees, otherwise keep the heading
    setElementRotation(veh, 0, 0, (rx > 90 and rx < 270) and (rz + 180) or rz)

    if target and target ~= player then
        adminAlert(target, L.msg("v_admin.vehicle.flipped_your_vehicle_back", { player = getPlayerName(player) }))
        adminAlert(player, L.msg("v_admin.vehicle.you_flipped_s_vehicle_back", { player = getPlayerName(target) }))
    else
        adminAlert(player, L.msg("v_admin.vehicle.vehicle_flipped_back"))
    end
end

addCommandHandler("flipveh", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end
    local veh, target = getTargetVehicle(player, idArg)
    if veh == false then return end
    adminFlipVeh(player, target)
end)

-- ------------------------------------------------------------
--  /getout <ID>  – pull the given player out of their vehicle
-- ------------------------------------------------------------
function adminGetOut(player, target)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end
    if not isElement(target) then return end

    local veh = getPedOccupiedVehicle(target)
    if not veh then
        return adminAlert(player, L.msg("v_admin.vehicle.is_not_in_vehicle", { player = getPlayerName(target) }), 255, 90, 90)
    end

    removePedFromVehicle(target)

    if target ~= player then
        adminAlert(target, L.msg("v_admin.vehicle.pulled_you_out_of_your_vehicle", { player = getPlayerName(player) }))
        adminAlert(player, L.msg("v_admin.vehicle.you_pulled_out_of_their_vehicle", { player = getPlayerName(target) }))
    else
        adminAlert(player, L.msg("v_admin.vehicle.you_left_your_vehicle"))
    end
end

addCommandHandler("getout", function(player, cmd, idArg)
    if not hasAdminLevel(player, ADMIN.perms.vehicle) then
        return denyAccess(player, ADMIN.perms.vehicle)
    end
    local target = resolveTarget(player, idArg)
    if target then adminGetOut(player, target) end
end)
