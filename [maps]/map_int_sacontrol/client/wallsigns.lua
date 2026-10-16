if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Draws the wall signs from shared/wallsigns.lua: each sign is rendered once into its own
-- render target (again after a device restore) and drawn with dxDrawMaterialLine3D.

local signs = {}
local fonts = {}

local function getFont(bold, px)
    px = math.max(8, math.floor(px + 0.5))
    local key = (bold and "b" or "r") .. px
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "fonts/RobotoB.ttf" or "fonts/Roboto.ttf", px, false, "antialiased") or false
    end
    return fonts[key] or "default-bold"
end

local function rgba(c, a)
    return tocolor(c[1], c[2], c[3], a or c[4] or 255)
end

local function renderSign(s)
    local rw, rh = s.rw, s.rh
    dxSetRenderTarget(s.rt, true)
    dxSetBlendMode("modulate_add")
    local bg, border = s.def.bg or WS.BG, s.def.border or WS.BORDER
    local bw = math.max(2, math.floor(rh * 0.04))
    dxDrawRectangle(0, 0, rw, rh, rgba(border))
    dxDrawRectangle(bw, bw, rw - bw * 2, rh - bw * 2, rgba(bg))

    -- line heights: size 1 = 45% of the plate height
    -- shrunk together (fit) when the widest line would not fit between the side margins
    local lines, total, fit = {}, 0, 1
    local maxW = rw - rh * 0.25
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
        dxDrawText(ln.l.text, bw, y, rw - bw, y + lh, rgba(ln.l.color or WS.TEXT), fit, ln.font, "center", "center", true)
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
    for _, def in ipairs(WS.SIGNS) do
        local rw, rh = math.floor(def.w * WS.PPM), math.floor(def.h * WS.PPM)
        local s = {
            def = def, rw = rw, rh = rh,
            rt = dxCreateRenderTarget(rw, rh, true),
            cx = def.x + def.nx * WS.OFFSET, cy = def.y + def.ny * WS.OFFSET, cz = def.z,
            int = def.int or WS.INT, dim = def.dim or WS.DIM,
            dirty = true,
        }
        signs[#signs + 1] = s
    end
end

addEventHandler("onClientResourceStart", resourceRoot, buildSigns)

addEventHandler("onClientRestore", root, function(cleared)
    if cleared then
        for _, s in ipairs(signs) do s.dirty = true end
    end
end)

addEventHandler("onClientRender", root, function()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    -- a copy of the interior in this dimension (server/copies.lua) shows the dimension 0 signs too
    local copies = getElementData(resourceRoot, "sac.copies")
    local copyDim = type(copies) == "table" and copies[dim] == true
    local cx, cy, cz = getCameraMatrix()
    local white = tocolor(255, 255, 255, 255)
    for _, s in ipairs(signs) do
        if s.int == int and (s.dim == dim or (copyDim and s.dim == 0)) and isElement(s.rt)
            and ((cx - s.cx) * s.def.nx + (cy - s.cy) * s.def.ny) > 0
            and getDistanceBetweenPoints3D(cx, cy, cz, s.cx, s.cy, s.cz) < WS.DRAW_DIST then
            if s.dirty then renderSign(s) end
            local d = s.def
            dxDrawMaterialLine3D(s.cx, s.cy, s.cz + d.h / 2, s.cx, s.cy, s.cz - d.h / 2,
                false, s.rt, d.w, white, s.cx + d.nx * 10, s.cy + d.ny * 10, s.cz)
        end
    end
end)
