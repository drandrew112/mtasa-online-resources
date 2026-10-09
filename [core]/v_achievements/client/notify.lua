-- Unlock toast + admin feedback through ui_core notifications.

addEvent("ach:unlocked", true)
addEventHandler("ach:unlocked", localPlayer, function(id, name, desc, xp)
    local text = tostring(name) .. " - " .. tostring(desc)
    if (tonumber(xp) or 0) > 0 then
        text = text .. "  (+" .. xp .. " XP)"
    end
    exports.ui_core:addNotification("Achievement unlocked", text)
end)

addEvent("ach:notify", true)
addEventHandler("ach:notify", localPlayer, function(title, text)
    exports.ui_core:addNotification(title, text, true)
end)
