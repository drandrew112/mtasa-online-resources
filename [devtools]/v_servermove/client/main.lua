-- Full-screen "we moved" notice: drawn over everything, blocks controls,
-- Connect redirects to the new server, Copy IP puts the address on the clipboard
local sx, sy = guiGetScreenSize()
local s = math.min(sx / 1920, sy / 1080)
local address = CONFIG.host .. ":" .. CONFIG.port

-- Roboto is bundled: system font names do not resolve in dxCreateFont and the
-- fallback would lose the Hungarian accents (ő, ű)
local fontTitle = dxCreateFont("fonts/RobotoB.ttf", math.floor(46 * s)) or "default-bold"
local fontText = dxCreateFont("fonts/Roboto.ttf", math.floor(20 * s)) or "default"
local fontIp = dxCreateFont("fonts/RobotoB.ttf", math.floor(34 * s)) or "default-bold"
local fontBtn = dxCreateFont("fonts/RobotoB.ttf", math.floor(20 * s)) or "default-bold"
local fontSmall = dxCreateFont("fonts/RobotoB.ttf", math.floor(15 * s)) or "default-bold"

local TEXTS = {
    hu = {
        title = "ÚJ SZERVERRE KÖLTÖZTÜNK",
        body = "Ez a szerver már nem üzemel. Kérjük, csatlakozz az alábbi új címre!\nMinden előrehaladásod ott vár rád.",
        connect = "CSATLAKOZÁS",
        connecting = "CSATLAKOZÁS...",
        copy = "IP MÁSOLÁSA",
        copied = "MÁSOLVA!",
    },
    en = {
        title = "WE HAVE MOVED TO A NEW SERVER",
        body = "This server is no longer in use. Please join the new address below.\nAll your progress is waiting for you there.",
        connect = "CONNECT",
        connecting = "CONNECTING...",
        copy = "COPY IP",
        copied = "COPIED!",
    },
}

-- Starts in Hungarian; the HU/EN buttons switch it
local lang = "hu"

local buttons = {}
local copiedUntil = 0
local connecting = false

local function inside(b, cx, cy)
    return cx >= b.x and cx <= b.x + b.w and cy >= b.y and cy <= b.y + b.h
end

local function layout()
    local bw, bh, gap = 320 * s, 70 * s, 30 * s
    local by = sy * 0.5 + 170 * s
    local lw, lh, m = 60 * s, 36 * s, 30 * s
    buttons = {
        { id = "connect", x = sx / 2 - bw - gap / 2, y = by, w = bw, h = bh,
          color = { 46, 160, 90 }, font = fontBtn },
        { id = "copy", x = sx / 2 + gap / 2, y = by, w = bw, h = bh,
          color = { 70, 90, 120 }, font = fontBtn },
        { id = "hu", x = sx - m - lw * 2 - 8 * s, y = m, w = lw, h = lh,
          color = { 40, 46, 60 }, font = fontSmall, label = "HU" },
        { id = "en", x = sx - m - lw, y = m, w = lw, h = lh,
          color = { 40, 46, 60 }, font = fontSmall, label = "EN" },
    }
end

local function buttonLabel(b, t)
    if b.label then return b.label end
    if b.id == "connect" then return connecting and t.connecting or t.connect end
    if b.id == "copy" then return getTickCount() < copiedUntil and t.copied or t.copy end
end

local function render()
    local t = TEXTS[lang]
    local cx, cy = getCursorPosition()
    if cx then cx, cy = cx * sx, cy * sy end

    dxDrawRectangle(0, 0, sx, sy, tocolor(10, 12, 18, 252), true)
    dxDrawRectangle(0, sy * 0.5 - 260 * s, sx, 4 * s, tocolor(46, 160, 90, 255), true)

    dxDrawText(t.title, 0, sy * 0.5 - 220 * s, sx, sy * 0.5 - 140 * s,
        tocolor(255, 255, 255), 1, fontTitle, "center", "center", false, false, true)
    dxDrawText(t.body, 0, sy * 0.5 - 130 * s, sx, sy * 0.5 - 40 * s,
        tocolor(190, 195, 205), 1, fontText, "center", "center", false, false, true)

    local iw, ih = 620 * s, 90 * s
    dxDrawRectangle(sx / 2 - iw / 2, sy * 0.5 - 10 * s, iw, ih, tocolor(25, 30, 40, 255), true)
    dxDrawText(address, sx / 2 - iw / 2, sy * 0.5 - 10 * s, sx / 2 + iw / 2, sy * 0.5 - 10 * s + ih,
        tocolor(120, 220, 150), 1, fontIp, "center", "center", false, false, true)
    dxDrawText("mtasa://" .. address, 0, sy * 0.5 + 90 * s, sx, sy * 0.5 + 130 * s,
        tocolor(130, 135, 145), 1, fontText, "center", "center", false, false, true)

    for _, b in ipairs(buttons) do
        local hover = cx and inside(b, cx, cy)
        local k = (hover or b.id == lang) and 1.4 or 1
        local r, g, bl = math.min(255, b.color[1] * k), math.min(255, b.color[2] * k), math.min(255, b.color[3] * k)
        dxDrawRectangle(b.x, b.y, b.w, b.h, tocolor(r, g, bl, 255), true)
        dxDrawText(buttonLabel(b, t), b.x, b.y, b.x + b.w, b.y + b.h, tocolor(255, 255, 255), 1, b.font,
            "center", "center", false, false, true)
    end
end

local function onClick(button, state, cx, cy)
    if button ~= "left" or state ~= "up" then return end
    for _, b in ipairs(buttons) do
        if inside(b, cx, cy) then
            if b.id == "connect" and not connecting then
                connecting = true
                triggerServerEvent("servermove:connect", resourceRoot)
            elseif b.id == "copy" then
                setClipboard(address)
                copiedUntil = getTickCount() + 2000
            elseif TEXTS[b.id] then
                lang = b.id
            end
            return
        end
    end
end

-- Keep cursor and blocked controls even if another resource toggles them
local function enforce()
    if not isCursorShowing() then showCursor(true, true) end
    toggleAllControls(false, true, false)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    layout()
    showChat(false)
    enforce()
    setTimer(enforce, 500, 0)
    addEventHandler("onClientRender", root, render, true, "low-1000")
    addEventHandler("onClientClick", root, onClick)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    showCursor(false)
    toggleAllControls(true, true, false)
    showChat(true)
end)
