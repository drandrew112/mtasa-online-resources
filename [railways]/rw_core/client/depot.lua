-- Depot menu (ui_inac temp menu). The server sends the options when the player presses the
-- depot key inside a depot marker, and re-checks every pick.

local inMarker = nil
local menuId = nil
local sw, sh = guiGetScreenSize()

local fonts = {}
local function font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "fonts/RobotoB.ttf" or "fonts/Roboto.ttf", math.floor(size * sh / 1080 + 0.5), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local COLOR = { 80, 160, 255 }
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

-- 3D label above the depot marker (same look as the work_core markers). It is drawn whenever
-- the marker is near, so it also says what the depot is for while the player stands outside.
local function drawLabel(sx, sy, k, alpha, title, hint)
    local function s(v) return v * sh / 1080 end
    local fName, fTitle, fHint = font(12, true), font(17, true), font(12)
    local a = alpha / 255
    local nameStr = RW.COMPANY:upper()
    local pad, iconSize, gap = s(10) * k, s(34) * k, s(10) * k
    local textW = math.max(dxGetTextWidth(title, k, fTitle), dxGetTextWidth(nameStr, k, fName), dxGetTextWidth(hint, k, fHint))
    local w = pad + iconSize + gap + textW + pad * 1.4
    local headH, hintH = s(46) * k, s(22) * k
    local h = headH + hintH
    local x, y = sx - w / 2, sy - h

    round(x, y, w, h, s(7) * k, tocolor(14, 17, 21, 220 * a))
    round(x, y + h - s(3) * k, w, s(3) * k, s(1.5) * k, rgb(COLOR, 235 * a))

    local ix, iy = x + pad, y + (headH - iconSize) / 2 + s(2) * k
    round(ix, iy, iconSize, iconSize, s(5) * k, rgb(COLOR, 240 * a))
    dxDrawText("D", ix, iy, ix + iconSize, iy + iconSize, tocolor(255, 255, 255, 255 * a), k, font(21, true), "center", "center")

    local tx = ix + iconSize + gap
    dxDrawText(nameStr, tx, y + s(6) * k, tx + textW, y + headH * 0.45, rgb(COLOR, 255 * a), k, fName, "left", "center")
    dxDrawText(title, tx, y + headH * 0.42, tx + textW, y + headH, tocolor(255, 255, 255, 255 * a), k, fTitle, "left", "center")
    dxDrawText(hint, x + pad, y + headH, x + w - pad, y + headH + hintH, tocolor(200, 205, 212, 220 * a), k, fHint, "left", "center")
    dxDrawRectangle(sx - s(1) * k, y + h, s(2) * k, s(10) * k, tocolor(14, 17, 21, 220 * a))
end

local MAX_DIST, FULL_DIST = 30, 12

addEventHandler("onClientRender", root, function()
    if menuId or isPlayerMapVisible() then return end
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    for _, m in ipairs(getElementsByType("marker", resourceRoot, true)) do
        local idx = getElementData(m, "rw.depot")
        local def = idx and RW.DEPOTS[idx]
        if def and getElementDimension(m) == dim and getElementInterior(m) == int then
            local x, y, z = getElementPosition(m)
            local dist = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local lz = z + 2.2
            if dist <= MAX_DIST and isLineOfSightClear(cx, cy, cz, x, y, lz, true, false, false, true, false, false, false) then
                local sx, sy = getScreenFromWorldPosition(x, y, lz, 0.1)
                if sx then
                    local k = 1
                    if dist > FULL_DIST then k = 1 - (dist - FULL_DIST) / (MAX_DIST - FULL_DIST) * 0.45 end
                    local alpha = dist > MAX_DIST * 0.8 and 255 * (MAX_DIST - dist) / (MAX_DIST * 0.2) or 255
                    local hint = (inMarker == m)
                        and ("Press %s · services, train assembly"):format(RW.DEPOT_KEY:upper())
                        or "Train services and assembly"
                    drawLabel(sx, sy, k, alpha, def.name, hint)
                end
            end
        end
    end
end)

