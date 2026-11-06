if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Immediate-mode dx drawing helpers of the ER tablet / PC (copy of med_erm client/gfx.lua, blue accent).
--
-- Every frame the widgets register their clickable rectangles in HGfx.hits and
-- their scrollable regions in HGfx.scrollAreas; tablet.lua routes clicks and the
-- mouse wheel to them. Overlays clear HGfx.hits before drawing so nothing below
-- them reacts.

HGfx = {
    hits        = {},
    scrollAreas = {},
    scroll      = {},     -- [id] = offset (rows)
    blockHover  = false,
}

local SX, SY = guiGetScreenSize()
HGfx.screenW, HGfx.screenH = SX, SY
HGfx.scale = math.max(0.7, math.min(SY / 1080, 1.4))

local S = HGfx.scale
function HGfx.s(v) return v * S end

HTheme = {
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
    accent = tocolor(47, 134, 232),
    shade  = tocolor(0, 0, 0, 150),
}

---------------------------------------------------------------- skins
-- "modern" (the J tablet, the bedside panel: as it always was) and "w7" (the hospital PC since
-- 2026-11-06: a dark Windows 7 look). The palette is swapped in place, so every `local T = HTheme`
-- sees it; HGfx.round / HGfx.button draw square, glossy two-tone controls in "w7".

local PALETTES = {
    modern = {
        bezel = { 16, 18, 21 }, edge = { 44, 48, 54 }, bg = { 21, 25, 30 }, header = { 14, 17, 21 },
        panel = { 30, 36, 43 }, panel2 = { 39, 46, 55 }, line = { 52, 60, 70 }, text = { 233, 237, 242 },
        dim = { 152, 162, 174 }, faint = { 98, 108, 120 }, accent = { 47, 134, 232 },
    },
    w7 = {
        bezel = { 8, 10, 12 }, edge = { 60, 68, 78 }, bg = { 30, 34, 39 }, header = { 38, 44, 51 },
        panel = { 40, 46, 53 }, panel2 = { 52, 60, 70 }, line = { 66, 74, 84 }, text = { 230, 234, 238 },
        dim = { 160, 170, 180 }, faint = { 118, 128, 139 }, accent = { 64, 132, 196 },
    },
}
HGfx.skin = "modern"
function HGfx.setSkin(name)
    if not PALETTES[name] or HGfx.skin == name then return end
    HGfx.skin = name
    for k, c in pairs(PALETTES[name]) do HTheme[k] = tocolor(c[1], c[2], c[3]) end
end

---------------------------------------------------------------- fonts

local fonts = {}
function HGfx.font(size, bold)
    local key = size .. (bold and "b" or "r")
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf",
            math.max(6, math.floor(size * S + 0.5)), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

---------------------------------------------------------------- primitives

function HGfx.rgb(c, a)
    return tocolor(c[1], c[2], c[3], a or 255)
end

function HGfx.rect(x, y, w, h, color)
    dxDrawRectangle(x, y, w, h, color)
end

function HGfx.round(x, y, w, h, r, color)
    if HGfx.skin == "w7" then r = math.min(r, HGfx.s(2)) end
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

function HGfx.text(str, x, y, w, h, color, font, alignX, alignY, wordBreak)
    dxDrawText(str, x, y, x + w, y + h, color or HTheme.text, 1, font or HGfx.font(10),
        alignX or "left", alignY or "center", true, wordBreak or false)
end

-- Truncates text with an ellipsis so it fits in width (v_locals: cached, UTF-8 safe).
function HGfx.fit(str, width, font)
    return L.fit(tostring(str or ""), width, 1, font)
end

-- Word-wraps text into lines that fit width (v_locals: cached; read-only table).
function HGfx.wrap(str, width, font)
    return L.wrap(tostring(str or ""), width, 1, font)
end

---------------------------------------------------------------- input

function HGfx.cursor()
    if not isCursorShowing() then return -1, -1 end
    local cx, cy = getCursorPosition()
    return cx * SX, cy * SY
end

function HGfx.inside(px, py, x, y, w, h)
    return px >= x and px <= x + w and py >= y and py <= y + h
end

function HGfx.hover(x, y, w, h)
    if HGfx.blockHover then return false end
    local cx, cy = HGfx.cursor()
    return HGfx.inside(cx, cy, x, y, w, h)
end

