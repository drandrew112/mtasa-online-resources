

function sendMessageToAll(sender, text)
    for i,player in ipairs( getElementsByType("player") ) do
        triggerClientEvent(player, "addMessage", sender, sender, text)
    end
end
addEvent("sendMessageToAll", true)
addEventHandler("sendMessageToAll", getRootElement(), function(sender, text)
    -- Drop the message if the real sender is muted (mute.lua).
    if isElement(client) and isChatMuted(client) then
        notifyMuteBlocked(client)
        return
    end
    sendMessageToAll(sender, text)
end)

