if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The loading screen: black, the ui_core spinner and the steps under it.
--   Account data        always done here (v_accounts loaded it at the login)
--   Game resources      until the server's gate asks for the ready reports
--   Setting up          resourceReady reports: done / running required
--   World               the spawn area is streaming in (normal mode only)

local active = false
local mode = "normal"
local worldStage = false
local sw, sh = guiGetScreenSize()
local S = math.max(0.6, sh / 1080)

addEvent("v_loading:screen", true)
addEvent("v_loading:playerLoaded", true)
addEvent("onClientLoadingStarted")  -- local; the loading screen appeared
addEvent("onClientPlayerLoaded")    -- local; the server finished loading the player (arg 1 = account name)

local C_DIM  = tocolor(146, 158, 170, 255)
local C_TEXT = tocolor(228, 233, 238, 255)
local C_OK   = tocolor(110, 220, 130, 255)
local C_BAR  = tocolor(255, 255, 255, 26)
local C_ACC  = tocolor(64, 156, 180, 255)

-- Stall watch: when nothing progresses for LOADING_FAIL_TIMEOUT the screen lists what
-- could not be loaded and suggests a reconnect (Enter / click) or keep waiting (Esc).
local failed = false
local lastSig, lastProgress = "", 0
local test = nil -- /loadingtest: { fail = bool, start = tick }
local C_ERR = tocolor(240, 120, 110, 255)

