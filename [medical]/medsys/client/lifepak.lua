-- "Lifepak 15" monitor / defibrillator window, drawn left of the examination panel while a
-- monitor is attached to the patient (panel.lua calls drawLifepak / clickLifepak).
-- Screen: HR (the ECG rate), SpO2, NIBP, the ECG with the rhythm name, the pleth wave and the
-- defibrillator status. Buttons: ENERGY SELECT (inactive, fixed energy), CHARGE, SOUND (ECG beep +
-- alarm of this patient on / off), SHOCK, ANALYZE (AED mode: it charges
-- when a shock is advised), SYNC (synchronised cardioversion). The server runs the defibrillator
-- (server/rhythm.lua); the buttons only send medic:defib requests.

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)

local function s(value) return value * scale end

local LW, LH = s(600), s(450)
local GAP = s(14)
local ECG_SECONDS = 4
local ADVICE_TIME = 10000
local MESSAGE_TIME = 6000

local C = {
    body = tocolor(124, 140, 156, 250),
    bodyEdge = tocolor(88, 102, 117, 255),
    bezel = tocolor(34, 37, 43, 255),
    keypad = tocolor(52, 58, 66, 255),
    screen = tocolor(0, 0, 0, 255),
    grid = tocolor(28, 32, 30, 255),
    white = tocolor(235, 238, 245, 255),
    muted = tocolor(120, 126, 136, 255),
    hr = tocolor(80, 230, 110, 255),
    spo2 = tocolor(80, 200, 255, 255),
    nibp = tocolor(200, 225, 240, 255),
    clock = tocolor(240, 220, 90, 255),
    warn = tocolor(255, 200, 60, 255),
    bad = tocolor(255, 80, 70, 255),
    button = tocolor(24, 26, 30, 255),
    buttonHover = tocolor(60, 66, 76, 255),
    yellow = tocolor(245, 200, 40, 255),
    yellowHover = tocolor(255, 222, 90, 255),
    yellowOff = tocolor(120, 104, 50, 255),
    shock = tocolor(230, 60, 50, 255),
    shockBright = tocolor(255, 120, 100, 255),
    shockOff = tocolor(110, 60, 58, 255),
    led = tocolor(70, 230, 100, 255),
    ledOff = tocolor(40, 50, 44, 255),
}

local fonts

local function ensureFonts()
    if fonts then return end
    local regular, bold = "assets/fonts/Roboto.ttf", "assets/fonts/RobotoB.ttf"
    fonts = {
        tiny = dxCreateFont(bold, math.floor(s(8)), false, "cleartype") or "default",
        small = dxCreateFont(regular, math.floor(s(10)), false, "cleartype") or "default",
        bold = dxCreateFont(bold, math.floor(s(11)), false, "cleartype") or "default-bold",
        title = dxCreateFont(bold, math.floor(s(14)), false, "cleartype") or "default-bold",
        number = dxCreateFont(bold, math.floor(s(30)), false, "cleartype") or "default-bold",
        mid = dxCreateFont(bold, math.floor(s(20)), false, "cleartype") or "default-bold",
    }
end

local function isInside(x, y, w, h, cx, cy)
    return cx >= x and cx <= x + w and cy >= y and cy <= y + h
end

-- Top-left corner of the window: left of the examination panel, kept on the screen
local function getOrigin(panelX, panelY)
    return math.max(s(4), panelX - LW - GAP), panelY
end

-- The buttons of the keypad: { op, value, x, y, w, h, kind }
local function getButtons(lx, ly)
    local kx, kw = lx + LW - s(170), s(160)
    local bx, bw = kx + s(10), kw - s(20)
    local half = (bw - s(8)) / 2
    local list = {
        -- ENERGY SELECT: inactive, the energy is fixed (MEDIC.DEFIB_ENERGY)
        { x = bx, y = ly + s(44), w = half, h = s(30), kind = "down" },
        { x = bx + half + s(8), y = ly + s(44), w = half, h = s(30), kind = "up" },
        { op = "charge", x = bx, y = ly + s(86), w = bw, h = s(34), kind = "charge" },
        { op = "shock", x = kx + kw / 2 - s(36), y = ly + s(132), w = s(72), h = s(72), kind = "shock" },
        { op = "analyze", x = bx, y = ly + s(220), w = bw, h = s(32), kind = "analyze" },
        { op = "sync", x = bx, y = ly + s(262), w = bw, h = s(32), kind = "sync" },
        -- ECG beep + alarm on / off for this patient (the defibrillator sounds always play)
        { op = "sound", x = bx, y = ly + s(304), w = bw, h = s(32), kind = "sound" },
    }
    return list, kx, kw
