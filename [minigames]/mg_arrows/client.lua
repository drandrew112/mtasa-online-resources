-- Arrows slide from left to right along the bottom of the screen. The player
-- has to press the matching arrow key while an arrow is inside the centre ring.

addEvent("onClientArrowsGameFinish", false)
addEvent("mg_arrows:start", true)
addEvent("mg_arrows:stop", true)

local screenW, screenH = guiGetScreenSize()
local scale = screenH / 1080

local ARROW_SIZE = 76 * scale
local RING_SIZE = 116 * scale
local HIT_WINDOW = 50 * scale           -- max distance between arrow and ring centre for a hit
local LANE_H = 120 * scale
local LANE_Y = screenH - 70 * scale - LANE_H
local LANE_CY = LANE_Y + LANE_H / 2
local CENTER_X = screenW / 2

local COLOR_IDLE = { 255, 255, 255 }
local COLOR_HIT = { 70, 220, 90 }
local COLOR_MISS = { 230, 60, 60 }

local KEY_DIRS = { arrow_l = "left", arrow_u = "up", arrow_r = "right", arrow_d = "down" }
local DIR_ROTATION = { right = 0, down = 90, left = 180, up = 270 }

local ARROW_SVG = [[<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<path d="M16 48 H64 V18 L112 64 L64 110 V80 H16 Z" fill="#ffffff" stroke="#111111" stroke-width="8" stroke-linejoin="round"/></svg>]]
local RING_SVG = [[<svg xmlns="http://www.w3.org/2000/svg" width="160" height="160" viewBox="0 0 160 160">
<circle cx="80" cy="80" r="70" fill="#ffffff" fill-opacity="0.08" stroke="#ffffff" stroke-width="7"/></svg>]]

local game
local arrowTexture, ringTexture

local function ensureTextures()
    if not isElement(arrowTexture) then arrowTexture = svgCreate(128, 128, ARROW_SVG) end
    if not isElement(ringTexture) then ringTexture = svgCreate(160, 160, RING_SVG) end
end

local function rgba(color, alpha)
    return tocolor(color[1], color[2], color[3], alpha or 255)
end

local function arrowX(arrow, t)
    return -ARROW_SIZE + (t - arrow.spawn) * game.pxPerSec
end

local function judge(arrow, result, now)
    arrow.result = result
    arrow.judgedAt = now
    game.judged = game.judged + 1
    if result == "hit" then game.hits = game.hits + 1 end
    game.flashColor = result == "hit" and COLOR_HIT or COLOR_MISS
    game.flashTick = now

    if game.judged >= game.total then
        game.resultTick = now
    end
end

local render, onKey

local function finish(reason, notifyServer)
    local g = game
    if not g then return end
    game = nil

    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientKey", root, onKey)

    local success = reason == "completed" and arrowsIsSuccess(g.hits, g.total, g.options.passPercent)
    if g.sessionId and notifyServer then
        triggerServerEvent("mg_arrows:onResult", resourceRoot, g.sessionId, g.hits, g.total)
    end
    -- success, hits, total, percent, reason, sessionId (nil for client-started games)
    triggerEvent("onClientArrowsGameFinish", localPlayer, success, g.hits, g.total,
        arrowsPercent(g.hits, g.total), reason, g.sessionId)
end

onKey = function(button, press)
    local dir = KEY_DIRS[button]
    if not dir then return end
    cancelEvent()
    if not press or game.resultTick then return end

    local now = getTickCount()
    local t = (now - game.startTick) / 1000

    -- closest unjudged arrow inside the ring
    local target, bestDist
    for _, arrow in ipairs(game.arrows) do
        if not arrow.result and t >= arrow.spawn then
            local dist = math.abs(arrowX(arrow, t) - CENTER_X)
            if dist <= HIT_WINDOW and (not bestDist or dist < bestDist) then
                target, bestDist = arrow, dist
            end
        end
    end
    if not target then return end

    judge(target, target.dir == dir and "hit" or "miss", now)
end

