-- Drawing helpers of the introduction (DX). The look follows the work_ems tutorial card: a dark
-- panel on the left, Roboto, with an amber accent for the introduction.

Draw = {}

local sw, sh = guiGetScreenSize()
local scale = math.max(0.7, sh / 1080)
local function s(v) return v * scale end
Draw.s, Draw.sw, Draw.sh = s, sw, sh

local C = {
    panel = tocolor(10, 13, 19, 232),
    edge = tocolor(44, 52, 64, 255),
    accent = tocolor(242, 171, 47, 255),
    accentSoft = tocolor(242, 171, 47, 70),
    text = tocolor(236, 239, 243, 255),
    muted = tocolor(160, 168, 180, 255),
    faint = tocolor(110, 118, 130, 255),
    row = tocolor(255, 255, 255, 14),
    good = tocolor(80, 200, 130, 255),
    black = tocolor(0, 0, 0, 255),
    dim = tocolor(4, 6, 10, 200),
    segment = tocolor(255, 255, 255, 60),
    segmentDone = tocolor(255, 255, 255, 190),
}
Draw.colors = C

local fonts
function Draw.fonts()
    if fonts then return fonts end
    local function make(file, size, fallback)
        return dxCreateFont(file, s(size), false, "antialiased") or fallback
    end
    fonts = {
        small = make("assets/fonts/RobotoB.ttf", 9, "default-bold"),
        body = make("assets/fonts/Roboto.ttf", 11.5, "default"),
        bold = make("assets/fonts/RobotoB.ttf", 11.5, "default-bold"),
        title = make("assets/fonts/RobotoB.ttf", 18, "default-bold"),
        subtitle = make("assets/fonts/Roboto.ttf", 15, "default-bold"),
        big = make("assets/fonts/RobotoB.ttf", 54, "bankgothic"),
        label = make("assets/fonts/RobotoB.ttf", 13, "default-bold"),
    }
    return fonts
end

-- Height of `text` wrapped to `width`
function Draw.textHeight(text, width, font)
    local lines = 0
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        local line = ""
        if paragraph == "" then lines = lines + 1 end
        for word in paragraph:gmatch("%S+") do
            local try = line == "" and word or (line .. " " .. word)
            if dxGetTextWidth(try, 1, font) > width and line ~= "" then
                lines = lines + 1
                line = word
            else
                line = try
            end
        end
        if line ~= "" then lines = lines + 1 end
    end
    return lines * dxGetFontHeight(1, font)
end

local function text(str, x, y, x2, y2, color, font, ax, ay, wrap)
    dxDrawText(str, x, y, x2, y2, color, 1, font, ax or "left", ay or "top", not wrap, wrap or false, true)
end

local function frame(x, y, w, h, t, color)
    dxDrawRectangle(x, y, w, t, color, true)
    dxDrawRectangle(x, y + h - t, w, t, color, true)
    dxDrawRectangle(x, y, t, h, color, true)
    dxDrawRectangle(x + w - t, y, t, h, color, true)
end

---------------------------------------------------------------- frame pieces

function Draw.letterbox()
    local h = sh * 0.1
    dxDrawRectangle(0, 0, sw, h, C.black, true)
    dxDrawRectangle(0, sh - h, sw, h, C.black, true)
end

-- Chapter bar: one segment per chapter at the top centre, label under it
function Draw.progress(index, total, label)
    local f = Draw.fonts()
    local segW, curW, gap, segH = s(34), s(54), s(5), s(5)
    local width = (total - 1) * segW + curW + (total - 1) * gap
    local x = (sw - width) / 2
    local y = s(22)
    for i = 1, total do
        local w = i == index and curW or segW
        local color = i == index and C.accent or (i < index and C.segmentDone or C.segment)
        dxDrawRectangle(x, y, w, segH, color, true)
        x = x + w + gap
    end
    text(label:upper(), 0, y + s(12), sw, y + s(32), C.muted, f.small, "center", "top")
end

