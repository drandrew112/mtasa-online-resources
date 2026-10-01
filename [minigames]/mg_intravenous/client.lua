-- IV cannulation: aim the needle over the vein (mouse, with hand tremor), press LMB to puncture,
-- hold LMB to advance until the tip and the cannula are inside the vein (flashback), release,
-- then drag the needle back out slowly so only the cannula stays in the vein.

addEvent("onClientIVGameFinish", false)
addEvent("mg_intravenous:start", true)
addEvent("mg_intravenous:stop", true)

local screenW, screenH = guiGetScreenSize()
local scale = screenH / 1080

local PANEL_W, PANEL_H = 1040 * scale, 470 * scale
local PANEL_X = (screenW - PANEL_W) / 2
local PANEL_Y = screenH - 60 * scale - PANEL_H
local PAD = 20 * scale

-- top view (the forearm from above) and the cross-section along the needle
local TOP_X, TOP_Y = PANEL_X + PAD, PANEL_Y + 56 * scale
local TOP_W, TOP_H = math.floor(640 * scale), math.floor(300 * scale)
local SEC_X, SEC_Y = TOP_X + TOP_W + PAD, TOP_Y
local SEC_W, SEC_H = math.floor(PANEL_X + PANEL_W - PAD - SEC_X), TOP_H

local PX_MM = TOP_H / IV.VIEW_MM                  -- top view pixels per mm
local ANGLE = math.rad(IV.NEEDLE_ANGLE)
local COS_A, SIN_A, TAN_A = math.cos(ANGLE), math.sin(ANGLE), math.tan(ANGLE)
local TOP_ENTRY_X = TOP_W * 0.55                  -- where the needle pierces the skin (top view)
local SEC_ENTRY_X = 40 * scale
local SEC_SKIN_Y = 34 * scale
local SEC_PX_MM = math.min((SEC_W - SEC_ENTRY_X - 20 * scale) / (IV.MAX_DEPTH / TAN_A),
    (SEC_H - SEC_SKIN_Y - 20 * scale) / (IV.MAX_DEPTH + 1))

-- along-needle layout (mm, measured back from the needle tip)
local CATH_GAP = 2        -- bare needle in front of the cannula
local CATH_LEN = 26
local CATH_HUB = 7
local NEEDLE_HUB = 12     -- flashback chamber
local GRIP = 13

local COLOR_GOOD = { 70, 220, 90 }
local COLOR_WARN = { 255, 170, 40 }
local COLOR_FAIL = { 230, 60, 60 }
local COLOR_BLOOD = { 175, 20, 30 }

local MISTAKES = {
    missed = "Missed the vein",
    through = "Went through the vein",
    dislodged = "Pulled too fast - the cannula came out",
}

-- movement/combat controls disabled for the whole game (the mouse is used for the needle)
local LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger", "next_weapon", "previous_weapon" }

local SKIN_SVG = [[<svg xmlns="http://www.w3.org/2000/svg" width="512" height="256" viewBox="0 0 512 256">
<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#9c6848"/><stop offset="0.14" stop-color="#d49a76"/>
<stop offset="0.5" stop-color="#e9b996"/><stop offset="0.86" stop-color="#d49a76"/>
<stop offset="1" stop-color="#9c6848"/></linearGradient></defs>
<rect width="512" height="256" fill="url(#g)"/></svg>]]

local game
local skinTexture

local function rgba(color, alpha)
    return tocolor(color[1], color[2], color[3], alpha or 255)
end

local function lockControls()
    game.lockedControls = {}
    for _, control in ipairs(LOCK_CONTROLS) do
        if isControlEnabled(control) then
            toggleControl(control, false)
            table.insert(game.lockedControls, control)
        end
    end
end

local function unlockControls(g)
    for _, control in ipairs(g.lockedControls or {}) do
        toggleControl(control, true)
    end
end

