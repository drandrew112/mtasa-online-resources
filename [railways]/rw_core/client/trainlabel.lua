-- 3D info board above the locomotives (the same idea as the med_erm unit labels): running
-- number, speed, the service (line, trip, destination, next stop, delay), doors and driver.
-- Everything comes from the lead's element data: rw.number / rw.cars / rw.auto (consist.lua),
-- rw.service (rw_timetable), rw.doors (rw_loco). /rwlabels hides / shows the boards.

local L = RW.LABEL
local sw, sh = guiGetScreenSize()
local S = sh / 1080
local enabled = true
local leads = {}             -- [lead vehicle] = { x, y, z, t, speed } (speed from the motion)

local fonts = {}
local function font(px, bold)
    local key = px .. (bold and "b" or "")
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and "fonts/RobotoB.ttf" or "fonts/Roboto.ttf", math.floor(px * S * 0.75 + 0.5), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

local C = {
    bg = { 14, 19, 28, 225 }, head = { 30, 70, 140, 240 }, line = { 46, 58, 80, 255 },
    text = { 235, 240, 250 }, muted = { 150, 162, 182 }, green = { 60, 210, 120 },
    red = { 240, 80, 70 }, yellow = { 245, 200, 60 }, blue = { 120, 175, 255 },
}
-- trip prefix -> badge colour
local PREFIX = { RB = { 40, 150, 90 }, IC = { 190, 45, 60 } }

local function col(c, a, k) return tocolor(c[1], c[2], c[3], (a or c[4] or 255) * (k or 1)) end

local function refresh(veh)
    if getElementData(veh, "rw.number") and isElementStreamedIn(veh) then
        leads[veh] = leads[veh] or { speed = 0 }
    else
        leads[veh] = nil
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do refresh(veh) end
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key == "rw.number" and getElementType(source) == "vehicle" then refresh(source) end
end)
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then refresh(source) end
end)
addEventHandler("onClientElementStreamOut", root, function() leads[source] = nil end)
addEventHandler("onClientElementDestroy", root, function() leads[source] = nil end)

addCommandHandler(L.TOGGLE_CMD, function()
    enabled = not enabled
    rwNotify(enabled and "Train info boards on." or "Train info boards off.", true)
end)

