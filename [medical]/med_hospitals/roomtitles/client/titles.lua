-- Draws the room titles from roomtitles/shared/config.lua: each sign is rendered once into its own
-- render target (black rounded plate, white text; again after a device restore or a language change)
-- and drawn with dxDrawMaterialLine3D (same method as the SA Control wall signs).

local signs = {}
local fonts = {}
local drawing = false
local drawSigns

local function getFont(bold, px)
    px = math.max(8, math.floor(px + 0.5))
    local key = (bold and "b" or "r") .. px
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", px, false, "antialiased") or false
    end
    return fonts[key] or "default-bold"
end

local function rgba(c, a)
    return tocolor(c[1], c[2], c[3], a or c[4] or 255)
end

-- rounded rectangle from rows (no overlap, so it also works in additive render target blending)
local function drawRoundedRect(x, y, w, h, r, color)
    r = math.floor(math.min(r, w / 2, h / 2))
    dxDrawRectangle(x, y + r, w, h - 2 * r, color)
    for i = 0, r - 1 do
        local dy = r - i - 0.5
        local inset = math.floor(r - math.sqrt(r * r - dy * dy) + 0.5)
        dxDrawRectangle(x + inset, y + i, w - 2 * inset, 1, color)
        dxDrawRectangle(x + inset, y + h - 1 - i, w - 2 * inset, 1, color)
    end
end

local function renderSign(s)
    local rw, rh = s.rw, s.rh
    dxSetRenderTarget(s.rt, true)
    dxSetBlendMode("modulate_add")
    drawRoundedRect(0, 0, rw, rh, rh * RT.RADIUS, rgba(s.def.bg or RT.BG))

    -- line heights: size 1 = 45% of the plate height, shrunk together when the widest line is too wide
    local lines, total, fit = {}, 0, 1
    local maxW = rw - rh * 0.5
    for _, l in ipairs(s.def.lines) do
        local px = rh * 0.45 * (l.size or 1) * 0.75
        local font = getFont(l.bold, px)
        local tw = L.width(l.text, 1, font)
        if tw > maxW then fit = math.min(fit, maxW / tw) end
        lines[#lines + 1] = { l = l, font = font, h = dxGetFontHeight(1, font) }
    end
    for _, ln in ipairs(lines) do total = total + ln.h * fit end
    local y = (rh - total) / 2
    for _, ln in ipairs(lines) do
        local lh = ln.h * fit
        dxDrawText(ln.l.text, 0, y, rw, y + lh, rgba(ln.l.color or RT.TEXT), fit, ln.font, "center", "center", true)
        y = y + lh
    end
    dxSetBlendMode("blend")
    dxSetRenderTarget()
    s.dirty = false
end

local function buildSigns()
    for _, s in ipairs(signs) do
        if isElement(s.rt) then destroyElement(s.rt) end
    end
    signs = {}
    for _, def in ipairs(RT.SIGNS or {}) do
        local rw, rh = math.floor(def.w * RT.PPM), math.floor(def.h * RT.PPM)
        signs[#signs + 1] = {
            def = def, rw = rw, rh = rh,
            rt = dxCreateRenderTarget(rw, rh, true),
            cx = def.x + def.nx * RT.OFFSET, cy = def.y + def.ny * RT.OFFSET, cz = def.z,
            int = def.int or RT.INT, dim = def.dim or RT.DIM,
            dirty = true,
        }
    end
end

-- the draw handler is attached only while the local player is in an interior / dimension that has signs
local function syncSigns()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local on = false
    for _, s in ipairs(signs) do
        if s.int == int and s.dim == dim then on = true break end
    end
    if on == drawing then return end
    drawing = on
    if on then
        addEventHandler("onClientRender", root, drawSigns)
    else
        removeEventHandler("onClientRender", root, drawSigns)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    buildSigns()
    syncSigns()
end)
addEventHandler("onClientElementInteriorChange", localPlayer, syncSigns, false)
addEventHandler("onClientElementDimensionChange", localPlayer, syncSigns, false)
addEventHandler("onClientPlayerSpawn", localPlayer, syncSigns, false)

addEventHandler("onClientRestore", root, function(cleared)
    if cleared then
        for _, s in ipairs(signs) do s.dirty = true end
    end
end)

-- language change: L.config re-runs RT first, the textures are rebuilt right after
L.onChange(function()
    setTimer(function() buildSigns() syncSigns() end, 100, 1)
end)

drawSigns = function()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local cx, cy, cz = getCameraMatrix()
    local white = tocolor(255, 255, 255, 255)
    for _, s in ipairs(signs) do
        if s.int == int and s.dim == dim and isElement(s.rt)
            and ((cx - s.cx) * s.def.nx + (cy - s.cy) * s.def.ny) > 0
            and getDistanceBetweenPoints3D(cx, cy, cz, s.cx, s.cy, s.cz) < RT.DRAW_DIST then
            if s.dirty then renderSign(s) end
            local d = s.def
            dxDrawMaterialLine3D(s.cx, s.cy, s.cz + d.h / 2, s.cx, s.cy, s.cz - d.h / 2,
                false, s.rt, d.w, white, s.cx + d.nx * 10, s.cy + d.ny * 10, s.cz)
        end
    end
end
