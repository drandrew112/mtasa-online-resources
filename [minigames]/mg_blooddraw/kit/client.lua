-- Hospital minigame kit, client side: the frame every hospital minigame shares (panel, countdown,
-- timer, result banner, placing the player next to the patient, control lock, cursor, input
-- routing, reporting the result). The game itself is the GAME table of client.lua.
--
-- IDENTICAL COPY in mg_suture (master), mg_irrigation, mg_cast, mg_reduction, mg_blooddraw, mg_fast,
-- mg_chestdrain and mg_ecg. Change it in mg_suture/kit/ and copy it to the others (README.md).
--
-- GAME fields (client.lua):
--   cursor            true = mouse game (cursor shown while playing)
--   init(g)           build the game state (g.options = normalised options)
--   update(g, dt)     every frame while playing (dt in s)
--   draw(g, x, y, w, h, now)   the play area inside the panel
--   key(g, key, press)          -> true when the key was used (the event is cancelled)
--   click(g, button, state, cx, cy)   mouse button down / up while playing
--   wheel(g, dir)     -1 = up, 1 = down
--   done(g)           -> true when the task is finished (the result shows)
--   score(g)          -> percent 0-100, details table (MGDEF.details lists the keys)
--   title(g), status(g), hint(g)  -> strings for the header (left / right) and the footer

MGK = {}

local sw, sh = guiGetScreenSize()
local S = sh / 1080
function sc(v) return v * S end
MGK.S, MGK.sw, MGK.sh = S, sw, sh
MGK.W, MGK.H = math.min(sc(1000), sw - sc(40)), sc(620)
MGK.X, MGK.Y = (sw - MGK.W) / 2, (sh - MGK.H) / 2 - sc(10)

-- the play area inside the panel: x, y, w, h (GAME.draw gets the same)
function MGK.area() return MGK.X + sc(14), MGK.Y + sc(52), MGK.W - sc(28), MGK.H - sc(110) end

COL = {
    bg = tocolor(18, 23, 28, 238), panel = tocolor(30, 36, 43, 255), panel2 = tocolor(39, 46, 55, 255),
    line = tocolor(52, 60, 70, 255), text = tocolor(233, 237, 242, 255), dim = tocolor(152, 162, 174, 255),
    accent = tocolor(47, 134, 232, 255), good = tocolor(63, 179, 122, 255), bad = tocolor(224, 82, 70, 255),
    warn = tocolor(229, 130, 42, 255), skin = tocolor(214, 160, 124, 255), skinDark = tocolor(181, 131, 95, 255),
    shade = tocolor(0, 0, 0, 150), white = tocolor(255, 255, 255, 255),
}

local COUNTDOWN, RESULT_TIME = 3, 2.2
local NEAR = 1.4               -- m: closer than this the player only turns towards the patient
local SIDE, FORWARD = 0.85, 0.2 -- placement next to the patient (right side, along the body)
local STAND_HEIGHT = 0.6       -- patient this much above the floor next to it -> standing animation
local ANIM_KNEEL = { "BOMBER", "BOM_Plant_Loop" }
local ANIM_STAND = { "INT_SHOP", "shop_loop" }
local LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger", "next_weapon", "previous_weapon", "action" }

local game          -- running game state
local mouse = {}    -- button -> true while held

---------------------------------------------------------------- drawing helpers

function MGK.text(str, x, y, w, h, color, size, alignX, alignY, clip)
    dxDrawText(tostring(str), x, y, x + w, y + h, color or COL.text, (size or 1) * S, "default-bold",
        alignX or "left", alignY or "center", clip == true, clip == true)
end

function MGK.shadowText(str, x, y, w, h, color, size, alignX, alignY)
    dxDrawText(tostring(str), x + 2, y + 2, x + w + 2, y + h + 2, tocolor(0, 0, 0, 170), (size or 1) * S, "default-bold", alignX or "center", alignY or "center")
    MGK.text(str, x, y, w, h, color, size, alignX or "center", alignY or "center")
end

function MGK.round(x, y, w, h, r, color)
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

function MGK.circle(x, y, r, color) dxDrawCircle(x, y, r, 0, 360, color, color, 24) end

-- outline circle; dashed = true leaves every second segment out
function MGK.ring(x, y, r, color, width, dashed)
    local n = 28
    for i = 0, n - 1 do
        if not dashed or i % 2 == 0 then
            local a1, a2 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
            dxDrawLine(x + math.cos(a1) * r, y + math.sin(a1) * r, x + math.cos(a2) * r, y + math.sin(a2) * r, color, width or 2)
        end
    end
end

function MGK.line(x1, y1, x2, y2, color, width) dxDrawLine(x1, y1, x2, y2, color, width or 2) end