-- state = { ready = bool, remaining = seconds, fraction = 0..1, message = string }
function Draw.continue(state)
    local f = Draw.fonts()
    local right, bottom = sw - s(36), sh - s(30)
    if state.message then
        text(state.message, 0, bottom - s(30), right, bottom, C.muted, f.bold, "right", "center")
        return
    end
    local key = INTRO.KEYS.continue
    local keyW = dxGetTextWidth(key, 1, f.bold) + s(16)
    local label = "Continue"
    local labelW = dxGetTextWidth(label, 1, f.bold)
    local x = right - keyW
    local color = state.ready and C.text or C.faint
    frame(x, bottom - s(30), keyW, s(30), math.max(1, s(1.5)), state.ready and C.text or C.edge)
    text(key, x, bottom - s(30), x + keyW, bottom, color, f.bold, "center", "center")
    x = x - s(10) - labelW
    text(label, x, bottom - s(30), x + labelW, bottom, color, f.bold, "left", "center")
    if not state.ready and state.remaining then
        -- countdown ring
        local r = s(14)
        local cx, cy = x - s(14) - r, bottom - s(15)
        dxDrawCircle(cx, cy, r, 0, 360, C.segment, C.segment, 32, 1, true)
        dxDrawCircle(cx, cy, r, -90, -90 + 360 * (state.fraction or 0), C.accent, C.accent, 32, 1, true)
        dxDrawCircle(cx, cy, r - s(3), 0, 360, C.panel, C.panel, 32, 1, true)
        text(tostring(math.ceil(state.remaining)), cx - r, cy - r, cx + r, cy + r, C.text, f.small, "center", "center")
    end
end

function Draw.subtitle(str, bottomOffset)
    local f = Draw.fonts()
    local w = math.min(sw * 0.62, s(1150))
    local x = (sw - w) / 2
    local h = Draw.textHeight(str, w, f.subtitle)
    local y = sh - sh * 0.1 - s(28) - h - (bottomOffset or 0)
    -- shadow for readability on bright skies
    dxDrawText(str, x + 2, y + 2, x + w + 2, y + h + 2, tocolor(0, 0, 0, 220), 1, f.subtitle, "center", "top", false, true, true)
    dxDrawText(str, x, y, x + w, y + h, C.text, 1, f.subtitle, "center", "top", false, true, true)
end

function Draw.bigTitle(small, big)
    local f = Draw.fonts()
    local x, y = s(70), sh * 0.5
    text(small:upper(), x, y, sw, y + s(24), C.muted, f.label, "left", "top")
    text(big:upper(), x - s(3), y + s(22), sw, y + s(110), C.text, f.big, "left", "top")
end

function Draw.toast(str, alpha)
    local f = Draw.fonts()
    local w = dxGetTextWidth(str, 1, f.label) + s(28)
    local x, y, h = (sw - w) / 2, s(74), s(34)
    dxDrawRectangle(x, y, w, h, tocolor(10, 13, 19, 220 * alpha), true)
    dxDrawRectangle(x, y + h - s(3), w, s(3), tocolor(242, 171, 47, 255 * alpha), true)
    text(str, x, y, x + w, y + h, tocolor(236, 239, 243, 255 * alpha), f.label, "center", "center")
end

---------------------------------------------------------------- card

-- spec = { step, title, text, tasks = { { text, done, current } }, note }
-- -> bounds { x, y, w, h }
function Draw.card(spec)
    local f = Draw.fonts()
    local W, PAD = s(450), s(22)
    local iw = W - PAD * 2
    local textH = spec.text and Draw.textHeight(spec.text, iw, f.body) or 0
    local taskH = {}
    local h = PAD + (spec.step and s(20) or 0) + s(34) + textH + s(8)
    for i, task in ipairs(spec.tasks or {}) do
        taskH[i] = math.max(s(40), Draw.textHeight(task.text, iw - s(46), f.bold) + s(18))
        h = h + taskH[i] + s(6)
    end
    local noteH = spec.note and (Draw.textHeight(spec.note, iw, f.bold) + s(10)) or 0
    h = h + noteH + PAD

    local x = s(36)
    local y = math.max(s(80), (sh - h) / 2 - s(40))
    dxDrawRectangle(x, y, W, h, C.panel, true)
    dxDrawRectangle(x, y, s(4), h, C.accent, true)

    local cy = y + PAD
    if spec.step then
        text(spec.step:upper(), x + PAD, cy, x + W - PAD, cy + s(18), C.accent, f.small)
        cy = cy + s(20)
    end
    text(spec.title or "", x + PAD, cy, x + W - PAD, cy + s(32), C.text, f.title)
    cy = cy + s(34)
    if spec.text then
        text(spec.text, x + PAD, cy, x + PAD + iw, cy + textH, C.text, f.body, "left", "top", true)
        cy = cy + textH + s(8)
    end
    for i, task in ipairs(spec.tasks or {}) do
        local th = taskH[i]
        dxDrawRectangle(x + PAD, cy, iw, th, C.row, true)
        local box = s(18)
        local bx, by = x + PAD + s(12), cy + (th - box) / 2
        if task.done then
            dxDrawRectangle(bx, by, box, box, C.good, true)
        else
            frame(bx, by, box, box, math.max(1, s(2)), task.current and C.accent or C.edge)
        end
        local color = task.done and C.muted or (task.current and C.text or C.faint)
        text(task.text, bx + box + s(14), cy, x + PAD + iw - s(8), cy + th, color, f.bold, "left", "center", true)
        cy = cy + th + s(6)
    end
    if spec.note then
        text(spec.note, x + PAD, cy + s(4), x + PAD + iw, cy + noteH, C.accent, f.bold, "left", "top", true)
    end
    return { x, y, W, h }
