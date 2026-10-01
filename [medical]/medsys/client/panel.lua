-- Patient examination panel (DX). The server opens it (medic:panelOpen), pushes a snapshot
-- every simulation step while it is open (medic:panelUpdate) and closes it when a procedure
-- starts. The buttons only send requests, the server validates and runs everything.

addEvent("medic:panelOpen", true)
addEvent("medic:panelUpdate", true)
addEvent("medic:panelClose", true)
addEvent("medic:panelMessage", true)

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)

local function s(value) return value * scale end

local W, H = s(640), s(660)
local X, Y = (screenW - W) / 2, (screenH - H) / 2
local PAD = s(20)
local ECG_SECONDS = 3
local ECG_SEGMENTS = 90
local MESSAGE_TIME = 5000
local MAX_INJURY_ROWS = 5

local C = {
    bg = tocolor(16, 18, 24, 240),
    tile = tocolor(28, 31, 40, 255),
    line = tocolor(48, 52, 64, 255),
    accent = tocolor(215, 55, 65, 255),
    text = tocolor(235, 238, 245, 255),
    muted = tocolor(140, 146, 160, 255),
    good = tocolor(80, 210, 120, 255),
    warn = tocolor(255, 185, 60, 255),
    orange = tocolor(255, 130, 50, 255),
    bad = tocolor(235, 70, 70, 255),
    dead = tocolor(120, 120, 130, 255),
    spo2 = tocolor(90, 200, 255, 255),
    button = tocolor(38, 42, 54, 255),
    buttonHover = tocolor(215, 55, 65, 255),
    buttonOff = tocolor(30, 32, 40, 255),
}

local CONSCIOUSNESS_COLOR = {
    stable = C.good, dazed = C.warn, unconscious = C.orange, clinical_death = C.bad, dead = C.dead,
}
local BLEEDING_COLOR = { [0] = C.good, C.warn, C.orange, C.bad }

local panel -- { target, name, data, message, messageError, messageTick, pending, hover }
local fonts

local function ensureFonts()
    if fonts then return end
    local regular, bold = "assets/fonts/Roboto.ttf", "assets/fonts/RobotoB.ttf"
    fonts = {
        small = dxCreateFont(regular, math.floor(s(10)), false, "cleartype") or "default",
        body = dxCreateFont(regular, math.floor(s(12)), false, "cleartype") or "default",
        bold = dxCreateFont(bold, math.floor(s(12)), false, "cleartype") or "default-bold",
        title = dxCreateFont(bold, math.floor(s(17)), false, "cleartype") or "default-bold",
        big = dxCreateFont(bold, math.floor(s(28)), false, "cleartype") or "default-bold",
    }
end

local function isInside(x, y, w, h, cx, cy)
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

---------------------------------------------------------------------------
-- Value -> colour / text helpers
---------------------------------------------------------------------------

local function heartRateColor(hr)
    if hr <= 0 then return C.bad end
    if hr >= 50 and hr <= 100 then return C.good end
    if hr >= 40 and hr <= 130 then return C.warn end
    return C.bad
end

local function pressureColor(systolic)
    if systolic >= 90 then return C.good end
    if systolic >= 70 then return C.warn end
    return C.bad
end

local function spo2Color(spo2)
    if spo2 >= 94 then return C.good end
    if spo2 >= 88 then return C.warn end
    return C.bad
end

-- What the medic sees on the skin instead of a blood volume number
local function describeSkin(data)
    if data.dead then return "Cold, mottled", C.dead end
    if data.spo2 < 85 then return "Cyanotic", C.bad end
    if data.bloodPercent < 70 then return "Pale, cold, clammy", C.orange end
    if data.bloodPercent < 85 then return "Pale", C.warn end
    return "Warm, normal", C.good
end

