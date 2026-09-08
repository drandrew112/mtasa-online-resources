-- Account System - client loading screen
--
-- A plain black screen with the ui_core loading spinner, shown between a
-- successful login/registration and the moment the server spawns the player
-- (while account data is being pulled from the shared MySQL store).

local active = false
local screenW, screenH = guiGetScreenSize()

addEvent("acc:loadingScreen", true)
addEventHandler("acc:loadingScreen", root, function(show)
    active = show and true or false

    if active then
        setElementData(localPlayer, "hideHUD", true)
        showCursor(false)
        fadeCamera(true)
        toggleAllControls(localPlayer, false, true, false)
    end
    -- When it turns off, acc:setPanel(nil) follows immediately and restores
    -- controls / HUD, so there is nothing to undo here.
end)

addEventHandler("onClientRender", root, function()
    if not active then return end
    dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, 255))
    exports.ui_core:drawLoadingText("Loading account data")
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        toggleAllControls(localPlayer, true, true, true)
    end
end)
