-- 3D DX labels above the work markers (same look as the med_hospitals labels). Vehicle
-- markers are labelled only for the players on duty in their work.

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

local RED = { 218, 54, 51 }

local markers = {}

local function refresh()
    markers = {}
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, WORK_DATA.MARKER_KIND) then markers[#markers + 1] = m end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    refresh()
    setTimer(refresh, 1000, 0)
end)

-- -> color, icon, title, hint
local function labelFor(marker, kind, work)
    local mine = getPlayerWork(localPlayer)
    local key = WORK.KEY:upper()
    local icon = work.name:sub(1, 1):upper()

    if kind == "duty" then
        if mine and mine ~= work.id then
            local other = Works[mine]
            return RED, "!", work.name,
                ("You are working as %s · go off duty first"):format(other and other.name or mine)
        elseif mine == work.id then
            return work.color, icon, "On Duty", ("Press %s · outfit / go off duty"):format(key)
        end
        return work.color, icon, "Go On Duty", ("Press %s · choose your outfit"):format(key)
    end

    -- vehicle marker
    if mine ~= work.id then return nil end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if vehicle and getElementData(vehicle, WORK_DATA.VEHICLE_OWNER) == localPlayer then
        return work.color, "V", "Work Vehicles", ("Press %s · return the vehicle"):format(key)
    end
    return work.color, "V", "Work Vehicles", ("Press %s · request a vehicle"):format(key)
end

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

local function drawLabel(sx, sy, k, alpha, color, icon, name, title, hint)
    local fTitle, fName, fHint = font(13, true), font(9, true), font(9)
    local a = alpha / 255

    local pad, iconSize, gap = s(10) * k, s(34) * k, s(10) * k
    local nameStr = name:upper()
    local textW = math.max(dxGetTextWidth(title, k, fTitle), dxGetTextWidth(nameStr, k, fName),
        dxGetTextWidth(hint, k, fHint))
    local w = pad + iconSize + gap + textW + pad * 1.4
    local headH, hintH = s(46) * k, s(22) * k
    local h = headH + hintH
    local x, y = sx - w / 2, sy - h

    round(x, y, w, h, s(7) * k, tocolor(14, 17, 21, 220 * a))
    round(x, y + h - s(3) * k, w, s(3) * k, s(1.5) * k, rgb(color, 235 * a))

    local ix, iy = x + pad, y + (headH - iconSize) / 2 + s(2) * k
    round(ix, iy, iconSize, iconSize, s(5) * k, rgb(color, 240 * a))
    dxDrawText(icon, ix, iy, ix + iconSize, iy + iconSize, tocolor(255, 255, 255, 255 * a), k, font(16, true), "center", "center")

    local tx = ix + iconSize + gap
    dxDrawText(nameStr, tx, y + s(6) * k, tx + textW, y + headH * 0.45, rgb(color, 255 * a), k, fName, "left", "center")
    dxDrawText(title, tx, y + headH * 0.42, tx + textW, y + headH, tocolor(255, 255, 255, 255 * a), k, fTitle, "left", "center")

    local hy = y + headH
    dxDrawText(hint, x + pad, hy, x + w - pad, hy + hintH, tocolor(200, 205, 212, 220 * a), k, fHint, "left", "center")

    dxDrawRectangle(sx - s(1) * k, y + h, s(2) * k, s(10) * k, tocolor(14, 17, 21, 220 * a))
end

addEventHandler("onClientRender", root, function()
    if #markers == 0 or isPlayerMapVisible() then return end
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local maxDist, fullDist = WORK.LABEL_DISTANCE, WORK.LABEL_FULL_DISTANCE

    for _, m in ipairs(markers) do
        if isElement(m) and getElementDimension(m) == dim and getElementInterior(m) == int then
            local x, y, z = getElementPosition(m)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local work = Works[getElementData(m, WORK_DATA.MARKER_WORK)]
            if work and dist <= maxDist then
                local color, icon, title, hint = labelFor(m, getElementData(m, WORK_DATA.MARKER_KIND), work)
                local lz = z + WORK.LABEL_HEIGHT
                if color and isLineOfSightClear(cx, cy, cz, x, y, lz, true, false, false, true, false, false, false) then
                    local sx, sy = getScreenFromWorldPosition(x, y, lz, 0.1)
                    if sx then
                        local k = 1
                        if dist > fullDist then
                            k = 1 - (dist - fullDist) / (maxDist - fullDist) * (1 - WORK.LABEL_MIN_SCALE)
                        end
                        local alpha = 255
                        if dist > maxDist * 0.8 then alpha = 255 * (maxDist - dist) / (maxDist * 0.2) end
                        drawLabel(sx, sy, k, alpha, color, icon, work.name, title, hint)
                    end
                end
            end
        end
    end
end)
