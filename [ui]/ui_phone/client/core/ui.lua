if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
--[[
    ui_phone / client/core/ui.lua
    Geometry, palette and the shared drawing helpers (incl. the standard list
    renderer most apps use).
]]

PhoneUI = {}

local sw, sh = guiGetScreenSize()
local SCALE  = math.min(sw / 1920, sh / 1080)
local function u(v) return v * SCALE end
PhoneUI.u = u

--------------------------------------------------------------------------------
-- Geometry
--------------------------------------------------------------------------------

local cfg   = PHONE_CONFIG
local safe  = u(48)
local M     = u(cfg.bezel)
local R     = u(cfg.radius)

local PW    = u(cfg.width)
local PH    = math.min(u(cfg.height), sh - safe * 2)
local PX    = sw - safe - PW
local PY    = sh - safe - PH

local IX    = PX + M
local IW    = PW - M * 2
local STATH = u(cfg.statusH)
local HEADH = u(cfg.headerH)

PhoneUI.M, PhoneUI.R = M, R
PhoneUI.rowH = u(cfg.rowH)

PhoneUI.phone  = { x = PX, y = PY, w = PW, h = PH }
PhoneUI.inner  = { x = IX, w = IW }
PhoneUI.status = { x = IX, y = PY + M,                  w = IW, h = STATH }
PhoneUI.header = { x = IX, y = PY + M + STATH,          w = IW, h = HEADH }
PhoneUI.SCREEN = {
    x = IX,
    y = PY + M + STATH + HEADH,
    w = IW,
    h = (PY + PH - M) - (PY + M + STATH + HEADH),
}

--------------------------------------------------------------------------------
-- Palette
--------------------------------------------------------------------------------

PhoneUI.C = {
    bezel   = { 6, 7, 9 },
    header  = tocolor(24, 26, 32, 255),
    line    = tocolor(255, 255, 255, 22),
    white   = tocolor(255, 255, 255, 255),
    dim     = tocolor(255, 255, 255, 125),
    faint   = tocolor(255, 255, 255, 70),
    selBg   = { 255, 255, 255 },      -- used with low alpha
    accent  = { 90, 170, 255 },
    good    = tocolor(70, 200, 120, 255),
    bad     = tocolor(255, 120, 120, 255),   -- light red (e.g. a destroyed vehicle)
    badge   = { 224, 48, 48 },
    tile    = { 44, 48, 58 },
}

--------------------------------------------------------------------------------
-- Primitive helpers
--------------------------------------------------------------------------------

PhoneUI.rounded = PhoneShader.rounded
PhoneUI.texture = PhoneShader.texture
local WHITE = PhoneShader.WHITE

function PhoneUI.text(str, x, y, w, h, color, size, font, ax, ay)
    dxDrawText(tostring(str), x, y, x + w, y + h,
        color or PhoneUI.C.white, size or u(1),
        font or "default", ax or "left", ay or "center",
        false, false, false, true)
end

function PhoneUI.image(x, y, w, h, path, color)
    local t = PhoneShader.texture(path)
    if t then dxDrawImage(x, y, w, h, t, 0, 0, 0, color or PhoneUI.C.white) end
end

--------------------------------------------------------------------------------
-- Standard list
--   rows[i] = { title=, subtitle=, image=, circle=bool, right=, rightColor= }
--   opts    = { hint=, empty= }
--------------------------------------------------------------------------------

function PhoneUI.drawEmpty(msg)
    local s = PhoneUI.SCREEN
    PhoneUI.text(msg, s.x + u(16), s.y, s.w - u(32), s.h, PhoneUI.C.dim, u(1.1), "default", "center", "center")
end

--- Draw one selection background (call for the selected row only).
function PhoneUI.selection(key, x, y, w, h)
    local c = PhoneUI.C
    PhoneUI.rounded(key,        x, y, w, h, u(10), WHITE, c.selBg[1], c.selBg[2], c.selBg[3], 28)
    PhoneUI.rounded(key .. "e", x, y, u(3), h, u(2), WHITE, c.accent[1], c.accent[2], c.accent[3], 255)
end

--- Height of one text line.
function PhoneUI.lineH(scale, font)
    return dxGetFontHeight(scale, font or "default")
end

--- Word-wrapped lines of `text` that fit `w` (shared table: do not modify).
--  maxLines cuts the rest and ends the last line with "…".
function PhoneUI.wrap(text, w, scale, font, maxLines)
    local lines = L.wrap(tostring(text or ""), w, scale, font, true)
    if not maxLines or #lines <= maxLines then return lines end
    local out = {}
    for i = 1, maxLines - 1 do out[i] = lines[i] end
    out[maxLines] = L.fit(lines[maxLines] .. " " .. lines[maxLines + 1], w, scale, font, true)
    return out
end

--- Draws pre-wrapped lines from (x, y) down; returns the height used.
function PhoneUI.lines(lines, x, y, w, color, scale, font, ax)
    local lh = PhoneUI.lineH(scale, font)
    for i, line in ipairs(lines) do
        PhoneUI.text(line, x, y + (i - 1) * lh, w, lh, color, scale, font, ax or "left", "top")
    end
    return #lines * lh
