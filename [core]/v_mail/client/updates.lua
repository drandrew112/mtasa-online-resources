-- receiveUpdateMails on the client (ui_pause Settings > Online, acc_menu Settings).
-- The server owns the value (accData, server/updates.lua) and pushes it after the
-- login and on start; until then it reads true (the default).

local value = true

addEvent("v_mail:updatesSetting", true)
addEventHandler("v_mail:updatesSetting", localPlayer, function(enabled)
    value = enabled ~= false
end)

function getReceiveUpdateMails()
    return value
end

function setReceiveUpdateMails(enabled)
    value = enabled == true
    triggerServerEvent("v_mail:setUpdates", localPlayer, value)
    return true
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("v_mail:updatesReady", localPlayer)
end)
