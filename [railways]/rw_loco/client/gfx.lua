-- Drawing helpers for cab panels: analog gauges (white face, black needle), lamps, toggle
-- switches, push buttons. Static parts are meant to be drawn once into a render target.

Gfx = {}

local rad, cos, sin, floor = math.rad, math.cos, math.sin, math.floor
local START, SWEEP = 135, 270     -- gauge sweep: from bottom-left, clockwise, to bottom-right

function Gfx.angle(frac)
    if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    return START + SWEEP * frac
end

local function pt(cx, cy, r, deg)
    local a = rad(deg)
    return cx + cos(a) * r, cy + sin(a) * r
end

function Gfx.rect(x, y, w, h, c) dxDrawRectangle(x, y, w, h, c) end

function Gfx.frame(x, y, w, h, t, c)
    dxDrawRectangle(x, y, w, t, c)
    dxDrawRectangle(x, y + h - t, w, t, c)
    dxDrawRectangle(x, y, t, h, c)
    dxDrawRectangle(x + w - t, y, t, h, c)
end

-- bevelled box: fill + light top/left + dark bottom/right edge
function Gfx.box(x, y, w, h, fill, light, dark, t)
    t = t or 2
    dxDrawRectangle(x, y, w, h, fill)
    dxDrawRectangle(x, y, w, t, light)
    dxDrawRectangle(x, y, t, h, light)
    dxDrawRectangle(x, y + h - t, w, t, dark)
    dxDrawRectangle(x + w - t, y, t, h, dark)
end

function Gfx.text(s, x, y, w, h, c, font, ax, ay)
    dxDrawText(s, x, y, x + (w or 0), y + (h or 0), c or tocolor(255, 255, 255), 1, font or "default", ax or "left", ay or "top", false, false, false, false, true)
end

--[[ gauge face. o = { min, max, major, minor, labelStep, red = { from, to }, title, unit,
     font, smallFont, s (scale) } ]]
function Gfx.gaugeFace(cx, cy, r, o)
    local s = o.s or 1
    dxDrawCircle(cx, cy, r + 4 * s, 0, 360, tocolor(55, 60, 70), tocolor(55, 60, 70), 48)     -- bezel
    dxDrawCircle(cx, cy, r + 2 * s, 0, 360, tocolor(10, 10, 12), tocolor(10, 10, 12), 48)
    dxDrawCircle(cx, cy, r, 0, 360, tocolor(244, 244, 238), tocolor(250, 250, 246), 48)    -- face
    local range = o.max - o.min
    if o.red then
        local a0 = Gfx.angle((o.red[1] - o.min) / range)
        local a1 = Gfx.angle((o.red[2] - o.min) / range)
        for a = a0, a1, 1.5 do
            local x1, y1 = pt(cx, cy, r * 0.80, a)
            local x2, y2 = pt(cx, cy, r * 0.93, a)
            dxDrawLine(x1, y1, x2, y2, tocolor(205, 30, 30), 2 * s)
        end
    end
    if o.minor then
        for v = o.min, o.max + 0.0001, o.minor do
            local a = Gfx.angle((v - o.min) / range)
            local x1, y1 = pt(cx, cy, r * 0.86, a)
            local x2, y2 = pt(cx, cy, r * 0.94, a)
            dxDrawLine(x1, y1, x2, y2, tocolor(20, 20, 20), math.max(1, s))
        end
    end
    local labelStep = o.labelStep or o.major
    for v = o.min, o.max + 0.0001, o.major do
        local a = Gfx.angle((v - o.min) / range)
        local x1, y1 = pt(cx, cy, r * 0.78, a)
        local x2, y2 = pt(cx, cy, r * 0.95, a)
        dxDrawLine(x1, y1, x2, y2, tocolor(10, 10, 10), 2.2 * s)
        if (v - o.min) % labelStep < 0.0001 then
            local tx, ty = pt(cx, cy, r * 0.60, a)
            local str = o.div and tostring(floor(v / o.div + 0.5)) or tostring(floor(v + 0.5))
            dxDrawText(str, tx, ty, tx, ty, tocolor(15, 15, 15), 1, o.font or "default-bold", "center", "center")
        end
    end
    if o.unit then   -- inside, under the hub
        dxDrawText(o.unit, cx, cy + r * 0.45, cx, cy + r * 0.45, tocolor(60, 60, 60), 1, o.smallFont or "default", "center", "center")
    end
    if o.title then  -- engraved label under the instrument
        dxDrawText(o.title, cx, cy + r + 4 * s, cx, cy + r + 4 * s, tocolor(190, 198, 214), 1, o.titleFont or o.smallFont or "default", "center", "top")
    end
end

function Gfx.needle(cx, cy, r, frac, s)
    s = s or 1
    local a = Gfx.angle(frac)
    local x, y = pt(cx, cy, r * 0.88, a)
    local bx, by = pt(cx, cy, r * 0.16, a + 180)
    dxDrawLine(bx, by, x, y, tocolor(12, 12, 12), math.max(2, r * 0.06))
    dxDrawCircle(cx, cy, math.max(3, r * 0.1), 0, 360, tocolor(25, 25, 25), tocolor(60, 60, 60), 16)
end

-- lamp: dark glass when off, coloured glow when on
function Gfx.lampBezel(cx, cy, r)
    dxDrawCircle(cx, cy, r + 2.5, 0, 360, tocolor(70, 74, 84), tocolor(70, 74, 84), 24)
    dxDrawCircle(cx, cy, r, 0, 360, tocolor(20, 22, 26), tocolor(32, 34, 40), 24)
end

function Gfx.lamp(cx, cy, r, color, on)
    if not on then return end
    local cr, cg, cb = color[1], color[2], color[3]
    dxDrawCircle(cx, cy, r * 1.9, 0, 360, tocolor(cr, cg, cb, 0), tocolor(cr, cg, cb, 70), 24)
    dxDrawCircle(cx, cy, r, 0, 360, tocolor(cr, cg, cb, 255), tocolor(255, 255, 255, 255), 24)
end

-- toggle switch: base plate (static) + lever up (on) / down (off)
function Gfx.toggleBase(cx, cy, s)
    dxDrawRectangle(cx - 13 * s, cy - 20 * s, 26 * s, 40 * s, tocolor(30, 33, 40))
    Gfx.frame(cx - 13 * s, cy - 20 * s, 26 * s, 40 * s, math.max(1, s), tocolor(120, 130, 150))
    dxDrawCircle(cx, cy, 7 * s, 0, 360, tocolor(150, 155, 165), tocolor(200, 205, 210), 16)
end

function Gfx.toggleLever(cx, cy, on, s)
    local ty = on and (cy - 17 * s) or (cy + 17 * s)
    dxDrawLine(cx, cy, cx, ty, tocolor(215, 218, 225), 5 * s)
    dxDrawCircle(cx, ty, 4.5 * s, 0, 360, tocolor(235, 235, 240), tocolor(255, 255, 255), 12)
end

-- round push button; pressed = darker + inset
function Gfx.button(cx, cy, r, color, pressed, lit)
    local k = pressed and 0.65 or 1
    dxDrawCircle(cx, cy, r + 3, 0, 360, tocolor(25, 27, 32), tocolor(25, 27, 32), 24)
    dxDrawCircle(cx, cy, r, 0, 360, tocolor(color[1] * k * 0.75, color[2] * k * 0.75, color[3] * k * 0.75),
        tocolor(math.min(255, color[1] * k * (lit and 1.25 or 1)), math.min(255, color[2] * k * (lit and 1.25 or 1)), math.min(255, color[3] * k * (lit and 1.25 or 1))), 24)
end
