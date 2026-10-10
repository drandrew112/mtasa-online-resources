-- ============================================================
--  v_admin / client/panel/core.lua
--  Admin panel (O key) – window, tabs and the immediate-mode DX
--  widgets every tab uses:
--    AP.button / AP.area / AP.text   – drawing + click targets
--    AP.field                        – in-panel text field (keyboard
--                                      goes through onClientCharacter)
--  While the panel is open every key bind is off (guiSetInputMode
--  "no_binds"); while a field is focused every key press is cancelled
--  and "textInputOpen" is set as well.
--    AP.openDropdown                 – a list drawn on top of everything
--    AP.scrollArea                   – mouse-wheel region
--  The tabs live in players.lua / reports.lua / server.lua / commands.lua
--  and register themselves with AP.addTab.
-- ============================================================

local uicore = exports.ui_core
local E = ADMIN.events

AP = {
    open     = false,
    players  = {},
    myLevel  = 0,
    tab      = "players",
    scale    = 1,
    tabs     = {},
    fields   = {},      -- [id] = { text, max, numeric, onEnter }
    focus    = nil,     -- focused field id
    dropdown = nil,     -- { x, y, w, items = { { label, fn, disabled } } }
}

local buttons, hitList = {}, {}
local scrolls, scrollList = {}, {}
local refreshTimer

function AP.S(v) return v * AP.scale end
function AP.F(v) return v * AP.scale * (ADMIN.panel.fontScale or 1) end
local S, F = AP.S, AP.F

AP.C = {
    bg        = tocolor(14, 16, 24, 245),
    side      = tocolor(20, 23, 34, 255),
    row       = tocolor(26, 30, 44, 255),
    rowHot    = tocolor(34, 39, 56, 255),
    btn       = tocolor(40, 46, 66, 255),
    btnHot    = tocolor(58, 66, 94, 255),
    btnOff    = tocolor(30, 33, 44, 255),
    field     = tocolor(9, 11, 17, 255),
    accent    = tocolor(0, 130, 220, 255),
    text      = tocolor(235, 238, 245, 255),
    dim       = tocolor(150, 158, 175, 255),
    off       = tocolor(90, 96, 110, 255),
    head      = tocolor(0, 150, 255, 255),
    good      = tocolor(110, 220, 130, 255),
    warn      = tocolor(255, 200, 90, 255),
    bad       = tocolor(255, 95, 95, 255),
    danger    = tocolor(150, 45, 45, 255),
    dangerHot = tocolor(190, 65, 65, 255),
    shadow    = tocolor(0, 0, 0, 160),
}
local C = AP.C

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

function AP.permLevel(perm)
    if not perm then return 0 end
    return ADMIN.perms[perm] or 99
end

function AP.can(perm)
    return AP.myLevel >= AP.permLevel(perm)
end

function AP.rankName(level)
    return ADMIN.rankNames[tonumber(level) or 0] or "Player"
end

function AP.fmtInt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local neg = s:sub(1, 1) == "-"
    if neg then s = s:sub(2) end
    s = s:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    return (neg and "-" or "") .. s
end

function AP.notify(text)
    uicore:addNotification("Admin panel", text, true)
end

function AP.sendAction(action, targetId, a, b)
    triggerServerEvent(E.panelAction, resourceRoot, action, targetId, a, b)
end

function AP.cursor()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    local sw, sh = guiGetScreenSize()
    return cx * sw, cy * sh
end

