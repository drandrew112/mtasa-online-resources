-- /hosppos: the server sends the formatted position, setClipboard is client-only.
-- (The marker cards are ui_core marker UIs: server/markerui.lua.)
addEvent("hosp:clipboard", true)
addEventHandler("hosp:clipboard", resourceRoot, function(text)
    if type(text) == "string" then setClipboard(text) end
end)
