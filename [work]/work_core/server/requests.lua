-- Client requests from the marker menus. Everything is validated here: the player has to
-- stand at the marker, the work has to exist, the outfit / vehicle has to belong to it.

local lastRequest = {}             -- player -> tick

function notifyPlayer(player, title, text, silent)
    if isElement(player) and isPlayerReady(player) then
        if silent == nil then silent = false end
        triggerClientEvent(player, "work:notify", resourceRoot, title, text, silent)
    end
end

local function workName(workId)
    local w = Works[workId]
    return w and w.name or "Work"
end

-- -> marker data | nil
local function check(player, marker, kind)
    if not isElement(player) then return nil end
    local now = getTickCount()
    if lastRequest[player] and now - lastRequest[player] < WORK.REQUEST_COOLDOWN then return nil end
    lastRequest[player] = now
    local m = Markers[marker]
    if not m or m.kind ~= kind or not Works[m.work] then return nil end
    if not isPlayerAtMarker(player, marker) then
        notifyPlayer(player, workName(m.work), "You are too far from the marker.")
        return nil
    end
    return m
end

addEventHandler("onPlayerQuit", root, function()
    lastRequest[source] = nil
end)

addEvent("work:dutyOn", true)
addEventHandler("work:dutyOn", resourceRoot, function(marker, skin)
    local m = check(client, marker, "duty")
    if not m then return end
    local ok, err = startDuty(client, m.work, skin)
    notifyPlayer(client, workName(m.work), ok and "You are now on duty." or err)
end)

addEvent("work:dutyOff", true)
addEventHandler("work:dutyOff", resourceRoot, function(marker)
    local m = check(client, marker, "duty")
    if not m then return end
    if not isPlayerOnDuty(client, m.work) then return end
    endDuty(client, "player")
    notifyPlayer(client, workName(m.work), "You are now off duty.")
end)

addEvent("work:outfit", true)
addEventHandler("work:outfit", resourceRoot, function(marker, skin)
    local m = check(client, marker, "duty")
    if not m then return end
    if not isPlayerOnDuty(client, m.work) then return end
    local ok, err = changeDutySkin(client, skin)
    if not ok then notifyPlayer(client, workName(m.work), err) end
end)

addEvent("work:vehicleSpawn", true)
addEventHandler("work:vehicleSpawn", resourceRoot, function(marker, index)
    local m = check(client, marker, "vehicle")
    if not m then return end
    local vehicle, err = spawnWorkVehicle(client, marker, index)
    if not vehicle then notifyPlayer(client, workName(m.work), err) end
end)

addEvent("work:vehicleReturn", true)
addEventHandler("work:vehicleReturn", resourceRoot, function(marker)
    local m = check(client, marker, "vehicle")
    if not m then return end
    local ok, err = returnWorkVehicle(client, marker)
    notifyPlayer(client, workName(m.work), ok and "Vehicle returned." or err)
end)