-- Puts the local player next to the ped, facing it
local function placeNextToPed(ped)
    local px, py, pz = getElementPosition(ped)
    local m = getElementMatrix(ped)
    local rx, ry = m[1][1], m[1][2]
    local fx, fy = m[2][1], m[2][2]
    local rl = math.sqrt(rx * rx + ry * ry)
    local fl = math.sqrt(fx * fx + fy * fy)
    if rl > 0 then rx, ry = rx / rl, ry / rl end
    if fl > 0 then fx, fy = fx / fl, fy / fl end

    local x = px + rx * IV.PED_SIDE_OFFSET + fx * IV.PED_FORWARD_OFFSET
    local y = py + ry * IV.PED_SIDE_OFFSET + fy * IV.PED_FORWARD_OFFSET
    local groundZ = getGroundPosition(x, y, pz + 1.5)
    local z = (groundZ and groundZ ~= 0) and groundZ + 1.0 or pz

    setElementPosition(localPlayer, x, y, z)
    setElementRotation(localPlayer, 0, 0, -math.deg(math.atan2(px - x, py - y)), "default", true)
end

------------------------------------------------------------------------------------------------
-- attempt / geometry helpers
------------------------------------------------------------------------------------------------

-- Centre of the vein (mm from the top edge of the top view) at a top-view x pixel
local function veinCenter(vein, x)
    return vein.center + vein.amp * math.sin(x / PX_MM * vein.freq + vein.phase)
end

local function newAttempt()
    local g = game
    g.vein = {
        center = IV.VIEW_MM / 2 + (math.random() - 0.5) * 6,
        amp = 1.2 + math.random() * 1.8,
        freq = 0.06 + math.random() * 0.08,
        phase = math.random() * math.pi * 2,
        depth = IV.VEIN_DEPTH_MIN + math.random() * (IV.VEIN_DEPTH_MAX - IV.VEIN_DEPTH_MIN),
    }
    g.state = "aim"
    g.stateTick = getTickCount()
    g.aim = g.vein.center
    g.offset = nil
    g.depth = 0
    g.holdTime = 0
    g.flashback = false
    g.catheterDepth = nil
    g.retract = 0
    g.grab = nil
    g.pullSpeed = 0
    g.stress = 0
    g.peakStress = 0
    g.needleOut = false
end

local function setState(state)
    game.state = state
    game.stateTick = getTickCount()
end

-- Lateral offset of the needle from the vein centre line and the half height of the vein there
local function currentChord()
    local offset = game.offset or (game.aim - veinCenter(game.vein, TOP_ENTRY_X))
    return offset, ivVeinChord(game.diff.veinRadius, offset)
end

local function inLumen(depth, chord)
    return chord > 0 and depth > game.vein.depth - chord and depth < game.vein.depth + chord
end

------------------------------------------------------------------------------------------------
-- finishing
------------------------------------------------------------------------------------------------

local render

local function finish(reason, notifyServer)
    local g = game
    if not g then return end
    game = nil

    removeEventHandler("onClientRender", root, render)
    unlockControls(g)
    showCursor(false)
    if g.localAnim then setPedAnimation(localPlayer) end
    if isElement(g.topRT) then destroyElement(g.topRT) end
    if isElement(g.secRT) then destroyElement(g.secRT) end

    local success = reason == "completed"
    local quality = success and g.quality or 0
    if g.sessionId and notifyServer then
        triggerServerEvent("mg_intravenous:onResult", resourceRoot, g.sessionId, reason, g.attempt, quality)
    end
    -- success, attempts used, quality (0-100), reason, sessionId (nil for client-started games)
    triggerEvent("onClientIVGameFinish", localPlayer, success, g.attempt, quality, reason, g.sessionId)
end

local function showResult(reason)
    game.resultReason = reason
    setState("result")
end

local function mistake(kind)
    game.mistake = kind
    if game.attempt < game.options.attempts then
        setState("retry")
    else
        showResult(kind)
    end
end

------------------------------------------------------------------------------------------------
-- input / simulation
------------------------------------------------------------------------------------------------

local function cursorPos()
    local cx, cy = getCursorPosition()
    if not cx then return nil end
    return cx * screenW, cy * screenH
end

local function tremor(t)
    local amount = game.diff.tremor
    return amount * (0.6 * math.sin(t * 5.3) + 0.4 * math.sin(t * 8.7 + 1.3))
