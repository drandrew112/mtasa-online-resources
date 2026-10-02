-- Patient examination panel (DX). The server opens it (medic:panelOpen), pushes a snapshot
-- every simulation step while it is open (medic:panelUpdate) and closes it when a procedure
-- starts. The buttons only send requests, the server validates and runs everything.
-- "Medication" opens a medicine grid inside the panel (the hovered one is described under it).
-- "O2 mask" puts the oxygen mask on / takes it off. "Transport" (a stable or intubated patient,
-- or the only button of a dead one) calls a vehicle; the client picks a free spot for it.

addEvent("medic:panelOpen", true)
addEvent("medic:panelUpdate", true)
addEvent("medic:panelClose", true)
addEvent("medic:panelMessage", true)
addEvent("onClientMedicPanel", false) -- source: localPlayer, (open, target) - e.g. for the EMS tutorial

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)

local function s(value) return value * scale end

local W, H = s(640), s(850)
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

local panel -- { target, name, data, message, messageError, messageTick, pending, drugMenu }
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
    if systolic >= 180 then return C.bad end
    if systolic >= 140 then return C.warn end
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

-- Button rows (MEDIC_ACTION_GROUPS) at the bottom of the panel, a group label on the left of each
local BUTTON_H = s(42)
local BUTTON_GAP = s(8)
local GROUP_LABEL_W = s(150)

-- Returns the rows { group, y, buttons = { { action, x, y, w, h } } } and the top of the first row
local function getButtonRows()
    local groups = panel.data.dead and MEDIC_DEAD_ACTION_GROUPS or MEDIC_ACTION_GROUPS
    local top = Y + H - PAD - #groups * BUTTON_H - (#groups - 1) * BUTTON_GAP
    local bx = X + PAD + GROUP_LABEL_W
    local areaW = W - PAD * 2 - GROUP_LABEL_W
    local rows = {}
    for gi, group in ipairs(groups) do
        local y = top + (gi - 1) * (BUTTON_H + BUTTON_GAP)
        local count = #group.actions
        local bw = (areaW - BUTTON_GAP * (count - 1)) / count
        local row = { group = group, y = y, buttons = {} }
        for i, action in ipairs(group.actions) do
            row.buttons[i] = { action = action, x = bx + (i - 1) * (bw + BUTTON_GAP), y = y, w = bw, h = BUTTON_H }
        end
        rows[gi] = row
    end
    return rows, top
end

