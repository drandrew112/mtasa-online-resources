addEvent("pausemenu_joinArenawar", true)
addEventHandler("pausemenu_joinArenawar", root, function()
    exports["v_arenawar"]:arenawarJoin(source)
end)
