if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- acc_menu core: the full-screen tile menu between the login and the loading.
--
-- Immediate-mode DX: every frame each drawn element that can take the focus
-- registers itself (Menu.reg) with its rect and handlers. The focus is kept by
-- element id, per layer:
--   tabs   the page selector on top
--   page   the tiles of the current page
--   view   what a tile opened (Profile > Statistics, Social > Messages, ...)
-- Arrows move the focus to the nearest element in that direction (left / right
-- go to the element's own handler first, e.g. a setting's value), Enter
-- activates, Backspace / Esc go back one layer, the mouse clicks / scrolls.
-- No other resource's binds are used: everything works through APIs
-- (acc_auth, acc_savesys via the server, ui_pause, v_socialpanel, acc_ui).

local sw, sh = guiGetScreenSize()
local SC = math.max(0.6, sh / 1080)
function S(v) return v * SC end

C = {
    shade    = tocolor(6, 9, 12, 200),
    tile     = tocolor(16, 20, 26, 225),
    tileFoc  = tocolor(28, 36, 46, 245),
    tileLine = tocolor(255, 255, 255, 12),
    join1    = tocolor(47, 138, 160, 255),
    join2    = tocolor(23, 72, 90, 255),
    accent   = tocolor(64, 156, 180, 255),
    accentDim= tocolor(64, 156, 180, 60),
    textSel  = tocolor(64, 156, 180, 120),
    text     = tocolor(228, 233, 238, 255),
    white    = tocolor(255, 255, 255, 255),
    dim      = tocolor(146, 158, 170, 255),
    faint    = tocolor(255, 255, 255, 140),
    money    = tocolor(110, 220, 130, 255),
    bank     = tocolor(120, 180, 255, 255),
    xp       = tocolor(255, 200, 90, 255),
    bad      = tocolor(230, 100, 100, 255),
    field    = tocolor(32, 36, 42, 255),
    btn      = tocolor(40, 118, 136, 255),
    btnFoc   = tocolor(64, 156, 180, 255),
    ghost    = tocolor(38, 43, 50, 255),
    ghostFoc = tocolor(64, 72, 82, 255),
    bar      = tocolor(255, 255, 255, 26),
    row      = tocolor(255, 255, 255, 6),
    rowSel   = tocolor(64, 156, 180, 55),
}

FONT = {}

Menu = {
    open = false,
    page = "home",
    layer = "page",
    focus = { tabs = "home", page = nil, view = nil },
    view = nil,          -- { id, args, fromTile }
    data = {},           -- server payload (profile, stats, vehicles, news, weekly, ...)
}

PAGES = { order = { "home", "profile", "social", "settings" }, defs = {} }
VIEWS = {}

-- area of the page / view content (set every frame)
AREA = { x = 0, y = 0, w = 0, h = 0 }

local regs = { tabs = {}, page = {}, view = {} }      -- this frame's focusables
local lastRegs = { tabs = {}, page = {}, view = {} }  -- previous frame's (for navigation)
local wheels = {}

--------------------------------------------------------------------------------
-- registration / helpers
--------------------------------------------------------------------------------

