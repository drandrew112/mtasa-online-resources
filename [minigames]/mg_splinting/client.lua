-- Securing a splint: a needle sweeps back and forth across a gauge. Press SPACE while it is
-- inside the centre window to cinch a wrap. No time pressure beyond the overall timer - wait for
-- the next pass if you miss. The game ends after `count` presses; it is won when the hit ratio is
-- above passPercent.

addEvent("onClientSplintGameFinish", false)
addEvent("mg_splinting:start", true)
addEvent("mg_splinting:stop", true)

local screenW, screenH = guiGetScreenSize()
local scale = screenH / 1080

local GAUGE_W, GAUGE_H = 640 * scale, 46 * scale
local GAUGE_X = (screenW - GAUGE_W) / 2
local GAUGE_Y = screenH - 150 * scale
local PIP_SIZE = 22 * scale
local PIP_GAP = 8 * scale

local COLOR_IDLE = { 255, 255, 255 }
local COLOR_GOOD = { 70, 220, 90 }
local COLOR_MISS = { 230, 60, 60 }

-- movement/combat controls disabled while kneeling next to a ped
local LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger", "next_weapon", "previous_weapon" }

local game

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

    local x = px + rx * SPLINT.PED_SIDE_OFFSET + fx * SPLINT.PED_FORWARD_OFFSET
    local y = py + ry * SPLINT.PED_SIDE_OFFSET + fy * SPLINT.PED_FORWARD_OFFSET
    local groundZ = getGroundPosition(x, y, pz + 1.5)
    local z = (groundZ and groundZ ~= 0) and groundZ + 1.0 or pz

    setElementPosition(localPlayer, x, y, z)
    setElementRotation(localPlayer, 0, 0, -math.deg(math.atan2(px - x, py - y)), "default", true)
end

-- Needle position on the gauge, 0-1 (0.5 = centre)
local function needleValue(t)
    return 0.5 + 0.5 * math.sin(t * game.options.speed * SPLINT.NEEDLE_HZ * 2 * math.pi)
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

    local success = reason == "completed" and splintIsSuccess(g.hits, g.total, g.options.passPercent)
    if g.sessionId and notifyServer then
        triggerServerEvent("mg_splinting:onResult", resourceRoot, g.sessionId, g.hits, g.judged, reason)
    end
    -- success, hits, total, percent, reason, sessionId (nil for client-started games)
    triggerEvent("onClientSplintGameFinish", localPlayer, success, g.hits, g.judged,
        splintPercent(g.hits, g.judged), reason, g.sessionId)
end

local function judge(now, t)
    local g = game
    local value = needleValue(t)
    local good = math.abs(value - 0.5) <= SPLINT.GOOD_WINDOW
    g.judged = g.judged + 1
    if good then g.hits = g.hits + 1 end
    g.pips[g.judged] = good and "good" or "miss"
    g.flashTick = now
    g.flashGood = good

    if g.judged >= g.total then
        g.resultTick = now
    end
end

onKey = function(button, press)
    if button ~= SPLINT.KEY then return end
    cancelEvent()
    if not press or not game or game.resultTick then return end

    local now = getTickCount()
    local t = (now - game.playTick) / 1000
    if t < 0 then return end

    judge(now, t)
end

local function shadowText(text, x1, y1, x2, y2, color, size, alignX, alignY, alpha)
    dxDrawText(text, x1 + 2, y1 + 2, x2 + 2, y2 + 2, tocolor(0, 0, 0, 180 * (alpha or 1)),
        size, "default-bold", alignX, alignY)
    dxDrawText(text, x1, y1, x2, y2, color, size, "default-bold", alignX, alignY)
end

local function drawGauge(now, t)
    local g = game
    local x, y, w, h = GAUGE_X, GAUGE_Y, GAUGE_W, GAUGE_H

    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 160))
    local winW = w * SPLINT.GOOD_WINDOW * 2
    dxDrawRectangle(x + w / 2 - winW / 2, y, winW, h, rgba(COLOR_GOOD, 90))
    dxDrawRectangle(x + w / 2 - 2 * scale, y, 4 * scale, h, tocolor(255, 255, 255, 60))

    if not g.resultTick then
        local value = needleValue(t)
        local nx = x + w * value

        local needleColor, needleScale = COLOR_IDLE, 1
        if g.flashTick and now - g.flashTick < 220 then
            needleColor = g.flashGood and COLOR_GOOD or COLOR_MISS
            needleScale = 1 + 0.25 * (1 - (now - g.flashTick) / 220)
        end
        local nw = 10 * scale * needleScale
        dxDrawRectangle(nx - nw / 2, y - 6 * scale, nw, h + 12 * scale, rgba(needleColor, 235))
    end
end

