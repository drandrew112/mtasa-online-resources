-- ============================================================
--  v_chat / c_mute.lua  (client)
--  Shows mute notifications through the ui_core Alert element
--  (the muted player cannot use the chat to read a reply).
-- ============================================================

addEvent("chat:muteAlert", true)
addEventHandler("chat:muteAlert", root, function(text, r, g, b, duration)
    if type(text) ~= "string" then return end
    exports.ui_core:setAlert(text, r, g, b, duration)
end)
