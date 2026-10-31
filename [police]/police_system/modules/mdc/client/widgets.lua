-- police_system / modules/mdc/client/widgets.lua
-- Immediate mode DX widgets of the MDC, drawn into its render target (local coordinates). Every redraw rebuilds the
-- hit list; hover / clicks are tested against it, a changed hover marks the MDC dirty (redraw only then).
--   W.button(id, x, y, w, h, label, fn, kind)      kind: nil | "primary" | "danger" | "ghost" | "active"
--   W.text(s, x, y, w, h, color, size, bold, ax, ay, clip)
--   W.badge(s, x, y, color) -> width
--   W.field(id, x, y, w, h, placeholder, opts)      a TextField (field.lua), focus on click
--   W.check(id, x, y, on, label, fn) -> width
--   W.select(id, x, y, w, h, options, value, fn)    options = { {value, label}, ... }, list opens over the content
--   W.table(id, x, y, w, h, cols, rows, onRow)      cols = { {label, ratio, align}, ... }, rows = { {cells, color?}, ... }
--   W.scroll[id] = offset (mouse wheel over its area)

W = { hits = {}, hover = nil, fields = {}, focus = nil, scroll = {}, scrollAreas = {}, popup = nil }

local C = POL.colors

function W.reset()
    W.hits = {}
    W.scrollAreas = {}
    W.popupDraw = nil
end