end

-- Live defibrillator state, interpolated since the last snapshot
local function getDefibState(monitor, elapsed)
    local charging = monitor.chargeLeft and monitor.chargeLeft - elapsed or nil
    local analyzing = monitor.analyzeLeft and monitor.analyzeLeft - elapsed or nil
    return {
        charging = charging and charging > 0 and charging or nil,
        charged = monitor.charged or (charging ~= nil and charging <= 0),
        analyzing = analyzing and analyzing > 0 and analyzing or nil,
    }
end

local function isButtonEnabled(button, defib)
    if not button.op then return false end
    if button.kind == "charge" then return not defib.charging and not defib.charged and not defib.analyzing end
    if button.kind == "shock" then return defib.charged end
    if button.kind == "analyze" then return not defib.analyzing end
    return true
end

local function drawTriangle(cx, cy, size, up, color)
    local h = size * 0.5
    local a = up and -h or h
    dxDrawPrimitive("trianglelist", false,
        { cx - size / 2, cy - a / 2, color }, { cx + size / 2, cy - a / 2, color }, { cx, cy + a / 2, color })
end

local function drawKeypad(lx, ly, data, defib, cx, cy, busy)
    local buttons, kx, kw = getButtons(lx, ly)
    dxDrawRectangle(kx, ly + s(10), kw, LH - s(20), C.keypad)
    dxDrawText("ENERGY SELECT", kx, ly + s(20), kx + kw, ly + s(40), C.white, 1, fonts.tiny, "center", "center")

    local blink = getTickCount() % 600 < 300
    for _, b in ipairs(buttons) do
        local enabled = not busy and isButtonEnabled(b, defib)
        local hovered = enabled and isInside(b.x, b.y, b.w, b.h, cx, cy)
        if b.kind == "shock" then
            local r = b.w / 2
            local color = not defib.charged and C.shockOff or (blink or hovered) and C.shockBright or C.shock
            dxDrawCircle(b.x + r, b.y + r, r + s(4), 0, 360, C.bezel, C.bezel, 32)
            dxDrawCircle(b.x + r, b.y + r, r, 0, 360, color, color, 32)
            dxDrawText("SHOCK", b.x, b.y, b.x + b.w, b.y + b.h, C.white, 1, fonts.bold, "center", "center")
        elseif b.kind == "charge" or b.kind == "analyze" then
            local color = not enabled and C.yellowOff or hovered and C.yellowHover or C.yellow
            dxDrawRectangle(b.x, b.y, b.w, b.h, color)
            dxDrawText(b.kind:upper(), b.x, b.y, b.x + b.w, b.y + b.h, tocolor(20, 20, 20, 255), 1, fonts.bold,
                "center", "center")
        else
            dxDrawRectangle(b.x, b.y, b.w, b.h, hovered and C.buttonHover or C.button)
            if not b.op then
                drawTriangle(b.x + b.w / 2, b.y + b.h / 2, s(14), b.kind == "up", C.muted)
            else -- toggles with a LED: SYNC, SOUND
                local on = b.kind == "sync" and data.monitor.sync or b.kind == "sound" and data.monitor.sound ~= false
                dxDrawCircle(b.x + s(16), b.y + b.h / 2, s(5), 0, 360, on and C.led or C.ledOff, on and C.led or C.ledOff, 16)
                dxDrawText(b.kind:upper(), b.x + s(24), b.y, b.x + b.w, b.y + b.h, C.white, 1, fonts.bold, "center", "center")
            end
        end
    end
    dxDrawText("Stand clear before SHOCK", kx, ly + LH - s(40), kx + kw, ly + LH - s(14), C.muted, 1, fonts.tiny,
        "center", "center", false, true)
end

local function rhythmColor(rhythm)
    local def = MEDIC_RHYTHMS[rhythm]
    if not def or def.shockable then return C.bad end
    if not def.pulse then return C.warn end
    return C.hr
