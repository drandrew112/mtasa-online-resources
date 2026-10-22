if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_core / client/notify.lua
-- Business notifications from the server (already in this player's language).

addEvent("biz_core:notify", true)
addEventHandler("biz_core:notify", resourceRoot, function(title, text)
    exports.ui_core:addNotification(L.resolve(title), L.resolve(text))
end)
