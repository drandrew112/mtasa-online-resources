if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Unlock toast + admin feedback through ui_core notifications.

addEvent("ach:unlocked", true)
addEventHandler("ach:unlocked", localPlayer, function(id, name, desc, xp)
    local text = tostring(name) .. " - " .. tostring(desc)
    if (tonumber(xp) or 0) > 0 then
        text = L("v_achievements.notify.xp", { text = text, xp = xp })
    end
    exports.ui_core:addNotification(L("v_achievements.notify.achievement_unlocked"), text)
end)

addEvent("ach:notify", true)
addEventHandler("ach:notify", localPlayer, function(title, text)
    exports.ui_core:addNotification(title, text, true)
end)