local function failedItems()
    local items = {}
    if test then
        return { "ui_phone", "v_jobmanager", "med_erm" }
    end
    local checking = isCheckingReady()
    if worldStage then
        items[1] = L("v_loading.fail.world")
    elseif checking then
        for _, name in ipairs(missingResources()) do items[#items + 1] = name end
        if #items == 0 then items[1] = L("v_loading.fail.setup") end
    else
        for _, res in ipairs(getResources()) do
            local state = getResourceState(res)
            if state == "starting" or state == "loading" then items[#items + 1] = getResourceName(res) end
        end
        if #items == 0 then items[1] = L("v_loading.fail.game_resources") end
    end
    local mod = getResourceFromName("v_modloader")
    if mod and getResourceState(mod) == "running" then
        local ok, mDone, mTotal, mFinished, mActive = pcall(function() return exports.v_modloader:getLoadProgress() end)
        if ok and mActive and not mFinished then
            items[#items + 1] = L("v_loading.fail.custom_models", { done = mDone or 0, total = mTotal or 0 })
        end
    end
    return items
end

local failList = {}

local function setFailed(state)
    failed = state
    showCursor(state)
    if state then
        failList = failedItems()
        local done, total = readyCounts()
        outputDebugString(("[v_loading] loading stalled: checking=%s ready=%d/%d world=%s missing=%s")
            :format(tostring(isCheckingReady()), done, total, tostring(worldStage), table.concat(failList, ", ")), 2)
    end
    lastProgress = getTickCount()
end

local function reconnect()
    if test then
        test = nil
        setFailed(false)
        triggerEvent("v_loading:screen", localPlayer, false)
        return
    end
    executeCommandHandler("reconnect")
end

local function keepWaiting()
    if test then return reconnect() end
    setFailed(false)
end

local btnReconnect, btnWait = {}, {}

local function drawFailure()
    local cx = sw / 2
    local y = sh * 0.60
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 255))
    dxDrawText(L("v_loading.fail.title"), 0, sh * 0.28, sw, sh * 0.28 + 40 * S, C_ERR, 1.8 * S, "default-bold", "center", "center")
    dxDrawText(L("v_loading.fail.subtitle"), 0, sh * 0.28 + 44 * S, sw, sh * 0.28 + 72 * S, C_TEXT, 1.15 * S, "default", "center", "center")
    local ly = sh * 0.28 + 100 * S
    dxDrawText(L("v_loading.fail.missing"), cx - 230 * S, ly, cx + 230 * S, ly + 24 * S, C_DIM, 1.1 * S, "default", "left", "center")
    ly = ly + 28 * S
    for i, item in ipairs(failList) do
        if i > 10 then
            dxDrawText("…", cx - 230 * S, ly, cx + 230 * S, ly + 22 * S, C_DIM, 1.1 * S, "default-bold", "left", "center")
            break
        end
        dxDrawText("• " .. item, cx - 230 * S, ly, cx + 230 * S, ly + 22 * S, C_TEXT, 1.1 * S, "default-bold", "left", "center")
        ly = ly + 22 * S
    end
    local by = math.max(ly + 30 * S, sh * 0.66)
    local bw, bh = 220 * S, 40 * S
    local mx, my = getCursorPosition()
    mx, my = (mx or 0) * sw, (my or 0) * sh
    btnReconnect = { cx - bw - 10 * S, by, bw, bh }
    btnWait = { cx + 10 * S, by, bw, bh }
    local function button(b, text, col)
        local over = mx >= b[1] and mx <= b[1] + b[3] and my >= b[2] and my <= b[2] + b[4]
        dxDrawRectangle(b[1], b[2], b[3], b[4], over and col or tocolor(255, 255, 255, 30))
        dxDrawText(text, b[1], b[2], b[1] + b[3], b[2] + b[4], C_TEXT, 1.15 * S, "default-bold", "center", "center")
    end
    button(btnReconnect, L("v_loading.fail.reconnect"), C_ACC)
    button(btnWait, L("v_loading.fail.wait"), tocolor(255, 255, 255, 70))
    dxDrawText(L("v_loading.fail.hint"), 0, by + bh + 12 * S, sw, by + bh + 36 * S, C_DIM, 1.0 * S, "default", "center", "center")
end

local function stallCheck(sig)
    if sig ~= lastSig then
        lastSig, lastProgress = sig, getTickCount()
        return
    end
    local limit = test and test.fail and 3000 or LOADING_FAIL_TIMEOUT
    if (test and test.fail or not test) and getTickCount() - lastProgress > limit then
        setFailed(true)
    end
end

addEventHandler("onClientClick", root, function(button, state)
    if not active or not failed or button ~= "left" or state ~= "up" then return end
    local mx, my = getCursorPosition()
    if not mx then return end
    mx, my = mx * sw, my * sh
    local function inside(b) return mx >= b[1] and mx <= b[1] + b[3] and my >= b[2] and my <= b[2] + b[4] end
    if inside(btnReconnect) then reconnect() elseif inside(btnWait) then keepWaiting() end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not active or not failed or not press then return end
    if key == "enter" or key == "num_enter" then reconnect() elseif key == "escape" then keepWaiting() end
    cancelEvent()
end)

local function row(y, label, value, valueColor, labelColor)
    local x, w = sw / 2 - 230 * S, 460 * S
    dxDrawText(label, x, y, x + w, y + 24 * S, labelColor or C_DIM, 1.1 * S, "default", "left", "center")
    dxDrawText(value, x, y, x + w, y + 24 * S, valueColor or C_DIM, 1.1 * S, "default-bold", "right", "center")
end

local function draw()
    if failed then return drawFailure() end
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 255))
    exports.ui_core:drawLoadingText(L("v_loading.screen.loading"))

    local y = sh * 0.60
    local checking = isCheckingReady()
    local done, total = readyCounts()
    if test then
        -- /loadingtest: fake progress (fail = stalls at 3 / 8, the normal one finishes)
        local t = (getTickCount() - test.start) / 1000
        checking, total = t > 1, 8
        done = test.fail and math.min(3, math.floor(t)) or math.min(8, math.floor(t))
        if not test.fail and t > 9 then
            test = nil
            return triggerEvent("v_loading:screen", localPlayer, false)
        end
    end
    local mDoneSig = ""
    if not test then
        local mod = getResourceFromName("v_modloader")
        if mod and getResourceState(mod) == "running" then
            local ok, d = pcall(function() return exports.v_modloader:getLoadProgress() end)
            if ok then mDoneSig = tostring(d) end
        end
    end
    stallCheck(("%s|%d|%d|%s|%s"):format(tostring(checking), done, total, tostring(worldStage), mDoneSig))
    local setupDone = (checking == false and worldStage) or (total > 0 and done >= total and checking)

    row(y, L("v_loading.screen.account_data"), "✓", C_OK)
    y = y + 28 * S
    local resourcesDone = checking or worldStage
    row(y, L("v_loading.screen.game_resources"), resourcesDone and "✓" or L("v_loading.screen.waiting"),
        resourcesDone and C_OK or C_DIM)
    y = y + 28 * S
    row(y, L("v_loading.screen.setting_up"), worldStage and "✓" or ("%d / %d"):format(done, total),
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
            local value = mFinished and "✓" or (mActive and ("%d / %d"):format(mDone or 0, mTotal or 0) or L("v_loading.screen.waiting"))
            row(y, L("v_loading.screen.custom_models"), value, mFinished and C_OK or (mActive and C_TEXT or C_DIM),
                mActive and not mFinished and C_TEXT or C_DIM)
        end
    end
    if mode ~= "fresh" then
        y = y + 40 * S
        row(y, L("v_loading.screen.world"), worldStage and L("v_loading.screen.streaming") or L("v_loading.screen.waiting"),
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
        failed = false
        lastSig, lastProgress = "", getTickCount()
        addEventHandler("onClientRender", root, draw)
        setElementData(localPlayer, "hideHUD", true)
        showCursor(false)
        guiSetInputMode("no_binds")
        fadeCamera(true)
        toggleAllControls(false, true, false)
        if not test then triggerEvent("onClientLoadingStarted", localPlayer) end -- /loadingtest must not start other resources' loading
    else
        removeEventHandler("onClientRender", root, draw)
        failed = false
        test = nil
        -- hand the game back (the account menu / panels are already closed)
        toggleAllControls(true, true, true)
        guiSetInputMode("allow_binds")
        showCursor(false)
        exports.ui_core:toggleMoveControls(true)
        setElementData(localPlayer, "hideHUD", false)
        setCameraTarget(localPlayer)
    end
end

addEventHandler("v_loading:screen", localPlayer, setActive)

addEvent("v_loading:startWorldCheck", true)
addEventHandler("v_loading:startWorldCheck", localPlayer, function()
    worldStage = true
end)

addEventHandler("v_loading:playerLoaded", localPlayer, function(accName)
    triggerEvent("onClientPlayerLoaded", localPlayer, accName)
end)

-- /loadingtest = fake loading that finishes, /loadingtest fail = stalls and shows the failure screen
addCommandHandler("loadingtest", function(_, arg)
    if active then return end
    test = { fail = arg == "fail", start = getTickCount() }
    triggerEvent("v_loading:screen", localPlayer, true, { mode = "normal" })
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
