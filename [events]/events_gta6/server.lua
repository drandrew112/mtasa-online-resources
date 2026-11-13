-- events_gta6: only registers the event; events_core switches the models / maps / collectible lists on and off.
-- Server events onEventStarted / onEventStopped (id == "gta6") are available for extra logic.

local function register()
    local res = getResourceFromName("events_core")
    if not res or getResourceState(res) ~= "running" then return end
    exports.events_core:registerEvent(EVENT_GTA6.id, {
        name = EVENT_GTA6.name,
        description = EVENT_GTA6.description,
        models = EVENT_GTA6.models,
        maps = EVENT_GTA6.maps,
        collectibles = EVENT_GTA6.collectibles,
    })
end

addEvent("onEventsCoreStart")
addEventHandler("onResourceStart", resourceRoot, register)
addEventHandler("onEventsCoreStart", root, register)
