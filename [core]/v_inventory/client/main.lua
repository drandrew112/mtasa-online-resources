if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Shared client helpers: the text gate (v_accounts loading), scaling, fonts, drawing, item names
-- and icons, notifications, the ground snap of dropped items.

local sw, sh = guiGetScreenSize()
SW, SH = sw, sh

function S(v) return v * math.max(0.65, sh / 1080) end

-- ---------------------------------------------------------------------------------------------
-- Texts load only once the player is loaded (v_accounts loading gate)
-- ---------------------------------------------------------------------------------------------

TextsLoaded = false

local function loadTexts()
    if TextsLoaded then return end
    TextsLoaded = true
    pcall(function() exports.v_accounts:resourceReady() end)
end
addEvent("onClientLoadingStarted", true)
addEventHandler("onClientLoadingStarted", root, loadTexts)
addEventHandler("onClientResourceStart", resourceRoot, function()
    if getElementData(localPlayer, "loaded") then loadTexts() end
end)

-- ---------------------------------------------------------------------------------------------
-- Fonts / colours
-- ---------------------------------------------------------------------------------------------

local fonts = {}
function Font(size, bold)
    local key = size .. (bold and "b" or "")
    if fonts[key] == nil then
        fonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", S(size), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end

function RGB(c, a) return tocolor(c[1], c[2], c[3], a or c[4] or 255) end
C = {}
for k, v in pairs(INV_COLORS) do C[k] = RGB(v) end

-- ---------------------------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------------------------

function Round(x, y, w, h, r, color)
    r = math.min(r, w / 2, h / 2)
    if r < 1 then return dxDrawRectangle(x, y, w, h, color) end
    dxDrawRectangle(x + r, y, w - 2 * r, h, color)
    dxDrawRectangle(x, y + r, r, h - 2 * r, color)
    dxDrawRectangle(x + w - r, y + r, r, h - 2 * r, color)
    dxDrawCircle(x + r, y + r, r, 180, 270, color, color, 10)
    dxDrawCircle(x + w - r, y + r, r, 270, 360, color, color, 10)
    dxDrawCircle(x + r, y + h - r, r, 90, 180, color, color, 10)
    dxDrawCircle(x + w - r, y + h - r, r, 0, 90, color, color, 10)
end

function Outline(x, y, w, h, t, color)
    dxDrawRectangle(x, y, w, t, color)
    dxDrawRectangle(x, y + h - t, w, t, color)
    dxDrawRectangle(x, y + t, t, h - 2 * t, color)
    dxDrawRectangle(x + w - t, y + t, t, h - 2 * t, color)
end

function Text(text, x, y, w, h, color, size, bold, alignX, clip)
    dxDrawText(text, x, y, x + w, y + h, color, 1, Font(size, bold), alignX or "left", "center", clip or false)
end

function TextW(text, size, bold)
    return L.width(text, 1, Font(size, bold))
end

function Fit(text, w, size, bold)
    return L.fit(text, w, 1, Font(size, bold))
end

-- A key chip with its label; returns the x after it
function KeyChip(x, y, key, label, h)
    h = h or S(24)
    local w = math.max(h, TextW(key, 11, true) + S(14))
    Round(x, y, w, h, S(4), C.key)
    Text(key, x, y, w, h, tocolor(20, 20, 20), 11, true, "center")
    if not label then return x + w + S(10) end
    Text(label, x + w + S(8), y, TextW(label, 12) + S(4), h, C.muted, 12)
    return x + w + S(8) + TextW(label, 12) + S(20)
end

function Bar(x, y, w, h, frac, color)
    Round(x, y, w, h, h / 2, tocolor(255, 255, 255, 38))
    frac = math.max(0, math.min(1, frac or 0))
    if frac > 0 then Round(x, y, math.max(h, w * frac), h, h / 2, color) end
end

-- ---------------------------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------------------------

function ItemName(defId)
    return L("v_inventory.item." .. tostring(defId) .. ".name")
end

function ItemDesc(defId)
    local key = "v_inventory.item." .. tostring(defId) .. ".desc"
    return L.has(key) and L(key) or ""
end

-- "x2" style amount text (stackables only)
function AmountText(v)
    local def = ITEMS[v.d]
    if def and def.stackable then return "x" .. tostring(v.a) end
    return nil
end

function WeightText(kg)
    return L("v_inventory.ui.kg", { kg = ("%.1f"):format(kg or 0) })
end

local textures = {}
local function iconTexture(path)
    if textures[path] == nil then
        textures[path] = fileExists(path) and dxCreateTexture(path, "argb", true, "clamp") or false
    end
    return textures[path] or nil
end

-- The icon tile: category colour + the PNG icon (or the glyph)
function DrawIcon(defId, x, y, size, alpha)
    local def = ITEMS[defId]
    local col = def and ITEM_CATEGORIES[def.category] or { 120, 120, 130 }
    alpha = alpha or 255
    Round(x, y, size, size, S(5), tocolor(col[1], col[2], col[3], alpha))
    local tex = def and def.icon and iconTexture(def.icon)
    if tex then
        local pad = size * 0.14
        dxDrawImage(x + pad, y + pad, size - 2 * pad, size - 2 * pad, tex, 0, 0, 0, tocolor(255, 255, 255, alpha))
    else
        local glyph = def and def.glyph or "?"
        dxDrawText(glyph, x, y, x + size, y + size, tocolor(255, 255, 255, alpha), 1, Font(math.max(6, math.floor(size * 0.36 / S(1))), true),
            "center", "center")
    end
end

-- Display lines of an item (meta.display: { { label, value } }), resolved
function DisplayLines(v)
    local out = {}
    for _, line in ipairs(type(v.disp) == "table" and v.disp or {}) do
        if type(line) == "table" then
            out[#out + 1] = { L.resolve(line.label or ""), L.resolve(line.value or "") }
        end
    end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------------------------------------

addEvent("inv:notify", true)
addEventHandler("inv:notify", resourceRoot, function(text, alert)
    local title = L("v_inventory.ui.inventory")
    local body = L.resolve(text)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then
        exports.ui_core:addNotification(title, body, false)
    end
    if alert then playSoundFrontEnd(5) end
end)

-- ---------------------------------------------------------------------------------------------
-- Ground snap: the server puts a dropped item at foot level, this client corrects the height
-- ---------------------------------------------------------------------------------------------

addEvent("inv:snap", true)
addEventHandler("inv:snap", resourceRoot, function(obj, heightAboveGround)
    if not isElement(obj) then return end
    local x, y, z = getElementPosition(obj)
    local hit, _, _, hz = processLineOfSight(x, y, z + 1.5, x, y, z - 3, true, false, false, true, false,
        false, false, false, obj)
    local ground = hit and hz or getGroundPosition(x, y, z + 1.5)
    if not ground or ground == 0 then return end
    triggerServerEvent("inv:snapResult", resourceRoot, obj, ground + (heightAboveGround or 0))
end)

-- Is any panel of another resource in the foreground (the same flags ui_interactobject checks)
local BLOCKING = { "paused", "socialPanelOpen", "phoneOpen", "browserOpen", "showChatInput",
    "reportPanelOpen", "adminPanelOpen", "textInputOpen", "interactionMenuOpen" }
function OtherPanelOpen()
    for _, key in ipairs(BLOCKING) do
        if getElementData(localPlayer, key) then return true end
    end
    local allow = getElementData(localPlayer, "intro.allow")
    if type(allow) == "table" and not allow.inventory then return true end
    return isChatBoxInputActive() or isConsoleActive() or isMainMenuActive()
end