end

local function update(now, t, dt, pressed, held)
    local g = game
    local state = g.state

    if state == "aim" then
        local _, cy = cursorPos()
        if cy then
            g.aim = (cy - TOP_Y) / PX_MM + tremor(t)
            g.aim = math.max(1, math.min(IV.VIEW_MM - 1, g.aim))
        end
        if pressed then
            g.offset = g.aim - veinCenter(g.vein, TOP_ENTRY_X)
            setState("push")
        end

    elseif state == "push" then
        local _, chord = currentChord()
        if held then
            g.holdTime = g.holdTime + dt
            -- starts slow, reaches full speed after a short hold: tapping gives finer control
            local speed = g.diff.pushSpeed * (0.45 + 0.55 * math.min(1, g.holdTime / 0.4))
            g.depth = g.depth + speed * dt

            if chord > 0 and g.depth >= g.vein.depth + chord then
                g.depth = g.vein.depth + chord
                return mistake("through")
            end
            if g.depth >= IV.MAX_DEPTH then
                g.depth = IV.MAX_DEPTH
                return mistake("missed")
            end
            g.flashback = g.flashback or inLumen(g.depth, chord)
        elseif g.holdTime > 0 then
            -- released: done if both the needle tip and the cannula tip are inside the vein
            g.holdTime = 0
            g.catheterDepth = g.depth - CATH_GAP * SIN_A
            if inLumen(g.depth, chord) and inLumen(g.catheterDepth, chord) then
                g.releaseDepth = g.depth
                setState("flash")
            end
        end

    elseif state == "flash" then
        if now - g.stateTick >= IV.FLASHBACK_TIME * 1000 then setState("pull") end

    elseif state == "pull" then
        local cx = cursorPos()
        local moved = 0
        if held and cx then
            if pressed or not g.grab then g.grab, g.grabBase = cx, g.retract end
            local target = g.grabBase + (g.grab - cx) / (PX_MM * COS_A)
            if target > g.retract then
                moved = target - g.retract
                g.retract = target
            end
        else
            g.grab = nil
        end

        -- smoothed withdraw speed, pulling faster than the limit loosens the cannula
        local instant = dt > 0 and moved / dt or 0
        g.pullSpeed = g.pullSpeed + (instant - g.pullSpeed) * math.min(1, dt * 10)
        local over = g.pullSpeed / g.diff.pullSpeed - 1
        if over > 0 then
            g.stress = g.stress + over * dt * 3
        else
            g.stress = math.max(0, g.stress - dt * 0.35)
        end
        g.peakStress = math.max(g.peakStress, math.min(1, g.stress))

        if g.stress >= 1 then return mistake("dislodged") end
        if g.retract >= IV.NEEDLE_LENGTH then
            g.needleOut = true
            local offset, chord = currentChord()
            g.quality = ivQuality(offset, g.diff.veinRadius, g.releaseDepth - g.vein.depth, chord, g.peakStress)
            showResult("completed")
        end

    elseif state == "retry" then
        if now - g.stateTick >= IV.RETRY_TIME * 1000 then
            g.attempt = g.attempt + 1
            newAttempt()
        end
    end
end

------------------------------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------------------------------

local function shadowText(text, x1, y1, x2, y2, color, size, alignX, alignY, alpha)
    dxDrawText(text, x1 + 2, y1 + 2, x2 + 2, y2 + 2, tocolor(0, 0, 0, 180 * (alpha or 1)),
        size, "default-bold", alignX, alignY)
    dxDrawText(text, x1, y1, x2, y2, color, size, "default-bold", alignX, alignY)
end

-- Along-needle position (mm from the skin entry) of the needle tip and the cannula tip
local function needlePositions()
    local g = game
    local tipA
    if g.state == "aim" then
        tipA = -0.8 -- hovering just above the skin
    elseif g.releaseDepth then
        tipA = g.releaseDepth / SIN_A - g.retract
    else
        tipA = g.depth / SIN_A
    end
    local cathA = g.releaseDepth and (g.releaseDepth / SIN_A - CATH_GAP) or (tipA - CATH_GAP)
    return tipA, cathA
