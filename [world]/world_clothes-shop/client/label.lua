if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- world_clothes-shop / client/label.lua
-- Marker UI of the changer markers (same look as the work_core / med_hospitals labels):
-- a 3D DX label above the marker, and while the outfit list is open the same box fixed at
-- the bottom of the screen (the camera looks at the player then). Purchase results show in it.

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

local GREEN, RED = { 70, 190, 90 }, { 218, 54, 51 }
local LBL = CLOTHES.label

local markers = {}

local function refresh()
    markers = {}
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, "clothes:shop") then markers[#markers + 1] = m end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    refresh()
    setTimer(refresh, 1000, 0)
end)

-- -> color, icon, name, title, hint
local function labelFor(marker)
    local shop = CLOTHES.shopById[getElementData(marker, "clothes:shop")]
    local int = shop and CLOTHES.interiors[shop.interior]
    local name = int and int.name or L("world_clothes_shop.label.clothes")
    local color, hint = LBL.color, nil

    if marker == ChangerMarker and Status and getTickCount() < Status.untilTick then
        color, hint = Status.ok and GREEN or RED, Status.text
    elseif isClothesMenuOpen() then
        hint = L("world_clothes_shop.label.every_outfit_enter_buy_backspace_back", { price = CLOTHES.price })
    elseif marker == ChangerMarker then
        hint = L("world_clothes_shop.label.press_browse_outfits_each", { key = CLOTHES.key:upper(), price = CLOTHES.price })
    else
        hint = L("world_clothes_shop.label.outfits_each", { price = CLOTHES.price })
    end
    return color, L.upper(L.sub(name, 1, 1)), name, L("world_clothes_shop.label.changing_room"), hint
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

-- sx, sy = bottom centre of the box; stem = draw the pointer under it
local function drawLabel(sx, sy, k, alpha, color, icon, name, title, hint, stem)
    local fTitle, fName, fHint = font(13, true), font(9, true), font(9)
    local a = alpha / 255

    local pad, iconSize, gap = s(10) * k, s(34) * k, s(10) * k
    local nameStr = L.upper(name)
    local textW = math.max(L.width(title, k, fTitle), L.width(nameStr, k, fName),
        L.width(hint, k, fHint))
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

    if stem then
        dxDrawRectangle(sx - s(1) * k, y + h, s(2) * k, s(10) * k, tocolor(14, 17, 21, 220 * a))
    end
end

addEventHandler("onClientRender", root, function()
    if #markers == 0 or isPlayerMapVisible() then return end

    -- outfit list open: fixed box at the bottom of the screen
    if isClothesMenuOpen() and isElement(ChangerMarker) then
        local color, icon, name, title, hint = labelFor(ChangerMarker)
        drawLabel(sw / 2, sh - s(60), 1, 255, color, icon, name, title, hint, false)
        return
    end

    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)

    for _, m in ipairs(markers) do
        if isElement(m) and getElementDimension(m) == dim and getElementInterior(m) == int then
            local x, y, z = getElementPosition(m)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local lz = z + LBL.height
            if dist <= LBL.distance
                and isLineOfSightClear(cx, cy, cz, x, y, lz, true, false, false, true, false, false, false) then
                local sx, sy = getScreenFromWorldPosition(x, y, lz, 0.1)
                if sx then
                    local k = 1
                    if dist > LBL.fullDistance then
                        k = 1 - (dist - LBL.fullDistance) / (LBL.distance - LBL.fullDistance) * (1 - LBL.minScale)
                    end
                    local alpha = 255
                    if dist > LBL.distance * 0.8 then alpha = 255 * (LBL.distance - dist) / (LBL.distance * 0.2) end
                    local color, icon, name, title, hint = labelFor(m)
                    drawLabel(sx, sy, k, alpha, color, icon, name, title, hint, true)
                end
            end
        end
    end
end, true, "high+5") -- drawn before (under) the pause menu and other UI
