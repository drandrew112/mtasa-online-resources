if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- bt_dispatch client: the text gate (v_accounts loading), drawing helpers, notifications, state.

local sw, sh = guiGetScreenSize()
SW, SH = sw, sh
function S(v) return v * math.max(0.65, sh / 1080) end

-- ---------------------------------------------------------------------------------------------
-- Texts load only once the player is loaded (v_accounts loading gate, like v_inventory)
-- ---------------------------------------------------------------------------------------------

TextsLoaded = false
local function loadTexts()
    if TextsLoaded then return end
    TextsLoaded = true
    pcall(function() exports.v_accounts:resourceReady() end)
    triggerServerEvent("btd:requestState", resourceRoot)
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)

-- ---------------------------------------------------------------------------------------------
-- Colours, fonts, drawing
-- ---------------------------------------------------------------------------------------------

COL = {
    bg = { 16, 18, 24, 232 }, head = { 22, 26, 34, 255 }, tile = { 28, 31, 40, 255 }, tile2 = { 36, 40, 52, 255 },
    acc = { 215, 55, 65 }, text = { 235, 238, 245 }, muted = { 140, 146, 160 }, off = { 95, 100, 112 },
    good = { 80, 210, 120 }, warn = { 255, 185, 60 }, bad = { 235, 70, 70 }, blue = { 0, 140, 200 },
    key = { 240, 184, 74 }, purple = { 180, 120, 230 }, orange = { 230, 150, 60 }, line = { 42, 50, 60 },
}
function RGB(c, a) return tocolor(c[1], c[2], c[3], a or c[4] or 255) end

local fonts = {}
function Font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", S(size), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

function Round(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then return dxDrawRectangle(x, y, w, h, color) end
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 8)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 8)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 8)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 8)
end

-- Text in a box; ax: "left" | "center" | "right", ay: "top" | "center"
function Text(str, x, y, w, h, color, size, bold, ax, ay)
    dxDrawText(str, x, y, x + w, y + h, color, 1, Font(size or 11, bold), ax or "left", ay or "center", true, false, false, false, true)
end

-- A text that is cut with an ellipsis to fit the width
function FitText(str, w, size, bold)
    return L.fit(str, w, 1, Font(size or 11, bold))
end

function TextWidth(str, size, bold)
    return dxGetTextWidth(str, 1, Font(size or 11, bold))
end

-- Clickable regions of the frame, filled by the draw functions
Hits = {}
function Hit(x, y, w, h, fn)
    Hits[#Hits + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

function Chip(x, y, label, color, size, alignRight)
    size = size or 9
    local w = TextWidth(label, size, true) + S(14)
    local h = S(size + 9)
    if alignRight then x = x - w end
    Round(x, y, w, h, S(4), RGB(color, 40))
    dxDrawRectangle(x, y, w, S(1), RGB(color)); dxDrawRectangle(x, y + h - S(1), w, S(1), RGB(color))
    dxDrawRectangle(x, y, S(1), h, RGB(color)); dxDrawRectangle(x + w - S(1), y, S(1), h, RGB(color))
    Text(label, x, y, w, h, RGB(color), size, true, "center")
    return w
end

function Button(x, y, w, h, label, kind, fn, size)
    local palette = {
        normal = { COL.tile2, COL.text }, primary = { COL.acc, { 255, 255, 255 } }, good = { COL.good, COL.good },
        warn = { COL.warn, COL.warn }, blue = { COL.blue, COL.blue }, off = { COL.tile, COL.off },
    }
    local p = palette[kind or "normal"]
    local outlined = kind == "good" or kind == "warn" or kind == "blue"
    Round(x, y, w, h, S(6), outlined and RGB(p[1], 34) or RGB(p[1]))
    Text(label, x, y, w, h, RGB(p[2]), size or 10, true, "center")
    if fn and kind ~= "off" then Hit(x, y, w, h, fn) end
end

function InBox(px, py, x, y, w, h) return px >= x and px <= x + w and py >= y and py <= y + h end

addEventHandler("onClientClick", root, function(button, state)
    if button ~= "left" or state ~= "down" or not PanelBig then return end
    local cx, cy = getCursorPosition()
    if not cx then return end
    cx, cy = cx * SW, cy * SH
    for i = #Hits, 1, -1 do
        local h = Hits[i]
        if InBox(cx, cy, h.x, h.y, h.w, h.h) then
            h.fn()
            return
        end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Server messages
-- ---------------------------------------------------------------------------------------------

addEvent("btd:notify", true)
addEventHandler("btd:notify", resourceRoot, function(title, text, sound)
    pcall(function() exports.ui_core:addNotification(title, text, sound == true) end)
    if sound then playSound("assets/new.wav") end
end)

State = { onDuty = false, tasks = {} }
local stateAt = 0
addEvent("btd:state", true)
addEventHandler("btd:state", resourceRoot, function(s)
    State = type(s) == "table" and s or { onDuty = false, tasks = {} }
    State.tasks = State.tasks or {}
    stateAt = getTickCount()
end)
function StateAge() return (getTickCount() - stateAt) / 1000 end

function HasRight() return getElementData(localPlayer, "bt.right") == true end

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == "bt.right" and TextsLoaded then triggerServerEvent("btd:requestState", resourceRoot) end
end)

-- Names of what is carried ("RBC 0+  x4") and the tags / tiles
local TILE = { rbc = { "RB", COL.acc }, ffp = { "FF", COL.acc }, platelets = { "PL", { 220, 100, 70 } } }

function TaskWhat(t)
    local key
    if t.type == "lab_sample" then key = "bt_dispatch.what.lab_sample"
    elseif t.type == "urgent_medicine" then key = "bt_dispatch.what.urgent_medicine"
    else key = "bt_dispatch.what." .. tostring(t.product) end
    local s = L(key)
    if t.group and t.group ~= "" then s = s .. " " .. t.group end
    return s .. "  \195\151" .. tostring(t.units or 1)
end

function TaskTile(t)
    if t.type == "lab_sample" then return "LB", COL.orange end
    if t.type == "urgent_medicine" then return "MD", COL.purple end
    local d = TILE[t.product] or { "BL", COL.acc }
    return d[1], d[2]
end

function TaskTag(t)
    if t.type == "lab_sample" then return L("bt_dispatch.tag.lab"), COL.orange end
    if t.type == "urgent_medicine" then return L("bt_dispatch.tag.medicine"), COL.purple end
    if t.type == "planned_blood" then return L("bt_dispatch.tag.planned"), COL.blue end
    if t.type == "urgent_blood" or t.urgency == "urgent" then return L("bt_dispatch.tag.urgent"), COL.bad end
    return L("bt_dispatch.tag.resupply"), COL.muted
end

STATUS_COLOR = { transit = COL.warn, waiting = COL.blue, delivered = COL.good, cancelled = COL.off }

function Money(n) return L.money(n) end

function FormatSeconds(s)
    s = math.max(0, math.floor(s))
    return ("%02d:%02d:%02d"):format(math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end