end

-- Top view: a horizontal bar between two along-needle positions, dimmed where it is under the skin
local function topBar(ox, oy, a1, a2, y, halfH, r, gr, b, alpha)
    local x1 = TOP_ENTRY_X + a1 * COS_A * PX_MM
    local x2 = TOP_ENTRY_X + a2 * COS_A * PX_MM
    if x2 <= x1 then return end
    local split = math.max(x1, math.min(x2, TOP_ENTRY_X))
    if split > x1 then
        dxDrawRectangle(ox + x1, oy + y - halfH, split - x1, halfH * 2, tocolor(r, gr, b, alpha))
    end
    if x2 > split then
        dxDrawRectangle(ox + split, oy + y - halfH, x2 - split, halfH * 2, tocolor(r, gr, b, alpha * 0.3))
    end
end

local function drawTopView(ox, oy)
    local g = game
    if isElement(skinTexture) then
        dxDrawImage(ox, oy, TOP_W, TOP_H, skinTexture)
    else
        dxDrawRectangle(ox, oy, TOP_W, TOP_H, tocolor(222, 170, 135))
    end

    -- vein, a soft bluish line under the skin
    local width = g.diff.veinRadius * 2 * PX_MM
    local visibility = ({ 150, 120, 90 })[g.options.difficulty]
    local step = 6 * scale
    local prevX, prevY = 0, veinCenter(g.vein, 0) * PX_MM
    for x = step, TOP_W + step, step do
        local y = veinCenter(g.vein, x) * PX_MM
        dxDrawLine(ox + prevX, oy + prevY, ox + x, oy + y, tocolor(95, 115, 175, visibility * 0.45), width * 1.35)
        dxDrawLine(ox + prevX, oy + prevY, ox + x, oy + y, tocolor(80, 95, 160, visibility), width * 0.8)
        prevX, prevY = x, y
    end

    -- tourniquet (proximal side, the needle points towards it)
    local tx = TOP_W - 70 * scale
    dxDrawRectangle(ox + tx, oy, 36 * scale, TOP_H, tocolor(45, 95, 175, 235))
    dxDrawRectangle(ox + tx + 14 * scale, oy, 8 * scale, TOP_H, tocolor(90, 145, 220, 235))

    -- needle + cannula, pointing right
    local y = g.aim * PX_MM
    if g.offset then y = (veinCenter(g.vein, TOP_ENTRY_X) + g.offset) * PX_MM end
    local tipA, cathA = needlePositions()
    local s = scale

    if not g.needleOut then
        topBar(ox, oy, tipA - CATH_GAP - CATH_LEN - CATH_HUB, tipA, y, 1.5 * s, 205, 210, 220, 255)
    end
    local cathColor = g.releaseDepth and g.retract > CATH_GAP and COLOR_BLOOD or { 245, 245, 250 }
    topBar(ox, oy, cathA - CATH_LEN, cathA, y, 3 * s, cathColor[1], cathColor[2], cathColor[3], 140)
    topBar(ox, oy, cathA - CATH_LEN - CATH_HUB, cathA - CATH_LEN, y, 8 * s, 230, 95, 160, 255)
    local wingA = cathA - CATH_LEN - CATH_HUB / 2
    topBar(ox, oy, wingA - 1.2, wingA + 1.2, y, 22 * s, 230, 95, 160, 235)

    if not g.needleOut then
        local hubEnd = tipA - CATH_GAP - CATH_LEN - CATH_HUB
        topBar(ox, oy, hubEnd - NEEDLE_HUB, hubEnd, y, 7 * s, 225, 232, 240, 190)
        if g.flashback then
            topBar(ox, oy, hubEnd - NEEDLE_HUB + 1.5, hubEnd - 0.5, y, 4.5 * s,
                COLOR_BLOOD[1], COLOR_BLOOD[2], COLOR_BLOOD[3], 255)
        end
        topBar(ox, oy, hubEnd - NEEDLE_HUB - GRIP, hubEnd - NEEDLE_HUB, y, 9 * s, 240, 240, 240, 255)
    end

    -- puncture mark
    if g.offset then
        dxDrawRectangle(ox + TOP_ENTRY_X - 2 * s, oy + y - 2 * s, 4 * s, 4 * s, tocolor(120, 30, 30, 200))
    end
