if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Notifications (ui_core), the restock progress bar, the "Equipment missing" label over the side
-- door of an ambulance standing in a hospital bay and the "On the stretcher" line of the pusher.
-- What the medic holds and the bag's contents are shown by v_inventory (HUD and window).

local sw, sh = guiGetScreenSize()
local function s(v) return v * math.max(0.65, sh / 1080) end

function showBagNotification(title, text, alert)
    title, text = L.resolve(title), L.resolve(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(title, text, alert == true)
    end
    if alert then playSoundFrontEnd(5) end
end

addEvent("bag:notify", true)
addEventHandler("bag:notify", resourceRoot, showBagNotification)

-- ---------------------------------------------------------------------------------------------
-- Progress bar
-- ---------------------------------------------------------------------------------------------

local progress -- { start, duration, text }
local syncHud  -- below: attaches the HUD render only while it has something to draw

addEvent("bag:progress", true)
addEventHandler("bag:progress", resourceRoot, function(duration, text)
    if not duration then progress = nil return syncHud() end
    progress = { start = getTickCount(), duration = duration, text = L.resolve(text or "") }
    syncHud()
end)

local function drawProgress()
    local f = math.min(1, (getTickCount() - progress.start) / progress.duration)
    if f >= 1 then progress = nil return syncHud() end
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

-- streamed-in anchors that carry BAG_DATA.MISSING (kept by the events at the end of the file)
local missingAnchors = {}

local function drawMissing()
    local px, py, pz = getElementPosition(localPlayer)
    for anchor in pairs(missingAnchors) do
        local missing = isElement(anchor) and getElementData(anchor, BAG_DATA.MISSING)
        if missing then
            local x, y, z = getElementPosition(anchor)
            local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            if d < LABEL_RANGE then
                local sx, sy = getScreenFromWorldPosition(x, y, z + 1.3)
                if sx then
                    local k = math.max(0.6, 1 - d / LABEL_RANGE)
                    local text = L("med_bag.hud.equipment_missing", { missing = missing })
                    local w = L.width(L("med_bag.hud.equipment_missing_2", { missing = missing }), k, "default-bold") * 0.75 + s(24)
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
-- What rides on the stretcher the local player pushes (BAG_DATA.ON_STRETCHER on the stretcher)
-- ---------------------------------------------------------------------------------------------

local C = {
    bg = tocolor(16, 18, 24, 225),
    accent = tocolor(215, 55, 65, 255),
    text = tocolor(235, 238, 245, 255),
    muted = tocolor(140, 146, 160, 255),
}

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
    dxDrawText(L("med_bag.hud.on_stretcher"), x + pad, y + pad * 0.6, x + w, y + pad + s(16), C.muted, 1, "default-bold", "left", "top")
    dxDrawText(table.concat(names, ", "), x + pad, y + pad + s(18), x + w - pad, y + h - pad * 0.5, C.text, 1,
        "default-bold", "left", "center", true)
end

local function renderHud()
    if progress then drawProgress() end
    drawMissing()
    if isPedInVehicle(localPlayer) then return end
    local stretcher = getElementData(localPlayer, "stretcher.pushing")
    local on = isElement(stretcher) and getElementData(stretcher, BAG_DATA.ON_STRETCHER)
    if type(on) == "table" then drawStretcherHud(on) end
end

-- attached only while there is a progress bar, a streamed-in anchor with missing equipment or the
-- local player pushes a stretcher
local hudOn = false
syncHud = function()
    local on = (progress or next(missingAnchors) or getElementData(localPlayer, "stretcher.pushing")) and true or false
    if on == hudOn then return end
    hudOn = on
    if on then
        addEventHandler("onClientRender", root, renderHud)
    else
        removeEventHandler("onClientRender", root, renderHud)
    end
end

local function refreshAnchor(el)
    local was = missingAnchors[el]
    local now = (isElement(el) and getElementType(el) == "object" and isElementStreamedIn(el)
        and getElementData(el, BAG_DATA.MISSING)) and true or nil
    if was == now then return end
    missingAnchors[el] = now
    syncHud()
end

-- anchors already streamed in when the resource starts count too
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, el in ipairs(getElementsByType("object", resourceRoot, true)) do refreshAnchor(el) end
    syncHud()
end)
addEventHandler("onClientElementStreamIn", resourceRoot, function() refreshAnchor(source) end)
addEventHandler("onClientElementStreamOut", resourceRoot, function() refreshAnchor(source) end)
addEventHandler("onClientElementDestroy", resourceRoot, function()
    if missingAnchors[source] then missingAnchors[source] = nil syncHud() end
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key == BAG_DATA.MISSING then
        if getElementType(source) == "object" then refreshAnchor(source) end
    elseif key == "stretcher.pushing" and source == localPlayer then
        syncHud()
    end
end)
