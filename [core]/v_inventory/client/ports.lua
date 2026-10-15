-- Port markers: the work_core style 3D label over the ports this player sees (the server sends the
-- list, inv:ports) and the E key while standing in one.

local ports = {}       -- the visible ports (server data)
local current          -- the port the player stands in

addEvent("inv:ports", true)
addEventHandler("inv:ports", resourceRoot, function(list)
    ports = type(list) == "table" and list or {}
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("inv:requestPorts", resourceRoot)
end)

local function holdsContainer()
    for _, slot in ipairs(INV.SLOTS) do
        if Hud[slot] and Hud[slot].cap then return true end
    end
    return false
end

local function inPort(port, px, py, pz)
    if getElementDimension(localPlayer) ~= port.dim or getElementInterior(localPlayer) ~= port.int then return false end
    return getDistanceBetweenPoints2D(px, py, port.x, port.y) <= port.radius + 0.6 and math.abs(pz - port.z) < 3
end

-- ---------------------------------------------------------------------------------------------
-- Label (the work_core look)
-- ---------------------------------------------------------------------------------------------

local function drawLabel(sx, sy, k, alpha, color, icon, name, title, hint, hintColor)
    local a = alpha / 255
    local fTitle, fName, fHint = Font(math.floor(13 * k + 0.5), true), Font(math.floor(9 * k + 0.5), true), Font(math.floor(9 * k + 0.5))
    local pad, iconSize, gap = S(10) * k, S(34) * k, S(10) * k
    local textW = math.max(L.width(title, 1, fTitle), L.width(name, 1, fName), L.width(hint, 1, fHint))
    local w = pad + iconSize + gap + textW + pad * 1.4
    local headH, hintH = S(46) * k, S(22) * k
    local h = headH + hintH
    local x, y = sx - w / 2, sy - h
    Round(x, y, w, h, S(7) * k, tocolor(14, 17, 21, 220 * a))
    Round(x, y + h - S(3) * k, w, S(3) * k, S(1.5) * k, tocolor(color[1], color[2], color[3], 235 * a))
    local ix, iy = x + pad, y + (headH - iconSize) / 2 + S(2) * k
    Round(ix, iy, iconSize, iconSize, S(5) * k, tocolor(color[1], color[2], color[3], 240 * a))
    dxDrawText(icon, ix, iy, ix + iconSize, iy + iconSize, tocolor(255, 255, 255, 255 * a), 1, Font(math.floor(16 * k + 0.5), true), "center", "center")
    local tx = ix + iconSize + gap
    dxDrawText(name, tx, y + S(6) * k, tx + textW, y + headH * 0.45, tocolor(color[1], color[2], color[3], 255 * a), 1, fName, "left", "center")
    dxDrawText(title, tx, y + headH * 0.42, tx + textW, y + headH, tocolor(255, 255, 255, 255 * a), 1, fTitle, "left", "center")
    dxDrawText(hint, x + pad, y + headH, x + w - pad, y + headH + hintH, tocolor(hintColor[1], hintColor[2], hintColor[3], 220 * a), 1, fHint, "left", "center")
    dxDrawRectangle(sx - S(1) * k, y + h, S(2) * k, S(10) * k, tocolor(14, 17, 21, 220 * a))
end

addEventHandler("onClientRender", root, function()
    if not TextsLoaded then return end
    local px, py, pz = getElementPosition(localPlayer)
    local now
    for _, port in ipairs(ports) do
        if inPort(port, px, py, pz) then now = port break end
    end
    current = now
    if #ports == 0 or WindowOpen or isPlayerMapVisible() or getElementData(localPlayer, "hideHUD") then return end
    local cx, cy, cz = getCameraMatrix()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local maxDist, fullDist = INV.PORT_LABEL_DISTANCE, INV.PORT_LABEL_FULL_DISTANCE
    for _, port in ipairs(ports) do
        if port.dim == dim and port.int == int then
            local dist = getDistanceBetweenPoints3D(px, py, pz, port.x, port.y, port.z)
            local lz = port.z + INV.PORT_LABEL_HEIGHT
            if dist <= maxDist and isLineOfSightClear(cx, cy, cz, port.x, port.y, lz, true, false, false, true, false, false, false) then
                local sx, sy = getScreenFromWorldPosition(port.x, port.y, lz, 0.1)
                if sx then
                    local k = 1
                    if dist > fullDist then k = 1 - (dist - fullDist) / (maxDist - fullDist) * (1 - INV.PORT_LABEL_MIN_SCALE) end
                    local alpha = 255
                    if dist > maxDist * 0.8 then alpha = 255 * (maxDist - dist) / (maxDist * 0.2) end
                    local hint, hintColor
                    if holdsContainer() then
                        hint, hintColor = L("v_inventory.ui.port_hint_open", { key = INV.KEY_PORT:upper() }), { 200, 205, 212 }
                    else
                        hint, hintColor = L("v_inventory.ui.port_hint_container"), { 255, 140, 130 }
                    end
                    local name = L("v_inventory.ui.port_sub", { name = port.name and L.upper(L.resolve(port.name)) or "" })
                    local title = port.title and L.resolve(port.title) or L("v_inventory.ui.storage")
                    drawLabel(sx, sy, k, alpha, port.color or INV.PORT_COLOR, port.icon or "P", name, title, hint, hintColor)
                end
            end
        end
    end
end, true, "high+5")

-- ---------------------------------------------------------------------------------------------
-- E in the marker
-- ---------------------------------------------------------------------------------------------

local lastOpen = 0
bindKey(INV.KEY_PORT, "down", function()
    if not current or WindowOpen or not TextsLoaded then return end
    if isCursorShowing() or OtherPanelOpen() or isPedInVehicle(localPlayer) or isPedDead(localPlayer) then return end
    if getTickCount() - lastOpen < 600 then return end
    lastOpen = getTickCount()
    triggerServerEvent("inv:openPort", resourceRoot, current.id)
end)
