-- Client side of the railway role (server/role.lua owns it). Only for UI decisions: the
-- server checks the role itself.

function isRailwayRoleRequired()
    return RW.REQUIRE_RAILWAY_ROLE == true
end

function isPlayerRailway(player)
    player = player or localPlayer
    return isElement(player) and getElementData(player, RW.DATA_ROLE) == true
end

function hasRailwayAccess(player)
    return not RW.REQUIRE_RAILWAY_ROLE or isPlayerRailway(player)
end

-- server messages -> ui_core notification
function rwNotify(text, ok)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(RW.COMPANY, text)
    else
        outputChatBox("[" .. RW.COMPANY_SHORT .. "] " .. text, ok and 120 or 255, ok and 220 or 140, ok and 120 or 100)
    end
end

addEvent("rw:notify", true)
addEventHandler("rw:notify", resourceRoot, rwNotify)