end

---------------------------------------------------------------- highlight

-- Darkens everything except `rect` and draws a pulsing frame around it
function Draw.spotlight(rect)
    local pad = s(10)
    local x, y, w, h = rect[1] - pad, rect[2] - pad, rect[3] + pad * 2, rect[4] + pad * 2
    dxDrawRectangle(0, 0, sw, y, C.dim, true)
    dxDrawRectangle(0, y + h, sw, sh - y - h, C.dim, true)
    dxDrawRectangle(0, y, x, h, C.dim, true)
    dxDrawRectangle(x + w, y, sw - x - w, h, C.dim, true)
    local pulse = 0.5 + 0.5 * math.sin(getTickCount() / 200)
    frame(x, y, w, h, s(3), tocolor(242, 171, 47, 150 + 105 * pulse))
end

function Draw.dimAll()
    dxDrawRectangle(0, 0, sw, sh, C.dim, true)
end

-- A small labelled box next to a point of the screen
function Draw.callout(x, y, title, str)
    local f = Draw.fonts()
    local W, PAD = s(330), s(14)
    local th = Draw.textHeight(str, W - PAD * 2, f.body)
    local h = PAD * 2 + s(20) + th
    x = math.min(math.max(s(10), x), sw - W - s(10))
    y = math.min(math.max(s(10), y), sh - h - s(10))
    dxDrawRectangle(x, y, W, h, C.panel, true)
    frame(x, y, W, h, 1, C.accentSoft)
    text(title:upper(), x + PAD, y + PAD, x + W - PAD, y + PAD + s(18), C.accent, f.small)
    text(str, x + PAD, y + PAD + s(20), x + W - PAD, y + h - PAD, C.text, f.body, "left", "top", true)
end

---------------------------------------------------------------- world

-- A pulsing ring on the ground and a label above it (the world scene)
function Draw.worldPoint(px, py, pz, label, radius)
    radius = radius or 3
    local pulse = 0.5 + 0.5 * math.sin(getTickCount() / 260)
    local color = tocolor(242, 171, 47, 140 + 100 * pulse)
    local segments = 40
    for i = 0, segments - 1 do
        local a1, a2 = (i / segments) * math.pi * 2, ((i + 1) / segments) * math.pi * 2
        dxDrawLine3D(px + math.cos(a1) * radius, py + math.sin(a1) * radius, pz + 0.05,
            px + math.cos(a2) * radius, py + math.sin(a2) * radius, pz + 0.05, color, 6)
    end
    dxDrawLine3D(px, py, pz, px, py, pz + 6, tocolor(242, 171, 47, 120), 2)
    if label then
        local x, y = getScreenFromWorldPosition(px, py, pz + 6.5, 0.1)
        if x then
            local f = Draw.fonts()
            local w = dxGetTextWidth(label, 1, f.label) + s(28)
            local h = s(36)
            dxDrawRectangle(x - w / 2, y - h, w, h, C.panel, true)
            dxDrawRectangle(x - w / 2, y - s(3), w, s(3), C.accent, true)
            text(label, x - w / 2, y - h, x + w / 2, y - s(3), C.text, f.label, "center", "center")
        end
    end
end

-- "Look for this icon on your map" box, bottom left (the world scene)
function Draw.mapIcon(image, str)
    local f = Draw.fonts()
    local icon = s(34)
    local tw = dxGetTextWidth(str, 1, f.bold)
    local w, h = icon + tw + s(40), s(52)
    local x, y = s(36), sh - sh * 0.1 - h - s(20)
    dxDrawRectangle(x, y, w, h, C.panel, true)
    if image then
        dxDrawImage(x + s(12), y + (h - icon) / 2, icon, icon, image, 0, 0, 0, tocolor(255, 255, 255), true)
    else
        dxDrawCircle(x + s(12) + icon / 2, y + h / 2, icon / 2, 0, 360, C.accent, C.accent, 24, 1, true)
    end
    text(str, x + icon + s(24), y, x + w, y + h, C.text, f.bold, "left", "center")
end
