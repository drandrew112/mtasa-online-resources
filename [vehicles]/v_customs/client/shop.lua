-- v_customs :: workshop session (client)
--
-- The server starts a session once the car is far enough into a workshop and
-- has moved it into a private dimension. Here: drive-in animation -> menu ->
-- (menu closed) turn + drive-out animation -> ask the server to close, which
-- puts car and driver back into the normal dimension.

Shop   = Shop or {}
uicore = uicore or exports.ui_core

local active  = false
local leaving = false
local curVeh, curWs, curDim

addEvent("v_customs:sessionStarted", true)
addEvent("v_customs:sessionEnded", true)

-- The default HUD is already permanently off (ui_core did it at boot); do NOT
-- touch setPlayerHudComponentVisible here or it comes back on exit.
local function setShopMode(on)
    showChat(not on)
    uicore:toggleMoveControls(not on)
end

addEventHandler("v_customs:sessionStarted", root, function(veh, wsIdx, dim)
    local ws = Customs.WORKSHOPS[wsIdx]
    if active or not isElement(veh) or not ws then return end
    active, leaving = true, false
    curVeh, curWs, curDim = veh, ws, dim

    setShopMode(true)
    Garage.enter(veh, ws, dim, function()
        if not active or leaving then return end
        CustomsCam.start(veh)
        if not Menu.open(veh) then
            -- ui_inac refused (another menu open) - drive straight back out
            Shop.onMenuClosed()
        end
    end)
end)

local function teardown()
    active, leaving = false, false
    curVeh, curWs, curDim = nil, nil, nil
    Garage.cleanup()
    Menu.close()
    Preview.restore()
    CustomsCam.stop()
    setShopMode(false)
end

addEventHandler("v_customs:sessionEnded", root, function()
    if not active then return end
    teardown()
end)

-- Called by menu.lua when the temp menu closes (Backspace at the root).
function Shop.onMenuClosed()
    if not active or leaving then return end
    leaving = true
    Preview.restore()
    CustomsCam.stop(true)

    if not isElement(curVeh) then
        triggerServerEvent("v_customs:closeSession", localPlayer)
        return
    end
    triggerServerEvent("v_customs:exitBegin", localPlayer)
    Garage.exit(curVeh, curWs, curDim, function(x, y, z, rz)
        triggerServerEvent("v_customs:closeSession", localPlayer, x, y, z, rz)
    end)
end

-- No getting out of the car inside the workshop.
addEventHandler("onClientVehicleStartExit", root, function(ped)
    if active and ped == localPlayer then cancelEvent() end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then teardown() end
end)
