-- v_ownveh :: /vehspawn (admin) - collect spawn points
--
-- Sit in a vehicle where a spawn point should be and type /vehspawn. The
-- vehicle's position + rotation is appended to Vehicles.config.spawnpointFile
-- as a ready-to-paste "{x, y, z, rx, ry, rz}," line. Move those lines into the
-- correct list in spawnpoints.lua by hand.

local function adminLevel(player)
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return 0 end
    return tonumber(getAccountData(account, "admin_level")) or 0
end

addCommandHandler("vehspawn", function(player)
    if adminLevel(player) < Vehicles.config.spawnpointAdminLevel then
        outputChatBox("v_ownveh: you don't have permission for /vehspawn.", player, 255, 90, 90)
        return
    end

    local veh = getPedOccupiedVehicle(player)
    if not veh then
        outputChatBox("v_ownveh: sit in a vehicle first.", player, 255, 90, 90)
        return
    end

    local x, y, z    = getElementPosition(veh)
    local rx, ry, rz = getElementRotation(veh)
    local category   = OwnVeh.categoryOf(getElementModel(veh))
    local line = string.format("{%.3f, %.3f, %.3f, %.3f, %.3f, %.3f}, -- %s",
        x, y, z, rx, ry, rz, category)

    local path = Vehicles.config.spawnpointFile
    local file = fileExists(path) and fileOpen(path) or fileCreate(path)
    if not file then
        outputChatBox("v_ownveh: could not write " .. path, player, 255, 90, 90)
        return
    end
    fileSetPos(file, fileGetSize(file))
    fileWrite(file, line .. "\n")
    fileClose(file)

    outputChatBox("v_ownveh [" .. category .. "] " .. line, player, 120, 220, 120)
    outputServerLog("[v_ownveh] /vehspawn by " .. getPlayerName(player) .. " -> " .. line)
end)
