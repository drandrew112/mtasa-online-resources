-- v_customs :: workshop session (client)
--
-- The server decides when a session starts (vehicle drives onto a lift) and
-- ends. This side just swings the camera + menu in and out.

Shop   = Shop or {}
uicore = uicore or exports.ui_core

local active = false

addEvent("v_customs:sessionStarted", true)
addEvent("v_customs:sessionEnded", true)

-- The default HUD is already permanently off (ui_core did it at boot); do NOT
-- touch setPlayerHudComponentVisible here or it comes back on exit.
local function setShopMode(on)
    showChat(not on)
    uicore:toggleMoveControls(not on)
end

addEventHandler("v_customs:sessionStarted", root, function(veh)
    if active or not isElement(veh) then return end
    active = true

    setShopMode(true)
    CustomsCam.start(veh)

    if not Menu.open(veh) then
        -- ui_inac refused (another menu open) - bail out cleanly
        Shop.onMenuClosed()
    end
end)

addEventHandler("v_customs:sessionEnded", root, function()
    if not active then return end
    active = false

    Menu.close()
    Preview.restore()
    CustomsCam.stop()
    setShopMode(false)
end)

-- Called by menu.lua when the temp menu closes (Backspace at the root).
function Shop.onMenuClosed()
    if not active then return end
    triggerServerEvent("v_customs:closeSession", localPlayer)
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        Menu.close()
        Preview.restore()
        CustomsCam.stop()
        setShopMode(false)
    end
end)
