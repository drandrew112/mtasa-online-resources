-- ui client: the panels before the account menu. Every decision is the
-- server's (auth, bans modules); this side only draws and calls the auth client API.

uicore = exports.ui_core
DGS = exports.dgs

sw, sh = uicore:getScreenWH()
safeX, safeY = uicore:getSafeZone()
ui = function (z) return uicore:ui(z) end

math.randomseed(getTickCount())
bg_img = "ui/bgs/" .. math.random(1, 11) .. ".png"

Panels = {}

-- Exported: this session's background, for v_mainmenu.
function getBackgroundImage()
    return ":v_accounts/" .. bg_img
end

-- Plays a short one-shot UI sound effect.
function uiSound(path)
    local s = playSound(path)
    if isElement(s) then
        setSoundVolume(s, 0.5)
    end
end

function init_panels()
    Panels.login = LoginPanel:create()
    Panels.register = RegisterPanel:create()
    Panels.forgot = ForgotPanel:create()
    Panels.banned = BannedPanel:create()

    setPanel(nil) -- hide everything until the server tells us what to show

    Music.init()

    -- Make sure we are not stuck on a black screen behind the panel.
    fadeCamera(true)
    setCameraMatrix(1468.75, -919.35, 120.0, 1468.75, -919.35, 60.0)

    -- The server decides whether we get the login panel or the ban lockdown.
    triggerServerEvent("v_accounts:requestPanel", localPlayer)
end

addEvent("download:finished", true)
addEventHandler("onClientResourceStart", resourceRoot, function()
    local download_active = exports["ui_download"]:isDownloadingActive()
    if download_active then
        -- one-shot: a later download (resource restart, v_modloader) must not rebuild the panels
        local function onFinished()
            removeEventHandler("download:finished", root, onFinished)
            init_panels()
        end
        addEventHandler("download:finished", root, onFinished)
    else
        init_panels()
    end
end)

addEvent("v_accounts:setPanel", true)
addEventHandler("v_accounts:setPanel", localPlayer, function(name) setPanel(name) end)

addEvent("v_accounts:onClientAuthError", true)
addEventHandler("v_accounts:onClientAuthError", localPlayer, function(text)
    if UIState.active then uicore:setInfobox(text, 255, 255, 255) end
end)

-- logged in: v_mainmenu (or the loading screen) takes over the screen
addEvent("v_accounts:onClientLoggedIn", true)
addEventHandler("v_accounts:onClientLoggedIn", localPlayer, function(_, isNew)
    -- the account menu keeps the music going (no restart in between); a new account goes to the loading
    local menu = getResourceFromName("v_mainmenu")
    if not isNew and menu and getResourceState(menu) == "running" then setMusicActive(true) end
    setPanel(nil, true)
end)

addEvent("v_accounts:onClientBanState", true)
addEventHandler("v_accounts:onClientBanState", localPlayer, function(banned)
    if banned then
        setPanel("banned")
    elseif getElementData(localPlayer, "isLogged") == true then
        setPanel(nil)
    else
        setPanel("login")
    end
end)

addEvent("v_accounts:onClientTokenInvalid", true)
addEventHandler("v_accounts:onClientTokenInvalid", localPlayer, function()
    if Panels.login then Panels.login:setMode("form") end
end)
