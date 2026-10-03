-- Glucometer window, drawn right of the examination panel while the medic holds it out (the
-- "Glucometer" button of the D row toggles it, panel.lua calls drawGlucometer / clickGlucometer).
-- MEASURE pricks the finger: the server reads the glucose after MEDIC.GLUCOMETER_TIME seconds and
-- sends it back (medic:glucoseResult). The reading stays on the screen, it is not continuous:
-- measure again to see a change. The last reading of every patient is kept in the meter's memory.

addEvent("medic:glucoseResult", true)

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)

local function s(value) return value * scale end

local GW, GH = s(240), s(400)
local GAP = s(14)

local C = {
    body = tocolor(46, 58, 78, 250),
    bodyEdge = tocolor(30, 38, 52, 255),
    bezel = tocolor(22, 26, 32, 255),
    lcd = tocolor(168, 186, 160, 255),
    lcdDark = tocolor(28, 36, 30, 255),
    lcdFaint = tocolor(120, 138, 116, 255),
    lcdBad = tocolor(150, 30, 30, 255),
    text = tocolor(235, 238, 245, 255),
    muted = tocolor(150, 160, 178, 255),
    button = tocolor(28, 32, 40, 255),
    buttonHover = tocolor(215, 55, 65, 255),
    buttonOff = tocolor(36, 40, 48, 255),
    strip = tocolor(235, 235, 225, 255),
    blood = tocolor(190, 25, 35, 255),
}

local fonts
local meter = { target = nil, phase = "idle" } -- phase: idle | measuring | result | error
local memory = {} -- [target] = { value, tick }

local function ensureFonts()
    if fonts then return end
    local regular, bold = "assets/fonts/Roboto.ttf", "assets/fonts/RobotoB.ttf"
    fonts = {
        small = dxCreateFont(regular, math.floor(s(10)), false, "cleartype") or "default",
        bold = dxCreateFont(bold, math.floor(s(11)), false, "cleartype") or "default-bold",
        title = dxCreateFont(bold, math.floor(s(13)), false, "cleartype") or "default-bold",
        number = dxCreateFont(bold, math.floor(s(46)), false, "cleartype") or "default-bold",
    }
end

local function isInside(x, y, w, h, cx, cy)
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

local function getOrigin(panelX, panelY, panelW)
    return math.min(screenW - GW - s(4), panelX + panelW + GAP), panelY
end

local function getButtons(gx, gy)
    local bw, bh = GW - s(40), s(40)
    return {
        { op = "measure", label = "MEASURE", x = gx + s(20), y = gy + GH - s(108), w = bw, h = bh },
        { op = "close", label = "PUT AWAY", x = gx + s(20), y = gy + GH - s(58), w = bw, h = bh },
    }
end

-- Screen rectangle { x, y, w, h } of the window next to a panel at (panelX, panelY, panelW)
function getGlucometerRect(panelX, panelY, panelW)
    local gx, gy = getOrigin(panelX, panelY, panelW)
    return { gx, gy, GW, GH }
end

-- The meter now belongs to this patient (a new patient starts with its memory)
function resetGlucometer(target)
    if meter.target == target then return end
    meter = { target = target, phase = "idle" }
end

local function formatAgo(ms)
    local seconds = math.floor(ms / 1000)
    return ("%02d:%02d ago"):format(math.floor(seconds / 60), seconds % 60)
end