end

-- The status line at the bottom of the screen: analysis, charge, advice, last event
local function getScreenMessage(monitor, defib, elapsed)
    local blink = getTickCount() % 800 < 500
    if defib.analyzing then return "ANALYZING - DO NOT TOUCH PATIENT", C.warn end
    if defib.charging then
        return ("CHARGING TO %dJ"):format(monitor.energy), C.warn,
            1 - defib.charging / (MEDIC.DEFIB_CHARGE_TIME * 1000)
    end
    if defib.charged then return ("PUSH SHOCK  %dJ"):format(monitor.energy), blink and C.bad or C.white end
    if monitor.advice and monitor.adviceAge + elapsed < ADVICE_TIME then
        if monitor.advice == "shock" then return "SHOCK ADVISED", C.bad end
        return "NO SHOCK ADVISED", C.warn
    end
    if monitor.message and monitor.messageAge + elapsed < MESSAGE_TIME then return monitor.message, C.white end
    return nil
end

-- Screen rows from the top: status bar, message line, HR + ECG (takes the free height), then
-- SpO2 + pleth and NIBP at the bottom. Every value sits on the left of its own row.
local TOP_H, MESSAGE_H = s(22), s(26)
local SPO2_H, NIBP_H = s(62), s(84)
local VALUE_W = s(100)

-- Label + unit on the top of the value column of a row, the value under them
local function drawValue(sx, rowY, rowH, label, unit, value, color, font)
    dxDrawText(label, sx + s(6), rowY + s(4), sx + VALUE_W, rowY + s(18), color, 1, fonts.tiny, "left", "top")
    dxDrawText(unit, sx + s(6), rowY + s(4), sx + VALUE_W - s(6), rowY + s(18), color, 1, fonts.tiny, "right", "top")
    dxDrawText(value, sx + s(6), rowY + s(16), sx + VALUE_W - s(6), rowY + rowH - s(2), color, 1, font or fonts.number,
        "right", "center")
end

