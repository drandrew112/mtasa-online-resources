-- Client side of the ATC rights (server/role.lua owns them). Only for UI decisions: the server
-- checks the rights itself.

function hasATCRight(player, right)
    player = player or localPlayer
    if not isElement(player) then return false end
    local rights = getElementData(player, AVI.DATA_RIGHTS)
    if type(rights) == "table" then return rights[right] == true end
    return AVI.DEFAULT_RIGHTS[right] == true
end

function hasATCAccess(player)
    for _, r in ipairs(AVI.RIGHTS) do
        if hasATCRight(player, r) then return true end
    end
    return false
end

-- server messages of every avi_* resource -> ui_core notification (v_chat hides the chat box)
addEvent("avi:notify", true)
addEventHandler("avi:notify", root, function(title, text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(title, text)
    else
        outputChatBox("[" .. tostring(title) .. "] " .. tostring(text), 120, 200, 255)
    end
end)
