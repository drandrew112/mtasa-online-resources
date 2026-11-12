-- events_xmas: only registers the event; events_core switches the models / map on and off.
-- Server events onEventStarted / onEventStopped (id == "xmas") are available for extra logic.

local function register()
    local res = getResourceFromName("events_core")
    if not res or getResourceState(res) ~= "running" then return end
    exports.events_core:registerEvent(EVENT_XMAS.id, {
        name = EVENT_XMAS.name,
        description = EVENT_XMAS.description,
        models = EVENT_XMAS.models,
        maps = EVENT_XMAS.maps,
    })
end

addEvent("onEventsCoreStart")
addEventHandler("onResourceStart", resourceRoot, register)
addEventHandler("onEventsCoreStart", root, register)
