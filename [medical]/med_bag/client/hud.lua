-- Notifications (ui_core if running, else chat), the carry HUD (what is in the hands + the
-- put-down key), the bag contents window, the restock progress bar and the "Equipment missing"
-- label over the side door of an ambulance standing in a hospital bay.

local sw, sh = guiGetScreenSize()
local function s(v) return v * math.max(0.65, sh / 1080) end

function showBagNotification(title, text, alert)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(title, text, alert == true)
    else
        outputChatBox("#e0474c[" .. tostring(title) .. "] #ffffff" .. tostring(text), 255, 255, 255, true)
    end
    if alert then playSoundFrontEnd(5) end
end

addEvent("bag:notify", true)
addEventHandler("bag:notify", resourceRoot, showBagNotification)

-- ---------------------------------------------------------------------------------------------
-- Progress bar
-- ---------------------------------------------------------------------------------------------

local progress -- { start, duration, text }

addEvent("bag:progress", true)
addEventHandler("bag:progress", resourceRoot, function(duration, text)
    if not duration then progress = nil return end
    progress = { start = getTickCount(), duration = duration, text = tostring(text or "") }
end)

local function drawProgress()
    local f = math.min(1, (getTickCount() - progress.start) / progress.duration)
    if f >= 1 then progress = nil return end
    local w, h = s(360), s(14)
    local x, y = (sw - w) / 2, sh * 0.78
    dxDrawText(progress.text, x, y - s(28), x + w, y - s(4), tocolor(235, 238, 245), 1, "default-bold", "center", "bottom")
    dxDrawRectangle(x, y, w, h, tocolor(16, 18, 24, 220))
    dxDrawRectangle(x + 2, y + 2, (w - 4) * f, h - 4, tocolor(215, 55, 65, 255))
end

-- ---------------------------------------------------------------------------------------------
-- "Equipment missing" (BAG_DATA.MISSING on the anchor)
-- ---------------------------------------------------------------------------------------------

local LABEL_RANGE = 25

local function drawMissing()
    local px, py, pz = getElementPosition(localPlayer)
    for _, anchor in ipairs(getElementsByType("object", resourceRoot, true)) do
        local missing = getElementData(anchor, BAG_DATA.MISSING)
        if missing then
            local x, y, z = getElementPosition(anchor)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d < LABEL_RANGE then
                local sx, sy = getScreenFromWorldPosition(x, y, z + 1.3)
                if sx then
                    local k = math.max(0.6, 1 - d / LABEL_RANGE)
                    local text = "EQUIPMENT MISSING\n" .. missing
                    local w = dxGetTextWidth("EQUIPMENT MISSING  " .. missing, k, "default-bold") * 0.75 + s(24)
                    local h = s(40) * k
                    dxDrawRectangle(sx - w / 2, sy - h / 2, w, h, tocolor(14, 17, 21, 210))
                    dxDrawRectangle(sx - w / 2, sy + h / 2 - 3, w, 3, tocolor(218, 54, 51, 235))
                    dxDrawText(text, sx - w / 2, sy - h / 2, sx + w / 2, sy + h / 2, tocolor(255, 120, 110), k,
                        "default-bold", "center", "center")
                end
            end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Carry HUD (BAG_DATA.HANDS of the local player)
-- ---------------------------------------------------------------------------------------------

local C = {
    bg = tocolor(16, 18, 24, 225),
    tile = tocolor(28, 31, 40, 255),
    accent = tocolor(215, 55, 65, 255),
    text = tocolor(235, 238, 245, 255),
    muted = tocolor(140, 146, 160, 255),
    good = tocolor(80, 210, 120, 255),
    warn = tocolor(255, 185, 60, 255),
    bad = tocolor(235, 70, 70, 255),
    key = tocolor(240, 184, 74, 255),
}

local function stockColor(left, full)
    if left <= 0 then return C.bad end
    if left <= full * BAG.LOW_STOCK_FRACTION then return C.warn end
    return C.text
end

local function drawCarryHud(hands)
    local rows = {}
    if hands.bag then
        local info = ("IV %d  ·  O2 %d%%"):format(hands.ivKits or 0, hands.oxygen or 0)
        rows[#rows + 1] = { "L", bagItemName("bag"), info,
            ((hands.oxygen or 0) <= BAG.OXYGEN_LOW or (hands.ivKits or 0) <= 0) and C.warn or C.muted }
    end
    if hands.monitor then rows[#rows + 1] = { "R", bagItemName("monitor") } end
    if #rows == 0 then return end
    local w, rowH, pad = s(320), s(26), s(12)
    local h = pad + s(18) + #rows * rowH + s(30) + pad * 0.5
    local x, y = sw - w - s(30), sh - h - s(260)
    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, s(4), h, C.accent)
    dxDrawText("CARRYING", x + pad, y + pad * 0.6, x + w, y + pad + s(16), C.muted, 1, "default-bold", "left", "top")
    local ry = y + pad + s(18)
    for _, row in ipairs(rows) do
        dxDrawRectangle(x + pad, ry + s(3), s(20), rowH - s(6), C.tile)
        dxDrawText(row[1], x + pad, ry, x + pad + s(20), ry + rowH, C.text, 1, "default-bold", "center", "center")
        dxDrawText(row[2], x + pad + s(28), ry, x + w - pad, ry + rowH, C.text, 1, "default-bold", "left", "center")
        if row[3] then
            dxDrawText(row[3], x + pad, ry, x + w - pad, ry + rowH, row[4], 1, "default", "right", "center")
        end
        ry = ry + rowH
    end
    local key = BAG.DROP_KEY:upper()
    local kw = s(24)
    dxDrawRectangle(x + pad, ry + s(6), kw, s(20), C.key)
    dxDrawText(key, x + pad, ry + s(6), x + pad + kw, ry + s(26), tocolor(20, 20, 20), 1, "default-bold", "center", "center")
    dxDrawText("Put down", x + pad + kw + s(8), ry + s(6), x + w, ry + s(26), C.muted, 1, "default", "left", "center")