local function drawLCD(lx, ly, lw, lh)
    dxDrawRectangle(lx - s(4), ly - s(4), lw + s(8), lh + s(8), C.bezel)
    dxDrawRectangle(lx, ly, lw, lh, C.lcd)
    local now = getTickCount()

    if meter.phase == "measuring" then
        local left = math.max(1, MEDIC.GLUCOMETER_TIME - math.floor((now - meter.start) / 1000))
        dxDrawText(tostring(left), lx, ly + s(10), lx + lw, ly + lh - s(30), C.lcdDark, 1, fonts.number,
            "center", "center")
        local dots = ("."):rep(math.floor(now / 400) % 4)
        dxDrawText("Measuring" .. dots, lx, ly + lh - s(34), lx + lw, ly + lh - s(8), C.lcdDark, 1, fonts.bold,
            "center", "center")
        return
    end
    if meter.phase == "error" then
        dxDrawText("Err", lx, ly + s(6), lx + lw, ly + lh * 0.6, C.lcdBad, 1, fonts.number, "center", "center")
        dxDrawText(meter.error or "", lx + s(8), ly + lh * 0.6, lx + lw - s(8), ly + lh - s(6), C.lcdDark, 1,
            fonts.small, "center", "center", true, true)
        return
    end

    local reading = meter.phase == "result" and meter or memory[meter.target]
    if not reading then
        dxDrawText("- - -", lx, ly + s(6), lx + lw, ly + lh - s(34), C.lcdFaint, 1, fonts.number, "center", "center")
        dxDrawText("Insert a strip, press MEASURE", lx, ly + lh - s(34), lx + lw, ly + lh - s(8), C.lcdDark, 1,
            fonts.small, "center", "center")
        return
    end

    local value = reading.value
    local text, mmol
    if value < MEDIC.GLUCOMETER_LOW then
        text = "LO"
    elseif value > MEDIC.GLUCOMETER_HIGH then
        text = "HI"
    else
        text = tostring(value)
        mmol = ("%.1f mmol/L"):format(medicGlucoseMmol(value))
    end
    local color = (value < MEDIC.HYPO_GLUCOSE or value >= 250) and C.lcdBad or C.lcdDark
    if meter.phase ~= "result" then
        dxDrawText("MEM", lx + s(8), ly + s(6), lx + lw, ly + s(24), C.lcdDark, 1, fonts.bold, "left", "top")
    end
    dxDrawText(text, lx, ly + s(8), lx + lw - s(56), ly + lh - s(44), color, 1, fonts.number, "right", "center")
    dxDrawText("mg/dL", lx + lw - s(54), ly + s(8), lx + lw, ly + lh - s(52), C.lcdDark, 1, fonts.bold,
        "left", "bottom")
    if mmol then
        dxDrawText(mmol, lx, ly + lh - s(48), lx + lw, ly + lh - s(28), C.lcdDark, 1, fonts.bold, "center", "center")
    end
    dxDrawText(formatAgo(now - reading.tick), lx, ly + lh - s(26), lx + lw, ly + lh - s(6), C.lcdFaint, 1,
        fonts.small, "center", "center")
end

-- disabled: the panel waits for the server (another request is pending)
function drawGlucometer(panelX, panelY, panelW, cx, cy, disabled)
    ensureFonts()
    local gx, gy = getOrigin(panelX, panelY, panelW)
    dxDrawRectangle(gx, gy, GW, GH, C.body)
    dxDrawRectangle(gx, gy, GW, s(4), C.bodyEdge)
    dxDrawText("GLUCOMETER", gx + s(16), gy + s(14), gx + GW, gy + s(34), C.text, 1, fonts.title, "left", "top")
    dxDrawText("blood glucose", gx + s(16), gy + s(34), gx + GW, gy + s(52), C.muted, 1, fonts.small, "left", "top")

    local lx, ly, lw, lh = gx + s(20), gy + s(66), GW - s(40), s(150)
    drawLCD(lx, ly, lw, lh)

    -- test strip slot, a strip with a drop of blood while measuring
    local sx, sy = gx + GW / 2 - s(18), ly + lh + s(14)
    dxDrawRectangle(sx, sy, s(36), s(8), C.bezel)
    if meter.phase == "measuring" then
        dxDrawRectangle(sx + s(8), sy + s(8), s(20), s(40), C.strip)
        dxDrawRectangle(sx + s(13), sy + s(36), s(10), s(10), C.blood)
    end

    local measuring = meter.phase == "measuring"
    for _, button in ipairs(getButtons(gx, gy)) do
        local enabled = not disabled and not (button.op == "measure" and measuring)
        local hovered = enabled and isInside(button.x, button.y, button.w, button.h, cx, cy)
        dxDrawRectangle(button.x, button.y, button.w, button.h,
            enabled and (hovered and C.buttonHover or C.button) or C.buttonOff)
        dxDrawText(button.label, button.x, button.y, button.x + button.w, button.y + button.h,
            enabled and C.text or C.muted, 1, fonts.bold, "center", "center")
    end
end

-- Returns "close" when the meter is put away, true when the click hit the window, false otherwise
function clickGlucometer(panelX, panelY, panelW, target, cx, cy, disabled)
    local gx, gy = getOrigin(panelX, panelY, panelW)
    if not isInside(gx, gy, GW, GH, cx, cy) then return false end
    if disabled then return true end
    for _, button in ipairs(getButtons(gx, gy)) do
        if isInside(button.x, button.y, button.w, button.h, cx, cy) then
            if button.op == "close" then return "close" end
            if meter.phase ~= "measuring" then
                resetGlucometer(target)
                meter.phase, meter.start = "measuring", getTickCount()
                triggerServerEvent("medic:measureGlucose", resourceRoot, target)
            end
            return true
        end
    end
    return true
end

addEventHandler("medic:glucoseResult", resourceRoot, function(target, value, reason)
    if meter.target ~= target then return end
    if value then
        meter.phase, meter.value, meter.tick = "result", value, getTickCount()
        memory[target] = { value = value, tick = meter.tick }
    else
        -- "Measuring..." = a request while the previous one runs: keep counting
        if meter.phase == "measuring" and reason == "Measuring..." then return end
        meter.phase, meter.error = "error", reason
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    memory[source] = nil
end)
