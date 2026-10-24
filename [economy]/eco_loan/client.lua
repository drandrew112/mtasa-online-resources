if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- eco_loan / client.lua
-- Loan notifications from the server.

addEvent("eco_loan:notify", true)
addEventHandler("eco_loan:notify", resourceRoot, function(title, text)
    exports.ui_core:addNotification(L.resolve(title), L.resolve(text))
end)
