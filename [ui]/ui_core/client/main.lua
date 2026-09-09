toggleControl("vehicle_look_left", false)
toggleControl("vehicle_look_right", false)
toggleControl("vehicle_look_behind", false)

setPlayerHudComponentVisible("radar", false)
setPlayerHudComponentVisible("health", false)
setPlayerHudComponentVisible("armour", false)
setPlayerHudComponentVisible("breath", false)
setPlayerHudComponentVisible("weapon", false)
setPlayerHudComponentVisible("ammo", false)
setPlayerHudComponentVisible("clock", false)
setPlayerHudComponentVisible("money", false)
showChat(false)

addEventHandler("onClientRender", root, function()
    UI.banner:draw()
    UI.infobox:draw()
    UI.subtitle:draw()
    UI.alert:draw()
    UI:drawNotifications()

    if UI.yOverlay.active then
        UI.yOverlay:draw()
    end
    UI.yOverlay:drawLevelOnly()
    UI.yOverlay:drawMoneyOnly()

    UI.textInput:draw()
end)
