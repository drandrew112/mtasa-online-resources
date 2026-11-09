-- maps_loader extras (was map_int_sacontrol/client/wallsigns.lua). Draws the wall signs of
-- extras/sacontrol/signs_shared.lua: each sign is rendered once into its own
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
        local text = l.key and L.text(l.key) or l.text or ""
        local tw = L.width(text, 1, font)
        if tw > maxW then fit = math.min(fit, maxW / tw) end
        lines[#lines + 1] = { l = l, text = text, font = font, h = dxGetFontHeight(1, font) }
    end
    for _, ln in ipairs(lines) do total = total + ln.h * fit end
    local y = (rh - total) / 2
    for _, ln in ipairs(lines) do
        local lh = ln.h * fit
        dxDrawText(ln.text, bw, y, rw - bw, y + lh, rgba(ln.l.color or WS.TEXT), fit, ln.font, "center", "center", true)
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

-- is the int_sacontrol map loaded in this dimension too (maps_loader dimension copy)?
function signCopyDim(dim)
    local dims = getElementData(resourceRoot, DATA_DIMS)
    local byDim = type(dims) == "table" and dims.int_sacontrol
    return type(byDim) == "table" and (byDim[dim] ~= nil or byDim[tostring(dim)] ~= nil)
end

local drawSigns
-- the signs are drawn only while the local player is in an interior / dimension that has signs
-- (checked at start and on every interior, dimension or maps_loader dimension list change)
local drawing = false
local function syncSigns()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local copyDim = signCopyDim(dim)
    local on = false
    for _, s in ipairs(signs) do
        if s.int == int and (s.dim == dim or (copyDim and s.dim == 0)) then on = true break end
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
addEventHandler("onClientElementDataChange", resourceRoot, function(key)
    if key == DATA_DIMS then syncSigns() end
end, false)

-- texts follow the language: redraw every sign
local function redrawAll() for _, s in ipairs(signs) do s.dirty = true end end
if L.onChange then L.onChange(redrawAll) end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, redrawAll)

addEventHandler("onClientRestore", root, function(cleared)
    if cleared then
        for _, s in ipairs(signs) do s.dirty = true end
    end
end)

drawSigns = function()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    -- a copy of the interior in this dimension (loadMapInDimension) shows the dimension 0 signs too
    local copyDim = signCopyDim(dim)
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
end
