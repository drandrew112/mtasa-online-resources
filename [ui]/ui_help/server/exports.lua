-- Server exports.
--
--   openHelp(player [, topicId]) -> bool   opens the help panel for a player

function openHelp(player, topicId)
    if not (isElement(player) and getElementType(player) == "player") then return false end
    return triggerClientEvent(player, "ui_help:open", resourceRoot, type(topicId) == "string" and topicId or nil)
end