-- horizontal gauge: value 0-1 marker, optional good band [from, to]
function MGK.gauge(x, y, w, h, value, from, to, label)
    MGK.round(x, y, w, h, h / 2, COL.panel2)
    if from then dxDrawRectangle(x + w * from, y, w * (to - from), h, tocolor(40, 86, 63, 255)) end
    local mx = x + w * math.max(0, math.min(1, value))
    dxDrawRectangle(mx - sc(2), y - sc(3), sc(4), h + sc(6), COL.white)
    if label then MGK.text(label, x - sc(110), y - sc(4), sc(100), h + sc(8), COL.dim, 0.95, "right") end
end

-- progress bar 0-1
function MGK.bar(x, y, w, h, value, color)
    MGK.round(x, y, w, h, h / 2, COL.panel2)
    local v = math.max(0, math.min(1, value))
    if v > 0 then MGK.round(x, y, math.max(h, w * v), h, h / 2, color or COL.good) end
end

-- point inside a rectangle / circle
function MGK.inRect(px, py, x, y, w, h) return px >= x and px <= x + w and py >= y and py <= y + h end
function MGK.dist(x1, y1, x2, y2) return ((x1 - x2) ^ 2 + (y1 - y2) ^ 2) ^ 0.5 end

function MGK.cursor()
    if not isCursorShowing() then return nil end
    local cx, cy = getCursorPosition()
    return cx * sw, cy * sh
end

function MGK.isDown(button) return mouse[button] == true end

---------------------------------------------------------------- placement / controls

