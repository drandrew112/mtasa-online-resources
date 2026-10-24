if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The loading screen: black, the ui_core spinner and the steps under it.
--   Account data        always done here (acc_auth loaded it at the login)
--   Game resources      until the server's gate asks for the ready reports
--   Setting up          resourceReady reports: done / running required
--   World               the spawn area is streaming in (normal mode only)

local active = false
local mode = "normal"
local worldStage = false
local sw, sh = guiGetScreenSize()
local S = math.max(0.6, sh / 1080)

addEvent("acc_loading:screen", true)
addEvent("acc_loading:playerLoaded", true)
addEvent("onClientLoadingStarted")  -- local; the loading screen appeared
addEvent("onClientPlayerLoaded")    -- local; the server finished loading the player (arg 1 = account name)

local C_DIM  = tocolor(146, 158, 170, 255)
local C_TEXT = tocolor(228, 233, 238, 255)
local C_OK   = tocolor(110, 220, 130, 255)
local C_BAR  = tocolor(255, 255, 255, 26)
local C_ACC  = tocolor(64, 156, 180, 255)

local function row(y, label, value, valueColor, labelColor)
    local x, w = sw / 2 - 230 * S, 460 * S
    dxDrawText(label, x, y, x + w, y + 24 * S, labelColor or C_DIM, 1.1 * S, "default", "left", "center")
    dxDrawText(value, x, y, x + w, y + 24 * S, valueColor or C_DIM, 1.1 * S, "default-bold", "right", "center")
end

local function draw()
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 255))
    exports.ui_core:drawLoadingText(L("acc_loading.screen.loading"))

    local y = sh * 0.60
    local checking = isCheckingReady()
    local done, total = readyCounts()
    local setupDone = (checking == false and worldStage) or (total > 0 and done >= total and checking)

    row(y, L("acc_loading.screen.account_data"), "✓", C_OK)
    y = y + 28 * S
    local resourcesDone = checking or worldStage
    row(y, L("acc_loading.screen.game_resources"), resourcesDone and "✓" or L("acc_loading.screen.waiting"),
        resourcesDone and C_OK or C_DIM)
    y = y + 28 * S
    row(y, L("acc_loading.screen.setting_up"), worldStage and "✓" or ("%d / %d"):format(done, total),
        worldStage and C_OK or C_TEXT, (resourcesDone and not worldStage) and C_TEXT or C_DIM)
    local bx, bw = sw / 2 - 230 * S, 460 * S
    dxDrawRectangle(bx, y + 27 * S, bw, 4 * S, C_BAR)
    dxDrawRectangle(bx, y + 27 * S, bw * ((worldStage or setupDone) and 1 or (total > 0 and done / total or 0)), 4 * S, C_ACC)
    -- v_modloader: the enabled + downloaded custom models being loaded
    local res = getResourceFromName("v_modloader")
    if res and getResourceState(res) == "running" then
        local ok, mDone, mTotal, mFinished, mActive = pcall(function() return exports.v_modloader:getLoadProgress() end)
        if ok then
            y = y + 40 * S
            local value = mFinished and "✓" or (mActive and ("%d / %d"):format(mDone or 0, mTotal or 0) or L("acc_loading.screen.waiting"))
            row(y, L("acc_loading.screen.custom_models"), value, mFinished and C_OK or (mActive and C_TEXT or C_DIM),
                mActive and not mFinished and C_TEXT or C_DIM)
        end
    end
    if mode ~= "fresh" then
        y = y + 40 * S
        row(y, L("acc_loading.screen.world"), worldStage and L("acc_loading.screen.streaming") or L("acc_loading.screen.waiting"),
            worldStage and C_TEXT or C_DIM, worldStage and C_TEXT or C_DIM)
    end
end

local function setActive(show, info)
    show = show and true or false
    if show == active then return end
    active = show
    if show then
        mode = type(info) == "table" and info.mode or "normal"
        worldStage = false
        addEventHandler("onClientRender", root, draw)
        setElementData(localPlayer, "hideHUD", true)
        showCursor(false)
        guiSetInputMode("no_binds")
        fadeCamera(true)
        toggleAllControls(false, true, false)
        triggerEvent("onClientLoadingStarted", localPlayer)
    else
        removeEventHandler("onClientRender", root, draw)
        -- hand the game back (the account menu / panels are already closed)
        toggleAllControls(true, true, true)
        guiSetInputMode("allow_binds")
        showCursor(false)
        exports.ui_core:toggleMoveControls(true)
        setElementData(localPlayer, "hideHUD", false)
        setCameraTarget(localPlayer)
    end
end

addEventHandler("acc_loading:screen", localPlayer, setActive)

addEvent("acc_loading:startWorldCheck", true)
addEventHandler("acc_loading:startWorldCheck", localPlayer, function()
    worldStage = true
end)

addEventHandler("acc_loading:playerLoaded", localPlayer, function(accName)
    triggerEvent("onClientPlayerLoaded", localPlayer, accName)
end)

function isLoadingActive()
    return active
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if active then
        toggleAllControls(true, true, true)
        guiSetInputMode("allow_binds")
    end
end)
