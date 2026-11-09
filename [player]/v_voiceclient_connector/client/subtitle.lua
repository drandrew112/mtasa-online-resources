-- v_voiceclient_connector / client/subtitle.lua
-- Voice radio feedback: the server sends the finished (translated, colour coded) text, ui_core shows it.

addEvent("voice:subtitle", true)
addEventHandler("voice:subtitle", resourceRoot, function(text, duration)
    if type(text) ~= "string" or text == "" then return end
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then return end
    exports.ui_core:drawSubtitle(text, tonumber(duration) or 4500)
end)