-- Returns all buttons with their rectangles (also used for the click hit test)
local function getButtons()
    local list = {}
    for _, row in ipairs((getButtonRows())) do
        for _, button in ipairs(row.buttons) do list[#list + 1] = button end
    end
    return list
end

-- Medicine cards of the medication grid (drawn over the injury list, two columns)
local DRUG_AREA_Y = s(368)
local DRUG_CARD_H = s(46)
local DRUG_GAP = s(6)

local function getDrugCards()
    local list = {}
    local top = Y + DRUG_AREA_Y + s(24)
    local cw = (W - PAD * 2 - DRUG_GAP) / 2
    for i, id in ipairs(MEDIC_DRUG_ORDER) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        list[i] = { id = id, x = X + PAD + col * (cw + DRUG_GAP), y = top + row * (DRUG_CARD_H + DRUG_GAP),
            w = cw, h = DRUG_CARD_H }
    end
    return list
end

-- Draws the grid and, under it (over the message line), the description of the hovered medicine
-- hoverReason: a disabled button's reason is shown there instead of the placeholder
local function drawDrugMenu(cx, cy, hoverReason)
    local x, y = X + PAD, Y + DRUG_AREA_Y
    local _, buttonsTop = getButtonRows()
    local bottom = buttonsTop - s(6)
    dxDrawRectangle(X, y - s(6), W, bottom - y + s(6), C.bg)
    dxDrawText("MEDICATION  -  given through the IV line", x, y, X + W - PAD, y + s(20), C.muted, 1,
        fonts.small, "left", "top")
    local hoveredDrug, cardsBottom = nil, y
    for _, card in ipairs(getDrugCards()) do
        local drug = MEDIC_DRUGS[card.id]
        local hovered = not panel.pending and isInside(card.x, card.y, card.w, card.h, cx, cy)
        if hovered then hoveredDrug = drug end
        dxDrawRectangle(card.x, card.y, card.w, card.h, hovered and C.button or C.tile)
        dxDrawRectangle(card.x, card.y, s(4), card.h, C.accent)
        local tx = card.x + s(14)
        dxDrawText(drug.name, tx, card.y + s(5), card.x + card.w - s(8), card.y + s(26), C.text, 1, fonts.bold,
            "left", "top", true)
        dxDrawText(drug.class, tx, card.y + s(25), card.x + card.w - s(8), card.y + card.h, C.spo2, 1,
            fonts.small, "left", "top", true)
        cardsBottom = card.y + card.h
    end
    if not hoveredDrug and hoverReason then return end
    local text = hoveredDrug and hoveredDrug.desc or "Point at a medicine to see what it does."
    dxDrawText(text, x, cardsBottom + s(8), X + W - PAD, bottom, hoveredDrug and C.text or C.muted, 1,
        fonts.small, "left", "top", true, true)
end

-- A free spot for the transport vehicle next to the body: the boot faces the body, the
-- vehicle can stand there (nothing in the way along its length) and, if possible, drive off.
local SPOT_DISTANCE = 5.5
local SPOT_DIRECTIONS = 16

local function findTransportSpot(target)
    local bx, by, bz = getElementPosition(target)
    local fallback
    for i = 0, SPOT_DIRECTIONS - 1 do
        local a = i / SPOT_DIRECTIONS * math.pi * 2
        local dx, dy = math.cos(a), math.sin(a)
        local x, y = bx + dx * SPOT_DISTANCE, by + dy * SPOT_DISTANCE
        local ground = getGroundPosition(x, y, bz + 3)
        if ground and ground ~= 0 and math.abs(ground - bz) < 1.5 then
            local z = ground + 1
            local clear = isLineOfSightClear(bx, by, bz + 0.5, x, y, z, true, true, true, true, false, false, false, target)
                and isLineOfSightClear(x - dx * 3, y - dy * 3, z, x + dx * 3, y + dy * 3, z, true, true, true, true, false, false, false, target)
                and isLineOfSightClear(x - dy * 1.3, y + dx * 1.3, z, x + dy * 1.3, y - dx * 1.3, z, true, true, true, true, false, false, false, target)
            if clear then
                local rotation = -math.deg(math.atan2(dx, dy)) -- the front points away from the body
                local canDrive = isLineOfSightClear(x, y, z, x + dx * 15, y + dy * 15, z, true, true, true, true, false, false, false, target)
                if canDrive then return { x, y, z, rotation, true } end
                fallback = fallback or { x, y, z, rotation, false }
            end
        end
    end
    return fallback
end

local function getCloseButton()
    local size = s(28)
    return X + W - PAD - size, Y + s(16), size, size
end

local function drawGroupLabel(group, y)
    local lx, lw = X + PAD, GROUP_LABEL_W - BUTTON_GAP
    dxDrawRectangle(lx, y, lw, BUTTON_H, C.tile)
    dxDrawRectangle(lx, y, s(4), BUTTON_H, C.accent)
    local tx = lx + s(12)
    if group.tag then
        dxDrawText(group.tag, tx, y + s(3), lx + lw, y + s(23), C.text, 1, fonts.bold, "left", "top")
        dxDrawText(group.label, tx, y + s(22), lx + lw - s(4), y + BUTTON_H, C.muted, 1, fonts.small,
            "left", "top", true)
    else
        dxDrawText(group.label, tx, y, lx + lw, y + BUTTON_H, C.muted, 1, fonts.bold, "left", "center", true)
    end
end

local function drawButtons(cx, cy)
    local hoverReason
    for _, row in ipairs((getButtonRows())) do
        drawGroupLabel(row.group, row.y)
        for _, button in ipairs(row.buttons) do
            local info = MEDIC_ACTIONS[button.action]
            local available = panel.data.actions and panel.data.actions[button.action]
            local enabled = available == true and not panel.pending
            local hovered = isInside(button.x, button.y, button.w, button.h, cx, cy)

            local selected = button.action == "medication" and panel.drugMenu
            local bg = enabled and ((hovered or selected) and C.buttonHover or C.button) or C.buttonOff
            dxDrawRectangle(button.x, button.y, button.w, button.h, bg)
            local label = (#row.buttons == 1 and info.wideLabel)
                or (info.activeLabel and button.action == "oxygen" and panel.data.oxygenMask and info.activeLabel)
                or info.label
            local font = dxGetTextWidth(label, 1, fonts.bold) > button.w - s(8) and fonts.small or fonts.bold
            dxDrawText(label, button.x, button.y, button.x + button.w, button.y + button.h,
                enabled and C.text or C.muted, 1, font, "center", "center")

            if hovered and not enabled and type(available) == "string" then hoverReason = available end
        end
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

    -- section rectangles, read by getExaminationPanelLayout (e.g. tutorial highlights)
    local layout = { panel = { X, Y, W, H } }
    panel.layout = layout

    -- consciousness banner
    local y = Y + s(70)
    layout.consciousness = { x, y, W - PAD * 2, s(40) }
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
    local vitalsY = y + s(52)
    y = drawVitals(x, vitalsY, data) + s(12)
    layout.vitals = { x, vitalsY, W - PAD * 2, y - s(12) - vitalsY }
    layout.status = { x, y, W - PAD * 2, s(22) }

    -- transport status, nil when none was requested
    local elapsed = math.floor((getTickCount() - panel.dataTick) / 1000)
    local transportText
    if data.transportPhase == "waiting" then
        transportText = "Transport: on the way, arrives in "
            .. formatTime(math.max(0, (data.transportTimeLeft or 0) - elapsed))
    elseif data.transportPhase then
        transportText = "Transport: the patient is being loaded"
    end

    -- treatment status line (the transport status for a dead body)
    if data.dead then
        dxDrawText(transportText or "Transport: not requested", x, y, x + W, y + s(22),
            transportText and C.warn or C.muted, 1, fonts.body, "left", "center")
    else
        local iv = data.ivAccess and "IV access: in place" or "IV access: none"
        local airway = data.intubated and "Airway: secured" or (data.oxygenMask and "Airway: O2 mask")
            or "Airway: not secured"
        dxDrawText(iv, x, y, x + W, y + s(22), data.ivAccess and C.good or C.muted, 1, fonts.body, "left", "center")
        dxDrawText(airway, x + s(190), y, x + W, y + s(22), (data.intubated or data.oxygenMask) and C.good or C.muted,
            1, fonts.body, "left", "center")
        dxDrawText(("Pain: %d/10"):format(math.floor(data.pain / 10 + 0.5)), x, y, X + W - PAD, y + s(22),
            data.pain >= 70 and C.orange or C.muted, 1, fonts.body, "right", "center")
    end
    y = y + s(32)

    -- active medicines, transport of a living patient
    if data.drugs and #data.drugs > 0 and not data.dead then
        dxDrawText("ACTIVE MEDICATION", x, y - s(8), X + W - PAD, y + s(10), C.muted, 1, fonts.small, "left", "top")
        y = y + s(12)
        local colW = (W - PAD * 2) / 2
        local rowH = s(20)
        for i, dose in ipairs(data.drugs) do
            local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
            local dx, dy = x + col * colW, y + row * rowH
            dxDrawText(formatTime(math.max(0, dose.timeLeft - elapsed)), dx, dy, dx + colW - s(12), dy + rowH,
                C.muted, 1, fonts.body, "right", "center")
            dxDrawText(dose.name, dx, dy, dx + colW - s(62), dy + rowH, C.spo2, 1, fonts.body, "left", "center", true)
        end
        y = y + math.ceil(#data.drugs / 2) * rowH + s(10)
    end
    if transportText and not data.dead then
        dxDrawText(transportText, x, y - s(8), X + W - PAD, y + s(14), C.warn, 1, fonts.body, "left", "center", true)
        y = y + s(24)
    end

    local injuriesEnd = drawInjuries(x, y, data)
    layout.injuries = { x, y, W - PAD * 2, injuriesEnd - y }

    -- buttons, the medicine grid, then the message / hint line above the buttons
    local hoverReason = drawButtons(cx, cy)
    if panel.drugMenu then
        if data.dead or not (data.actions and data.actions.medication == true) then
            panel.drugMenu = false
        else
            drawDrugMenu(cx, cy, hoverReason)
        end
    end
    local _, buttonsTop = getButtonRows()
    layout.buttons = { x, buttonsTop, W - PAD * 2, Y + H - PAD - buttonsTop }
    layout.buttonList = getButtons()
    local messageY = buttonsTop - s(30)
    local text, color
    if hoverReason then
        text, color = hoverReason, C.muted
    elseif panel.drugMenu then
        text = nil -- the medicine description is there
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
    if panel.drugMenu then
        for _, card in ipairs(getDrugCards()) do
            if isInside(card.x, card.y, card.w, card.h, cx, cy) then
                panel.pending = true
                panel.drugMenu = false
                triggerServerEvent("medic:requestTreatment", resourceRoot, panel.target, "medication", card.id)
                return
            end
        end
    end
    for _, btn in ipairs(getButtons()) do
        if isInside(btn.x, btn.y, btn.w, btn.h, cx, cy) and panel.data.actions
            and panel.data.actions[btn.action] == true then
            if btn.action == "medication" then
                panel.drugMenu = not panel.drugMenu
            elseif btn.action == "transport" then
                panel.pending = true
                triggerServerEvent("medic:requestTransport", resourceRoot, panel.target, findTransportSpot(panel.target))
            else
                panel.pending = true
                panel.drugMenu = false
                triggerServerEvent("medic:requestTreatment", resourceRoot, panel.target, btn.action)
            end
            return
        end
    end
end

local function onKey(key, press)
    if not panel or not press then return end
    if key == "backspace" then
        cancelEvent()
        if panel.drugMenu then
            panel.drugMenu = false -- back to the injury list first
        else
            closePanel(true)
        end
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
    triggerEvent("onClientMedicPanel", localPlayer, false)
end

function isExaminationOpen()
    return panel ~= nil
end

-- Screen rectangles { x, y, w, h } of the open panel: panel, consciousness, vitals, status,
-- injuries, buttons, plus buttonList = { { action, x, y, w, h } }. false while closed / not drawn yet.
function getExaminationPanelLayout()
    return panel and panel.layout or false
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
        triggerEvent("onClientMedicPanel", localPlayer, true, target)
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