end

-- Cross-section along the needle: point at along-needle distance a (mm) from the entry
local function secPoint(a)
    return SEC_ENTRY_X + a * COS_A * SEC_PX_MM, SEC_SKIN_Y + a * SIN_A * SEC_PX_MM
end

local function secLine(ox, oy, a1, a2, color, width)
    if a2 <= a1 then return end
    local x1, y1 = secPoint(a1)
    local x2, y2 = secPoint(a2)
    dxDrawLine(ox + x1, oy + y1, ox + x2, oy + y2, color, width)
end

local function drawSection(ox, oy)
    local g = game
    local function depthY(mm) return SEC_SKIN_Y + mm * SEC_PX_MM end

    dxDrawRectangle(ox, oy, SEC_W, SEC_H, tocolor(20, 22, 28))
    dxDrawRectangle(ox, oy + depthY(0), SEC_W, depthY(0.5) - depthY(0), tocolor(200, 140, 110))
    dxDrawRectangle(ox, oy + depthY(0.5), SEC_W, depthY(2.2) - depthY(0.5), tocolor(215, 150, 140))
    dxDrawRectangle(ox, oy + depthY(2.2), SEC_W, depthY(9.5) - depthY(2.2), tocolor(232, 205, 140))
    dxDrawRectangle(ox, oy + depthY(9.5), SEC_W, SEC_H - depthY(9.5), tocolor(150, 55, 55))

    local _, chord = currentChord()
    local reveal = g.options.showDepth or g.state == "result" or g.state == "retry"
    if reveal and chord > 0 then
        local top, bottom = depthY(g.vein.depth - chord), depthY(g.vein.depth + chord)
        local wall = math.max(2, 3 * scale)
        dxDrawRectangle(ox, oy + top, SEC_W, bottom - top, tocolor(125, 20, 30))
        dxDrawRectangle(ox, oy + top, SEC_W, wall, tocolor(85, 40, 70))
        dxDrawRectangle(ox, oy + bottom - wall, SEC_W, wall, tocolor(85, 40, 70))
    end

    local tipA, cathA = needlePositions()
    if not g.needleOut then
        secLine(ox, oy, tipA - 60, tipA, tocolor(200, 205, 215), math.max(2, 3 * scale))
    end
    if g.releaseDepth and tipA < cathA then
        -- blood follows the needle back into the cannula
        secLine(ox, oy, math.max(tipA, cathA - CATH_LEN), cathA, rgba(COLOR_BLOOD, 230), math.max(2, 3 * scale))
    end
    secLine(ox, oy, cathA - CATH_LEN, cathA, tocolor(245, 245, 250, 120), 7 * scale)
    if g.flashback and not g.needleOut then
        local x, y = secPoint(tipA)
        dxDrawRectangle(ox + x - 3 * scale, oy + y - 3 * scale, 6 * scale, 6 * scale, rgba(COLOR_BLOOD))
    end
end

local function drawBar(x, y, w, h, value, color, label)
    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 35))
    dxDrawRectangle(x, y, w * math.max(0, math.min(1, value)), h, rgba(color, 220))
    dxDrawText(label, x, y - 22 * scale, x + w, y - 2 * scale, tocolor(200, 200, 200, 220), 1.0 * scale,
        "default-bold", "left", "bottom")
end

