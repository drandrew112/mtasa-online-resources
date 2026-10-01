-- Immediate-mode dx drawing helpers for the tablet.
--
-- Every frame the widgets register their clickable rectangles in Gfx.hits and
-- their scrollable regions in Gfx.scrollAreas; tablet.lua routes clicks and the
-- mouse wheel to them. Overlays clear Gfx.hits before drawing so nothing below
-- them reacts.

Gfx = {
    hits        = {},
    scrollAreas = {},
    scroll      = {},     -- [id] = offset (rows)
    blockHover  = false,
}

local SX, SY = guiGetScreenSize()
Gfx.screenW, Gfx.screenH = SX, SY
Gfx.scale = math.max(0.7, math.min(SY / 1080, 1.4))

local S = Gfx.scale
function Gfx.s(v) return v * S end

Theme = {
    bezel  = tocolor(16, 18, 21),
    edge   = tocolor(44, 48, 54),
    bg     = tocolor(21, 25, 30),
    header = tocolor(14, 17, 21),
    panel  = tocolor(30, 36, 43),
    panel2 = tocolor(39, 46, 55),
    line   = tocolor(52, 60, 70),
    text   = tocolor(233, 237, 242),
    dim    = tocolor(152, 162, 174),
    faint  = tocolor(98, 108, 120),
    accent = tocolor(224, 60, 49),
    shade  = tocolor(0, 0, 0, 150),
}

---------------------------------------------------------------- fonts

local fonts = {}
function Gfx.font(size, bold)
    local key = size .. (bold and "b" or "r")
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf",
            math.max(6, math.floor(size * S + 0.5)), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

---------------------------------------------------------------- primitives

function Gfx.rgb(c, a)
    return tocolor(c[1], c[2], c[3], a or 255)
end

function Gfx.rect(x, y, w, h, color)
    dxDrawRectangle(x, y, w, h, color)
end

function Gfx.round(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then return dxDrawRectangle(x, y, w, h, color) end
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 12)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 12)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 12)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 12)
end

function Gfx.text(str, x, y, w, h, color, font, alignX, alignY, wordBreak)
    dxDrawText(str, x, y, x + w, y + h, color or Theme.text, 1, font or Gfx.font(10),
        alignX or "left", alignY or "center", true, wordBreak or false)
end

-- Truncates text with an ellipsis so it fits in width.
function Gfx.fit(str, width, font)
    str = tostring(str or "")
    if dxGetTextWidth(str, 1, font) <= width then return str end
    local n = utf8.len(str) or #str
    while n > 0 and dxGetTextWidth(utf8.sub(str, 1, n) .. "…", 1, font) > width do n = n - 1 end
    return utf8.sub(str, 1, n) .. "…"
end

-- Word-wraps text into lines that fit width.
function Gfx.wrap(str, width, font)
    local lines = {}
    for para in (tostring(str or "") .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            local try = (line == "") and word or (line .. " " .. word)
            if dxGetTextWidth(try, 1, font) <= width then
                line = try
            else
                if line ~= "" then lines[#lines + 1] = line end
                while dxGetTextWidth(word, 1, font) > width and (utf8.len(word) or 0) > 1 do
                    local n = utf8.len(word)
                    while n > 1 and dxGetTextWidth(utf8.sub(word, 1, n), 1, font) > width do n = n - 1 end
                    lines[#lines + 1] = utf8.sub(word, 1, n)
                    word = utf8.sub(word, n + 1)
                end
                line = word
            end
        end
        lines[#lines + 1] = line
    end
    return lines
end

---------------------------------------------------------------- input

function Gfx.cursor()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    return cx * SX, cy * SY
end

function Gfx.inside(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function Gfx.hover(x, y, w, h)
    if Gfx.blockHover then return false end
    local cx, cy = Gfx.cursor()
    return Gfx.inside(cx, cy, x, y, w, h)
end

function Gfx.hit(x, y, w, h, fn)
    Gfx.hits[#Gfx.hits + 1] = { x, y, w, h, fn }
end

function Gfx.scrollArea(id, x, y, w, h)
    Gfx.scrollAreas[#Gfx.scrollAreas + 1] = { x, y, w, h, id }
end

-- Clamps and returns the scroll offset of a list.
function Gfx.getScroll(id, maxOffset)
    local v = math.max(0, math.min(Gfx.scroll[id] or 0, math.max(0, maxOffset)))
    Gfx.scroll[id] = v
    return v
end

function Gfx.click(px, py)
    for i = #Gfx.hits, 1, -1 do
        local h = Gfx.hits[i]
        if Gfx.inside(px, py, h[1], h[2], h[3], h[4]) then
            h[5]()
            return true
        end
    end
    return false
end

function Gfx.wheel(delta)
    local cx, cy = Gfx.cursor()
    for i = #Gfx.scrollAreas, 1, -1 do
        local a = Gfx.scrollAreas[i]
        if Gfx.inside(cx, cy, a[1], a[2], a[3], a[4]) then
            Gfx.scroll[a[5]] = (Gfx.scroll[a[5]] or 0) + delta
            return true
        end
    end
    return false
end

---------------------------------------------------------------- widgets

local function lighten(c, amount)
    return { math.min(255, c[1] + amount), math.min(255, c[2] + amount), math.min(255, c[3] + amount) }
end

-- opt: color {r,g,b}, textColor, font, radius, disabled, align
function Gfx.button(x, y, w, h, label, opt, onClick)
    opt = opt or {}
    local hov = not opt.disabled and Gfx.hover(x, y, w, h)
    local c = opt.color or { 48, 56, 66 }
    if hov then c = lighten(c, 22) end
    Gfx.round(x, y, w, h, opt.radius or Gfx.s(6), Gfx.rgb(c, opt.disabled and 70 or 255))

    local tc = opt.textColor or Theme.text
    if opt.disabled then tc = tocolor(255, 255, 255, 80) end
    local pad = opt.align == "left" and Gfx.s(12) or 0
    Gfx.text(label, x + pad, y, w - pad * 2, h, tc, opt.font or Gfx.font(10, true), opt.align or "center", "center")

    if onClick and not opt.disabled then Gfx.hit(x, y, w, h, onClick) end
    return hov
end

function Gfx.priorityBadge(x, y, w, h, priority)
    local c = Config.PRIORITY_COLORS[priority]
    if c then
        Gfx.round(x, y, w, h, Gfx.s(4), Gfx.rgb(c))
        Gfx.text("P" .. priority, x, y, w, h, tocolor(15, 15, 15), Gfx.font(10, true), "center")
    else
        Gfx.round(x, y, w, h, Gfx.s(4), Theme.panel2)
        Gfx.text("--", x, y, w, h, Theme.dim, Gfx.font(10, true), "center")
    end
end

function Gfx.label(str, x, y, w)
    Gfx.text(str, x, y, w, Gfx.s(16), Theme.faint, Gfx.font(8, true), "left", "center")
end

-- Red cross logo.
function Gfx.cross(x, y, size, color)
    local t = size / 3
    dxDrawRectangle(x + t, y, t, size, color)
    dxDrawRectangle(x, y + t, size, t, color)
end
