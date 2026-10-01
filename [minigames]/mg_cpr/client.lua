-- The player presses SPACE in a steady rhythm. Every press after the first is
-- judged by the time since the previous one: inside [minBPM, maxBPM] is good,
-- otherwise too fast / too slow. Long pauses count as missed compressions.

addEvent("onClientCPRGameFinish", false)
addEvent("mg_cpr:start", true)
addEvent("mg_cpr:stop", true)

local screenW, screenH = guiGetScreenSize()
local scale = screenH / 1080

local PANEL_W, PANEL_H = 560 * scale, 170 * scale
local PANEL_X = (screenW - PANEL_W) / 2
local PANEL_Y = screenH - 60 * scale - PANEL_H
local HEART_SIZE = 96 * scale
local GAUGE_MIN, GAUGE_MAX = 50, 150

local COLOR_HEART = { 220, 50, 60 }
local COLOR_GOOD = { 70, 220, 90 }
local COLOR_FAST = { 255, 150, 40 }
local COLOR_SLOW = { 80, 170, 255 }
local COLOR_FAIL = { 230, 60, 60 }

local FEEDBACK = {
    good = { "GOOD", COLOR_GOOD },
    fast = { "TOO FAST", COLOR_FAST },
    slow = { "TOO SLOW", COLOR_SLOW },
}

-- movement/combat controls disabled while kneeling next to a ped
local LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger", "next_weapon", "previous_weapon" }

local HEART_SVG = [[<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<path d="M64 112 L20 68 C4 52 8 24 32 20 C46 18 58 28 64 38 C70 28 82 18 96 20 C120 24 124 52 108 68 Z"
fill="#ffffff" stroke="#111111" stroke-width="7" stroke-linejoin="round"/></svg>]]
local RING_SVG = [[<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="26" fill="#ffffff" fill-opacity="0.15" stroke="#ffffff" stroke-width="5"/></svg>]]

local game
local heartTexture, ringTexture

local function ensureTextures()
    if not isElement(heartTexture) then heartTexture = svgCreate(128, 128, HEART_SVG) end
    if not isElement(ringTexture) then ringTexture = svgCreate(64, 64, RING_SVG) end
end

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

    local x = px + rx * CPR.PED_SIDE_OFFSET + fx * CPR.PED_FORWARD_OFFSET
    local y = py + ry * CPR.PED_SIDE_OFFSET + fy * CPR.PED_FORWARD_OFFSET
    local groundZ = getGroundPosition(x, y, pz + 1.5)
    local z = (groundZ and groundZ ~= 0) and groundZ + 1.0 or pz

    setElementPosition(localPlayer, x, y, z)
    setElementRotation(localPlayer, 0, 0, -math.deg(math.atan2(px - x, py - y)), "default", true)
end

local function averageBPM(g)
    if g.judged <= 0 or not g.firstPress then return 0 end
    return math.floor(g.judged / (g.lastPress - g.firstPress) * 60 + 0.5)
end

-- Rate shown on the HUD: average of the last few presses, decaying while the player pauses
local function currentBPM(t)
    local recent = game.recent
    if #recent == 0 then return nil end
    local sum = 0
    for _, bpm in ipairs(recent) do sum = sum + bpm end
    local bpm = sum / #recent

    local since = t - game.lastPress
    if since > 60 / bpm and since > 60 / game.options.maxBPM then
        bpm = 60 / since
    end
    return bpm
end

local render, onKey

local function finish(reason, notifyServer)
    local g = game
    if not g then return end
    game = nil

    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientKey", root, onKey)
    unlockControls(g)
    if g.localAnim then setPedAnimation(localPlayer) end

    local total = g.judged + g.missed
    local success = reason == "completed" and cprIsSuccess(g.good, total, g.options.passPercent)
    local avg = averageBPM(g)
    if g.sessionId and notifyServer then
        triggerServerEvent("mg_cpr:onResult", resourceRoot, g.sessionId, g.good, g.judged, g.missed, avg)
    end
    -- success, good, total, percent, reason, sessionId (nil for client-started games), avgBPM
    triggerEvent("onClientCPRGameFinish", localPlayer, success, g.good, total,
        cprPercent(g.good, total), reason, g.sessionId, avg)
end