local function hintText()
    local g = game
    local state = g.state
    if state == "aim" then
        return "Aim over the vein with the mouse, press LMB to puncture the skin", nil
    elseif state == "push" then
        if g.flashback and g.holdTime == 0 and g.catheterDepth then
            local _, chord = currentChord()
            if inLumen(g.depth, chord) then
                return "Flashback! Advance a little more so the cannula is in the vein too", COLOR_WARN
            end
        end
        if g.flashback then return "Flashback! The needle tip is in the vein", COLOR_GOOD end
        return "Hold LMB to advance the needle - release when blood appears in the chamber", nil
    elseif state == "flash" then
        return "Cannula in the vein", COLOR_GOOD
    elseif state == "pull" then
        return "Hold LMB and drag LEFT to withdraw the needle - slowly!", nil
    elseif state == "retry" then
        return MISTAKES[g.mistake] .. " - try again", COLOR_FAIL
    elseif state == "result" then
        if g.resultReason == "completed" then return "IV access secured", COLOR_GOOD end
        return MISTAKES[g.resultReason] or "Out of time", COLOR_FAIL
    end
    return "", nil
end

local function drawPanel(now, t)
    local g = game
    local x, y, w, h = PANEL_X, PANEL_Y, PANEL_W, PANEL_H
    local playing = t >= 0

    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 170))
    local progress = playing and math.min(1, t / g.options.time) or 0
    dxDrawRectangle(x, y, w, 4 * scale, tocolor(255, 255, 255, 40))
    dxDrawRectangle(x, y, w * (1 - progress), 4 * scale, tocolor(90, 170, 255, 220))

    -- header: hint + time left
    local hint, hintColor = hintText()
    if not playing then hint, hintColor = "Get ready", nil end
    dxDrawText(hint, x + PAD, y + 12 * scale, x + w - 120 * scale, y + 46 * scale,
        hintColor and rgba(hintColor) or tocolor(230, 230, 230, 230), 1.2 * scale, "default-bold", "left", "center",
        true)
    local timeLeft = playing and math.max(0, g.options.time - t) or g.options.time
    dxDrawText(("%.1f s"):format(timeLeft), x, y + 12 * scale, x + w - PAD, y + 46 * scale,
        tocolor(255, 255, 255, 240), 1.3 * scale, "default-bold", "right", "center")

    -- the two views, clipped through render targets when available
    if isElement(g.topRT) and isElement(g.secRT) then
        dxSetBlendMode("modulate_add")
        dxSetRenderTarget(g.topRT, true)
        drawTopView(0, 0)
        dxSetRenderTarget(g.secRT, true)
        drawSection(0, 0)
        dxSetRenderTarget()
        dxSetBlendMode("add")
        dxDrawImage(TOP_X, TOP_Y, TOP_W, TOP_H, g.topRT)
        dxDrawImage(SEC_X, SEC_Y, SEC_W, SEC_H, g.secRT)
        dxSetBlendMode("blend")
    else
        drawTopView(TOP_X, TOP_Y)
        drawSection(SEC_X, SEC_Y)
    end

    local labelColor = tocolor(255, 255, 255, 200)
    local labelBottom = TOP_Y + 30 * scale
    dxDrawText("TOP VIEW", TOP_X + 8 * scale, TOP_Y + 6 * scale, TOP_X + TOP_W, labelBottom, labelColor,
        0.9 * scale, "default-bold")
    dxDrawText("CROSS-SECTION", SEC_X + 8 * scale, SEC_Y + 6 * scale, SEC_X + SEC_W, labelBottom, labelColor,
        0.9 * scale, "default-bold")
    dxDrawText(("Depth %.1f mm"):format(g.depth), SEC_X, SEC_Y + 6 * scale, SEC_X + SEC_W - 8 * scale, labelBottom,
        labelColor, 0.9 * scale, "default-bold", "right")

    -- footer: attempts + withdraw bars
    local fy = TOP_Y + TOP_H + 14 * scale
    dxDrawText(("Attempt %d / %d"):format(g.attempt, g.options.attempts), x + PAD, fy, x + w, fy + 60 * scale,
        tocolor(200, 200, 200, 220), 1.1 * scale, "default-bold", "left", "center")

    if g.state == "pull" or (g.state == "result" and g.releaseDepth) then
        local bx, bw, bh = x + 260 * scale, 330 * scale, 12 * scale
        local by = fy + 34 * scale
        drawBar(bx, by, bw, bh, g.retract / IV.NEEDLE_LENGTH, { 90, 170, 255 }, "Needle withdrawn")
        local stressColor = g.stress > 0.6 and COLOR_FAIL or (g.stress > 0.25 and COLOR_WARN or COLOR_GOOD)
        drawBar(bx + bw + 30 * scale, by, bw, bh, g.stress, stressColor, "Cannula strain")
    end
