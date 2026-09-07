uicore = exports.ui_core
DGS = exports.dgs

sw, sh = uicore:getScreenWH()
safeX, safeY = uicore:getSafeZone()
ui = function (z) return uicore:ui(z) end

math.randomseed(getTickCount())
bg_img = "bgs/"..math.random(1, 11)..".png"

Panels = {}

-- Plays a short one-shot UI sound effect.
function uiSound(path)
    local s = playSound(path)
    if isElement(s) then
        setSoundVolume(s, 0.5)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    Panels.login = LoginPanel:create()
    Panels.register = RegisterPanel:create()
    Panels.banned = BannedPanel:create()

    setPanel(nil) -- hide everything until the server tells us what to show

    Music.init()

    -- Make sure we are not stuck on a black screen behind the panel.
    fadeCamera(true)
    setCameraMatrix(1468.75, -919.35, 120.0, 1468.75, -919.35, 60.0)

    -- The server decides whether we get the login panel or the ban lockdown.
    triggerServerEvent("acc:requestPanel", localPlayer)
end)

addEvent("acc:setPanel", true)
addEventHandler("acc:setPanel", root, setPanel)

addEvent("acc:error", true)
addEventHandler("acc:error", root, function(text)
    uicore:setInfobox(text)
end)