end

--- Small scroll bar at the right edge of the screen (only when it scrolls).
function PhoneUI.scrollBar(viewTop, viewH, scroll, total)
    if total <= viewH + 1 then return end
    local s = PhoneUI.SCREEN
    local barH = math.max(u(24), viewH * viewH / total)
    local y = viewTop + (viewH - barH) * math.min(1, scroll / (total - viewH))
    dxDrawRectangle(s.x + s.w - u(5), y, u(3), barH, PhoneUI.C.faint)
end

-- Rows grow with their text: the title and the subtitle are word-wrapped to the
-- row width (row.titleLines / row.subtitleLines cap them, default 3 / 4), and
-- the list scrolls so the selected row stays in view.
local TITLE_S, SUB_S, RIGHT_S = 1.05, 0.9, 0.9
local listScroll = 0

local function rowLayout(row, w, rowH)
    local tx = u(14)
    local ps = rowH - u(16)
    if row.image or row.swatch then tx = u(16) + ps end
    local rightW = 0
    if row.right then
        rightW = math.min(u(110), L.width(row.right, u(RIGHT_S), "default-bold", true)) + u(10)
    end
    local textW = w - tx - u(10) - rightW
    local title = PhoneUI.wrap(row.title, textW, u(TITLE_S), "default-bold", row.titleLines or 3)
    local sub = (row.subtitle and row.subtitle ~= "")
        and PhoneUI.wrap(row.subtitle, textW, u(SUB_S), "default", row.subtitleLines or 4) or nil
    local contentH = #title * PhoneUI.lineH(u(TITLE_S), "default-bold")
    if sub then contentH = contentH + u(2) + #sub * PhoneUI.lineH(u(SUB_S), "default") end
    return {
        tx = tx, ps = ps, rightW = rightW, textW = textW, title = title, sub = sub,
        contentH = contentH, h = math.max(rowH - u(6), contentH + u(14)),
    }
end

function PhoneUI.drawList(rows, selected, opts)
    opts = opts or {}
    local s = PhoneUI.SCREEN
    local x, w = s.x + u(12), s.w - u(24)
    local viewTop = s.y + u(10)
    local viewH = s.y + s.h - (opts.hint and u(26) or u(8)) - viewTop
    local gap = u(6)

    if #rows == 0 then
        listScroll = 0
        PhoneUI.drawEmpty(opts.empty or L("ui_phone.phone.nothing_here_yet"))
        return
    end

    local layouts, offsets, total = {}, {}, 0
    for i, row in ipairs(rows) do
        layouts[i] = rowLayout(row, w, PhoneUI.rowH)
        offsets[i] = total
        total = total + layouts[i].h + gap
    end
    total = total - gap

    -- keep the selected row in view
    local sel = layouts[selected] and selected or 1
    if offsets[sel] < listScroll then listScroll = offsets[sel] end
    if offsets[sel] + layouts[sel].h > listScroll + viewH then listScroll = offsets[sel] + layouts[sel].h - viewH end
    listScroll = math.max(0, math.min(listScroll, math.max(0, total - viewH)))

    for i, row in ipairs(rows) do
        local lay = layouts[i]
        local y = viewTop + offsets[i] - listScroll
        if y >= viewTop - 1 and y + lay.h <= viewTop + viewH + 1 then
            if i == selected then PhoneUI.selection("list_sel_" .. i, x, y, w, lay.h) end

            if row.image or row.swatch then
                local iy = y + (lay.h - lay.ps) / 2
                if row.image then
                    PhoneUI.rounded("list_img_" .. i, x + u(8), iy, lay.ps, lay.ps,
                        row.circle and lay.ps * 0.5 or u(6), row.image, 255, 255, 255, 255)
                else
                    local c = row.swatch
                    PhoneUI.rounded("list_img_" .. i, x + u(8), iy, lay.ps, lay.ps, u(6),
                        PhoneShader.WHITE, c[1], c[2], c[3], 255)
                end
            end

            local ty = y + (lay.h - lay.contentH) / 2
            ty = ty + PhoneUI.lines(lay.title, x + lay.tx, ty, lay.textW, row.titleColor or PhoneUI.C.white, u(TITLE_S), "default-bold")
            if lay.sub then
                PhoneUI.lines(lay.sub, x + lay.tx, ty + u(2), lay.textW, PhoneUI.C.dim, u(SUB_S), "default")
            end

            if row.right then
                PhoneUI.text(L.fit(row.right, lay.rightW - u(10), u(RIGHT_S), "default-bold", true),
                    x + w - lay.rightW, y, lay.rightW - u(8), lay.h,
                    row.rightColor or PhoneUI.C.good, u(RIGHT_S), "default-bold", "right", "center")
            end
        end
    end
    PhoneUI.scrollBar(viewTop, viewH, listScroll, total)

    if opts.hint then
        PhoneUI.text(opts.hint, s.x, s.y + s.h - u(20), s.w, u(18), PhoneUI.C.faint, u(0.85), "default", "center", "top")
    end
end
