-- biz_int / client/fade.lua - fade around the teleports
addEvent("bizint:fadeOut", true)
addEvent("bizint:fadeIn", true)

addEventHandler("bizint:fadeOut", resourceRoot, function()
    fadeCamera(false, BINT.fadeMs / 1000)
end)

addEventHandler("bizint:fadeIn", resourceRoot, function()
    fadeCamera(true, 0.4)
end)