addEventHandler("onClientMarkerHit", root, function(el, dim)
    if el ~= localPlayer or not dim or not getElementData(source, "rw.depot") then return end
    if isPedInVehicle(localPlayer) then return end
    inMarker = source
end)

addEventHandler("onClientMarkerLeave", root, function(el)
    if el ~= localPlayer or source ~= inMarker then return end
    inMarker = nil
    if menuId then exports.ui_inac:closeTempMenu() menuId = nil end
end)

bindKey(RW.DEPOT_KEY, "down", function()
    if not inMarker or menuId or isChatBoxInputActive() or isCursorShowing() then return end
    if exports.ui_inac:isTempMenuOpen() then return end
    triggerServerEvent("rw:depot:open", resourceRoot)
end)

addEvent("rw:depot:menu", true)
addEventHandler("rw:depot:menu", resourceRoot, function(data)
    if not inMarker then return end
    local serviceItems = {}
    for _, v in ipairs(data.services) do
        local label = ("%s %02d:%02d - %s"):format(v.number, math.floor(v.dep / 3600) % 24, math.floor(v.dep / 60) % 60, v.toName)
        if v.ok then
            serviceItems[#serviceItems + 1] = { label = label, value = { "apply", v.tripId }, desc = ("%s, from %s. The train is created now."):format(v.name, v.fromName) }
        else
            serviceItems[#serviceItems + 1] = { label = label, value = { "none" }, desc = "Not available: " .. tostring(v.reason) }
        end
    end
    if #serviceItems == 0 then
        serviceItems[1] = { label = "No service available now", value = { "none" } }
    end

    local spawnItems = {}
    for _, s in ipairs(data.spawns) do
        local presets = {}
        for _, p in ipairs(data.presets) do
            presets[#presets + 1] = { label = p.name, value = { "spawn", s.id, p.id } }
        end
        spawnItems[#spawnItems + 1] = { label = s.name, title = s.name, items = presets }
    end

    local trainItems = {}
    for _, c in ipairs(data.consists) do
        local sub = {}
        for _, t in ipairs(data.carriageTypes) do
            sub[#sub + 1] = { label = "Add " .. t.name:lower(), value = { "add", c.id, t.id }, desc = "Coupled to the end of the train" }
        end
        if c.carriages > 0 then
            sub[#sub + 1] = { label = "Uncouple last carriage", value = { "remove", c.id } }
        end
        sub[#sub + 1] = { label = "Send to the shed (remove)", value = { "despawn", c.id } }
        trainItems[#trainItems + 1] = { label = c.label, title = c.number, items = sub }
    end
    if #trainItems == 0 then
        trainItems[1] = { label = "No train at this depot", value = { "none" } }
    end

    local items = {
        { label = "Services", title = "Services", desc = "Apply for a service: your train is created and the service starts", items = serviceItems },
        { label = "Trains at the depot", title = "Assembly", desc = "Couple / uncouple carriages", items = trainItems },
    }
    if data.admin then
        items[#items + 1] = { label = "New train (admin)", title = "Spawn point", desc = "Assemble a free train on a free track", items = spawnItems }
    end
    menuId = exports.ui_inac:createTempMenu({ title = data.depot, items = items })
end)

addEvent("ui_inac:tempMenuSelect", false)
addEventHandler("ui_inac:tempMenuSelect", root, function(id, value)
    if id ~= menuId or type(value) ~= "table" then return end
    if value[1] ~= "none" then
        triggerServerEvent("rw:depot:action", resourceRoot, value[1], value[2], value[3])
    end
end)

addEvent("ui_inac:tempMenuClose", false)
addEventHandler("ui_inac:tempMenuClose", root, function(id)
    if id == menuId then menuId = nil end
end)
