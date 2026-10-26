if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Custom models (v_modloader): the first-entry warning, the Home reminder strip while
-- models are not downloaded, the menu hiding for the download screen and Auto-update.

ModelsNotice = { open = false, sel = 1 }   -- the first-entry modal (sel 1 = Open settings, 2 = Later)

local function modloaderRunning()
    local res = getResourceFromName("v_modloader")
    return res and getResourceState(res) == "running"
end

local function mbText(bytes)
    return ("%.1f MB"):format((tonumber(bytes) or 0) / 1048576)
end

--- count, bytes of the not downloaded models (0 while v_modloader checks the files)
function missingModels()
    if not modloaderRunning() then return 0, 0 end
    local ok, count, bytes, checking = pcall(function() return exports.v_modloader:getMissingModels() end)
    if not ok or checking then return 0, 0 end
    return tonumber(count) or 0, tonumber(bytes) or 0
end

function openModelSettings()
    Menu.goto("settings", "settings_cat", { id = "models" })
end

-- ---------------------------------------------------------------------------
-- Home reminder strip (home.lua leaves room for it)
-- ---------------------------------------------------------------------------

local C_WARN   = tocolor(196, 120, 30, 255)
local C_WARNBG = tocolor(70, 44, 12, 235)

--- Draws the strip when models are missing; returns the height it used (0 = nothing).
function drawModelsReminder(x, y, w)
    local count, bytes = missingModels()
    if count <= 0 then return 0 end
    local h = S(58)
    local focused = Menu.reg("page", "home_models", x, y, w, h, { activate = openModelSettings })
    dxDrawRectangle(x, y, w, h, C_WARNBG)
    dxDrawRectangle(x, y, S(6), h, C_WARN)
    if focused then
        dxDrawRectangle(x, y, w, S(2), C.white)
        dxDrawRectangle(x, y + h - S(2), w, S(2), C.white)
    end
    text("!", x + S(22), y, S(30), h, C_WARN, 1.6, FONT.head, "center", "center")
    text(L("v_mainmenu.models.reminder", { count = count, size = mbText(bytes) }), x + S(66), y, w - S(400), h, C.white, 1.05, FONT.rowB)
    local hint = L("v_mainmenu.models.reminder_hint")
    text(hint, x + w - S(330), y, S(310), h, focused and C.white or C.faint, 0.95, FONT.rowB, "right", "center")
    return h + S(14)
end

-- ---------------------------------------------------------------------------
-- first-entry modal
-- ---------------------------------------------------------------------------

local function closeNotice(openSettings)
    ModelsNotice.open = false
    Menu.data.modelsNotice = false
    triggerServerEvent("v_mainmenu:modelsNoticeSeen", localPlayer)
    playUI("select")
    if openSettings then openModelSettings() end
end

local buttons = {}   -- this frame's button rects of the modal

function ModelsNotice.draw()
    if not ModelsNotice.open then return end
    local sw, sh = guiGetScreenSize()
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 190))
    local w, h = S(820), S(380)
    local x, y = (sw - w) / 2, (sh - h) / 2
    dxDrawRectangle(x, y, w, h, tocolor(20, 16, 10, 250))
    dxDrawRectangle(x, y, w, S(8), C_WARN)
    dxDrawRectangle(x, y + h - S(2), w, S(2), C_WARN)

    local pad = S(40)
    text("!", x + pad, y + S(44), S(60), S(60), C_WARN, 2.6, FONT.big, "left", "center")
    text(L.upper(L("v_mainmenu.models.notice_title")), x + pad + S(70), y + S(44), w - pad * 2 - S(70), S(60), C.white, 1.5, FONT.head, "left", "center")
    local s = modloaderRunning() and exports.v_modloader:getModelStatus("vehicles") or nil
    text(L("v_mainmenu.models.notice_body", { size = mbText(s and s.totalBytes or 0) }), x + pad, y + S(130), w - pad * 2, S(140),
        C.text, 1.1, FONT.row, "left", "top", true, true)

    buttons = {}
    local bw, bh = (w - pad * 2 - S(16)) / 2, S(56)
    local by = y + h - pad - bh
    local defs = { { "v_mainmenu.models.notice_open", true }, { "v_mainmenu.models.notice_later", false } }
    for i, d in ipairs(defs) do
        local bx = x + pad + (i - 1) * (bw + S(16))
        local mx, my = cursorPos()
        local hover = mx >= bx and mx <= bx + bw and my >= by and my <= by + bh
        local on = ModelsNotice.sel == i or hover
        local bg = i == 1 and (on and tocolor(226, 146, 50, 255) or C_WARN) or (on and C.ghostFoc or C.ghost)
        dxDrawRectangle(bx, by, bw, bh, bg)
        if ModelsNotice.sel == i then dxDrawRectangle(bx, by + bh - S(3), bw, S(3), C.white) end
        text(L(d[1]), bx, by, bw, bh, C.white, 1.1, FONT.rowB, "center", "center")
        buttons[i] = { x = bx, y = by, w = bw, h = bh, settings = d[2] }
    end
end

--- core.lua input: true = the modal took the key
function ModelsNotice.key(key)
    if not ModelsNotice.open then return false end
    if key == "arrow_l" or key == "arrow_r" or key == "tab" then
        ModelsNotice.sel = ModelsNotice.sel == 1 and 2 or 1
        playUI("move")
    elseif key == "enter" or key == "num_enter" then
        closeNotice(ModelsNotice.sel == 1)
    elseif key == "backspace" or key == "escape" then
        closeNotice(false)
    end
    return true
end

function ModelsNotice.click(px, py)
    if not ModelsNotice.open then return false end
    for _, b in ipairs(buttons) do
        if px >= b.x and px <= b.x + b.w and py >= b.y and py <= b.y + b.h then
            closeNotice(b.settings)
            break
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- the menu opened (core.lua Menu.show): modal, Auto-update
-- ---------------------------------------------------------------------------

function onMenuShownModels(reopened)
    if reopened then return end
    ModelsNotice.sel = 1
    ModelsNotice.open = Menu.data.modelsNotice == true
    -- the saved settings arrive with the login; give them a moment
    setTimer(function()
        if Menu.open and not ModelsNotice.open and modloaderRunning() then
            pcall(function() exports.v_modloader:autoUpdate() end)
        end
    end, 1000, 1)
end

-- ---------------------------------------------------------------------------
-- download screen: the menu hides and comes back where it was
-- ---------------------------------------------------------------------------

local hiddenState = nil

addEvent("onClientModelDownloadStart")
addEventHandler("onClientModelDownloadStart", root, function()
    if not Menu.open then return end
    hiddenState = {
        page = Menu.page, layer = Menu.layer, view = Menu.view,
        focus = { tabs = Menu.focus.tabs, page = Menu.focus.page, view = Menu.focus.view },
    }
    Menu.hide()
end)

addEvent("onClientModelDownloadFinish")
addEventHandler("onClientModelDownloadFinish", root, function()
    local st = hiddenState
    if not st then return end
    hiddenState = nil
    if getElementData(localPlayer, "isLogged") ~= true or getElementData(localPlayer, "loaded") == true then return end
    Menu.show(Menu.data, true)
    Menu.page, Menu.layer, Menu.view = st.page, st.layer, st.view
    Menu.focus = st.focus
    local def = PAGES.defs[Menu.page]
    if def and def.onShow then def.onShow() end
    if Menu.view and VIEWS[Menu.view.id] and VIEWS[Menu.view.id].onOpen then VIEWS[Menu.view.id].onOpen(Menu.view.args) end
end)