local function drawScreen(sx, sy, sw, sh, data, defib, elapsed)
    local monitor = data.monitor
    local def = MEDIC_RHYTHMS[data.rhythm] or MEDIC_RHYTHMS.ASYSTOLE
    local pulse = def.pulse and not data.dead
    local lineW = math.max(1, s(2))

    dxDrawRectangle(sx, sy, sw, sh, C.screen)

    -- status bar: shocks, clock, sync, energy
    local time = getRealTime()
    dxDrawText(("Shocks: %d"):format(monitor.shocks or 0), sx + s(6), sy, sx + s(120), sy + TOP_H, C.muted, 1,
        fonts.small, "left", "center")
    dxDrawText(("%02d:%02d:%02d"):format(time.hour, time.minute, time.second), sx, sy, sx + sw, sy + TOP_H,
        C.clock, 1, fonts.bold, "center", "center")
    if monitor.sync then
        dxDrawText("SYNC", sx + sw - s(110), sy, sx + sw - s(68), sy + TOP_H, C.led, 1, fonts.bold, "right", "center")
    end
    dxDrawRectangle(sx + sw - s(62), sy + s(2), s(58), TOP_H - s(4), tocolor(70, 110, 160, 255))
    dxDrawText(monitor.energy .. "J", sx + sw - s(62), sy, sx + sw - s(4), sy + TOP_H, C.white, 1, fonts.bold,
        "center", "center")

    -- message line: analysis, charge (its bar follows the charge sound), advice, last event
    local my = sy + TOP_H
    local text, color, progress = getScreenMessage(monitor, defib, elapsed)
    if progress then
        dxDrawRectangle(sx + s(4), my + MESSAGE_H - s(5), (sw - s(8)) * math.max(0, math.min(1, progress)), s(3), C.warn)
    end
    if text then
        local font = dxGetTextWidth(text, 1, fonts.title) > sw - s(8) and fonts.bold or fonts.title
        dxDrawText(text, sx, my, sx + sw, my + MESSAGE_H - s(4), color, 1, font, "center", "center", true)
    end

    -- rows: HR fills the space between the message line and the two bottom rows
    local nibpY = sy + sh - NIBP_H
    local spo2Y = nibpY - SPO2_H
    local hrY = my + MESSAGE_H
    local hrH = spo2Y - hrY
    for _, y in ipairs({ hrY, spo2Y, nibpY }) do dxDrawLine(sx, y, sx + sw, y, C.grid, 1) end
    dxDrawLine(sx + VALUE_W, hrY, sx + VALUE_W, sy + sh, C.grid, 1)
    local tx, tw = sx + VALUE_W + s(8), sw - VALUE_W - s(14)

    -- HR (the ECG rate) + ECG with the rhythm name under it
    local hasComplexes = def.wave == "sinus" or def.wave == "vt" -- PEA: no QRS the monitor can count
    drawValue(sx, hrY, hrH, "HR", "bpm", (hasComplexes and data.ecgRate > 0) and tostring(data.ecgRate) or "---", C.hr)
    local labelH = s(38)
    local ecgY, ecgH = hrY + s(8), hrH - labelH - s(10)
    dxDrawText("II  x1.0", tx, hrY + s(3), tx + tw, hrY + s(16), C.hr, 1, fonts.tiny, "right", "top")
    ecgDraw("ecg", tx, ecgY, tw, ecgH, ECG_SECONDS, C.hr, lineW, 0.62, 0.55)
    dxDrawText(def.label, tx, hrY + hrH - labelH, tx + tw, hrY + hrH - s(2), rhythmColor(data.rhythm), 1,
        fonts.title, "left", "center", false, true)

    -- SpO2 + pleth
    drawValue(sx, spo2Y, SPO2_H, "SpO2", "%", pulse and tostring(data.spo2) or "---", C.spo2)
    dxDrawText("SpO2", tx, spo2Y + s(3), tx + tw, spo2Y + s(16), C.spo2, 1, fonts.tiny, "right", "top")
    ecgDraw("pleth", tx, spo2Y + s(8), tw, SPO2_H - s(14), ECG_SECONDS, C.spo2, lineW, 0.95, 0.85)

    -- NIBP on the bottom row: systolic, the diastolic under it, the mean pressure in brackets beside it
    local right = sx + VALUE_W - s(6)
    dxDrawText("NIBP", sx + s(6), nibpY + s(4), sx + VALUE_W, nibpY + s(18), C.nibp, 1, fonts.tiny, "left", "top")
    dxDrawText("mmHg", sx + s(6), nibpY + s(4), right, nibpY + s(18), C.nibp, 1, fonts.tiny, "right", "top")
    if pulse then
        dxDrawText(tostring(data.systolic), sx + s(6), nibpY + s(14), right, nibpY + s(50), C.nibp, 1, fonts.number,
            "right", "center")
        dxDrawText(tostring(data.diastolic), sx + s(36), nibpY + s(48), right, nibpY + NIBP_H - s(4), C.nibp, 1,
            fonts.mid, "right", "center")
        local map = math.floor(data.diastolic + (data.systolic - data.diastolic) / 3 + 0.5)
        dxDrawText(("(%d)"):format(map), sx + s(6), nibpY + s(48), sx + s(46), nibpY + NIBP_H - s(4), C.nibp, 1,
            fonts.small, "left", "center")
    else
        dxDrawText("---", sx + s(6), nibpY + s(14), right, nibpY + s(50), C.nibp, 1, fonts.number, "right", "center")
    end
end

---------------------------------------------------------------------------
-- Sounds (only for the medics at the panel, like the ECG beep)
---------------------------------------------------------------------------

local SOUNDS = {
    charge = { file = "sounds/defib_charge.wav", volume = 0.6 },          -- as long as DEFIB_CHARGE_TIME
    complete = { file = "sounds/defib_charge_complate.wav", volume = 0.6 },
    ready = { file = "sounds/defib_ready_loop.wav", volume = 0.5, looped = true }, -- charged, until the shock
    alarm = { file = "sounds/lifepak_alarm_loop.wav", volume = 0.15, looped = true }, -- life-threatening rhythm
}
local READY_DELAY = 400 -- ms after the charge-complete tone before the ready loop

local playing = {} -- [name] = sound element
local soundState = {} -- charging, charged, chargedTick

