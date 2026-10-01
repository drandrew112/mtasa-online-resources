-- 3D DX labels above every hospital marker (bay / handover / heal) + the local player's
-- progress bar (stretcher handover 5 s, treatment 15 s). Occupied bays have no label (and an
-- invisible marker, set by the server).

local sw, sh = guiGetScreenSize()
local function s(v) return v * sh / 1080 end

local fonts = {}
local function font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", s(size), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local STYLE = {
    bay      = { color = { 230, 190, 40 },  icon = "P" },
    handover = { color = { 56, 132, 244 },  icon = "cross" },
    heal     = { color = { 46, 160, 67 },   icon = "cross" },
}

local markers = {}   -- list of hospital markers of this resource
local progress = nil -- { marker, start, duration, text }

local function refresh()
    markers = {}
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, HOSP_DATA.KIND) then markers[#markers + 1] = m end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    refresh()
    setTimer(refresh, 1000, 0)
end)

addEvent("hosp:progress", true)
addEventHandler("hosp:progress", resourceRoot, function(marker, duration, text)
    progress = { marker = marker, start = getTickCount(), duration = tonumber(duration) or 1000, text = tostring(text or "") }
end)

addEvent("hosp:progressStop", true)
addEventHandler("hosp:progressStop", resourceRoot, function()
    progress = nil
end)

---------------------------------------------------------------- drawing

local function rgb(c, a) return tocolor(c[1], c[2], c[3], a or 255) end

local function round(x, y, w, h, r, color)
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

local function cross(x, y, size, color)
    local t = size / 3
    dxDrawRectangle(x + t, y, t, size, color)
    dxDrawRectangle(x, y + t, size, t, color)
end

local function drawLabel(sx, sy, k, alpha, kind, name, prog)
    local st = STYLE[kind]
    local text = HOSP_TEXT[kind]
    local fTitle, fName, fHint = font(13, true), font(9, true), font(9)
    local a = alpha / 255

    local pad, icon, gap = s(10) * k, s(34) * k, s(10) * k
    local nameStr = name:upper()
    local textW = math.max(dxGetTextWidth(text.title, k, fTitle), dxGetTextWidth(nameStr, k, fName),
        dxGetTextWidth(text.hint, k, fHint))
    local w = pad + icon + gap + textW + pad * 1.4
    local headH = s(46) * k
    local hintH = s(22) * k
    local progH = prog and s(30) * k or 0
    local h = headH + hintH + progH
    local x, y = sx - w / 2, sy - h

    round(x, y, w, h, s(7) * k, tocolor(14, 17, 21, 220 * a))
    round(x, y + h - s(3) * k, w, s(3) * k, s(1.5) * k, rgb(st.color, 235 * a))

    -- icon tile
    local ix, iy = x + pad, y + (headH - icon) / 2 + s(2) * k
    round(ix, iy, icon, icon, s(5) * k, rgb(st.color, 240 * a))
    if st.icon == "cross" then
        local c = icon * 0.62
        cross(ix + (icon - c) / 2, iy + (icon - c) / 2, c, tocolor(255, 255, 255, 255 * a))
    else
        dxDrawText(st.icon, ix, iy, ix + icon, iy + icon, tocolor(20, 20, 20, 255 * a), k, font(16, true), "center", "center")
    end

    -- title / hospital name
    local tx = ix + icon + gap
    dxDrawText(nameStr, tx, y + s(6) * k, tx + textW, y + headH * 0.45, rgb(st.color, 255 * a), k, fName, "left", "center")
    dxDrawText(text.title, tx, y + headH * 0.42, tx + textW, y + headH, tocolor(255, 255, 255, 255 * a), k, fTitle, "left", "center")

    -- hint
    local hy = y + headH
    dxDrawText(text.hint, x + pad, hy, x + w - pad, hy + hintH, tocolor(200, 205, 212, 220 * a), k, fHint, "left", "center")

    -- progress
    if prog then
        local py = hy + hintH
        local bx, bw, bh = x + pad, w - pad * 2, s(8) * k
        local elapsed = getTickCount() - prog.start
        local f = math.min(1, elapsed / prog.duration)
        local left = math.max(0, math.ceil((prog.duration - elapsed) / 1000))
        dxDrawText(prog.text, bx, py, bx + bw, py + s(14) * k, tocolor(255, 255, 255, 240 * a), k, fHint, "left", "center")
        dxDrawText(left .. " s", bx, py, bx + bw, py + s(14) * k, rgb(st.color, 255 * a), k, font(9, true), "right", "center")
        local by = py + s(16) * k
        round(bx, by, bw, bh, bh / 2, tocolor(255, 255, 255, 40 * a))
        if f > 0 then round(bx, by, math.max(bh, bw * f), bh, bh / 2, rgb(st.color, 255 * a)) end
    end

    -- pointer
    dxDrawRectangle(sx - s(1) * k, y + h, s(2) * k, s(10) * k, tocolor(14, 17, 21, 220 * a))
end

addEventHandler("onClientRender", root, function()
    if #markers == 0 or isPlayerMapVisible() then return end
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local maxDist, fullDist = HOSP.LABEL_DISTANCE, HOSP.LABEL_FULL_DISTANCE

    for _, m in ipairs(markers) do
        if isElement(m) and getElementDimension(m) == dim and getElementInterior(m) == int then
            local kind = getElementData(m, HOSP_DATA.KIND)
            local x, y, z = getElementPosition(m)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local prog = progress and progress.marker == m and progress or nil
            local occupied = kind == "bay" and getElementData(m, HOSP_DATA.OCCUPIED)

            if STYLE[kind] and dist <= maxDist and not occupied then
                local lz = z + HOSP.LABEL_HEIGHT
                if isLineOfSightClear(cx, cy, cz, x, y, lz, true, false, false, true, false, false, false) then
                    local sx, sy = getScreenFromWorldPosition(x, y, lz, 0.1)
                    if sx then
                        local k = 1
                        if dist > fullDist then
                            k = 1 - (dist - fullDist) / (maxDist - fullDist) * (1 - HOSP.LABEL_MIN_SCALE)
                        end
                        local alpha = 255
                        if dist > maxDist * 0.8 then alpha = 255 * (maxDist - dist) / (maxDist * 0.2) end
                        drawLabel(sx, sy, k, alpha, kind, tostring(getElementData(m, HOSP_DATA.NAME) or ""), prog)
                    end
                end
            end
        end
    end
end)

-- /hosppos: the server sends the formatted position, setClipboard is client-only
addEvent("hosp:clipboard", true)
addEventHandler("hosp:clipboard", resourceRoot, function(text)
    if type(text) == "string" then setClipboard(text) end
end)