local function lockControls(g)
    g._locked = {}
    for _, c in ipairs(LOCK_CONTROLS) do
        if isControlEnabled(c) then toggleControl(c, false) g._locked[#g._locked + 1] = c end
    end
end

local function unlockControls(g)
    for _, c in ipairs(g._locked or {}) do toggleControl(c, true) end
end

-- Puts the player next to the patient facing it; -> stand (true: the patient lies on a stretcher / bed)
local function placeNextToPed(ped)
    local px, py, pz = getElementPosition(ped)
    local mx, my, mz = getElementPosition(localPlayer)
    local x, y = mx, my
    if getDistanceBetweenPoints2D(px, py, mx, my) > NEAR then
        local _, _, rz = getElementRotation(ped)
        local a = math.rad(rz)
        local rx, ry = math.cos(a), math.sin(a)
        local fx, fy = -math.sin(a), math.cos(a)
        x, y = px + rx * SIDE + fx * FORWARD, py + ry * SIDE + fy * FORWARD
    end
    local ground = getGroundPosition(x, y, math.max(pz, mz) + 1.5)
    if not ground or ground == 0 then ground = mz - 1 end
    if x ~= mx or y ~= my then setElementPosition(localPlayer, x, y, ground + 1.0) end
    setElementRotation(localPlayer, 0, 0, -math.deg(math.atan2(px - x, py - y)), "default", true)
    return pz - ground > STAND_HEIGHT
end

---------------------------------------------------------------- lifecycle

local render, onKey, onClick

local function finish(reason, notifyServer)
    local g = game
    if not g then return end
    game = nil
    mouse = {}
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientKey", root, onKey)
    removeEventHandler("onClientClick", root, onClick)
    if g.cursor then showCursor(false) end
    unlockControls(g)
    if g.localAnim then setPedAnimation(localPlayer) end

    local percent, details = g.percent or 0, g.details or {}
    local success = reason == "completed" and MGDEF.pass(percent, details, g.options) or false
    if g.sessionId and notifyServer then
        triggerServerEvent(MGDEF.res .. ":onResult", resourceRoot, g.sessionId, percent, details, reason)
    end
    -- success, percent, reason, sessionId (nil for a client-started game), details
    triggerEvent(MGDEF.clientEvent, localPlayer, success, percent, reason, g.sessionId, details)
end
MGK.finish = finish

local function endPlay(g, now)
    if g.resultTick then return end
    g.resultTick = now
    g.finished = GAME.done(g) == true
    local percent, details = GAME.score(g)
    g.percent = math.max(0, math.min(100, math.floor((tonumber(percent) or 0) + 0.5)))
    g.details = type(details) == "table" and details or {}
    g.success = g.finished and MGDEF.pass(g.percent, g.details, g.options)
    if g.cursor then showCursor(false) end
end

render = function()
    local g = game
    if not g then return end
    local now = getTickCount()
    local t = (now - g.playTick) / 1000
    local dt = math.min(0.1, (now - (g.lastTick or now)) / 1000)
    g.lastTick = now
    g.now, g.t = now, t

    if t >= 0 and not g.resultTick then
        if g.cursor and not g.cursorShown then showCursor(true) g.cursorShown = true end
        if GAME.update then GAME.update(g, dt) end
        if GAME.done(g) or t >= g.options.time then endPlay(g, now) end
    end

    local X, Y, W, H = MGK.X, MGK.Y, MGK.W, MGK.H
    MGK.round(X - sc(4), Y - sc(4), W + sc(8), H + sc(8), sc(12), tocolor(10, 12, 15, 230))
    MGK.round(X, Y, W, H, sc(10), COL.bg)
    MGK.text(GAME.title(g), X + sc(18), Y + sc(8), W * 0.6, sc(32), COL.text, 1.35)
    MGK.text(GAME.status and GAME.status(g) or "", X + W * 0.4, Y + sc(8), W * 0.6 - sc(18), sc(32), COL.dim, 1.1, "right")
    dxDrawRectangle(X + sc(14), Y + sc(44), W - sc(28), 1, COL.line)

    local ax, ay, aw, ah = MGK.area()
    GAME.draw(g, ax, ay, aw, ah, now)

    -- footer: hint + time left
    dxDrawRectangle(X + sc(14), Y + H - sc(52), W - sc(28), 1, COL.line)
    if not g.resultTick then
        MGK.text(GAME.hint and GAME.hint(g) or "", X + sc(18), Y + H - sc(48), W * 0.78, sc(42), COL.dim, 1.0, "left", "center", true)
        if t >= 0 then
            MGK.text(L("common.time_left_s", { time_left = math.max(0, g.options.time - t) }), X + W * 0.7, Y + H - sc(48),
                W * 0.3 - sc(18), sc(42), t > g.options.time - 5 and COL.bad or COL.text, 1.2, "right")
        end
    end

    if t < 0 then
        dxDrawRectangle(ax, ay, aw, ah, tocolor(0, 0, 0, 120))
        local n = math.ceil(-t)
        MGK.shadowText(tostring(n), ax, ay + ah / 2 - sc(70), aw, sc(80), COL.white, 4)
        MGK.shadowText(L("common.get_ready"), ax, ay + ah / 2 + sc(10), aw, sc(40), COL.text, 1.5)
    end

    if g.resultTick then
        local k = math.min(1, (now - g.resultTick) / 250)
        dxDrawRectangle(ax, ay, aw, ah, tocolor(0, 0, 0, 110 * k))
        local text = ("%s  %d%%"):format(L(MGDEF.res .. (g.success and ".kit.success" or ".kit.failed")), g.percent)
        MGK.shadowText(text, ax, ay + ah / 2 - sc(40), aw, sc(80), g.success and COL.good or COL.bad, 2.4 + (1 - k))
        if now - g.resultTick >= RESULT_TIME * 1000 then
            finish(g.finished and "completed" or "expired", true)
        end
    end
end

onKey = function(key, press)
    local g = game
    if not g then return end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        cancelEvent()
        if press and not g.resultTick and (g.t or -1) >= 0 and GAME.wheel then GAME.wheel(g, key == "mouse_wheel_up" and -1 or 1) end
        return
    end
    if key == "mouse1" or key == "mouse2" then return end
    if g.resultTick or (g.t or -1) < 0 then
        if key ~= "escape" and key ~= "F8" and key ~= "t" then cancelEvent() end
        return
    end
    if GAME.key and GAME.key(g, key, press) then cancelEvent() end
end

onClick = function(button, state, cx, cy)
    local g = game
    if not g then return end
    mouse[button] = state == "down" or nil
    if g.resultTick or (g.t or -1) < 0 then return end
    if GAME.click then GAME.click(g, button, state, cx, cy) end
end

-- options are normalised (MGDEF.normalize); sessionId nil = client-only game
function MGK.begin(ped, options, sessionId)
    if game then return false end
    if ped ~= nil and (not isElement(ped) or ped == localPlayer) then return false end
    options = MGDEF.normalize(options)
    local g = {
        sessionId = sessionId, options = options, ped = ped, cursor = GAME.cursor == true,
        playTick = getTickCount() + COUNTDOWN * 1000,
    }
    game = g
    GAME.init(g)
    lockControls(g)
    if ped then
        local stand = placeNextToPed(ped)
        if options.stand ~= nil then stand = options.stand == true end
        if sessionId then
            triggerServerEvent(MGDEF.res .. ":ready", resourceRoot, sessionId, stand)
        else
            g.localAnim = true
            local anim = stand and ANIM_STAND or ANIM_KNEEL
            setPedAnimation(localPlayer, anim[1], anim[2], -1, true, false, false, false)
        end
    end
    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    addEventHandler("onClientClick", root, onClick)
    return true
end

function MGK.active() return game ~= nil end

addEvent(MGDEF.clientEvent, false)
addEvent(MGDEF.res .. ":start", true)
addEvent(MGDEF.res .. ":stop", true)

addEventHandler(MGDEF.res .. ":start", resourceRoot, function(sessionId, options, ped)
    if game then finish("cancelled", false) end
    MGK.begin(ped, options, sessionId)
end)

addEventHandler(MGDEF.res .. ":stop", resourceRoot, function() finish("cancelled", false) end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if game and not game.sessionId then finish("died", false) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if game then finish("cancelled", false) end
end)