onKey = function(button, press)
    if button ~= CPR.KEY then return end
    cancelEvent()
    if not press or game.resultTick then return end

    local now = getTickCount()
    local t = (now - game.playTick) / 1000
    if t < 0 or t > game.duration then return end

    if not game.lastPress then
        game.firstPress = t
        game.missed = game.missed + cprStartMissed(t, game.options)
    else
        local interval = t - game.lastPress
        local result = cprClassify(interval, game.options)
        game.missed = game.missed + cprGapMissed(interval, game.options)
        game.judged = game.judged + 1
        if result == "good" then game.good = game.good + 1 end
        game.feedback = result
        game.feedbackTick = now

        table.insert(game.recent, 60 / interval)
        if #game.recent > 3 then table.remove(game.recent, 1) end
    end
    game.lastPress = t
    game.pressTick = now
end

local function endRound(now)
    if game.lastPress then
        game.missed = game.missed + cprTrailingMissed(game.duration - game.lastPress, game.options)
    else
        game.missed = game.missed + cprStartMissed(game.duration, game.options)
    end
    game.resultTick = now
end

local function shadowText(text, x1, y1, x2, y2, color, size, alignX, alignY, alpha)
    dxDrawText(text, x1 + 2, y1 + 2, x2 + 2, y2 + 2, tocolor(0, 0, 0, 180 * (alpha or 1)),
        size, "default-bold", alignX, alignY)
    dxDrawText(text, x1, y1, x2, y2, color, size, "default-bold", alignX, alignY)
end

local function drawGauge(x, y, w, h, bpm)
    local function bx(v)
        return x + (math.max(GAUGE_MIN, math.min(GAUGE_MAX, v)) - GAUGE_MIN) / (GAUGE_MAX - GAUGE_MIN) * w
    end

    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 35))
    local zx1, zx2 = bx(game.options.minBPM), bx(game.options.maxBPM)
    dxDrawRectangle(zx1, y, zx2 - zx1, h, rgba(COLOR_GOOD, 110))

    local labelY = y + h + 12 * scale
    dxDrawText(tostring(game.options.minBPM), zx1, labelY, zx1, labelY, tocolor(200, 200, 200, 200),
        0.9 * scale, "default-bold", "center", "center")
    dxDrawText(tostring(game.options.maxBPM), zx2, labelY, zx2, labelY, tocolor(200, 200, 200, 200),
        0.9 * scale, "default-bold", "center", "center")

    if bpm then
        local mx = bx(bpm)
        local inside = bpm >= game.options.minBPM and bpm <= game.options.maxBPM
        local color = inside and COLOR_GOOD or (bpm > game.options.maxBPM and COLOR_FAST or COLOR_SLOW)
        dxDrawRectangle(mx - 3 * scale, y - 5 * scale, 6 * scale, h + 10 * scale, rgba(color))
    end
end

local function drawPanel(now, t)
    local x, y, w, h = PANEL_X, PANEL_Y, PANEL_W, PANEL_H
    local playing = t >= 0

    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 160))
    local progress = playing and math.min(1, t / game.duration) or 0
    dxDrawRectangle(x, y, w, 4 * scale, tocolor(255, 255, 255, 40))
    dxDrawRectangle(x, y, w * (1 - progress), 4 * scale, rgba(COLOR_HEART, 220))

    -- heart, pulses on every compression
    local heartColor, heartSize = COLOR_HEART, HEART_SIZE
    if game.pressTick then
        local k = (now - game.pressTick) / 180
        if k < 1 then heartSize = HEART_SIZE * (1 + 0.22 * (1 - k)) end
    end
    if game.feedbackTick and now - game.feedbackTick < 350 then
        heartColor = FEEDBACK[game.feedback][2]
    end
    local hcx, hcy = x + 20 * scale + HEART_SIZE / 2, y + h / 2 + 4 * scale
    dxDrawImage(hcx - heartSize / 2, hcy - heartSize / 2, heartSize, heartSize, heartTexture, 0, 0, 0,
        rgba(heartColor))

    local cx = x + 40 * scale + HEART_SIZE
    local right = x + w - 20 * scale

    -- header: hint + time left
    dxDrawText(("Press %s in rhythm"):format(CPR.KEY:upper()), cx, y + 12 * scale, right, y + 36 * scale,
        tocolor(220, 220, 220, 220), 1.1 * scale, "default-bold", "left", "center")
    local timeLeft = playing and math.max(0, game.duration - t) or game.duration
    dxDrawText(("%.1f s"):format(timeLeft), cx, y + 12 * scale, right, y + 36 * scale,
        tocolor(255, 255, 255, 240), 1.3 * scale, "default-bold", "right", "center")

    -- current rate + feedback
    local bpm = playing and currentBPM(t)
    local bpmText = bpm and ("%d BPM"):format(math.floor(bpm + 0.5)) or "--- BPM"
    dxDrawText(bpmText, cx, y + 40 * scale, right, y + 84 * scale, tocolor(255, 255, 255, 255),
        2.0 * scale, "default-bold", "left", "center")

    if game.feedbackTick then
        local age = now - game.feedbackTick
        if age < 700 then
            local fb = FEEDBACK[game.feedback]
            local alpha = 255 * math.min(1, (700 - age) / 250)
            dxDrawText(fb[1], cx + 170 * scale, y + 40 * scale, right, y + 84 * scale, rgba(fb[2], alpha),
                1.6 * scale, "default-bold", "left", "center")
        end
    end

    -- rhythm guide: blinks at the middle of the allowed range
    if game.options.guide and playing then
        local interval = cprTargetInterval(game.options)
        local phase = (t % interval) / interval
        local size = 26 * scale * (1 + 0.35 * math.max(0, 1 - phase * 4))
        local gx, gy = right - 13 * scale, y + 62 * scale
        dxDrawImage(gx - size / 2, gy - size / 2, size, size, ringTexture, 0, 0, 0,
            tocolor(255, 255, 255, 90 + 165 * (1 - phase)))
    end

    drawGauge(cx, y + 98 * scale, right - cx, 14 * scale, bpm or nil)

    local total = game.judged + game.missed
    local accuracy = total > 0 and cprPercent(game.good, total) or 100
    dxDrawText(("Accuracy: %d%%   (need %d%%)"):format(accuracy, game.options.passPercent),
        cx, y + 132 * scale, right, y + 158 * scale, tocolor(200, 200, 200, 210), 1.05 * scale,
        "default-bold", "left", "center")