end

render = function()
    local g = game
    if not isElement(skinTexture) then skinTexture = svgCreate(512, 256, SKIN_SVG) end

    local now = getTickCount()
    local dt = math.min(0.1, (now - (g.lastTick or now)) / 1000)
    g.lastTick = now
    local t = (now - g.playTick) / 1000

    local held = getKeyState("mouse1")
    local pressed = held and not g.wasHeld
    g.wasHeld = held

    if t >= 0 and g.state ~= "result" then
        if t >= g.options.time then
            showResult("expired")
        else
            update(now, t, dt, pressed, held)
        end
    end

    drawPanel(now, t)

    if t < 0 then
        local n = math.ceil(-t)
        local k = 1 - (-t - (n - 1))
        local cy = PANEL_Y - 110 * scale
        shadowText(tostring(n), 0, cy, screenW, cy, tocolor(255, 255, 255, 255 * (1 - k * 0.6)),
            (4 - k) * scale, "center", "center")
        shadowText("Get ready", 0, cy + 60 * scale, screenW, cy + 60 * scale, tocolor(220, 220, 220, 230),
            1.4 * scale, "center", "center")
    end

    if g.state == "result" then
        local elapsed = now - g.stateTick
        local k = math.min(1, elapsed / 250)
        local success = g.resultReason == "completed"
        local text = success and ("SUCCESS  %d%%"):format(g.quality) or "FAILED"
        local ty = PANEL_Y - 70 * scale
        shadowText(text, 0, ty, screenW, ty, rgba(success and COLOR_GOOD or COLOR_FAIL, 255 * k),
            (2.4 + (1 - k)) * scale, "center", "center", k)

        if elapsed >= IV.RESULT_TIME * 1000 then
            finish(g.resultReason, true)
        end
    end
end

local function begin(ped, options, sessionId)
    if game then return false end
    if ped ~= nil and (not isElement(ped) or ped == localPlayer) then return false end
    if not isElement(skinTexture) then skinTexture = svgCreate(512, 256, SKIN_SVG) end

    options = ivNormalizeOptions(options)
    game = {
        sessionId = sessionId,
        options = options,
        diff = ivDifficulty(options),
        ped = ped,
        attempt = 1,
        quality = 0,
        playTick = getTickCount() + IV.COUNTDOWN * 1000,
        topRT = dxCreateRenderTarget(TOP_W, TOP_H, true),
        secRT = dxCreateRenderTarget(SEC_W, SEC_H, true),
    }
    newAttempt()

    lockControls()
    showCursor(true)
    if ped then
        placeNextToPed(ped)
        if sessionId then
            -- server-started: the server plays the animation so everyone sees it
            triggerServerEvent("mg_intravenous:ready", resourceRoot, sessionId)
        else
            game.localAnim = true
            setPedAnimation(localPlayer, IV.ANIM_BLOCK, IV.ANIM_NAME, -1, true, false, false, false)
        end
    end

    addEventHandler("onClientRender", root, render)
    return true
end

-- Local game, the server is not involved (the animation is only visible to this client).
-- ped is optional.
-- options: { difficulty = 2, time = 45, attempts = 2, showDepth = true }
function startIVGame(ped, options)
    return begin(ped, options, nil)
end

-- Aborts the current game. onClientIVGameFinish fires with reason "cancelled".
-- A server-started game should be stopped from the server instead.
function stopIVGame()
    if not game then return false end
    finish("cancelled", false)
    return true
end

function isIVGameActive()
    return game ~= nil
end

addEventHandler("mg_intravenous:start", resourceRoot, function(sessionId, options, ped)
    if game then finish("cancelled", false) end
    begin(ped, options, sessionId)
end)

addEventHandler("mg_intravenous:stop", resourceRoot, function()
    finish("cancelled", false)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if game and not game.sessionId then finish("died", false) end
end)