local function drawHud(now)
    local textScale = 1.6 * scale
    local y = LANE_Y - 34 * scale
    local accuracy = game.judged > 0 and arrowsPercent(game.hits, game.judged) or 100

    dxDrawText(("%d / %d"):format(game.judged, game.total), 0, y, screenW, y,
        tocolor(255, 255, 255, 230), textScale, "default-bold", "center", "center")
    dxDrawText(("Accuracy: %d%%   (need > %d%%)"):format(accuracy, game.options.passPercent),
        0, y + 26 * scale, screenW, y + 26 * scale, tocolor(200, 200, 200, 200), 1.1 * scale,
        "default-bold", "center", "center")

    if game.resultTick then
        local k = math.min(1, (now - game.resultTick) / 250)
        local success = arrowsIsSuccess(game.hits, game.total, game.options.passPercent)
        local color = success and COLOR_HIT or COLOR_MISS
        local text = ("%s  %d%%"):format(success and "SUCCESS" or "FAILED", arrowsPercent(game.hits, game.total))
        local ty = LANE_Y - 110 * scale
        dxDrawText(text, 2, ty + 2, screenW + 2, ty + 2, tocolor(0, 0, 0, 180 * k),
            (2.4 + (1 - k)) * scale, "default-bold", "center", "center")
        dxDrawText(text, 0, ty, screenW, ty, rgba(color, 255 * k),
            (2.4 + (1 - k)) * scale, "default-bold", "center", "center")
    end
end

render = function()
    local now = getTickCount()
    local t = (now - game.startTick) / 1000

    -- lane
    dxDrawRectangle(0, LANE_Y, screenW, LANE_H, tocolor(0, 0, 0, 150))
    dxDrawRectangle(0, LANE_Y, screenW, 2 * scale, tocolor(255, 255, 255, 60))
    dxDrawRectangle(0, LANE_Y + LANE_H - 2 * scale, screenW, 2 * scale, tocolor(255, 255, 255, 60))

    -- ring, flashes green/red after each judgement
    local ringColor, ringScale = COLOR_IDLE, 1
    if game.flashTick then
        local k = (now - game.flashTick) / 200
        if k < 1 then
            ringColor = game.flashColor
            ringScale = 1 + 0.12 * (1 - k)
        end
    end
    local ring = RING_SIZE * ringScale
    dxDrawImage(CENTER_X - ring / 2, LANE_CY - ring / 2, ring, ring, ringTexture, 0, 0, 0, rgba(ringColor, 230))

    -- arrows
    local allGone = true
    for _, arrow in ipairs(game.arrows) do
        if t >= arrow.spawn then
            local x = arrowX(arrow, t)

            if not arrow.result and x - CENTER_X > HIT_WINDOW then
                judge(arrow, "miss", now)
            end

            if x - ARROW_SIZE / 2 < screenW then
                allGone = false
                local color, size = COLOR_IDLE, ARROW_SIZE
                if arrow.result then
                    color = arrow.result == "hit" and COLOR_HIT or COLOR_MISS
                    local k = (now - arrow.judgedAt) / 150
                    if k < 1 then size = ARROW_SIZE * (1 + 0.3 * (1 - k)) end
                end
                dxDrawImage(x - size / 2, LANE_CY - size / 2, size, size, arrowTexture,
                    DIR_ROTATION[arrow.dir], 0, 0, rgba(color))
            end
        else
            allGone = false
        end
    end

    drawHud(now)

    if game.resultTick and now - game.resultTick >= ARROWS.RESULT_TIME * 1000 and allGone then
        finish("completed", true)
    end
end

local function begin(count, options, sessionId)
    if game then return false end
    ensureTextures()

    count = arrowsClampCount(count)
    options = arrowsNormalizeOptions(options)

    local arrows, spawn = {}, ARROWS.SPAWN_LEAD
    for i = 1, count do
        arrows[i] = { dir = ARROW_DIRS[math.random(#ARROW_DIRS)], spawn = spawn }
        local gap = ARROWS.SPAWN_MIN + math.random() * (ARROWS.SPAWN_MAX - ARROWS.SPAWN_MIN)
        spawn = spawn + gap / options.speed
    end

    game = {
        sessionId = sessionId,
        options = options,
        total = count,
        arrows = arrows,
        hits = 0,
        judged = 0,
        pxPerSec = ARROWS.SPEED_PX * scale * options.speed,
        startTick = getTickCount(),
    }

    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    return true
end

-- Local game, the server is not involved. count defaults to 15.
-- options: { speed = 1.0, passPercent = 70 }
function startArrowsGame(count, options)
    return begin(count, options, nil)
end

-- Aborts the current game. onClientArrowsGameFinish fires with reason "cancelled".
-- A server-started game should be stopped from the server instead.
function stopArrowsGame()
    if not game then return false end
    finish("cancelled", false)
    return true
end

function isArrowsGameActive()
    return game ~= nil
end

addEventHandler("mg_arrows:start", resourceRoot, function(sessionId, count, options)
    if game then finish("cancelled", false) end
    begin(count, options, sessionId)
end)

addEventHandler("mg_arrows:stop", resourceRoot, function()
    finish("cancelled", false)
end)
