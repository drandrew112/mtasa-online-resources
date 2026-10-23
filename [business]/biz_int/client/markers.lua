if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_int / client/markers.lua
-- 3D labels above the entrance / exit markers (world_interiors look) and the
-- interact key: standing in a marker is not enough, BINT.key has to be
-- pressed. When a door leads to several of the player's places, the server
-- sends the list and a ui_inac temp menu asks which one.

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

local markers = {}
local current
local chooseMenu, chooseMarker, chooseUnits

local function refresh()
    markers = {}
    for _, m in ipairs(getElementsByType("marker", resourceRoot)) do
        if getElementData(m, "bizint:kind") then markers[#markers + 1] = m end
    end
end

---------------------------------------------------------------- key

local function onKey()
    if not isElement(current) then return end
    if isCursorShowing() or isChatBoxInputActive() or isMainMenuActive() then return end
    if exports.ui_inac:isTempMenuOpen() then return end
    if isPedInVehicle(localPlayer) then return end
    triggerServerEvent("bizint:use", resourceRoot, current)
end

local function setCurrent(marker)
    if marker == current then return end
    if marker and not current then bindKey(BINT.key, "down", onKey) end
    if not marker and current then unbindKey(BINT.key, "down", onKey) end
    current = marker
    if not marker and chooseMenu then
        exports.ui_inac:closeTempMenu()
    end
end

addEventHandler("onClientMarkerHit", resourceRoot, function(hit, matchingDim)
    if hit ~= localPlayer or not matchingDim or not getElementData(source, "bizint:kind") then return end
    setCurrent(source)
end)

addEventHandler("onClientMarkerLeave", resourceRoot, function(leaver)
    if leaver == localPlayer and source == current then setCurrent(nil) end
end)

addEventHandler("onClientElementDestroy", resourceRoot, function()
    if source == current then setCurrent(nil) end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    refresh()
    setTimer(function()
        refresh()
        if current and (not isElement(current) or not isElementWithinMarker(localPlayer, current)
            or getElementDimension(current) ~= getElementDimension(localPlayer)) then
            setCurrent(nil)
        end
        if not current then
            for _, m in ipairs(markers) do
                if getElementDimension(m) == getElementDimension(localPlayer)
                    and getElementInterior(m) == getElementInterior(localPlayer)
                    and isElementWithinMarker(localPlayer, m) then
                    setCurrent(m)
                    break
                end
            end
        end
    end, 500, 0)
end)

---------------------------------------------------------------- choose (several places behind one door)

addEvent("bizint:choose", true)
addEvent("ui_inac:tempMenuSelect")
addEvent("ui_inac:tempMenuClose")
addEventHandler("bizint:choose", resourceRoot, function(marker, units)
    if type(units) ~= "table" or #units == 0 then return end
    local items = {}
    for _, u in ipairs(units) do
        local label = u.role == "founder" and L("biz_int.choose.own", { name = u.name })
            or L("biz_int.choose.associate", { name = u.name, company = u.companyName })
        items[#items + 1] = { label = label, value = u.unitId, desc = u.companyName }
    end
    chooseMarker, chooseUnits = marker, units
    chooseMenu = exports.ui_inac:createTempMenu({ title = L("biz_int.choose.title"), items = items })
end)

addEventHandler("ui_inac:tempMenuSelect", localPlayer, function(rootId, value)
    if not chooseMenu or rootId ~= chooseMenu then return end
    local marker = chooseMarker
    exports.ui_inac:closeTempMenu()
    triggerServerEvent("bizint:choose", resourceRoot, marker, value)
end)

addEventHandler("ui_inac:tempMenuClose", localPlayer, function(rootId)
    if rootId == chooseMenu then chooseMenu, chooseMarker, chooseUnits = nil, nil, nil end
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

local function drawLabel(sx, sy, k, alpha, color, icon, name, title, hint, active)
    local fTitle, fName, fHint = font(13, true), font(9, true), font(9, active)
    local a = alpha / 255
    local pad, iconSize, gap = s(10) * k, s(34) * k, s(10) * k
    local nameStr = L.upper(name)
    local textW = math.max(L.width(title, k, fTitle), L.width(nameStr, k, fName), L.width(hint, k, fHint))
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
    local hintColor = active and tocolor(255, 255, 255, 255 * a) or tocolor(200, 205, 212, 220 * a)
    dxDrawText(hint, x + pad, hy, x + w - pad, hy + hintH, hintColor, k, fHint, "left", "center")
    dxDrawRectangle(sx - s(1) * k, y + h, s(2) * k, s(10) * k, tocolor(14, 17, 21, 220 * a))
end

addEventHandler("onClientRender", root, function()
    if #markers == 0 or isPlayerMapVisible() then return end
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local maxDist, fullDist = BINT.labelDistance, BINT.labelFullDistance
    local key = BINT.key:upper()

    for _, m in ipairs(markers) do
        if isElement(m) and getElementDimension(m) == dim and getElementInterior(m) == int then
            local x, y, z = getElementPosition(m)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if dist <= maxDist then
                local lz = z + BINT.labelHeight
                if isLineOfSightClear(cx, cy, cz, x, y, lz, true, false, false, true, false, false, false) then
                    local sx, sy = getScreenFromWorldPosition(x, y, lz, 0.1)
                    if sx then
                        local k = 1
                        if dist > fullDist then
                            k = 1 - (dist - fullDist) / (maxDist - fullDist) * (1 - BINT.labelMinScale)
                        end
                        local alpha = 255
                        if dist > maxDist * 0.8 then alpha = 255 * (maxDist - dist) / (maxDist * 0.2) end
                        local entering = getElementData(m, "bizint:kind") == "enter"
                        local color = getElementData(m, "bizint:color") or { 255, 255, 255 }
                        local active = m == current
                        local verb = L(entering and "biz_int.markers.enter" or "biz_int.markers.exit")
                        local hint = active and L("biz_int.markers.press", { key = key, action = verb })
                            or L("biz_int.markers.step_into_marker")
                        drawLabel(sx, sy, k, alpha, color, entering and "€" or "«",
                            getElementData(m, "bizint:name") or "", verb, hint, active)
                    end
                end
            end
        end
    end
end, true, "high+5")
