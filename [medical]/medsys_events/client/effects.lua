-- Controls disabled by the injuries (the list comes from the server, see MEDEV_EFFECTS).
-- Other scripts (e.g. medsys while the player is down) toggle controls too, so ours are
-- re-applied periodically.

addEvent("medev:effects", true)

local disabled = {} -- control -> true

addEventHandler("medev:effects", resourceRoot, function(list)
    local wanted = {}
    for _, control in ipairs(list or {}) do wanted[control] = true end

    for control in pairs(disabled) do
        if not wanted[control] then toggleControl(control, true) end
    end
    for control in pairs(wanted) do toggleControl(control, false) end
    disabled = wanted
end)

setTimer(function()
    for control in pairs(disabled) do
        if isControlEnabled(control) then toggleControl(control, false) end
    end
end, 500, 0)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for control in pairs(disabled) do toggleControl(control, true) end
    disabled = {}
end)
