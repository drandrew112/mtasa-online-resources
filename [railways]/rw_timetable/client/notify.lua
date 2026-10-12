if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Service messages for the driver -> ui_core notification (chat as a fallback)

addEvent("rw:tt:notify", true)
addEventHandler("rw:tt:notify", resourceRoot, function(text, ok)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(L("rw_timetable.notify.timetable"), text)
    else
        outputChatBox("[Timetable] " .. text, ok and 120 or 255, ok and 220 or 160, ok and 120 or 90)
    end
end)
