-- 3D label above the vehicles of signed-in units: red cross + callsign and
-- a status line. The server tags the vehicle with "erm.unit" element data
-- (server/units.lua: Units.tagVehicle).

local LABEL_KEY  = "erm.unit"
local MAX_DIST   = 70      -- metres
local FULL_DIST  = 15      -- full size up to this distance
local MIN_SCALE  = 0.55
local HEIGHT     = 0.7     -- metres above the vehicle's roof

local tagged = {}          -- [vehicle] = true

local function refresh(veh)
    if getElementData(veh, LABEL_KEY) and isElementStreamedIn(veh) then
        tagged[veh] = true
    else
        tagged[veh] = nil
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do refresh(veh) end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == LABEL_KEY and getElementType(source) == "vehicle" then refresh(source) end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then refresh(source) end
end)

addEventHandler("onClientElementStreamOut", root, function()
    tagged[source] = nil
end)

addEventHandler("onClientElementDestroy", root, function()
    tagged[source] = nil
end)

local function drawLabel(sx, sy, k, data)
    local s = Gfx.s
    local fBig, fSmall = Gfx.font(12, true), Gfx.font(8, true)
    local st = Config.STATUS[data.status] or { label = tostring(data.status), color = { 150, 150, 150 } }

    local callsign = tostring(data.callsign or "EMS")
    local status = st.label:upper()
    local pad, icon, gap = s(8) * k, s(26) * k, s(8) * k
    local textW = math.max(dxGetTextWidth(callsign, k, fBig), dxGetTextWidth(status, k, fSmall))
    local w = pad + icon + gap + textW + pad * 1.4
    local h = s(38) * k
    local x, y = sx - w / 2, sy - h

    -- body + status strip
    Gfx.round(x, y, w, h, s(6) * k, tocolor(14, 17, 21, 215))
    Gfx.round(x, y + h - s(3) * k, w, s(3) * k, s(1.5) * k, Gfx.rgb(st.color, 235))

    -- red cross tile
    local ix, iy = x + pad, y + (h - s(3) * k - icon) / 2
    Gfx.round(ix, iy, icon, icon, s(4) * k, tocolor(255, 255, 255, 240))
    local c = icon * 0.7
    Gfx.cross(ix + (icon - c) / 2, iy + (icon - c) / 2, c, Theme.accent)

    -- callsign / status
    local tx = ix + icon + gap
    local th = h - s(3) * k
    dxDrawText(callsign, tx, y + s(3) * k, tx + textW, y + th * 0.62, Theme.text, k, fBig, "left", "center")
    dxDrawText(status, tx, y + th * 0.58, tx + textW, y + th - s(2) * k, Gfx.rgb(st.color), k, fSmall, "left", "center")

    -- pointer
    local px = sx
    dxDrawRectangle(px - s(1) * k, y + h, s(2) * k, s(8) * k, tocolor(14, 17, 21, 215))
end

addEventHandler("onClientRender", root, function()
    if not next(tagged) or isPlayerMapVisible() then return end
    local cx, cy, cz = getCameraMatrix()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)

    for veh in pairs(tagged) do
        local data = isElement(veh) and getElementData(veh, LABEL_KEY)
        if type(data) == "table" and getElementDimension(veh) == dim and getElementInterior(veh) == int then
            local x, y, z = getElementPosition(veh)
            local _, _, _, _, _, maxZ = getElementBoundingBox(veh)
            z = z + (maxZ or 1.5) + HEIGHT
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
            if dist <= MAX_DIST
                and isLineOfSightClear(cx, cy, cz, x, y, z, true, false, false, true, false, false, false, veh) then
                local sx, sy = getScreenFromWorldPosition(x, y, z, 0.05)
                if sx then
                    local k = 1
                    if dist > FULL_DIST then
                        k = 1 - (1 - MIN_SCALE) * (dist - FULL_DIST) / (MAX_DIST - FULL_DIST)
                    end
                    drawLabel(sx, sy, k, data)
                end
            end
        elseif not isElement(veh) then
            tagged[veh] = nil
        end
    end
end)
