-- Notifications sent by the server side of work_ems
addEvent("ems:notify", true)
addEventHandler("ems:notify", resourceRoot, function(title, text)
    exports.ui_core:addNotification(title, text)
end)