end

render = function()
    if not isElement(heartTexture) or not isElement(ringTexture) then ensureTextures() end
    local now = getTickCount()
    local t = (now - game.playTick) / 1000

    if not game.resultTick and t >= game.duration then
        endRound(now)
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

    if game.resultTick then
        local k = math.min(1, (now - game.resultTick) / 250)
        local total = game.judged + game.missed
        local success = cprIsSuccess(game.good, total, game.options.passPercent)
        local text = ("%s  %d%%"):format(success and "SUCCESS" or "FAILED", cprPercent(game.good, total))
        local ty = PANEL_Y - 70 * scale
        shadowText(text, 0, ty, screenW, ty, rgba(success and COLOR_GOOD or COLOR_FAIL, 255 * k),
            (2.4 + (1 - k)) * scale, "center", "center", k)

        if now - game.resultTick >= CPR.RESULT_TIME * 1000 then
            finish("completed", true)
        end
    end
end

local function begin(duration, ped, options, sessionId)
    if game then return false end
    if ped ~= nil and (not isElement(ped) or ped == localPlayer) then return false end
    ensureTextures()

    game = {
        sessionId = sessionId,
        duration = cprClampDuration(duration),
        options = cprNormalizeOptions(options),
        ped = ped,
        good = 0,
        judged = 0,
        missed = 0,
        recent = {},
        playTick = getTickCount() + CPR.COUNTDOWN * 1000,
    }

    if ped then
        placeNextToPed(ped)
        lockControls()
        if sessionId then
            -- server-started: the server plays the animation so everyone sees it
            triggerServerEvent("mg_cpr:ready", resourceRoot, sessionId)
        else
            game.localAnim = true
            setPedAnimation(localPlayer, CPR.ANIM_BLOCK, CPR.ANIM_NAME, -1, true, false, false, false)
        end
    end

    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    return true
end

-- Local game, the server is not involved (the animation is only visible to this client).
-- duration defaults to 30 seconds, ped is optional.
-- options: { minBPM = 90, maxBPM = 130, passPercent = 70, guide = true }
function startCPRGame(duration, ped, options)
    return begin(duration, ped, options, nil)
end

-- Aborts the current game. onClientCPRGameFinish fires with reason "cancelled".
-- A server-started game should be stopped from the server instead.
function stopCPRGame()
    if not game then return false end
    finish("cancelled", false)
    return true
end

function isCPRGameActive()
    return game ~= nil
end

addEventHandler("mg_cpr:start", resourceRoot, function(sessionId, duration, options, ped)
    if game then finish("cancelled", false) end
    begin(duration, ped, options, sessionId)
end)

addEventHandler("mg_cpr:stop", resourceRoot, function()
    finish("cancelled", false)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if game and not game.sessionId then finish("died", false) end
end)
