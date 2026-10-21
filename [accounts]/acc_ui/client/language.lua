if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Language dropdown: sits next to the music toggle in the Settings card
-- (settings.lua hands over the rect) and opens a list downwards. Choosing a language goes through v_locals (setLanguage), which
-- remembers it on the client, stores it on the account once logged in, and
-- fires v_locals:onClientLanguageChange. The panels' DGS elements keep their
-- text, so they are rewritten by Lang.refreshAll() on that event; everything
-- drawn with dxDrawText follows L() on its own.

Lang = {}

local btn = { x = 0, y = 0, w = 0, h = 0 }
local open = false
local rowH = ui(34)

local function languages()
    return exports.v_locals:getLanguages() or {}
end

local function currentLabel()
    local code = exports.v_locals:getLanguage()
    for _, l in ipairs(languages()) do
        if l.value == code then return l.label, code end
    end
    return tostring(code), code
end

local function inRect(px, py, x, y, w, h)
    return px and w > 0 and px >= x and px <= x + w and py >= y and py <= y + h
end

local function listRect(count)
    local h = rowH * count
    return btn.x, btn.y + btn.h + ui(4), btn.w, h
end

local function drawCaret(cx, cy, size, up)
    local s = size
    local a, b, c
    if up then
        a, b, c = { cx - s, cy + s / 2 }, { cx + s, cy + s / 2 }, { cx, cy - s / 2 }
    else
        a, b, c = { cx - s, cy - s / 2 }, { cx, cy + s / 2 }, { cx + s, cy - s / 2 }
    end
    dxDrawPrimitive("trianglefan", false, a[1], a[2], Theme.text, b[1], b[2], Theme.text, c[1], c[2], Theme.text)
end

-- Called from settings.lua, after the music toggle.
function Lang.draw(x, y, w, h)
    btn.x, btn.y, btn.w, btn.h = x, y, w, h
    local cx, cy = getCursorPosition()
    local mx, my
    if cx then mx, my = cx * sw, cy * sh end

    local hover = inRect(mx, my, btn.x, btn.y, btn.w, btn.h)
    dxDrawRectangle(btn.x, btn.y, btn.w, btn.h, (hover or open) and Theme.accent or Theme.fieldBG)
    dxDrawRectangle(btn.x, btn.y, ui(3), btn.h, Theme.accent)
    dxDrawText(currentLabel(), btn.x + ui(15), btn.y, btn.x + btn.w - ui(30), btn.y + btn.h,
        Theme.text, ui(1.15), "default-bold", "left", "center", true)
    drawCaret(btn.x + btn.w - ui(16), btn.y + btn.h / 2, ui(4), open)

    if not open then return end

    local list = languages()
    local lx, ly, lw, lh = listRect(#list)
    dxDrawRectangle(lx, ly, lw, lh, tocolor(18, 21, 26, 245))
    local _, code = currentLabel()
    for i, l in ipairs(list) do
        local ry = ly + (i - 1) * rowH
        local rowHover = inRect(mx, my, lx, ry, lw, rowH)
        if rowHover then
            dxDrawRectangle(lx, ry, lw, rowH, Theme.accent)
        elseif l.value == code then
            dxDrawRectangle(lx, ry, ui(3), rowH, Theme.accent)
        end
        dxDrawText(l.label, lx + ui(15), ry, lx + lw - ui(8), ry + rowH,
            Theme.text, ui(1.1), l.value == code and "default-bold" or "default", "left", "center", true)
    end
end

function Lang.close()
    open = false
end

addEventHandler("onClientClick", root, function(mouseButton, state, absX, absY)
    if mouseButton ~= "left" or state ~= "down" then return end
    if not (UIState and UIState.active) then return end

    if inRect(absX, absY, btn.x, btn.y, btn.w, btn.h) then
        open = not open
        uiSound("audio/ui_btn_click.mp3")
        return
    end

    if not open then return end
    open = false

    local list = languages()
    local lx, ly, lw, lh = listRect(#list)
    if inRect(absX, absY, lx, ly, lw, lh) then
        local l = list[math.floor((absY - ly) / rowH) + 1]
        if l then
            uiSound("audio/ui_btn_click.mp3")
            exports.v_locals:setLanguage(l.value)
        end
    end
end)

-- Rewrites every text that was handed to DGS once at creation time.
function Lang.refreshAll()
    for _, panel in pairs(Panels) do
        if panel.refreshTexts then panel:refreshTexts() end
    end
end

addEvent("v_locals:onClientLanguageChange")
addEventHandler("v_locals:onClientLanguageChange", root, function()
    Lang.refreshAll()
end)
