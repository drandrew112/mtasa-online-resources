-- Admin helpers shared by the avi_* resources: admin level, player lookup, notifications, /avipos.

-- admin level through v_mysql (like rw_core / med_erm), element data as a fallback
function getAdminLevel(player)
    local res = getResourceFromName("v_mysql")
    if res and getResourceState(res) == "running" then
        return tonumber(exports.v_mysql:getAccData(player, "admin_level")) or 0
    end
    return tonumber(getElementData(player, "admin_level")) or 0
end

function isAviationAdmin(player)
    return getAdminLevel(player) >= AVI.ADMIN_LEVEL
end

function findPlayer(name)
    local p = getPlayerFromName(name)
    if p then return p end
    local q = name:lower()
    for _, pl in ipairs(getElementsByType("player")) do
        if getPlayerName(pl):gsub("#%x%x%x%x%x%x", ""):lower():find(q, 1, true) then return pl end
    end
end

-- v_chat hides the chat box: player messages go through ui_core notifications (client side)
function aviNotify(player, text)
    triggerClientEvent(player, "avi:notify", resourceRoot, AVI.TAG, text)
end

-- /avipos : current position for the JSON data files (x, y, z, heading), also into the console (F8)
addCommandHandler("avipos", function(player)
    if not isAviationAdmin(player) then return end
    local x, y, z = getElementPosition(player)
    local veh = getPedOccupiedVehicle(player)
    local _, _, rz = getElementRotation(veh or player)
    local hdg = (360 - rz) % 360   -- GTA rotation is anticlockwise, compass heading is clockwise
    local line = ('"x": %.1f, "y": %.1f, "z": %.1f, "hdg": %d'):format(x, y, z, math.floor(hdg + 0.5))
    outputConsole(line, player)
    aviNotify(player, line .. " (also in F8)")
end)
