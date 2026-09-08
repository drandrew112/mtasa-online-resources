-- v_ownveh :: admin commands
--
--   /vehspawn       collect the spawn point under the admin's vehicle
--   /showvehspawns  toggle checkpoint markers on every configured spawn point
--
-- Both need admin_level >= Vehicles.config.spawnpointAdminLevel.
--
-- The markers are "checkpoint" markers made visible only to the admin who ran
-- the command:
--   * newPointMarkers[player]  - one per /vehspawn, kept for the session
--   * shownMarkers[player]     - the /showvehspawns set, toggled on/off

local newPointMarkers = {}
local shownMarkers    = {}

local function adminLevel(player)
    local account = getPlayerAccount(player)
    if not account or isGuestAccount(account) then return 0 end
    return tonumber(getAccountData(account, "admin_level")) or 0
end

local function isAdmin(player)
    return adminLevel(player) >= Vehicles.config.spawnpointAdminLevel
end

-- Creates a checkpoint marker + attached radar blip, both visible only to
-- `player`. The blip is a child of the marker, so destroying the marker also
-- removes the blip.
local function createSpawnMarker(player, x, y, z, colorKey)
    local m = Vehicles.config.marker
    local c = m.colors[colorKey] or m.colors.new

    local marker = createMarker(x, y, z, m.type, m.size, c[1], c[2], c[3], m.alpha)
    if not marker then return nil end
    setElementVisibleTo(marker, root, false)
    setElementVisibleTo(marker, player, true)

    local b = m.blip
    local blip = createBlipAttachedTo(marker, b.icon, b.size, c[1], c[2], c[3], 255,
        b.ordering, b.visibleDistance)
    if blip then
        setElementVisibleTo(blip, root, false)
        setElementVisibleTo(blip, player, true)
    end

    return marker
end

local function destroyMarkerList(list)
    for _, marker in ipairs(list) do
        if isElement(marker) then destroyElement(marker) end
    end
end

--------------------------------------------------------------------------------
-- /vehspawn
--------------------------------------------------------------------------------

addCommandHandler("vehspawn", function(player)
    if not isAdmin(player) then
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

    local marker = createSpawnMarker(player, x, y, z, "new")
    if marker then
        newPointMarkers[player] = newPointMarkers[player] or {}
        table.insert(newPointMarkers[player], marker)
    end

    outputChatBox("v_ownveh [" .. category .. "] " .. line, player, 120, 220, 120)
    outputServerLog("[v_ownveh] /vehspawn by " .. getPlayerName(player) .. " -> " .. line)
end)

--------------------------------------------------------------------------------
-- /showvehspawns
--------------------------------------------------------------------------------

addCommandHandler("showvehspawns", function(player)
    if not isAdmin(player) then
        outputChatBox("v_ownveh: you don't have permission for /showvehspawns.", player, 255, 90, 90)
        return
    end

    -- Already shown -> toggle off.
    if shownMarkers[player] then
        destroyMarkerList(shownMarkers[player])
        shownMarkers[player] = nil
        outputChatBox("v_ownveh: spawn point markers hidden.", player, 200, 200, 200)
        return
    end

    local markers, count = {}, 0
    for category, points in pairs(Vehicles.spawnpoints) do
        for _, p in ipairs(points) do
            local marker = createSpawnMarker(player, p[1], p[2], p[3], category)
            if marker then
                table.insert(markers, marker)
                count = count + 1
            end
        end
    end
    shownMarkers[player] = markers

    outputChatBox(string.format("v_ownveh: showing %d spawn point marker(s). " ..
        "land=green boats=blue heli=yellow plane=red. /showvehspawns again to hide.",
        count), player, 120, 220, 120)
end)

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

addEventHandler("onPlayerQuit", root, function()
    if newPointMarkers[source] then
        destroyMarkerList(newPointMarkers[source])
        newPointMarkers[source] = nil
    end
    if shownMarkers[source] then
        destroyMarkerList(shownMarkers[source])
        shownMarkers[source] = nil
    end
end)