function HGfx.hit(x, y, w, h, fn)
    HGfx.hits[#HGfx.hits + 1] = { x, y, w, h, fn }
end

function HGfx.scrollArea(id, x, y, w, h)
    HGfx.scrollAreas[#HGfx.scrollAreas + 1] = { x, y, w, h, id }
end

-- Clamps and returns the scroll offset of a list.
function HGfx.getScroll(id, maxOffset)
    local v = math.max(0, math.min(HGfx.scroll[id] or 0, math.max(0, maxOffset)))
    HGfx.scroll[id] = v
    return v
end

function HGfx.click(px, py)
    for i = #HGfx.hits, 1, -1 do
        local h = HGfx.hits[i]
        if HGfx.inside(px, py, h[1], h[2], h[3], h[4]) then
            h[5]()
            return true
        end
    end
    return false
end

function HGfx.wheel(delta)
    local cx, cy = HGfx.cursor()
    for i = #HGfx.scrollAreas, 1, -1 do
        local a = HGfx.scrollAreas[i]
        if HGfx.inside(cx, cy, a[1], a[2], a[3], a[4]) then
            HGfx.scroll[a[5]] = (HGfx.scroll[a[5]] or 0) + delta
            return true
        end
    end
    return false
end

---------------------------------------------------------------- widgets

local function lighten(c, amount)
    return { math.min(255, c[1] + amount), math.min(255, c[2] + amount), math.min(255, c[3] + amount) }
end

local function darken(c, amount)
    return { math.max(0, c[1] - amount), math.max(0, c[2] - amount), math.max(0, c[3] - amount) }
end

-- Win7 glossy button: dark border, lighter upper half, base lower half, a 1 px highlight inside.
-- opt.tab: a classic tab (the active one joins the window background).
local function w7Button(x, y, w, h, c, hov, opt)
    local a = opt.disabled and 90 or 255
    if opt.tab then
        if opt.active then
            dxDrawRectangle(x, y, w, h + 1, tocolor(86, 98, 112, a))
            dxDrawRectangle(x + 1, y + 1, w - 2, h, HTheme.bg)
            dxDrawRectangle(x + 1, y + 1, w - 2, 1, tocolor(255, 255, 255, 40))
        else
            local base = hov and { 58, 66, 76 } or { 44, 50, 57 }
            dxDrawRectangle(x, y + 2, w, h - 2, tocolor(70, 79, 90, a))
            dxDrawRectangle(x + 1, y + 3, w - 2, (h - 4) / 2, HGfx.rgb(lighten(base, 8), a))
            dxDrawRectangle(x + 1, y + 3 + (h - 4) / 2, w - 2, (h - 4) / 2, HGfx.rgb(base, a))
        end
        return
    end
    if hov then c = lighten(c, 18) end
    dxDrawRectangle(x, y, w, h, HGfx.rgb(darken(c, 40), a))
    dxDrawRectangle(x + 1, y + 1, w - 2, (h - 2) / 2, HGfx.rgb(lighten(c, 18), a))
    dxDrawRectangle(x + 1, y + 1 + (h - 2) / 2, w - 2, (h - 2) / 2, HGfx.rgb(c, a))
    dxDrawRectangle(x + 1, y + 1, w - 2, 1, tocolor(255, 255, 255, opt.disabled and 15 or 45))
end

-- opt: color {r,g,b}, textColor, font, radius, disabled, align, tab, active (w7 tabs)
function HGfx.button(x, y, w, h, label, opt, onClick)
    opt = opt or {}
    local hov = not opt.disabled and HGfx.hover(x, y, w, h)
    local c = opt.color or { 48, 56, 66 }
    if HGfx.skin == "w7" then
        w7Button(x, y, w, h, c, hov, opt)
    else
        if hov then c = lighten(c, 22) end
        HGfx.round(x, y, w, h, opt.radius or HGfx.s(6), HGfx.rgb(c, opt.disabled and 70 or 255))
    end

    local tc = opt.textColor or HTheme.text
    if opt.disabled then tc = tocolor(255, 255, 255, 80) end
    local pad = opt.align == "left" and HGfx.s(12) or 0
    HGfx.text(label, x + pad, y, w - pad * 2, h, tc, opt.font or HGfx.font(10, true), opt.align or "center", "center")

    if onClick and not opt.disabled then HGfx.hit(x, y, w, h, onClick) end
    return hov
end

HGfx.lighten, HGfx.darken = lighten, darken

function HGfx.label(str, x, y, w)
    HGfx.text(str, x, y, w, HGfx.s(16), HTheme.faint, HGfx.font(8, true), "left", "center")
end

-- Red cross logo.
function HGfx.cross(x, y, size, color)
    local t = size / 3
    dxDrawRectangle(x + t, y, t, size, color)
    dxDrawRectangle(x, y + t, size, t, color)
end
