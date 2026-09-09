-- v_customs :: workshop session (client)
--
-- The server decides when a session starts (vehicle drives onto a lift) and
-- ends. This side just swings the camera / menu / HUD in and out.

Shop   = Shop or {}
uicore = uicore or exports.ui_core

local active = false

addEvent("v_customs:sessionStarted", true)
addEvent("v_customs:sessionEnded", true)

local function setShopHud(on)
    setPlayerHudComponentVisible("all", not on)
    showChat(not on)
    uicore:toggleMoveControls(not on)
end

addEventHandler("v_customs:sessionStarted", root, function(veh)
    if active or not isElement(veh) then return end
    active = true

    setShopHud(true)
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
    setShopHud(false)
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
        setShopHud(false)
    end
end)