local function drawPips(now)
    local g = game
    local total = g.total
    local totalW = total * PIP_SIZE + (total - 1) * PIP_GAP
    local px = (screenW - totalW) / 2
    local py = GAUGE_Y - PIP_SIZE - 18 * scale

    for i = 1, total do
        local x = px + (i - 1) * (PIP_SIZE + PIP_GAP)
        local result = g.pips[i]
        local color, alpha = { 255, 255, 255 }, 40
        if result == "good" then
            color, alpha = COLOR_GOOD, 230
        elseif result == "miss" then
            color, alpha = COLOR_MISS, 230
        end
        local size = PIP_SIZE
        if result and g.flashTick and i == g.judged and now - g.flashTick < 220 then
            size = PIP_SIZE * (1 + 0.25 * (1 - (now - g.flashTick) / 220))
        end
        dxDrawRectangle(x - (size - PIP_SIZE) / 2, py - (size - PIP_SIZE) / 2, size, size, rgba(color, alpha))
    end
end

local function drawHud(now, t)
    local g = game
    local playing = t >= 0
    local y = GAUGE_Y - PIP_SIZE - 18 * scale - 54 * scale

    dxDrawText(("Wraps secured: %d / %d"):format(g.judged, g.total), 0, y, screenW, y,
        tocolor(220, 220, 220, 220), 1.15 * scale, "default-bold", "center", "center")

    if playing and not g.resultTick then
        dxDrawText(("Press %s when the needle is in the green zone"):format(SPLINT.KEY:upper()),
            0, y + 28 * scale, screenW, y + 28 * scale, tocolor(200, 200, 200, 200), 1.0 * scale,
            "default-bold", "center", "center")
        local timeLeft = math.max(0, g.options.time - t)
        dxDrawText(("%.1f s"):format(timeLeft), 0, GAUGE_Y + GAUGE_H + 10 * scale, screenW,
            GAUGE_Y + GAUGE_H + 10 * scale, tocolor(255, 255, 255, 200), 1.05 * scale, "default-bold", "center")
    end

    if g.resultTick then
        local k = math.min(1, (now - g.resultTick) / 250)
        local success = splintIsSuccess(g.hits, g.total, g.options.passPercent)
        local text = ("%s  %d%%"):format(success and "SUCCESS" or "FAILED", splintPercent(g.hits, g.total))
        local ty = y - 50 * scale
        shadowText(text, 0, ty, screenW, ty, rgba(success and COLOR_GOOD or COLOR_MISS, 255 * k),
            (2.0 + (1 - k)) * scale, "center", "center", k)
    end
end

render = function()
    local g = game
    local now = getTickCount()
    local t = (now - g.playTick) / 1000

    if not g.resultTick and t >= g.options.time then
        g.resultTick = now
    end

    drawGauge(now, t)
    drawPips(now)
    drawHud(now, t)

    if t < 0 then
        local n = math.ceil(-t)
        local k = 1 - (-t - (n - 1))
        local cy = GAUGE_Y - 220 * scale
        shadowText(tostring(n), 0, cy, screenW, cy, tocolor(255, 255, 255, 255 * (1 - k * 0.6)),
            (4 - k) * scale, "center", "center")
        shadowText("Get ready", 0, cy + 60 * scale, screenW, cy + 60 * scale, tocolor(220, 220, 220, 230),
            1.4 * scale, "center", "center")
    end

    if g.resultTick and now - g.resultTick >= SPLINT.RESULT_TIME * 1000 then
        finish(g.judged >= g.total and "completed" or "expired", true)
    end
end

local function begin(ped, count, options, sessionId)
    if game then return false end
    if ped ~= nil and (not isElement(ped) or ped == localPlayer) then return false end

    options = splintNormalizeOptions(options)
    game = {
        sessionId = sessionId,
        options = options,
        total = splintClampCount(count),
        ped = ped,
        hits = 0,
        judged = 0,
        pips = {},
        playTick = getTickCount() + SPLINT.COUNTDOWN * 1000,
    }

    if ped then
        placeNextToPed(ped)
        lockControls()
        if sessionId then
            -- server-started: the server plays the animation so everyone sees it
            triggerServerEvent("mg_splinting:ready", resourceRoot, sessionId)
        else
            game.localAnim = true
            setPedAnimation(localPlayer, SPLINT.ANIM_BLOCK, SPLINT.ANIM_NAME, -1, true, false, false, false)
        end
    end

    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    return true
end

-- Local game, the server is not involved (the animation is only visible to this client). ped is optional.
-- count defaults to 8. options: { speed = 1.0, passPercent = 70, time = 40 }
function startSplintGame(ped, count, options)
    return begin(ped, count, options, nil)
end

-- Aborts the current game. onClientSplintGameFinish fires with reason "cancelled".
-- A server-started game should be stopped from the server instead.
function stopSplintGame()
    if not game then return false end
    finish("cancelled", false)
    return true
end

function isSplintGameActive()
    return game ~= nil
end

addEventHandler("mg_splinting:start", resourceRoot, function(sessionId, count, options, ped)
    if game then finish("cancelled", false) end
    begin(ped, count, options, sessionId)
end)

addEventHandler("mg_splinting:stop", resourceRoot, function()
    finish("cancelled", false)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if game and not game.sessionId then finish("died", false) end
end)
