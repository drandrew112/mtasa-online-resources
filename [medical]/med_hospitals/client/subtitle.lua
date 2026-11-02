-- Bay area entry hint (server/handover.lua, server/tutorial.lua): ui_core subtitle
addEvent("hosp:subtitle", true)
addEventHandler("hosp:subtitle", resourceRoot, function(text, duration)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then exports.ui_core:drawSubtitle(text, duration) end
end)