function Menu.reg(layer, id, x, y, w, h, opts)
    opts = opts or {}
    opts.id, opts.x, opts.y, opts.w, opts.h, opts.layer = id, x, y, w, h, layer
    regs[layer][#regs[layer] + 1] = opts
    return Menu.layer == layer and Menu.focus[layer] == id
end

function Menu.wheel(x, y, w, h, fn)
    wheels[#wheels + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

function Menu.isFocused(layer, id)
    return Menu.layer == layer and Menu.focus[layer] == id
end

local function inRect(px, py, r)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

function cursorPos()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    return cx * sw, cy * sh
end

-- the dx fonts are created at the screen's size (scale 1); the built-in
-- fallback fonts ("default", ...) need the screen scale
function fontScale(font)
    return isElement(font) and 1 or SC
end

function text(str, x, y, w, h, color, scale, font, alignX, alignY, clip, wrap)
    font = font or FONT.row
    dxDrawText(tostring(str or ""), x, y, x + w, y + h, color or C.text, (scale or 1) * fontScale(font), font,
        alignX or "left", alignY or "center", clip ~= false, wrap == true)
end

function textW(str, scale, font)
    font = font or FONT.row
    return dxGetTextWidth(tostring(str or ""), (scale or 1) * fontScale(font), font)
end

function bar(x, y, w, h, frac, color)
    dxDrawRectangle(x, y, w, h, C.bar)
    dxDrawRectangle(x, y, w * math.max(0, math.min(1, frac or 0)), h, color or C.accent)
end

function chip(str, x, y, color, bg)
    local w = textW(str, 0.85, FONT.rowB) + S(14)
    dxDrawRectangle(x, y, w, S(22), bg or tocolor(255, 255, 255, 26))
    text(str, x, y, w, S(22), color or C.white, 0.85, FONT.rowB, "center", "center")
    return w
end

function fmtInt(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^%s+", ""):gsub("^%- ", "-"))
end

function fmtDuration(sec)
    sec = math.floor(tonumber(sec) or 0)
    local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
    if h > 0 then return ("%dh %02dm"):format(h, m) end
    return ("%dm"):format(m)
end

function notify(str)
    if str and str ~= "" then exports.ui_core:addNotification(L("acc_menu.title"), str) end
end

--------------------------------------------------------------------------------
-- widgets
--------------------------------------------------------------------------------

-- A tile. content(x, y, w, h, focused) draws inside; activate() on Enter / click.
function tile(layer, id, x, y, w, h, title, subtitle, content, activate, style)
    local focused = Menu.reg(layer, id, x, y, w, h, { activate = activate })
    if style == "join" then
        dxDrawRectangle(x, y, w, h, C.join2)
        dxDrawRectangle(x, y, w, h * 0.55, C.join1)
    else
        dxDrawRectangle(x, y, w, h, focused and C.tileFoc or C.tile)
        dxDrawRectangle(x, y, w, 1, C.tileLine)
    end
    if focused then
        local t = S(3)
        dxDrawRectangle(x, y, w, t, C.white)
        dxDrawRectangle(x, y + h - t, w, t, C.white)
        dxDrawRectangle(x, y, t, h, C.white)
        dxDrawRectangle(x + w - t, y, t, h, C.white)
        dxDrawRectangle(x + t, y + h - S(7), w - t * 2, S(4), C.accent)
    end
    local pad = S(18)
    -- the clip box must fit the scaled font, or the bottom of the letters is cut
    local ts = style == "join" and 2.1 or 1.15
    local th = math.max(S(26), dxGetFontHeight(ts * fontScale(FONT.head), FONT.head))
    if title then
        text(L.upper(title), x + pad, y + pad, w - pad * 2, th, C.white, ts, FONT.head, "left", "top")
    end
    if subtitle then
        text(subtitle, x + pad, y + pad + (style == "join" and th + S(4) or S(28)), w - pad * 2, S(20), style == "join" and C.text or C.dim, 0.95, FONT.row, "left", "top")
    end
    if content then content(x + pad, y + pad, w - pad * 2, h - pad * 2, focused) end
    return focused
end

-- style: "primary" | "ghost" | "danger"
function button(layer, id, x, y, w, h, label, fn, style)
    local focused = Menu.reg(layer, id, x, y, w, h, { activate = fn })
    local mx, my = cursorPos()
    local hover = mx >= x and mx <= x + w and my >= y and my <= y + h
    local bg
    if style == "ghost" then bg = (focused or hover) and C.ghostFoc or C.ghost
    elseif style == "danger" then bg = (focused or hover) and tocolor(170, 60, 60, 255) or tocolor(122, 45, 45, 255)
    else bg = (focused or hover) and C.btnFoc or C.btn end
    dxDrawRectangle(x, y, w, h, bg)
    if focused then dxDrawRectangle(x, y + h - S(3), w, S(3), C.white) end
    text(label, x, y, w, h, C.white, 1.0, FONT.rowB, "center", "center")
    return focused
end

-- A text field (TextField from field.lua). onEnter(text) on Enter.
function field(layer, id, x, y, w, h, tf, placeholder, onEnter, masked)
    local focused = Menu.reg(layer, id, x, y, w, h, { field = tf, onEnter = onEnter, masked = masked })
    dxDrawRectangle(x, y, w, h, C.field)
    dxDrawRectangle(x, y, S(3), h, C.accent)
    if focused then
        dxDrawRectangle(x, y + h - S(2), w, S(2), C.accent)
    end
    local pad = S(12)
    local style = { font = FONT.row, scale = fontScale(FONT.row), color = C.text, caret = C.white, sel = C.textSel }
    if tf:getText() == "" and not focused then
        text(placeholder or "", x + pad, y, w - pad * 2, h, C.dim, 1.0, FONT.row)
    elseif masked then
        local shown = TextField.new{ max = 200 }
        shown:setText(("•"):rep(utf8.len(tf:getText()) or 0))
        shown.caret, shown.anchor = tf.caret, tf.anchor
        shown:draw(x + pad, y, w - pad * 2, h, focused, style)
        -- one dot per char: clicks / drags on tf map through the dots' layout
        tf.drawRect, tf.layout, tf.layoutKey, tf.shift = shown.drawRect, shown.layout, nil, shown.shift
        tf.font, tf.scale = shown.font, shown.scale
    else
        tf:draw(x + pad, y, w - pad * 2, h, focused, style)
    end
    return focused
end

-- A selectable list row; left/right handlers make it a value row (settings).
function row(layer, id, x, y, w, h, opts)
    local focused = Menu.reg(layer, id, x, y, w, h, opts)
    dxDrawRectangle(x, y, w, h, focused and C.rowSel or C.row)
    if focused then dxDrawRectangle(x, y, S(3), h, C.accent) end
    return focused
end

function panelBox(x, y, w, h)
    dxDrawRectangle(x, y, w, h, C.tile)
    dxDrawRectangle(x, y, w, 1, C.tileLine)
end

function heading(str, x, y, w)
    text(L.upper(str), x, y, w, S(24), C.white, 1.1, FONT.head, "left", "center")
end

--------------------------------------------------------------------------------
-- navigation
--------------------------------------------------------------------------------

local function findReg(layer, id)
    for _, r in ipairs(lastRegs[layer]) do
        if r.id == id then return r end
    end
end

local function center(r) return r.x + r.w / 2, r.y + r.h / 2 end

-- nearest focusable in direction dir ("l","r","u","d") from `from`
local function nearest(layer, from, dir)
    local fx, fy = center(from)
    local best, bestScore
    for _, r in ipairs(lastRegs[layer]) do
        if r.id ~= from.id then
            local cx, cy = center(r)
            local dx, dy = cx - fx, cy - fy
            local primary, secondary
            if dir == "l" then primary, secondary = -dx, dy
            elseif dir == "r" then primary, secondary = dx, dy
            elseif dir == "u" then primary, secondary = -dy, dx
            else primary, secondary = dy, dx end
            if primary > 1 then
                local score = primary + math.abs(secondary) * 2.2
                if not bestScore or score < bestScore then best, bestScore = r, score end
            end
        end
    end
    return best
end

function Menu.setFocus(layer, id)
    local old = findReg(Menu.layer, Menu.focus[Menu.layer])
    if old and old.field and old.id ~= id then old.field.anchor = nil end
    Menu.layer = layer
    Menu.focus[layer] = id
    local r = findReg(layer, id)
    setElementData(localPlayer, "textInputOpen", (r and r.field) and true or false, false)
end

function Menu.setPage(id)
    if not PAGES.defs[id] then return end
    Menu.page = id
    Menu.view = nil
    Menu.focus.page = nil
    Menu.focus.tabs = id
    local def = PAGES.defs[id]
    if def.onShow then def.onShow() end
end

function Menu.openView(id, args)
    local v = VIEWS[id]
    if not v then return end
    Menu.view = { id = id, args = args or {}, fromTile = Menu.focus.page, fromPage = Menu.page }
    Menu.focus.view = nil
    Menu.layer = "view"
    if v.onOpen then v.onOpen(Menu.view.args) end
end

-- opens a view of another page (Home shortcuts)
function Menu.goto(pageId, viewId, args)
    Menu.setPage(pageId)
    if viewId then Menu.openView(viewId, args) else Menu.layer = "page" end
end

function Menu.back()
    if Menu.layer == "view" and Menu.view then
        local v = VIEWS[Menu.view.id]
        if v and v.onBack and v.onBack(Menu.view.args) then return end -- the view handled it (inner step)
        local from = Menu.view.fromTile
        Menu.view = nil
        Menu.layer = "page"
        Menu.focus.page = from
        setElementData(localPlayer, "textInputOpen", false, false)
    elseif Menu.layer == "page" then
        Menu.layer = "tabs"
        Menu.focus.tabs = Menu.page
    end
end

local function move(dir)
    local layer = Menu.layer
    local cur = findReg(layer, Menu.focus[layer])
    if not cur then
        local first = lastRegs[layer][1]
        if first then Menu.setFocus(layer, first.id) end
        return
    end
    local target = nearest(layer, cur, dir)
    if target then
        Menu.setFocus(layer, target.id)
        if layer == "tabs" then Menu.setPage(target.id) end
        playUI("move")
    elseif dir == "u" and layer == "page" then
        Menu.setFocus("tabs", Menu.page)
        playUI("move")
    elseif dir == "d" and layer == "tabs" then
        Menu.layer = "page"
    end
end

local function activate(r)
    if not r then return end
    if r.layer == "tabs" then
        Menu.setPage(r.id)
        Menu.layer = "page"
        playUI("select")
    elseif r.field then
        if r.onEnter then r.onEnter(r.field:getText()) end
    elseif r.activate then
        playUI("select")
        r.activate()
    end
end

--------------------------------------------------------------------------------
-- sounds
--------------------------------------------------------------------------------

function playUI(kind)
    local s = playSound(kind == "select" and "files/select.wav" or "files/click.wav")
    if isElement(s) then setSoundVolume(s, 0.4) end
end

--------------------------------------------------------------------------------
-- frame
--------------------------------------------------------------------------------

local function drawTop()
    local h = S(92)
    dxDrawRectangle(0, 0, sw, h, tocolor(0, 0, 0, 120))
    local x = S(60)
    dxDrawRectangle(x, S(22), S(48), S(48), C.accent)
    text("FV", x, S(22), S(48), S(48), C.white, 1.3, FONT.head, "center", "center")
    x = x + S(90)
    for _, id in ipairs(PAGES.order) do
        local def = PAGES.defs[id]
        local label = L.upper(L(def.label))
        local w = textW(label, 1.25, FONT.head) + S(8)
        local focused = Menu.reg("tabs", id, x - S(4), S(26), w + S(8), S(40), {})
        local on = Menu.page == id
        text(label, x, S(26), w, S(40), on and C.white or C.faint, 1.25, FONT.head, "left", "center")
        if on then dxDrawRectangle(x, S(66), w - S(8), S(3), C.accent) end
        if focused then
            dxDrawRectangle(x - S(10), S(22), w + S(12), S(2), C.white)
            dxDrawRectangle(x - S(10), S(70), w + S(12), S(2), C.white)
        end
        x = x + w + S(40)
    end

    local p = Menu.data.profile or {}
    local rx = sw - S(60)
    local name = tostring(p.account or getElementData(localPlayer, "accName") or "")
    local nw = textW(name, 1.1, FONT.rowB)
    text(name, rx - nw, S(26), nw, S(40), C.white, 1.1, FONT.rowB, "right", "center")
    rx = rx - nw - S(16)
    local lvl = L("acc_menu.top.level", { level = p.level or 1 })
    local lw = textW(lvl, 0.95, FONT.rowB) + S(16)
    dxDrawRectangle(rx - lw, S(34), lw, S(24), C.accent)
    text(lvl, rx - lw, S(34), lw, S(24), C.white, 0.95, FONT.rowB, "center", "center")
    rx = rx - lw - S(16)
    local money = "€ " .. fmtInt(p.money or 0)
    local mw = textW(money, 1.1, FONT.rowB)
    text(money, rx - mw, S(26), mw, S(40), C.money, 1.1, FONT.rowB, "right", "center")
    rx = rx - mw - S(16)
    local bank = "€ " .. fmtInt(p.bank or 0)
    local bw = textW(bank, 1.1, FONT.rowB)
    text(bank, rx - bw, S(26), bw, S(40), C.bank, 1.1, FONT.rowB, "right", "center")
end

local function drawHint()
    local y = sh - S(52)
    local x = S(60)
    local keys
    if Menu.layer == "view" then
        keys = { { "ARROWS", "acc_menu.hint.navigate" }, { "ENTER", "acc_menu.hint.select" }, { "BACKSPACE", "acc_menu.hint.back" } }
    else
        keys = { { "ARROWS", "acc_menu.hint.navigate" }, { "ENTER", "acc_menu.hint.select" }, { "BACKSPACE", "acc_menu.hint.back" }, { "MOUSE", "acc_menu.hint.click" } }
    end
    for _, k in ipairs(keys) do
        local kw = textW(k[1], 0.8, FONT.rowB) + S(14)
        dxDrawRectangle(x, y, kw, S(24), tocolor(255, 255, 255, 30))
        text(k[1], x, y, kw, S(24), C.white, 0.8, FONT.rowB, "center", "center")
        x = x + kw + S(8)
        local label = L(k[2])
        local w = textW(label, 0.9, FONT.row)
        text(label, x, y, w, S(24), C.faint, 0.9, FONT.row)
        x = x + w + S(28)
    end
end

local dragging, dragFrom = nil, nil -- TextField under a held left click / press point (selection)

local function render()
    if dragging then
        if getKeyState("mouse1") and isCursorShowing() then
            local cx, cy = cursorPos()
            if dragFrom and math.abs(cx - dragFrom[1]) + math.abs(cy - dragFrom[2]) > 3 then dragFrom = nil end
            if not dragFrom then dragging:dragTo(cx, cy) end
        else
            dragging = nil
        end
    end
    regs = { tabs = {}, page = {}, view = {} }
    wheels = {}

    local bg = Menu.background
    if bg then dxDrawImage(0, 0, sw, sh, bg) end
    dxDrawRectangle(0, 0, sw, sh, C.shade)

    drawTop()

    AREA.x, AREA.y, AREA.w, AREA.h = S(60), S(150), sw - S(120), sh - S(150) - S(84)
    if Menu.view then
        local v = VIEWS[Menu.view.id]
        local crumb = L.upper(L(PAGES.defs[Menu.page].label)) .. "  ›  " .. L.upper(v.title(Menu.view.args) or "")
        text(crumb, AREA.x, S(106), AREA.w, S(30), C.dim, 1.05, FONT.head)
        v.draw(AREA.x, AREA.y, AREA.w, AREA.h, Menu.view.args)
    else
        PAGES.defs[Menu.page].draw(AREA.x, AREA.y, AREA.w, AREA.h)
    end

    drawHint()

    lastRegs = regs
    -- keep a valid focus in the active layer
    local layer = Menu.layer
    if not findReg(layer, Menu.focus[layer]) then
        local first = regs[layer][1]
        if first then
            Menu.focus[layer] = first.id
        elseif layer == "view" and not Menu.view then
            Menu.layer = "page"
        end
    end
end

--------------------------------------------------------------------------------
-- input
--------------------------------------------------------------------------------

local function focusedReg()
    return findReg(Menu.layer, Menu.focus[Menu.layer])
end

addEventHandler("onClientKey", root, function(key, press)
    if not Menu.open or not press then return end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        local mx, my = cursorPos()
        for i = #wheels, 1, -1 do
            if inRect(mx, my, wheels[i]) then
                wheels[i].fn(key == "mouse_wheel_up" and -1 or 1)
                return
            end
        end
        return
    end
    if key:find("^mouse") then return end
    local r = focusedReg()
    if r and r.field and key == "v" and (getKeyState("lctrl") or getKeyState("rctrl")) then
        -- MTA only fires onClientPaste for a "v" stroke that onClientKey did not cancel;
        -- keep GTA's V (camera) quiet for that one press instead
        if isControlEnabled("change_camera") then
            toggleControl("change_camera", false)
            setTimer(toggleControl, 250, 1, "change_camera", true)
        end
        return
    end
    cancelEvent()

    if r and r.field then
        local f = r.field
        if getKeyState("lctrl") or getKeyState("rctrl") then
            if key == "a" then return f:selectAll() end
            if (key == "c" or key == "x") and not r.masked then
                local sel = f:getSelected()
                if sel then
                    setClipboard(sel)
                    if key == "x" then f:deleteSelection() end
                end
                return
            end
            if key == "c" or key == "x" then return end
        end
        -- Backspace in an empty field goes back like everywhere else
        local editing = not (key == "backspace" and f:getText() == "")
        if editing and (key == "backspace" or key == "delete" or key == "home" or key == "end"
        or key == "arrow_l" or key == "arrow_r") then
            return f:key(key, getKeyState("lshift") or getKeyState("rshift"))
        end
    end

    if key == "arrow_l" or key == "arrow_r" then
        local fn = r and (key == "arrow_l" and r.left or r.right)
        if fn then
            playUI("move")
            return fn()
        end
        return move(key == "arrow_l" and "l" or "r")
    elseif key == "arrow_u" then
        return move("u")
    elseif key == "arrow_d" then
        return move("d")
    elseif key == "enter" or key == "num_enter" then
        return activate(r)
    elseif key == "backspace" or key == "escape" then
        playUI("move")
        return Menu.back()
    end
end)

addEventHandler("onClientCharacter", root, function(ch)
    if not Menu.open then return end
    local r = focusedReg()
    if r and r.field then r.field:insert(ch) end
end)

addEventHandler("onClientPaste", root, function(str)
    if not Menu.open then return end
    local r = focusedReg()
    if r and r.field then r.field:insert(str) end
end)

addEventHandler("onClientClick", root, function(btn, state, absX, absY)
    if not Menu.open or btn ~= "left" or state ~= "down" then return end
    for _, layer in ipairs({ "tabs", "view", "page" }) do
        local list = lastRegs[layer]
        for i = #list, 1, -1 do
            local r = list[i]
            if inRect(absX, absY, r) then
                local shift = Menu.isFocused(layer, r.id) and (getKeyState("lshift") or getKeyState("rshift"))
                Menu.setFocus(layer, r.id)
                if r.field then
                    r.field:clickAt(absX, absY, shift)
                    dragging, dragFrom = r.field, { absX, absY }
                else
                    activate(r)
                end
                return
            end
        end
    end
end)

addEventHandler("onClientDoubleClick", root, function(btn, absX, absY)
    if not Menu.open or btn ~= "left" then return end
    local r = focusedReg()
    if r and r.field and inRect(absX, absY, r) then
        dragging = nil
        r.field:selectWordAt(absX, absY)
    end
end)

--------------------------------------------------------------------------------
-- open / close
--------------------------------------------------------------------------------

local function accUi(fn, ...)
    local res = getResourceFromName("acc_ui")
    if not res or getResourceState(res) ~= "running" then return nil end
    return exports.acc_ui[fn](exports.acc_ui, ...)
end

function Menu.show(data)
    Menu.data = type(data) == "table" and data or {}
    if Menu.open then return end
    Menu.open = true
    Menu.page = "home"
    Menu.layer = "page"
    Menu.view = nil
    Menu.focus = { tabs = "home", page = "home_join", view = nil }
    Menu.background = accUi("getBackgroundImage")
    for _, def in pairs(PAGES.defs) do
        if def.onMenuOpen then def.onMenuOpen() end
    end
    addEventHandler("onClientRender", root, render)
    setElementData(localPlayer, "accountMenuOpen", true, false)
    setElementData(localPlayer, "hideHUD", true)
    showCursor(true)
    guiSetInputMode("no_binds")
    accUi("setMusicActive", false) -- no music in the menu (stops the login music too)
end

function Menu.hide()
    if not Menu.open then return end
    Menu.open = false
    removeEventHandler("onClientRender", root, render)
    setElementData(localPlayer, "accountMenuOpen", false, false)
    setElementData(localPlayer, "textInputOpen", false, false)
    accUi("setMusicActive", false)
    showCursor(false)
end

function Menu.join()
    Menu.hide()
    triggerServerEvent("acc_menu:join", localPlayer)
end

addEvent("acc_menu:open", true)
addEventHandler("acc_menu:open", localPlayer, function(data) Menu.show(data) end)

addEvent("acc_menu:data", true)
addEventHandler("acc_menu:data", localPlayer, function(data)
    if type(data) == "table" then
        for k, v in pairs(data) do Menu.data[k] = v end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local function font(file, px, fallback)
        local f = dxCreateFont(file, math.floor(px * SC + 0.5))
        return isElement(f) and f or fallback
    end
    FONT.row  = font("files/Roboto.ttf", 12, "default")
    FONT.rowB = font("files/RobotoB.ttf", 12, "default-bold")
    FONT.head = font("files/RobotoB.ttf", 14, "default-bold")
    FONT.big  = font("files/RobotoB.ttf", 30, "default-bold")
    -- logged in but not loaded (acc_menu restarted while the menu was up)
    if getElementData(localPlayer, "isLogged") == true and getElementData(localPlayer, "loaded") ~= true then
        triggerServerEvent("acc_menu:reopen", localPlayer)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if Menu.open then
        setElementData(localPlayer, "textInputOpen", false, false)
        setElementData(localPlayer, "accountMenuOpen", false, false)
        guiSetInputMode("allow_binds")
    end
end)
