if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Preferences menu -> acc_savesys (it validates the id / value and saves it on the account).

addEvent("ui_inac:setPreference", true)
addEventHandler("ui_inac:setPreference", root, function(id, value)
    local player = client
    if not isElement(player) or type(id) ~= "string" then return end
    local res = getResourceFromName("acc_savesys")
    if not res or getResourceState(res) ~= "running" then return end
    if exports.acc_savesys:setPreference(player, id, value) then
        triggerClientEvent(player, "ui_inac:notify", player, L.msg("ui_inac.main.preferences"), L.msg("ui_inac.main.preference_saved"))
    end
end)