local function hhmm(s)
    if not s then return "" end
    s = math.floor(s) % 86400
    return ("%02d:%02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60))
end

local function clean(name) return (name or ""):gsub("#%x%x%x%x%x%x", "") end

-- the lines of the board -> list of { text, color, font, right = {text, color}, badge = {text, rgb} }
local function content(veh, info)
    local rows = {}
    local v = getElementData(veh, "rw.service")
    local auto = getElementData(veh, "rw.auto")
    if type(v) == "table" then
        local prefix = tostring(v.trip or ""):match("^(%a+)")
        rows[#rows + 1] = { text = tostring(v.trip or "") .. "  " .. tostring(v.toName or v.to or ""), color = C.text,
            font = font(15, true), badge = { text = tostring(v.line or ""), rgb = PREFIX[prefix] or C.head } }
        local st = v.stops and v.stops[v.nextStop]
        if v.status == "completed" then
            rows[#rows + 1] = { text = "Terminates here - please alight", color = C.yellow, font = font(12, true) }
        elseif v.status == "cancelled" then
            rows[#rows + 1] = { text = "Service cancelled", color = C.red, font = font(12, true) }
        elseif st then
            local text
            if st.state == "stopped" then
                text = ("At %s, dep %s"):format(st.name or st.station, hhmm(st.dep))
            else
                text = ("Next: %s  %s"):format(st.name or st.station, hhmm(st.arr))
            end
            local m = math.floor((v.delay or 0) / 60 + 0.5)
            rows[#rows + 1] = { text = text, color = C.muted, font = font(12),
                right = m >= 1 and { "+" .. m .. " min", C.red } or { "on time", C.green } }
        end
        local doors = getElementData(veh, "rw.doors")
        if doors and doors ~= "closed" then
            rows[#rows + 1] = { text = "Doors open - boarding", color = C.green, font = font(12, true) }
        end
    else
        rows[#rows + 1] = { text = "Not in service", color = C.muted, font = font(13, true) }
    end
    local driver = getVehicleOccupant(veh, 0)
    local who = auto and "Automatic" or (driver and getElementType(driver) == "player" and clean(getPlayerName(driver))) or "No driver"
    local cars = tonumber(getElementData(veh, "rw.cars")) or 0
    rows[#rows + 1] = { text = who, color = C.muted, font = font(11),
        right = { cars > 0 and (cars .. (cars == 1 and " coach" or " coaches")) or "light engine", C.muted } }
    return rows
end

local function drawBoard(veh, info, sx, sy, k)
    local number = tostring(getElementData(veh, "rw.number") or "")
    local rows = content(veh, info)
    local pad = 10 * S * k
    local fHead, fSpeed = font(15, true), font(12, true)
    local headH = 26 * S * k
    local speedText = ("%d km/h"):format(math.floor(info.speed * 3.6 + 0.5))

    -- width: the widest row
    local w = dxGetTextWidth(RW.COMPANY_SHORT .. "   " .. number, k, fHead) + dxGetTextWidth(speedText, k, fSpeed) + pad * 3
    local rowH = {}
    for i, r in ipairs(rows) do
        local rw = dxGetTextWidth(r.text, k, r.font) + pad * 2
        if r.badge then rw = rw + dxGetTextWidth(r.badge.text, k, font(11, true)) + 14 * S * k end
        if r.right then rw = rw + dxGetTextWidth(r.right[1], k, r.font) + pad end
        w = math.max(w, rw)
        rowH[i] = dxGetFontHeight(k, r.font) + 5 * S * k
    end
    w = math.max(w, 230 * S * k)
    local h = headH + pad * 0.6
    for _, rh in ipairs(rowH) do h = h + rh end
    local x, y = sx - w / 2, sy - h - 10 * S * k

    -- body, header strip, pointer
    dxDrawRectangle(x, y, w, h, col(C.bg))
    dxDrawRectangle(x, y, w, headH, col(C.head))
    dxDrawRectangle(x, y + headH, w, math.max(1, S * k), col(C.line))
    dxDrawRectangle(sx - 1.5 * S * k, y + h, 3 * S * k, 10 * S * k, col(C.bg))

    local shortW = dxGetTextWidth(RW.COMPANY_SHORT, k, fHead)
    dxDrawText(RW.COMPANY_SHORT, x + pad, y, 0, y + headH, col(C.blue), k, fHead, "left", "center")
    dxDrawText(number, x + pad + shortW + 8 * S * k, y, 0, y + headH, col(C.text), k, fHead, "left", "center")
    dxDrawText(speedText, x, y, x + w - pad, y + headH, col(C.text), k, fSpeed, "right", "center")

    local cy = y + headH + pad * 0.3
    for i, r in ipairs(rows) do
        local tx = x + pad
        if r.badge then
            local bf = font(11, true)
            local bw = dxGetTextWidth(r.badge.text, k, bf) + 10 * S * k
            local bh = rowH[i] - 7 * S * k
            dxDrawRectangle(tx, cy + (rowH[i] - bh) / 2, bw, bh, col(r.badge.rgb, 255))
            dxDrawText(r.badge.text, tx, cy, tx + bw, cy + rowH[i], col(C.text), k, bf, "center", "center")
            tx = tx + bw + 6 * S * k
        end
        dxDrawText(r.text, tx, cy, x + w - pad, cy + rowH[i], col(r.color), k, r.font, "left", "center", true)
        if r.right then
            dxDrawText(r.right[1], x, cy, x + w - pad, cy + rowH[i], col(r.right[2]), k, r.font, "right", "center")
        end
        cy = cy + rowH[i]
    end
end

addEventHandler("onClientRender", root, function()
    if not enabled or not next(leads) or isPlayerMapVisible() then return end
    local cx, cy, cz = getCameraMatrix()
    local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local mine = getPedOccupiedVehicle(localPlayer)
    local t = getTickCount()

    for veh, info in pairs(leads) do
        if not isElement(veh) then
            leads[veh] = nil
        else
            -- speed from the motion (auto trains are placed by the clients, no velocity)
            local x, y, z = getElementPosition(veh)
            if info.t then
                local dt = (t - info.t) / 1000
                if dt > 0.2 then
                    local d = getDistanceBetweenPoints3D(x, y, z, info.x, info.y, info.z)
                    local v = d < 80 and d / dt or 0
                    info.speed = info.speed * 0.5 + v * 0.5
                    if info.speed < 0.3 then info.speed = 0 end
                    info.x, info.y, info.z, info.t = x, y, z, t
                end
            else
                info.x, info.y, info.z, info.t = x, y, z, t
            end

            -- not the driver's own train (the cab panel shows it all)
            if veh ~= mine and getElementDimension(veh) == dim and getElementInterior(veh) == int then
                local _, _, _, _, _, maxZ = getElementBoundingBox(veh)
                local lz = z + (maxZ or 2) + L.HEIGHT
                local dist = getDistanceBetweenPoints3D(cx, cy, cz, x, y, lz)
                if dist <= L.MAX_DIST
                    and isLineOfSightClear(cx, cy, cz, x, y, lz, true, false, false, true, false, false, false, veh) then
                    local sx, sy = getScreenFromWorldPosition(x, y, lz, 0.05)
                    if sx then
                        local k = 1
                        if dist > L.FULL_DIST then
                            k = 1 - (1 - L.MIN_SCALE) * (dist - L.FULL_DIST) / (L.MAX_DIST - L.FULL_DIST)
                        end
                        drawBoard(veh, info, sx, sy, k)
                    end
                end
            end
        end
    end
end)