function W.hit(id, x, y, w, h, fn, cursor)
    W.hits[#W.hits + 1] = { id = id, x = x, y = y, w = w, h = h, fn = fn }
    return W.hover == id
end

function W.text(s, x, y, w, h, color, size, bold, ax, ay, clip, wrap)
    dxDrawText(tostring(s or ""), x, y, x + w, y + h, color or C.text, 1, POL.font(size or 10, bold), ax or "left", ay or "center",
        clip ~= false, wrap or false)
end

function W.badge(s, x, y, color, size)
    local f = POL.font(size or 8, true)
    local w = dxGetTextWidth(s, 1, f) + POL.px(12)
    local h = POL.px(18)
    dxDrawRectangle(x, y, w, h, color)
    dxDrawText(s, x, y, x + w, y + h, C.white, 1, f, "center", "center")
    return w
end

function W.button(id, x, y, w, h, label, fn, kind, disabled)
    local hov = not disabled and W.hit(id, x, y, w, h, not disabled and fn or nil)
    local bg = C.panel2
    if kind == "primary" then bg = hov and tocolor(90, 160, 255, 255) or C.accent
    elseif kind == "danger" then bg = hov and tocolor(255, 90, 90, 255) or tocolor(190, 50, 50, 255)
    elseif kind == "active" then bg = C.accentDim
    elseif kind == "ghost" then bg = hov and C.hover or tocolor(0, 0, 0, 0)
    elseif hov then bg = C.hover end
    if disabled then bg = tocolor(30, 40, 60, 255) end
    dxDrawRectangle(x, y, w, h, bg)
    if kind == "ghost" or kind == nil then dxDrawRectangle(x, y + h - 1, w, 1, C.line) end
    dxDrawText(label, x, y, x + w, y + h, disabled and C.dim or C.white, 1, POL.font(10, true), "center", "center", true)
end

function W.check(id, x, y, on, label, fn)
    local s = POL.px(16)
    local f = POL.font(10)
    local w = s + POL.px(8) + dxGetTextWidth(label, 1, f)
    local hov = W.hit(id, x, y, w, s, fn)
    dxDrawRectangle(x, y, s, s, hov and C.hover or C.panel2)
    if on then dxDrawRectangle(x + POL.px(4), y + POL.px(4), s - POL.px(8), s - POL.px(8), C.accent) end
    dxDrawText(label, x + s + POL.px(8), y, x + w, y + s, C.text, 1, f, "left", "center")
    return w
end

function W.fieldOf(id, opts)
    local f = W.fields[id]
    if not f then
        f = TextField.new(opts or {})
        W.fields[id] = f
    end
    return f
end

function W.field(id, x, y, w, h, placeholder, opts)
    local f = W.fieldOf(id, opts)
    local focused = W.focus == id
    W.hit(id, x, y, w, h, function(mx, my)
        W.focus = id
        f:clickAt(mx, my, getKeyState("lshift"))
    end)
    dxDrawRectangle(x, y, w, h, C.panel)
    dxDrawRectangle(x, y + h - POL.px(2), w, POL.px(2), focused and C.accent or C.line)
    local pad = POL.px(8)
    if f:getText() == "" and not focused then
        dxDrawText(placeholder or "", x + pad, y, x + w - pad, y + h, C.dim, 1, POL.font(10), "left", f.multiline and "top" or "center", true)
    end
    f:draw(x + pad, y + (f.multiline and pad or 0), w - pad * 2 - (f.multiline and POL.px(8) or 0), h - (f.multiline and pad * 2 or 0),
        focused, { font = POL.font(10), color = C.text, caret = C.accent })
    if f.multiline then W.scrollAreas[#W.scrollAreas + 1] = { x = x, y = y, w = w, h = h, field = f } end
    return f
end

-- dropdown: the list is drawn after everything else (popupDraw) so it is on top
function W.select(id, x, y, w, h, options, value, fn)
    local label = "-"
    for _, o in ipairs(options) do if o[1] == value then label = o[2] end end
    local open = W.popup == id
    W.hit(id, x, y, w, h, function() W.popup = open and nil or id end)
    dxDrawRectangle(x, y, w, h, W.hover == id and C.hover or C.panel2)
    dxDrawText(label, x + POL.px(8), y, x + w - POL.px(20), y + h, C.text, 1, POL.font(10), "left", "center", true)
    dxDrawText("▾", x, y, x + w - POL.px(8), y + h, C.dim, 1, POL.font(10), "right", "center")
    if open then
        W.popupDraw = function()
            local ih = h
            local py = y + h
            dxDrawRectangle(x, py, w, ih * #options, C.panel2)
            for i, o in ipairs(options) do
                local oy = py + (i - 1) * ih
                local hov = W.hit(id .. ":" .. i, x, oy, w, ih, function() W.popup = nil; fn(o[1]) end)
                if hov then dxDrawRectangle(x, oy, w, ih, C.hover) end
                dxDrawText(o[2], x + POL.px(8), oy, x + w, oy + ih, o[1] == value and C.accent or C.text, 1, POL.font(10), "left", "center", true)
            end
        end
    end
end

-- table with a header row and scrollable rows. rows[i] = { cells = {...}, colors = {...}, data }
function W.table(id, x, y, w, h, cols, rows, onRow, rowH)
    rowH = rowH or POL.px(28)
    local headH = POL.px(26)
    dxDrawRectangle(x, y, w, headH, C.panel2)
    local cx = x
    local total = 0
    for _, c in ipairs(cols) do total = total + c[2] end
    local widths = {}
    for i, c in ipairs(cols) do
        widths[i] = w * c[2] / total
        dxDrawText(L.upper(c[1]), cx + POL.px(8), y, cx + widths[i] - POL.px(4), y + headH, C.dim, 1, POL.font(8, true), c[3] or "left", "center", true)
        cx = cx + widths[i]
    end
    local areaY, areaH = y + headH, h - headH
    local visible = math.floor(areaH / rowH)
    local maxScroll = math.max(0, #rows - visible)
    local sc = math.min(W.scroll[id] or 0, maxScroll)
    W.scroll[id] = sc
    W.scrollAreas[#W.scrollAreas + 1] = { x = x, y = areaY, w = w, h = areaH, id = id, max = maxScroll }
    if #rows == 0 then
        dxDrawText(L("police_system.mdc.empty"), x, areaY, x + w, areaY + POL.px(40), C.dim, 1, POL.font(10), "center", "center")
    end
    for i = sc + 1, math.min(#rows, sc + visible) do
        local r = rows[i]
        local ry = areaY + (i - sc - 1) * rowH
        local hov = onRow and W.hit(id .. ":" .. i, x, ry, w, rowH, function() onRow(r, i) end)
        if hov then dxDrawRectangle(x, ry, w, rowH, C.hover)
        elseif i % 2 == 0 then dxDrawRectangle(x, ry, w, rowH, tocolor(255, 255, 255, 6)) end
        cx = x
        for ci, c in ipairs(cols) do
            local cell = r.cells[ci]
            if type(cell) == "function" then
                cell(cx + POL.px(8), ry, widths[ci] - POL.px(12), rowH)
            else
                dxDrawText(tostring(cell or ""), cx + POL.px(8), ry, cx + widths[ci] - POL.px(4), ry + rowH,
                    (r.colors and r.colors[ci]) or C.text, 1, POL.font(9, ci == 1), c[3] or "left", "center", true)
            end
            cx = cx + widths[ci]
        end
        dxDrawRectangle(x, ry + rowH - 1, w, 1, tocolor(255, 255, 255, 10))
    end
    if maxScroll > 0 then
        local thumbH = math.max(POL.px(16), areaH * visible / #rows)
        local thumbY = areaY + (areaH - thumbH) * (sc / maxScroll)
        dxDrawRectangle(x + w - POL.px(3), thumbY, POL.px(3), thumbH, C.accentDim)
    end
end

function W.card(x, y, w, h, title, right)
    dxDrawRectangle(x, y, w, h, C.panel)
    if title then
        dxDrawText(L.upper(title), x + POL.px(12), y, x + w, y + POL.px(32), C.dim, 1, POL.font(9, true), "left", "center")
        if right then dxDrawText(right, x, y, x + w - POL.px(12), y + POL.px(32), C.text, 1, POL.font(9, true), "right", "center") end
        dxDrawRectangle(x, y + POL.px(32), w, 1, C.line)
        return y + POL.px(38)
    end
    return y
end

function W.stars(level, x, y, size)
    local f = POL.font(size or 10, true)
    local s = ("★"):rep(level or 0) .. ("☆"):rep(6 - (level or 0))
    dxDrawText(s, x, y, x + POL.px(120), y + POL.px(20), C.yellow, 1, f, "left", "center")
end

-- the topmost hit under (mx, my)
function W.hitAt(mx, my)
    for i = #W.hits, 1, -1 do
        local h = W.hits[i]
        if mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h then return h end
    end
    return nil
end