end

-- What rides on the stretcher the local player pushes (BAG_DATA.ON_STRETCHER on the stretcher)
local function drawStretcherHud(on)
    local names = {}
    for _, kind in ipairs(BAG.KINDS) do
        if on[kind] then names[#names + 1] = bagItemName(kind) end
    end
    if #names == 0 then return end
    local w, h, pad = s(320), s(58), s(12)
    local x, y = sw - w - s(30), sh - h - s(260)
    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, s(4), h, C.accent)
    dxDrawText("ON THE STRETCHER", x + pad, y + pad * 0.6, x + w, y + pad + s(16), C.muted, 1, "default-bold", "left", "top")
    dxDrawText(table.concat(names, ", "), x + pad, y + pad + s(18), x + w - pad, y + h - pad * 0.5, C.text, 1,
        "default-bold", "left", "center", true)
end

-- ---------------------------------------------------------------------------------------------
-- Bag contents window ("Check contents")
-- ---------------------------------------------------------------------------------------------

local CONTENTS_TIME = 15000
local contents -- { data, tick, x, y, z }

addEvent("bag:contents", true)
addEventHandler("bag:contents", resourceRoot, function(data)
    local x, y, z = getElementPosition(localPlayer)
    contents = { data = data, tick = getTickCount(), x = x, y = y, z = z }
end)

local function drawContents()
    local px, py, pz = getElementPosition(localPlayer)
    if getTickCount() - contents.tick > CONTENTS_TIME
        or getDistanceBetweenPoints3D(px, py, pz, contents.x, contents.y, contents.z) > 6 then
        contents = nil
        return
    end
    local d = contents.data
    local w, pad, rowH = s(380), s(14), s(21)
    local drugRows = math.ceil(#d.drugs / 2)
    local h = pad + s(50) + s(56) + s(22) + drugRows * rowH + pad
    local x, y = sw - w - s(30), (sh - h) / 2
    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, w, s(4), C.accent)
    dxDrawText(d.title, x + pad, y + pad, x + w - pad, y + pad + s(20), C.text, 1.15, "default-bold", "left", "top")
    dxDrawText(("Bag: %s   ·   Monitor: %s"):format(d.where or "?", d.monitor or "?"), x + pad, y + pad + s(24),
        x + w - pad, y + pad + s(44), C.muted, 1, "default", "left", "top", true)
    local ty = y + pad + s(50)
    local half = (w - pad * 3) / 2
    local tiles = {
        { "IV KITS", ("%d / %d"):format(d.ivKits[1], d.ivKits[2]), stockColor(d.ivKits[1], d.ivKits[2]) },
        { "OXYGEN", d.oxygen .. "%", d.oxygen <= 0 and C.bad or (d.oxygen <= BAG.OXYGEN_LOW and C.warn or C.text) },
    }
    for i, tile in ipairs(tiles) do
        local tx = x + pad + (i - 1) * (half + pad)
        dxDrawRectangle(tx, ty, half, s(46), C.tile)
        dxDrawText(tile[1], tx + s(10), ty + s(4), tx + half, ty + s(20), C.muted, 1, "default", "left", "top")
        dxDrawText(tile[2], tx + s(10), ty + s(18), tx + half, ty + s(44), tile[3], 1.3, "default-bold", "left", "center")
    end
    ty = ty + s(56)
    dxDrawText("MEDICINES", x + pad, ty, x + w, ty + s(18), C.muted, 1, "default", "left", "top")
    ty = ty + s(22)
    for i, drug in ipairs(d.drugs) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local dx, dy = x + pad + col * (half + pad), ty + row * rowH
        local name = drug[1]:gsub("%s*%b()", "")
        dxDrawText(name, dx, dy, dx + half - s(44), dy + rowH, C.text, 1, "default", "left", "center", true)
        dxDrawText(("%d/%d"):format(drug[2], drug[3]), dx, dy, dx + half, dy + rowH, stockColor(drug[2], drug[3]), 1,
            "default-bold", "right", "center")
    end
end

addEventHandler("onClientRender", root, function()
    if progress then drawProgress() end
    drawMissing()
    if contents then drawContents() end
    if isPedInVehicle(localPlayer) then return end
    local hands = getElementData(localPlayer, BAG_DATA.HANDS)
    if type(hands) == "table" then
        drawCarryHud(hands)
        return
    end
    local stretcher = getElementData(localPlayer, "stretcher.pushing")
    local on = isElement(stretcher) and getElementData(stretcher, BAG_DATA.ON_STRETCHER)
    if type(on) == "table" then drawStretcherHud(on) end
end)