local function formatTime(seconds)
    return ("%02d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------------------
-- ECG trace
---------------------------------------------------------------------------

-- One heartbeat, phase 0..1 -> amplitude (-0.3..1)
local function ecgWave(p)
    if p < 0.08 then return 0 end
    if p < 0.16 then return 0.12 * math.sin((p - 0.08) / 0.08 * math.pi) end
    if p < 0.26 then return 0 end
    if p < 0.29 then return -0.15 * (p - 0.26) / 0.03 end
    if p < 0.32 then return -0.15 + 1.15 * (p - 0.29) / 0.03 end
    if p < 0.35 then return 1.0 - 1.3 * (p - 0.32) / 0.03 end
    if p < 0.38 then return -0.3 + 0.3 * (p - 0.35) / 0.03 end
    if p < 0.50 then return 0 end
    if p < 0.66 then return 0.25 * math.sin((p - 0.5) / 0.16 * math.pi) end
    return 0
end

local function drawECG(x, y, w, h, hr, color)
    local now = getTickCount() / 1000
    local mid = y + h * 0.65
    local lastX, lastY
    for i = 0, ECG_SEGMENTS do
        local px = x + w * i / ECG_SEGMENTS
        local amplitude = 0
        if hr > 0 then
            local t = now - ECG_SECONDS * (1 - i / ECG_SEGMENTS)
            amplitude = ecgWave((t * hr / 60) % 1)
        end
        local py = mid - amplitude * h * 0.6
        if lastX then dxDrawLine(lastX, lastY, px, py, color, math.max(1, s(2))) end
        lastX, lastY = px, py
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawTile(x, y, w, h, title)
    dxDrawRectangle(x, y, w, h, C.tile)
    dxDrawText(title, x + s(12), y + s(8), x + w, y + s(26), C.muted, 1, fonts.small, "left", "top")
end

local function drawVitals(x, y, data)
    local tw, th = (W - PAD * 2 - s(10)) / 2, s(96)
    local x2, y2 = x + tw + s(10), y + th + s(10)
    local dead = data.dead or data.clinicalDeath

    -- heart rate + ECG
    drawTile(x, y, tw, th, "HEART RATE")
    local hrColor = heartRateColor(data.heartRate)
    dxDrawText(dead and "---" or tostring(data.heartRate), x + s(12), y + s(24), x + tw * 0.45, y + s(64),
        hrColor, 1, fonts.big, "left", "top")
    dxDrawText("BPM", x + s(12), y + s(64), x + tw, y + s(84), C.muted, 1, fonts.small, "left", "top")
    drawECG(x + tw * 0.4, y + s(26), tw * 0.56, th - s(36), data.heartRate, hrColor)

    -- blood pressure
    drawTile(x2, y, tw, th, "BLOOD PRESSURE")
    dxDrawText(dead and "---/---" or data.bloodPressure, x2 + s(12), y + s(24), x2 + tw, y + s(64),
        pressureColor(data.systolic), 1, fonts.big, "left", "top")
    dxDrawText("mmHg", x2 + s(12), y + s(64), x2 + tw, y + s(84), C.muted, 1, fonts.small, "left", "top")

    -- SpO2 with a bar
    drawTile(x, y2, tw, th, "OXYGEN SATURATION (SpO2)")
    local spo2Col = spo2Color(data.spo2)
    dxDrawText(dead and "--" or (data.spo2 .. "%"), x + s(12), y2 + s(24), x + tw, y2 + s(64),
        spo2Col, 1, fonts.big, "left", "top")
    local barX, barY, barW, barH = x + s(12), y2 + th - s(18), tw - s(24), s(6)
    dxDrawRectangle(barX, barY, barW, barH, C.line)
    dxDrawRectangle(barX, barY, barW * (dead and 0 or data.spo2 / 100), barH, spo2Col)

    -- bleeding + skin
    drawTile(x2, y2, tw, th, "BLEEDING")
    dxDrawText(data.bleedingLabel, x2 + s(12), y2 + s(24), x2 + tw, y2 + s(56),
        BLEEDING_COLOR[data.bleeding] or C.text, 1, fonts.title, "left", "top")
    local skin, skinColor = describeSkin(data)
    dxDrawText("Skin:", x2 + s(12), y2 + s(62), x2 + tw, y2 + s(84), C.muted, 1, fonts.body, "left", "top")
    dxDrawText(skin, x2 + s(52), y2 + s(62), x2 + tw, y2 + s(84), skinColor, 1, fonts.body, "left", "top")

    return y2 + th
end

local function drawInjuries(x, y, data)
    dxDrawText("INJURIES", x, y, x + W, y + s(20), C.muted, 1, fonts.small, "left", "top")
    y = y + s(22)
    local rowH = s(26)
    local injuries = data.injuries

    if #injuries == 0 then
        dxDrawText("No visible injuries", x, y, x + W, y + rowH, C.text, 1, fonts.body, "left", "center")
        return y + rowH
    end

    for i = 1, math.min(#injuries, MAX_INJURY_ROWS) do
        local injury = injuries[i]
        local severityColor = injury.severity >= 3 and C.bad or (injury.severity == 2 and C.orange or C.warn)
        dxDrawRectangle(x, y + s(8), s(4), s(12), severityColor)
        dxDrawText(injury.label, x + s(12), y, x + s(210), y + rowH, C.text, 1, fonts.bold, "left", "center")
        dxDrawText(injury.severityLabel, x + s(210), y, x + s(300), y + rowH, severityColor, 1, fonts.body, "left", "center")
        if injury.bleeding > 0 then
            dxDrawText("Bleeding: " .. MEDIC_BLEEDING[injury.bleeding], x + s(300), y, x + s(460), y + rowH,
                BLEEDING_COLOR[injury.bleeding], 1, fonts.body, "left", "center")
        end
        local status = injury.treated and injury.treatedLabel or "Untreated"
        dxDrawText(status, x, y, x + W - PAD * 2, y + rowH, injury.treated and C.good or C.muted, 1,
            fonts.body, "right", "center")
        y = y + rowH
    end
    if #injuries > MAX_INJURY_ROWS then
        dxDrawText(("+ %d more"):format(#injuries - MAX_INJURY_ROWS), x + s(12), y, x + W, y + s(18),
            C.muted, 1, fonts.small, "left", "top")
        y = y + s(18)
    end
    return y
end

-- Returns the buttons with their rectangles (also used for the click hit test)
local function getButtons()
    local count = #MEDIC_ACTION_ORDER
    local gap = s(10)
    local bw = (W - PAD * 2 - gap * (count - 1)) / count
    local bh = s(50)
    local by = Y + H - PAD - bh
    local list = {}
    for i, action in ipairs(MEDIC_ACTION_ORDER) do
        list[i] = { action = action, x = X + PAD + (i - 1) * (bw + gap), y = by, w = bw, h = bh }
    end
    return list
end

local function getCloseButton()
    local size = s(28)
    return X + W - PAD - size, Y + s(16), size, size
end

local function drawButtons(cx, cy)
    local hoverReason
    for _, button in ipairs(getButtons()) do
        local info = MEDIC_ACTIONS[button.action]
        local available = panel.data.actions and panel.data.actions[button.action]
        local enabled = available == true and not panel.pending
        local hovered = isInside(button.x, button.y, button.w, button.h, cx, cy)

        local bg = enabled and (hovered and C.buttonHover or C.button) or C.buttonOff
        dxDrawRectangle(button.x, button.y, button.w, button.h, bg)
        dxDrawText(info.label, button.x, button.y + s(6), button.x + button.w, button.y + s(30),
            enabled and C.text or C.muted, 1, fonts.bold, "center", "top")
        dxDrawText(info.game, button.x, button.y + s(28), button.x + button.w, button.y + button.h - s(4),
            C.muted, 1, fonts.small, "center", "top")

        if hovered and not enabled and type(available) == "string" then hoverReason = available end
    end
    return hoverReason
end

local function render()
    if not panel then return end
    if not isElement(panel.target) then
        closePanel(true)
        return
    end
    local px, py, pz = getElementPosition(localPlayer)
    local tx, ty, tz = getElementPosition(panel.target)
    if getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz) > MEDIC.PANEL_RANGE + 0.5 then
        closePanel(true)
        return
    end

    local data = panel.data
    local cx, cy = -1, -1
    if isCursorShowing() then
        local rx, ry = getCursorPosition()
        cx, cy = rx * screenW, ry * screenH
    end

    dxDrawRectangle(X, Y, W, H, C.bg)
    dxDrawRectangle(X, Y, W, s(4), C.accent)

    -- header
    local x = X + PAD
    dxDrawText("PATIENT EXAMINATION", x, Y + s(16), X + W, Y + s(32), C.muted, 1, fonts.small, "left", "top")
    dxDrawText(panel.name, x, Y + s(30), X + W - s(60), Y + s(58), C.text, 1, fonts.title, "left", "top", true)
    local bx, by, bs = getCloseButton()
    dxDrawRectangle(bx, by, bs, bs, isInside(bx, by, bs, bs, cx, cy) and C.buttonHover or C.button)
    dxDrawText("X", bx, by, bx + bs, by + bs, C.text, 1, fonts.bold, "center", "center")

    -- consciousness banner
    local y = Y + s(70)
    local stateColor = CONSCIOUSNESS_COLOR[data.consciousness] or C.text
    dxDrawRectangle(x, y, W - PAD * 2, s(40), C.tile)
    dxDrawRectangle(x, y, s(6), s(40), stateColor)
    dxDrawText("CONSCIOUSNESS", x + s(18), y, x + s(160), y + s(40), C.muted, 1, fonts.small, "left", "center")
    dxDrawText(data.consciousnessLabel:upper(), x + s(140), y, X + W - PAD, y + s(40), stateColor, 1,
        fonts.title, "left", "center")
    if data.clinicalDeath and data.deathTimeLeft then
        local blink = getTickCount() % 1000 < 600
        local left = math.max(0, data.deathTimeLeft - math.floor((getTickCount() - panel.dataTick) / 1000))
        dxDrawText("Time left " .. formatTime(left), x, y, X + W - PAD - s(14), y + s(40),
            blink and C.bad or C.text, 1, fonts.title, "right", "center")
    end

    -- vitals
    y = drawVitals(x, y + s(52), data) + s(12)

    -- treatment status line
    local iv = data.ivAccess and "IV access: in place" or "IV access: none"
    local airway = data.intubated and "Airway: secured" or "Airway: not secured"
    dxDrawText(iv, x, y, x + W, y + s(22), data.ivAccess and C.good or C.muted, 1, fonts.body, "left", "center")
    dxDrawText(airway, x + s(190), y, x + W, y + s(22), data.intubated and C.good or C.muted, 1, fonts.body, "left", "center")
    dxDrawText(("Pain: %d/10"):format(math.floor(data.pain / 10 + 0.5)), x, y, X + W - PAD, y + s(22),
        data.pain >= 70 and C.orange or C.muted, 1, fonts.body, "right", "center")
    y = y + s(32)

    drawInjuries(x, y, data)

    -- buttons, then the message / hint line above them
    local hoverReason = drawButtons(cx, cy)
    local messageY = Y + H - PAD - s(50) - s(30)
    local text, color
    if hoverReason then
        text, color = hoverReason, C.muted
    elseif panel.message and getTickCount() - panel.messageTick < MESSAGE_TIME then
        text, color = panel.message, panel.messageError and C.bad or C.good
    elseif panel.pending then
        text, color = "Preparing...", C.muted
    end
    if text then
        dxDrawText(text, x, messageY, X + W - PAD, messageY + s(24), color, 1, fonts.bold, "center", "center")
    end
end

---------------------------------------------------------------------------
-- Open / close / input
---------------------------------------------------------------------------

local function onClick(button, state)
    if not panel or button ~= "left" or state ~= "up" then return end
    local rx, ry = getCursorPosition()
    if not rx then return end
    local cx, cy = rx * screenW, ry * screenH

    local bx, by, bs = getCloseButton()
    if isInside(bx, by, bs, bs, cx, cy) then
        closePanel(true)
        return
    end
    if panel.pending then return end
    for _, btn in ipairs(getButtons()) do
        if isInside(btn.x, btn.y, btn.w, btn.h, cx, cy) and panel.data.actions
            and panel.data.actions[btn.action] == true then
            panel.pending = true
            triggerServerEvent("medic:requestTreatment", resourceRoot, panel.target, btn.action)
            return
        end
    end
end

local function onKey(key, press)
    if not panel or not press then return end
    if key == "backspace" then
        cancelEvent()
        closePanel(true)
    end
end

-- notifyServer = true when the client closes it on its own
function closePanel(notifyServer)
    if not panel then return end
    panel = nil
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientClick", root, onClick)
    removeEventHandler("onClientKey", root, onKey)
    showCursor(false)
    if notifyServer then
        triggerServerEvent("medic:closeExamine", resourceRoot)
    end
end

addEventHandler("medic:panelOpen", resourceRoot, function(target, name, data, message, isError)
    ensureFonts()
    local wasOpen = panel ~= nil
    panel = {
        target = target,
        name = name,
        data = data,
        dataTick = getTickCount(),
        message = message,
        messageError = isError,
        messageTick = getTickCount(),
    }
    if not wasOpen then
        addEventHandler("onClientRender", root, render)
        addEventHandler("onClientClick", root, onClick)
        addEventHandler("onClientKey", root, onKey)
        showCursor(true)
    end
end)

addEventHandler("medic:panelUpdate", resourceRoot, function(target, data)
    if not panel or panel.target ~= target then return end
    panel.data = data
    panel.dataTick = getTickCount()
end)

addEventHandler("medic:panelClose", resourceRoot, function()
    closePanel(false)
end)

addEventHandler("medic:panelMessage", resourceRoot, function(message, isError)
    if not panel then return end
    panel.pending = false
    panel.message = message
    panel.messageError = isError
    panel.messageTick = getTickCount()
end)