local function playLifepakSound(name, position)
    local def = SOUNDS[name]
    if isElement(playing[name]) then stopSound(playing[name]) end
    local sound = playSound(def.file, def.looped == true)
    if sound then
        setSoundVolume(sound, def.volume)
        if position and position > 0 then setSoundPosition(sound, position) end
    end
    playing[name] = sound
end

local function stopLifepakSound(name)
    if isElement(playing[name]) then stopSound(playing[name]) end
    playing[name] = nil
end

-- The monitor window is gone (panel closed / no monitor): silence
function stopLifepakSounds()
    for name in pairs(SOUNDS) do stopLifepakSound(name) end
    soundState = {}
end

-- VF, pulseless VT, PEA and VT with pulse sound the alarm (asystole does not)
local function isAlarmRhythm(data)
    local def = MEDIC_RHYTHMS[data.rhythm]
    if data.dead or not def or data.rhythm == "ASYSTOLE" then return false end
    return not def.pulse or data.rhythm == "VT_WITH_PULSE"
end

local function updateSounds(data, defib)
    local now = getTickCount()
    local wasCharging = soundState.charging
    -- charging: the tone runs from where the charge is (a panel opened mid-charge joins in)
    if defib.charging and not soundState.charging then
        playLifepakSound("charge", MEDIC.DEFIB_CHARGE_TIME - defib.charging / 1000)
    elseif not defib.charging and soundState.charging then
        stopLifepakSound("charge")
    end
    soundState.charging = defib.charging ~= nil

    if defib.charged and not soundState.charged then
        if wasCharging then playLifepakSound("complete") end -- not when the panel opens on a charged one
        soundState.chargedTick = now
    elseif not defib.charged and soundState.charged then
        stopLifepakSound("ready") -- shocked or dumped
    end
    soundState.charged = defib.charged == true
    if soundState.charged and not playing.ready and now - soundState.chargedTick >= READY_DELAY then
        playLifepakSound("ready")
    end

    local alarm = isAlarmRhythm(data) and data.monitor.sound ~= false
    if alarm and not playing.alarm then
        playLifepakSound("alarm")
    elseif not alarm and playing.alarm then
        stopLifepakSound("alarm")
    end
end

-- data: the panel snapshot (data.monitor is set), elapsed: ms since it arrived,
-- busy: the panel waits for the server (buttons off)
function drawLifepak(panelX, panelY, data, elapsed, cx, cy, busy)
    ensureFonts()
    local lx, ly = getOrigin(panelX, panelY)
    local defib = getDefibState(data.monitor, elapsed)

    dxDrawRectangle(lx, ly, LW, LH, C.body)
    dxDrawRectangle(lx, ly + LH - s(6), LW, s(6), C.bodyEdge)

    local bx, by, bw, bh = lx + s(10), ly + s(10), LW - s(190), LH - s(20)
    dxDrawRectangle(bx, by, bw, bh, C.bezel)
    dxDrawText("LIFEPAK 15", bx + s(10), by, bx + bw, by + s(26), C.white, 1, fonts.title, "left", "center")
    dxDrawText("MONITOR/DEFIBRILLATOR", bx, by, bx + bw - s(10), by + s(26), C.white, 1, fonts.tiny, "right", "center")
    drawScreen(bx + s(6), by + s(28), bw - s(12), bh - s(34), data, defib, elapsed)
    updateSounds(data, defib)

    drawKeypad(lx, ly, data, defib, cx, cy, busy)
end

-- True when the click hit the window (a button press is sent to the server)
function clickLifepak(panelX, panelY, target, data, elapsed, cx, cy, busy)
    local lx, ly = getOrigin(panelX, panelY)
    if not isInside(lx, ly, LW, LH, cx, cy) then return false end
    if busy then return true end
    local defib = getDefibState(data.monitor, elapsed)
    for _, b in ipairs((getButtons(lx, ly))) do
        if isInside(b.x, b.y, b.w, b.h, cx, cy) and isButtonEnabled(b, defib) then
            triggerServerEvent("medic:defib", resourceRoot, target, b.op, b.value)
            break
        end
    end
    return true
end

-- Window rectangle { x, y, w, h } next to a panel at panelX / panelY (for the panel layout)
function getLifepakRect(panelX, panelY)
    local lx, ly = getOrigin(panelX, panelY)
    return { lx, ly, LW, LH }
end
