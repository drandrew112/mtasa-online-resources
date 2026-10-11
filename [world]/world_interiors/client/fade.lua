-- world_interiors / client/fade.lua — fade effect around teleports
addEvent("world_interiors:fadeOut", true)
addEvent("world_interiors:fadeIn", true)

addEventHandler("world_interiors:fadeOut", resourceRoot, function()
    fadeCamera(false, INT.fadeMs / 1000)
end)

addEventHandler("world_interiors:fadeIn", resourceRoot, function()
    fadeCamera(true, 0.4)
end)
