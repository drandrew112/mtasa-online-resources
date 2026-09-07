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
--   rows[i] = { title=, subtitle=, image=, circle=bool, right= }
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

function PhoneUI.drawList(rows, selected, opts)
    opts = opts or {}
    local s = PhoneUI.SCREEN
    local rowH = PhoneUI.rowH
    local x, w = s.x + u(12), s.w - u(24)
    local top  = s.y + u(10)

    if #rows == 0 then
        PhoneUI.drawEmpty(opts.empty or "Nothing here yet")
        return
    end

    for i, row in ipairs(rows) do
        local y = top + (i - 1) * rowH
        if y + rowH - u(6) > s.y + s.h then break end

        local rh = rowH - u(6)
        if i == selected then PhoneUI.selection("list_sel_" .. i, x, y, w, rh) end

        local tx = x + u(14)
        if row.image or row.swatch then
            local ps = rh - u(10)
            if row.image then
                PhoneUI.rounded("list_img_" .. i, x + u(8), y + u(5), ps, ps,
                    row.circle and ps * 0.5 or u(6), row.image, 255, 255, 255, 255)
            else
                local c = row.swatch
                PhoneUI.rounded("list_img_" .. i, x + u(8), y + u(5), ps, ps, u(6),
                    PhoneShader.WHITE, c[1], c[2], c[3], 255)
            end
            tx = x + u(16) + ps
        end

        if row.subtitle and row.subtitle ~= "" then
            PhoneUI.text(row.title, tx, y + u(5), w - u(28), u(20), PhoneUI.C.white, u(1.05), "default-bold", "left", "top")
            PhoneUI.text(row.subtitle, tx, y + u(24), w - u(28), u(18), PhoneUI.C.dim, u(0.9), "default", "left", "top")
        else
            PhoneUI.text(row.title, tx, y, w - u(28) - (row.right and u(70) or 0), rh, PhoneUI.C.white, u(1.08), "default-bold", "left", "center")
        end

        if row.right then
            PhoneUI.text(row.right, x + w - u(76), y, u(70), rh, PhoneUI.C.good, u(0.9), "default-bold", "right", "center")
        end
    end

    if opts.hint then
        PhoneUI.text(opts.hint, s.x, s.y + s.h - u(20), s.w, u(18), PhoneUI.C.faint, u(0.85), "default", "center", "top")
    end
end