local function inRect(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function AP.hovered(x, y, w, h, layer)
    local mx, my = AP.cursor()
    if not inRect(mx, my, x, y, w, h) then return false end
    local d = AP.dropRect
    if layer ~= "dropdown" and d and inRect(mx, my, d.x, d.y, d.w, d.h) then return false end
    return true
end

-- Word-wrap plain text into lines that fit `w` at font size `size`.
function AP.wrap(str, w, size, font)
    font = font or "default"
    local sc = F(size or 1)
    local lines = {}
    for para in (tostring(str) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            local try = line == "" and word or (line .. " " .. word)
            if dxGetTextWidth(try, sc, font) <= w or line == "" then
                line = try
            else
                lines[#lines + 1] = line
                line = word
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

--------------------------------------------------------------------------------
-- widgets
--------------------------------------------------------------------------------

function AP.text(str, x, y, w, h, color, size, font, ax, ay, clip, wrap, coded)
    dxDrawText(str, x, y, x + w, y + h, color or C.text, F(size or 1), font or "default",
        ax or "left", ay or "center", clip ~= false, wrap or false, false, coded or false)
end

function AP.area(x, y, w, h, fn, layer)
    buttons[#buttons + 1] = { x = x, y = y, w = w, h = h, fn = fn, layer = layer }
end

-- style: nil | "active" | "danger" | "off" | "good"
function AP.button(x, y, w, h, label, fn, style, sub, layer)
    local hot = style ~= "off" and AP.hovered(x, y, w, h, layer)
    local col
    if style == "active" then col = C.accent
    elseif style == "danger" then col = hot and C.dangerHot or C.danger
    elseif style == "off" then col = C.btnOff
    else col = hot and C.btnHot or C.btn end
    dxDrawRectangle(x, y, w, h, col, layer == "dropdown")
    local tc = style == "off" and C.off or C.text
    if sub then
        dxDrawText(label, x, y, x + w, y + h * 0.58, tc, F(0.95), "default-bold", "center", "bottom", true, false, layer == "dropdown")
        dxDrawText(sub, x, y + h * 0.56, x + w, y + h, style == "off" and C.off or C.dim, F(0.75), "default", "center", "top", true, false, layer == "dropdown")
    else
        dxDrawText(label, x, y, x + w, y + h, tc, F(0.95), "default-bold", "center", "center", true, false, layer == "dropdown")
    end
    if fn and style ~= "off" then AP.area(x, y, w, h, fn, layer) end
end

function AP.scrollArea(x, y, w, h, fn)
    scrolls[#scrolls + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

--------------------------------------------------------------------------------
-- text fields
--------------------------------------------------------------------------------

function AP.setFocus(id)
    if AP.focus == id then return end
    AP.focus = id
    setElementData(localPlayer, "textInputOpen", id and true or false, false)
end

function AP.fieldText(id)
    local f = AP.fields[id]
    return f and f.text or ""
end

function AP.setField(id, text)
    AP.fields[id] = AP.fields[id] or { text = "" }
    AP.fields[id].text = tostring(text or "")
end

-- opts: { placeholder, max, numeric, onEnter }
function AP.field(id, x, y, w, h, opts)
    opts = opts or {}
    local f = AP.fields[id]
    if not f then
        f = { text = "" }
        AP.fields[id] = f
    end
    f.max, f.numeric, f.onEnter = opts.max or 64, opts.numeric, opts.onEnter

    local focused = AP.focus == id
    dxDrawRectangle(x, y, w, h, focused and C.accent or C.btn)
    dxDrawRectangle(x + S(2), y + S(2), w - S(4), h - S(4), C.field)

    local pad = S(10)
    local sc = F(0.95)
    local shown = f.text
    while shown ~= "" and dxGetTextWidth(shown, sc, "default") > w - pad * 2 - S(4) do
        shown = utf8.sub(shown, 2)
    end
    if f.text == "" and not focused then
        AP.text(opts.placeholder or "", x + pad, y, w - pad * 2, h, C.off, 0.95)
    else
        AP.text(shown, x + pad, y, w - pad * 2, h, C.text, 0.95)
    end
    if focused and getTickCount() % 1000 < 520 then
        local cx = x + pad + dxGetTextWidth(shown, sc, "default") + S(1)
        dxDrawRectangle(cx, y + h * 0.22, S(2), h * 0.56, C.text)
    end
    AP.area(x, y, w, h, function() AP.setFocus(id) end)
end

local function fieldInsert(str)
    local f = AP.focus and AP.fields[AP.focus]
    if not f then return end
    str = tostring(str)
    for i = 1, utf8.len(str) or 0 do
        local ch = utf8.sub(str, i, i)
        if (utf8.len(f.text) or #f.text) >= f.max then return end
        if not f.numeric or ch:match("^%d$") then
            f.text = f.text .. ch
        end
    end
end

addEventHandler("onClientCharacter", root, function(ch)
    if not AP.open or not AP.focus then return end
    if ch:byte() and ch:byte() < 32 then return end
    fieldInsert(ch)
end)

addEventHandler("onClientPaste", root, function(text)
    if not AP.open or not AP.focus then return end
    fieldInsert((tostring(text):gsub("[\r\n\t]", " ")))
end)

--------------------------------------------------------------------------------
-- dropdown
--------------------------------------------------------------------------------

-- items: { { label = "...", fn = function, disabled = bool, active = bool } }
function AP.openDropdown(x, y, w, items)
    AP.dropdown = { x = x, y = y, w = w, items = items }
end

local function drawDropdown()
    local d = AP.dropdown
    AP.dropRect = nil
    if not d then return end
    local ih = S(44)
    local h = #d.items * ih + S(8)
    local sw, sh = guiGetScreenSize()
    local y = d.y
    if y + h > sh - S(10) then y = sh - S(10) - h end
    AP.dropRect = { x = d.x, y = y, w = d.w, h = h }

    dxDrawRectangle(d.x + S(4), y + S(4), d.w, h, C.shadow, true)
    dxDrawRectangle(d.x, y, d.w, h, C.side, true)
    dxDrawRectangle(d.x, y, d.w, S(3), C.accent, true)
    for i, it in ipairs(d.items) do
        local style = it.disabled and "off" or (it.active and "active" or nil)
        AP.button(d.x + S(4), y + S(6) + (i - 1) * ih, d.w - S(8), ih - S(4), it.label, function()
            AP.dropdown = nil
            it.fn()
        end, style, nil, "dropdown")
    end
end

--------------------------------------------------------------------------------
-- tabs
--------------------------------------------------------------------------------

-- def: { id, label = string|function, perm, draw(x, y, w, h), onShow(), order }
function AP.addTab(def)
    AP.tabs[#AP.tabs + 1] = def
    table.sort(AP.tabs, function(a, b) return (a.order or 0) < (b.order or 0) end)
end

local function getTab(id)
    for _, t in ipairs(AP.tabs) do
        if t.id == id then return t end
    end
end

function AP.setTab(id)
    local t = getTab(id)
    if not t or not AP.can(t.perm) then return end
    AP.tab = id
    AP.dropdown = nil
    AP.setFocus(nil)
    if t.onShow then t.onShow() end
end

--------------------------------------------------------------------------------
-- window
--------------------------------------------------------------------------------

local function drawPanel()
    if not AP.open then return end
    buttons, scrolls = {}, {}

    local sw, sh = guiGetScreenSize()
    local W, H = math.min(S(1640), sw - S(30)), math.min(S(980), sh - S(30))
    local X, Y = (sw - W) / 2, (sh - H) / 2
    local pad = S(18)

    dxDrawRectangle(X, Y, W, H, C.bg)
    dxDrawRectangle(X, Y, W, S(4), C.accent)
    AP.text("ADMIN PANEL", X + pad, Y + S(12), S(320), S(48), C.head, 1.7, "default-bold")
    AP.text(("Your level: %d  %s"):format(AP.myLevel, AP.rankName(AP.myLevel)),
        X + pad + S(320), Y + S(12), S(400), S(48), C.dim, 1.0)

    -- tabs (right aligned) + close
    local tabW, tabH = S(170), S(44)
    local closeW = S(48)
    local tx = X + W - pad - closeW - S(10)
    for i = #AP.tabs, 1, -1 do
        local t = AP.tabs[i]
        tx = tx - tabW
        local label = type(t.label) == "function" and t.label() or t.label
        local style = not AP.can(t.perm) and "off" or (AP.tab == t.id and "active" or nil)
        AP.button(tx, Y + S(14), tabW, tabH, label, function() AP.setTab(t.id) end, style)
        tx = tx - S(6)
    end
    AP.button(X + W - pad - closeW, Y + S(14), closeW, tabH, "X", AP.close, "danger")

    local cx, cy = X + pad, Y + S(76)
    local cw, ch = W - pad * 2, H - S(76) - pad
    local t = getTab(AP.tab)
    if t then t.draw(cx, cy, cw, ch) end

    drawDropdown()
end

-- publish the finished frame's click / scroll targets
local function publish()
    if AP.open then hitList, scrollList = buttons, scrolls end
end

function AP.close()
    if not AP.open then return end
    AP.open = false
    AP.dropdown, AP.dropRect = nil, nil
    AP.setFocus(nil)
    buttons, hitList, scrolls, scrollList = {}, {}, {}, {}
    if isTimer(refreshTimer) then killTimer(refreshTimer) end
    refreshTimer = nil
    removeEventHandler("onClientRender", root, drawPanel)
    removeEventHandler("onClientRender", root, publish)
    setElementData(localPlayer, "adminPanelOpen", false, false)
    guiSetInputMode("allow_binds")
    showCursor(false)
    uicore:toggleMoveControls(true)
    for _, t in ipairs(AP.tabs) do
        if t.onClose then t.onClose() end
    end
end

local function openPanel(tab)
    AP.scale = math.max(0.6, tonumber(uicore:ui(1)) or 1) * (ADMIN.panel.size or 1)
    AP.open = true
    addEventHandler("onClientRender", root, drawPanel)
    addEventHandler("onClientRender", root, publish, false, "low-10")
    setElementData(localPlayer, "adminPanelOpen", true, false)
    guiSetInputMode("no_binds")     -- every bindKey of every resource is off while open
    showCursor(true)
    uicore:toggleMoveControls(false)
    refreshTimer = setTimer(function()
        if AP.open then triggerServerEvent(E.panelRequest, resourceRoot, true) end
    end, ADMIN.panel.refresh, 0)
    AP.tab = "players"
    AP.setTab(tab or "players")
end

addEvent(E.panelData, true)
addEventHandler(E.panelData, resourceRoot, function(players, myLevel, isRefresh, tab)
    if not players then return AP.close() end
    AP.players = players
    AP.myLevel = myLevel
    if AP.open then
        if tab then AP.setTab(tab) end
        return
    end
    if not isRefresh then openPanel(tab) end
end)

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function otherPanelOpen()
    for _, key in ipairs({ "paused", "socialPanelOpen", "phoneOpen", "browserOpen", "showChatInput",
                           "reportPanelOpen", "textInputOpen", "interactionMenuOpen" }) do
        if getElementData(localPlayer, key) then return true end
    end
    return isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
end

bindKey(ADMIN.panel.key, "down", function()
    if AP.open then return end
    if (tonumber(getElementData(localPlayer, "admin_level")) or 0) < ADMIN.perms.panel then return end
    if otherPanelOpen() then return end
    triggerServerEvent(E.panelRequest, resourceRoot, false)
end)

local function wheel(dir)
    local mx, my = AP.cursor()
    for i = #scrollList, 1, -1 do
        local s = scrollList[i]
        if inRect(mx, my, s.x, s.y, s.w, s.h) then
            s.fn(dir)
            return
        end
    end
end

addEventHandler("onClientKey", root, function(key, press)
    if not AP.open or not press then return end

    if key == "mouse_wheel_up" then return wheel(-1) end
    if key == "mouse_wheel_down" then return wheel(1) end

    if AP.focus then
        -- Typing: swallow every key (characters still arrive via onClientCharacter).
        if not key:find("^mouse") then cancelEvent() end
        local f = AP.fields[AP.focus]
        if key == "backspace" then
            if f and f.text ~= "" then f.text = utf8.sub(f.text, 1, (utf8.len(f.text) or 1) - 1) end
        elseif key == "enter" or key == "num_enter" then
            if f and f.onEnter then f.onEnter(f.text) end
        elseif key == "escape" or key == "tab" then
            AP.setFocus(nil)
        end
        return
    end

    if key == "escape" then
        cancelEvent()
        if AP.dropdown then AP.dropdown = nil else AP.close() end
    elseif key == ADMIN.panel.key then
        -- the O bind is off while the panel is open (no_binds), so close here
        cancelEvent()
        AP.close()
    end
end)

addEventHandler("onClientClick", root, function(btn, state)
    if not AP.open or btn ~= "left" or state ~= "down" then return end
    local mx, my = AP.cursor()

    if AP.dropdown then
        for i = #hitList, 1, -1 do
            local b = hitList[i]
            if b.layer == "dropdown" and inRect(mx, my, b.x, b.y, b.w, b.h) then
                return b.fn()
            end
        end
        AP.dropdown = nil
        return
    end

    AP.setFocus(nil)
    for i = #hitList, 1, -1 do
        local b = hitList[i]
        if inRect(mx, my, b.x, b.y, b.w, b.h) then
            return b.fn()
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if AP.open then AP.close() end
end)
