-- Endotracheal intubation in four phases, against a falling SpO2:
--   1. LARYNGOSCOPY  hold SPACE to lift the blade until the vocal cords come into view
--   2. THE CORDS     aim the tube tip with the mouse and push it (SPACE) between the
--                    vocal cords while they are open - not into the oesophagus behind them
--   3. DEPTH         push / pull the tube (SPACE / S) to the right depth, above the carina
--   4. CUFF          inflate / deflate the cuff (SPACE / S) to 20-30 cmH2O
-- Every mistake (tooth, trauma, oesophagus, bronchus, cuff) counts against maxMistakes.

addEvent("onClientAirwayGameFinish", false)
addEvent("mg_airway:start", true)
addEvent("mg_airway:stop", true)

local screenW, screenH = guiGetScreenSize()
local scale = screenH / 1080

local R = 230 * scale                   -- radius of the scope window
local HALF = R * 1.25                   -- half size of the view panel
local VCX, VCY = screenW / 2 - 120 * scale, screenH / 2 - 20 * scale
local PANEL_X, PANEL_Y = VCX + HALF + 20 * scale, VCY - HALF
local PANEL_W, PANEL_H = 270 * scale, HALF * 2
local GAUGE_X, GAUGE_Y, GAUGE_W, GAUGE_H = VCX - HALF, VCY + HALF + 18 * scale, HALF * 2, 16 * scale

local COLOR_GOOD = { 70, 220, 90 }
local COLOR_WARN = { 255, 190, 40 }
local COLOR_BAD = { 235, 60, 60 }
local COLOR_INFO = { 110, 190, 255 }
local COLOR_TEXT = { 225, 225, 225 }

local PHASES = { "Laryngoscopy", "Pass the cords", "Tube depth", "Cuff pressure" }

local HINTS = {
    "Hold SPACE to lift the laryngoscope - keep it in the green zone",
    "Aim with the MOUSE, hold SPACE to push the tube between the open cords",
    "SPACE push / S pull back - release inside the green zone",
    "SPACE inflate / S deflate the cuff - release inside the green zone",
}

local LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger", "next_weapon", "previous_weapon",
    "look_behind", "change_camera" }

---------------------------------------------------------------------------
-- Textures
---------------------------------------------------------------------------
local SVG = {}

SVG.pharynx = [[<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
<defs><radialGradient id="g" cx="50%" cy="52%" r="62%">
<stop offset="0" stop-color="#5c121b"/><stop offset="0.5" stop-color="#b24e5a"/><stop offset="1" stop-color="#732530"/>
</radialGradient></defs>
<rect width="512" height="512" fill="url(#g)"/>
<g fill="none" stroke="#e39aa2" stroke-opacity="0.28" stroke-width="9" stroke-linecap="round">
<path d="M70 430 Q256 340 442 430"/><path d="M40 330 Q90 250 70 150"/><path d="M472 330 Q422 250 442 150"/>
<path d="M120 470 Q256 410 392 470"/></g></svg>]]

SVG.tongue = [[<svg xmlns="http://www.w3.org/2000/svg" width="512" height="256" viewBox="0 0 512 256">
<defs><linearGradient id="t" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#9c3a46"/><stop offset="0.75" stop-color="#cf6f7a"/><stop offset="1" stop-color="#eba4ab"/>
</linearGradient></defs>
<path d="M0 0 H512 V150 Q400 250 256 250 Q112 250 0 150 Z" fill="url(#t)"/>
<path d="M20 160 Q120 240 256 242 Q392 240 492 160" fill="none" stroke="#f6c4c8" stroke-opacity="0.6" stroke-width="6"/>
</svg>]]

SVG.epiglottis = [[<svg xmlns="http://www.w3.org/2000/svg" width="256" height="128" viewBox="0 0 256 128">
<path d="M16 116 Q26 18 128 12 Q230 18 240 116 Q204 72 128 68 Q52 72 16 116 Z"
fill="#e9a0a6" stroke="#9e4852" stroke-width="6" stroke-linejoin="round"/>
<path d="M60 40 Q128 22 196 40" fill="none" stroke="#fbd3d6" stroke-opacity="0.7" stroke-width="5"/></svg>]]

SVG.larynx = [[<svg xmlns="http://www.w3.org/2000/svg" width="256" height="280" viewBox="0 0 256 280">
<path d="M128 8 C40 30 16 170 70 228 L186 228 C240 170 216 30 128 8 Z"
fill="#c25e69" stroke="#eaa6ac" stroke-width="8" stroke-linejoin="round"/>
<ellipse cx="128" cy="236" rx="46" ry="15" fill="#d98a92"/>
<ellipse cx="128" cy="236" rx="40" ry="10" fill="#2a060b"/></svg>]]

SVG.opening = [[<svg xmlns="http://www.w3.org/2000/svg" width="128" height="160" viewBox="0 0 128 160">
<defs><linearGradient id="o" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#140306"/><stop offset="1" stop-color="#4a1016"/></linearGradient></defs>
<path d="M64 0 L128 160 L0 160 Z" fill="url(#o)"/>
<g fill="none" stroke="#b86470" stroke-opacity="0.55" stroke-width="4">
<path d="M34 112 Q64 102 94 112"/><path d="M26 132 Q64 120 102 132"/><path d="M18 152 Q64 138 110 152"/></g>
<path d="M64 1 L0 160 L18 160 L63 16 Z" fill="#f4ebe2" stroke="#c8b4a8" stroke-width="2"/>
<path d="M64 1 L128 160 L110 160 L65 16 Z" fill="#f4ebe2" stroke="#c8b4a8" stroke-width="2"/></svg>]]

SVG.blob = [[<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<defs><radialGradient id="a" cx="40%" cy="38%" r="60%"><stop offset="0" stop-color="#ffffff"/>
<stop offset="1" stop-color="#9a9a9a"/></radialGradient></defs>
<circle cx="32" cy="32" r="29" fill="url(#a)"/></svg>]]

SVG.blood = [[<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<defs><radialGradient id="b" cx="45%" cy="45%" r="60%"><stop offset="0" stop-color="#5e000c"/>
<stop offset="0.7" stop-color="#9c0c1c"/><stop offset="1" stop-color="#c62a3a"/></radialGradient></defs>
<path d="M64 10 C96 12 118 40 112 70 C108 100 84 120 60 116 C30 112 10 90 14 62 C18 34 36 8 64 10 Z" fill="url(#b)"/>
<ellipse cx="50" cy="40" rx="12" ry="7" fill="#ffffff" fill-opacity="0.25"/></svg>]]

SVG.tip = [[<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">
<circle cx="64" cy="64" r="50" fill="#ffffff" fill-opacity="0.12" stroke="#ffffff" stroke-width="10"/>
<circle cx="64" cy="64" r="36" fill="none" stroke="#ffffff" stroke-opacity="0.35" stroke-width="3"/>
<path d="M64 14 A50 50 0 0 1 114 64" fill="none" stroke="#2f7dff" stroke-width="10"/></svg>]]

SVG.mask = [[<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 512 512">
<defs><radialGradient id="v" cx="50%" cy="50%" r="50%"><stop offset="0.8" stop-color="#000000" stop-opacity="0"/>
<stop offset="1" stop-color="#000000" stop-opacity="0.75"/></radialGradient></defs>
<circle cx="256" cy="256" r="205" fill="url(#v)"/>
<path fill-rule="evenodd" fill="#0c0d10" d="M40 0 H472 A40 40 0 0 1 512 40 V472 A40 40 0 0 1 472 512 H40 A40 40 0 0 1 0 472 V40 A40 40 0 0 1 40 0 Z
M256 51.2 A204.8 204.8 0 1 0 256 460.8 A204.8 204.8 0 1 0 256 51.2 Z"/>
<circle cx="256" cy="256" r="209" fill="none" stroke="#3b3f47" stroke-width="8"/>
<circle cx="256" cy="256" r="224" fill="none" stroke="#1d1f24" stroke-width="4"/></svg>]]

do
    local rings = {}
    for y = 16, 250, 22 do
        rings[#rings + 1] = ('<path d="M36 %d Q64 %d 92 %d"/>'):format(y, y + 9, y)
    end
    SVG.trachea = [[<svg xmlns="http://www.w3.org/2000/svg" width="128" height="384" viewBox="0 0 128 384">
<path d="M34 0 V262 L4 384 H40 L64 300 L88 384 H124 L94 262 V0 Z" fill="#c86a72" stroke="#7e333b" stroke-width="4" stroke-linejoin="round"/>
<path d="M46 0 V266 L22 384 H30 L64 290 L98 384 H106 L82 266 V0 Z" fill="#8f3a44" fill-opacity="0.55"/>
<g fill="none" stroke="#f0b0b6" stroke-opacity="0.55" stroke-width="5">]] .. table.concat(rings) .. [[</g></svg>]]
end

-- trachea texture layout (svg units): depth in cm at the teeth -> svg y
local TRACHEA_W, TRACHEA_H = 128, 384
local TRACHEA_LUMEN = 60     -- inner width of the trachea
local TUBE_WIDTH = 34
local function depthToSvgY(depth)
    return (depth - 14) * 25 -- 14 cm = top of the picture, 26 cm = carina (y 300)
end

local textures = {}
local renderTarget

local function ensureTextures()
    for name, svg in pairs(SVG) do
        if not isElement(textures[name]) then
            local w, h = svg:match('width="(%d+)" height="(%d+)"')
            textures[name] = svgCreate(tonumber(w), tonumber(h), svg)
        end
    end
    if not isElement(renderTarget) then
        renderTarget = dxCreateRenderTarget(math.ceil(HALF * 2), math.ceil(HALF * 2), true) or nil
    end
end

local function releaseTextures()
    for name, tex in pairs(textures) do
        if isElement(tex) then destroyElement(tex) end
        textures[name] = nil
    end
    if isElement(renderTarget) then destroyElement(renderTarget) end
    renderTarget = nil
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function rgba(color, alpha)
    return tocolor(color[1], color[2], color[3], alpha or 255)
end

local function lerp(a, b, k)
    return a + (b - a) * k
end

local function shadowText(text, x1, y1, x2, y2, color, size, alignX, alignY, alpha)
    dxDrawText(text, x1 + 2, y1 + 2, x2 + 2, y2 + 2, tocolor(0, 0, 0, 190 * (alpha or 1)),
        size, "default-bold", alignX, alignY)
    dxDrawText(text, x1, y1, x2, y2, color, size, "default-bold", alignX, alignY)
end

local game
local render, onKey, updateSpO2

-- Larynx position in view coordinates (0,0 = top left of the view panel)
local function glottisGeometry(t)
    local d = game.options.drift
    local ox = (math.sin(t * 0.53) * 0.10 + math.sin(t * 1.37 + 2) * 0.04) * d
    local oy = (math.sin(t * 0.71 + 1) * 0.07 + math.sin(t * 1.9) * 0.03) * d
    local cx, cy = HALF + ox * R, HALF + (0.02 + oy) * R
    local gh = 0.62 * R

    local cycle = 0.5 + 0.5 * math.sin(t * 2 * math.pi / AIRWAY.CORD_CYCLE)
    local open = game.options.openMin + (1 - game.options.openMin) * cycle

    return {
        ox = ox * R, oy = oy * R,
        cx = cx, cy = cy, gh = gh,
        apexY = cy - gh / 2, baseY = cy + gh / 2,
        half = 0.23 * R * open,
        open = open,
        escX = cx, escY = cy + gh / 2 + 0.2 * R,
    }
end

-- "glottis" | "esophagus" | "tissue" for a point in view coordinates
local function hitRegion(geo, x, y)
    local tol = 5 * scale
    local rel = y - geo.apexY
    if rel >= -tol and rel <= geo.gh + tol then
        local halfW = geo.half * math.max(0, math.min(1, rel / geo.gh))
        if math.abs(x - geo.cx) <= halfW + tol then return "glottis" end
    end
    local ex, ey = (x - geo.escX) / (0.21 * R), (y - geo.escY) / (0.09 * R)
    if ex * ex + ey * ey <= 1 then return "esophagus" end
    return "tissue"
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

-- Kneels the local player behind the patient's head, facing it
local function placeAtHead(ped)
    local hx, hy, hz = getPedBonePosition(ped, 8)
    local sx, sy = getPedBonePosition(ped, 3)
    local dx, dy = 0, 0
    if hx and sx then dx, dy = hx - sx, hy - sy end
    local len = math.sqrt(dx * dx + dy * dy)
    if not hx or len < 0.05 then
        -- bones not available (not streamed in yet): assume the head is in front of the ped
        hx, hy, hz = getElementPosition(ped)
        local m = getElementMatrix(ped)
        dx, dy = m[2][1], m[2][2]
        len = math.sqrt(dx * dx + dy * dy)
        hx, hy = hx + dx / len * 0.8, hy + dy / len * 0.8
    end
    dx, dy = dx / len, dy / len

    local x, y = hx + dx * AIRWAY.HEAD_OFFSET, hy + dy * AIRWAY.HEAD_OFFSET
    local groundZ = getGroundPosition(x, y, hz + 1.5)
    local z = (groundZ and groundZ ~= 0) and groundZ + 1.0 or hz

    setElementPosition(localPlayer, x, y, z)
    setElementRotation(localPlayer, 0, 0, -math.deg(math.atan2(hx - x, hy - y)), "default", true)
end

---------------------------------------------------------------------------
-- Game flow
---------------------------------------------------------------------------
local function toast(text, color)
    game.toast = { text = text, color = color, tick = getTickCount() }
end

local function endGame(reason)
    if game.resultTick then return end
    game.resultTick = getTickCount()
    game.reason = reason
    game.finalTime = math.max(0, game.t)
end

local function mistake(key)
    game.details[key] = game.details[key] + 1
    game.mistakes = game.mistakes + 1
    game.flashTick = getTickCount()
    toast(AIRWAY_MISTAKES[key]:upper() .. "!", COLOR_BAD)
    if game.mistakes > game.options.maxMistakes then
        endGame("too_many_mistakes")
    end
end

local function nextPhase(text)
    game.phase = game.phase + 1
    game.lockTime = 0
    if game.phase > 2 then game.blood = {} end -- the scope view is gone
    toast(text, COLOR_GOOD)
end

local function finish(reason, notifyServer)
    local g = game
    if not g then return end
    game = nil

    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientKey", root, onKey)
    unlockControls(g)
    if g.localAnim then setPedAnimation(localPlayer) end
    setCursorAlpha(255)
    if g.cursorShown then showCursor(false) end
    releaseTextures()

    local time = g.finalTime or math.max(0, g.t)
    local details = {}
    for key in pairs(AIRWAY_MISTAKES) do details[key] = g.details[key] end
    details.depth = math.floor(g.depth * 10 + 0.5) / 10
    details.cuffPressure = math.floor(g.cuff + 0.5)

    if g.sessionId and notifyServer then
        triggerServerEvent("mg_airway:onResult", resourceRoot, g.sessionId, reason, time, details)
    end

    details.difficulty = g.options.difficulty
    details.minSpO2 = math.floor(g.minSpO2 + 0.5)
    local success = reason == "intubated"
    local score = success and airwayScore(time, g.mistakes) or 0
    -- success, score, time, mistakes, reason, sessionId (nil for client-started games), details
    triggerEvent("onClientAirwayGameFinish", localPlayer, success, score, time, g.mistakes, reason, g.sessionId, details)
end

onKey = function(button, press)
    local action
    if button == AIRWAY.KEY_ACTION then action = "holdAction"
    elseif button == AIRWAY.KEY_BACK then action = "holdBack"
    elseif button == AIRWAY.KEY_SUCTION then action = "holdSuction"
    else return end
    cancelEvent()
    game[action] = press
end

local function updateTip(dt, t)
    local cx, cy = getCursorPosition()
    if cx then
        game.aimX = cx * screenW - (VCX - HALF)
        game.aimY = cy * screenH - (VCY - HALF)
    end
    local k = math.min(1, dt * 9)
    game.baseX = lerp(game.baseX, game.aimX, k)
    game.baseY = lerp(game.baseY, game.aimY, k)

    -- keep the tip inside the scope
    local dx, dy = game.baseX - HALF, game.baseY - HALF
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > R * 0.9 then
        game.baseX, game.baseY = HALF + dx / dist * R * 0.9, HALF + dy / dist * R * 0.9
    end

    local tremor = game.options.tremor * scale
    game.tipX = game.baseX + tremor * (math.sin(t * 7.3) + 0.6 * math.sin(t * 12.7 + 1)) / 1.6
    game.tipY = game.baseY + tremor * (math.sin(t * 6.1 + 2) + 0.6 * math.sin(t * 10.3)) / 1.6
end

local function updateBlood(dt, t)
    local blood = game.options.blood
    if blood and game.phase <= 2 and t >= game.nextBlood and #game.blood < 6 then
        game.nextBlood = t + blood * (0.7 + math.random() * 0.6)
        local a = math.random() * math.pi * 2
        local r = math.random() * 0.4 * R
        table.insert(game.blood, {
            x = math.cos(a) * r, y = math.sin(a) * r * 0.8 - 0.05 * R,
            size = (0.18 + math.random() * 0.2) * R,
            rot = math.random(0, 359),
            alpha = 0,
        })
    end
    for i = #game.blood, 1, -1 do
        local drop = game.blood[i]
        if game.holdSuction then
            drop.alpha = drop.alpha - 500 * dt
            if drop.alpha <= 0 then table.remove(game.blood, i) end
        else
            drop.alpha = math.min(215, drop.alpha + 300 * dt)
            drop.y = drop.y + 0.02 * R * dt -- runs down slowly
        end
    end
end

local function updatePhase(dt, t)
    local o = game.options
    local phase = game.phase

    if phase == 1 then
        if game.holdAction then
            game.lift = game.lift + AIRWAY.LIFT_UP * dt
        else
            game.lift = math.max(0, game.lift - AIRWAY.LIFT_DOWN * dt)
        end
        if game.lift >= AIRWAY.LIFT_TOOTH then
            game.lift = 0.25
            game.liftHold = 0
            mistake("teeth")
        elseif game.lift >= o.liftMin and game.lift <= o.liftMax then
            game.liftHold = game.liftHold + dt
            if game.liftHold >= AIRWAY.LIFT_HOLD then
                nextPhase("CORDS IN VIEW")
                game.lift = (o.liftMin + o.liftMax) / 2
            end
        else
            game.liftHold = math.max(0, game.liftHold - dt * 0.5)
        end

    elseif phase == 2 then
        updateTip(dt, t)
        local geo = glottisGeometry(t)
        local region = hitRegion(geo, game.tipX, game.tipY)
        game.region = region
        game.cordsOpen = geo.open >= AIRWAY.CORD_PASSABLE

        if game.holdAction then
            if region == "glottis" and game.cordsOpen then
                game.progress = game.progress + AIRWAY.PASS_SPEED * dt
                game.trauma = math.max(0, game.trauma - 0.3 * dt)
            elseif region == "glottis" then
                game.trauma = game.trauma + AIRWAY.TRAUMA_SPEED * 0.7 * dt
            elseif region == "esophagus" then
                game.eso = game.eso + AIRWAY.ESOPHAGUS_SPEED * dt
                if game.eso >= 1 then
                    game.eso, game.progress = 0, 0
                    mistake("esophageal")
                end
            else
                game.trauma = game.trauma + AIRWAY.TRAUMA_SPEED * dt
            end
            if game.trauma >= 1 then
                game.trauma = 0
                game.progress = math.max(0, game.progress - 0.3)
                mistake("trauma")
            end
        else
            game.trauma = math.max(0, game.trauma - 0.5 * dt)
            game.eso = math.max(0, game.eso - 0.8 * dt)
        end
        if game.progress >= 1 then
            nextPhase("THROUGH THE CORDS")
        end

    elseif phase == 3 then
        if game.holdAction then
            game.depth = game.depth + AIRWAY.DEPTH_SPEED * dt
        elseif game.holdBack then
            game.depth = math.max(AIRWAY.DEPTH_START - 1, game.depth - AIRWAY.DEPTH_SPEED * dt)
        end
        if game.depth >= AIRWAY.DEPTH_BRONCHUS then
            game.depth = AIRWAY.DEPTH_RESET
            game.lockTime = 0
            mistake("bronchus")
        elseif not game.holdAction and not game.holdBack
            and game.depth >= AIRWAY.DEPTH_MIN and game.depth <= AIRWAY.DEPTH_MAX then
            game.lockTime = game.lockTime + dt
            if game.lockTime >= AIRWAY.LOCK_TIME then
                nextPhase(("DEPTH OK - %d CM AT THE TEETH"):format(math.floor(game.depth + 0.5)))
            end
        else
            game.lockTime = 0
        end

    elseif phase == 4 then
        if game.holdAction then
            game.cuff = game.cuff + AIRWAY.CUFF_UP * dt
        elseif game.holdBack then
            game.cuff = math.max(0, game.cuff - AIRWAY.CUFF_DOWN * dt)
        else
            game.cuff = math.max(0, game.cuff - AIRWAY.CUFF_LEAK * dt)
        end
        if game.cuff >= AIRWAY.CUFF_BURST then
            game.cuff = 0
            game.lockTime = 0
            mistake("cuff")
        elseif not game.holdAction and not game.holdBack
            and game.cuff >= AIRWAY.CUFF_MIN and game.cuff <= AIRWAY.CUFF_MAX then
            game.lockTime = game.lockTime + dt
            if game.lockTime >= AIRWAY.LOCK_TIME then
                game.phase = 5
                endGame("intubated")
            end
        else
            game.lockTime = 0
        end
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

-- Laryngoscope view (phases 1-2), drawn with (bx, by) as the top left of the view
local function drawScope(bx, by, t)
    local geo = glottisGeometry(t)
    local cx, cy = bx + geo.cx, by + geo.cy
    local apexY, baseY = by + geo.apexY, by + geo.baseY

    dxDrawImage(bx + geo.ox * 0.4 - 0.05 * R, by + geo.oy * 0.4 - 0.05 * R, HALF * 2 + 0.1 * R, HALF * 2 + 0.1 * R,
        textures.pharynx)
    dxDrawImage(cx - 0.5 * R, apexY - 0.1 * R, R, R * 280 / 256, textures.larynx)
    dxDrawImage(cx - geo.half, apexY, geo.half * 2, geo.gh, textures.opening)

    local as = 0.17 * R
    local ax = geo.half + 0.02 * R
    dxDrawImage(cx - ax - as / 2, baseY - as * 0.4, as, as, textures.blob, 0, 0, 0, tocolor(226, 140, 148))
    dxDrawImage(cx + ax - as / 2, baseY - as * 0.4, as, as, textures.blob, 0, 0, 0, tocolor(226, 140, 148))

    -- epiglottis + tongue, pushed away by the laryngoscope
    local reveal = 1
    if game.phase == 1 then
        reveal = math.max(0, math.min(1, (game.lift - 0.1) / (game.options.liftMin - 0.1)))
    end
    local tongueBottom = lerp(baseY + 0.3 * R, apexY - 0.4 * R, reveal)
    dxDrawImage(cx - 0.38 * R, tongueBottom - 0.12 * R, 0.76 * R, 0.38 * R, textures.epiglottis)
    local tongueH = 1.5 * R
    dxDrawImage(bx + geo.ox * 0.6 - 0.1 * R, tongueBottom - tongueH * 250 / 256, HALF * 2 + 0.2 * R, tongueH,
        textures.tongue)

    for _, drop in ipairs(game.blood) do
        dxDrawImage(cx + drop.x - drop.size / 2, cy + drop.y - drop.size / 2, drop.size, drop.size,
            textures.blood, drop.rot, 0, 0, tocolor(255, 255, 255, drop.alpha))
    end

    if game.phase == 2 and game.tipX then
        local tx, ty = bx + game.tipX, by + game.tipY
        local color = COLOR_BAD
        if game.region == "glottis" then color = game.cordsOpen and COLOR_GOOD or COLOR_WARN end

        -- the tube comes in from the bottom right corner
        dxDrawLine(bx + HALF + 1.0 * R, by + HALF + 1.1 * R, tx, ty, tocolor(235, 240, 245, 70), 0.16 * R)
        dxDrawLine(bx + HALF + 1.0 * R, by + HALF + 1.1 * R, tx + 0.05 * R, ty, tocolor(47, 125, 255, 110), 4 * scale)
        local size = 0.2 * R * (1 - 0.55 * game.progress)
        dxDrawImage(tx - size / 2, ty - size / 2, size, size, textures.tip, t * 20, 0, 0, rgba(color, 235))
    end
end

-- Trachea cutaway (phases 3-4)
local function drawTrachea(bx, by, t)
    dxDrawRectangle(bx, by, HALF * 2, HALF * 2, tocolor(20, 12, 16))

    local h = 1.8 * R
    local s = h / TRACHEA_H
    local w = TRACHEA_W * s
    local tx, ty = bx + HALF - w / 2, by + HALF - h / 2 - 0.05 * R
    dxDrawImage(tx, ty, w, h, textures.trachea)

    local midX = bx + HALF
    -- target zone + ruler
    local zoneTop, zoneBottom = ty + depthToSvgY(AIRWAY.DEPTH_MIN) * s, ty + depthToSvgY(AIRWAY.DEPTH_MAX) * s
    local rulerX = tx + w + 18 * scale
    dxDrawRectangle(rulerX - 4 * scale, zoneTop, 8 * scale, zoneBottom - zoneTop, rgba(COLOR_GOOD, 150))
    for cm = 15, 26 do
        local y = ty + depthToSvgY(cm) * s
        local long = cm % 5 == 0
        dxDrawLine(rulerX - (long and 10 or 5) * scale, y, rulerX + (long and 10 or 5) * scale, y,
            tocolor(220, 220, 220, 180), 1)
        if long or cm == 26 then
            dxDrawText(cm == 26 and "carina" or (cm .. " cm"), rulerX + 14 * scale, y, rulerX + 14 * scale, y,
                tocolor(200, 200, 200, 200), 0.9 * scale, "default-bold", "left", "center")
        end
    end

    -- tube
    local tipY = ty + depthToSvgY(game.depth) * s
    local tubeW = TUBE_WIDTH * s
    dxDrawRectangle(midX - tubeW / 2, by + HALF - R, tubeW, tipY - (by + HALF - R), tocolor(235, 240, 245, 120))
    dxDrawRectangle(midX + tubeW / 2 - 5 * scale, by + HALF - R, 3 * scale, tipY - (by + HALF - R),
        tocolor(47, 125, 255, 200))
    dxDrawLine(rulerX - 16 * scale, tipY, midX + tubeW / 2, tipY, tocolor(255, 255, 255, 120), 1)

    -- cuff: seals the trachea exactly at CUFF_MAX
    local cuffW = tubeW + (TRACHEA_LUMEN - TUBE_WIDTH) * s * (game.cuff / AIRWAY.CUFF_MAX)
    local cuffH = 32 * s + game.cuff * 0.4 * s
    local cuffY = tipY - 44 * s
    local cuffColor = { 150, 200, 255 }
    if game.phase == 4 then
        if game.cuff > AIRWAY.CUFF_MAX then cuffColor = COLOR_BAD
        elseif game.cuff >= AIRWAY.CUFF_MIN then cuffColor = COLOR_GOOD end
    end
    dxDrawImage(midX - cuffW / 2, cuffY - cuffH / 2, cuffW, cuffH, textures.blob, 0, 0, 0, rgba(cuffColor, 150))

    -- air leaking past a soft cuff
    if game.phase == 4 and game.cuff < AIRWAY.CUFF_MIN then
        for i = 0, 3 do
            local k = ((t * 0.9 + i / 4) % 1)
            local bx2 = midX + (i % 2 == 0 and -1 or 1) * (cuffW / 2 + 4 * scale)
            local by2 = cuffY - k * 0.5 * R
            local size = 10 * scale * (1 - k * 0.5)
            dxDrawImage(bx2 - size / 2, by2 - size / 2, size, size, textures.blob, 0, 0, 0,
                tocolor(210, 230, 255, 200 * (1 - k)))
        end
        dxDrawText("AIR LEAK", tx - 20 * scale, cuffY, tx - 20 * scale, cuffY, rgba(COLOR_WARN), 1.1 * scale,
            "default-bold", "right", "center")
    end

    local label = game.phase == 3 and ("%.1f cm"):format(game.depth) or ("%d cmH2O"):format(math.floor(game.cuff + 0.5))
    dxDrawText(label, bx + HALF - R * 0.9, by + HALF + R * 0.72, bx + HALF + R * 0.9, by + HALF + R * 0.92,
        tocolor(255, 255, 255, 235), 1.6 * scale, "default-bold", "center", "center")
end

local function drawView(now, t)
    local bx, by = VCX - HALF, VCY - HALF
    if renderTarget then
        dxSetRenderTarget(renderTarget, true)
        bx, by = 0, 0
    end

    if game.phase <= 2 then drawScope(bx, by, t) else drawTrachea(bx, by, t) end

    if renderTarget then
        dxSetRenderTarget()
        dxDrawImage(VCX - HALF, VCY - HALF, HALF * 2, HALF * 2, renderTarget)
    end

    if game.flashTick and now - game.flashTick < 350 then
        dxDrawCircle(VCX, VCY, R, 0, 360, tocolor(255, 0, 0, 0), tocolor(255, 30, 30, 120 * (1 - (now - game.flashTick) / 350)), 48)
    end
    dxDrawImage(VCX - HALF, VCY - HALF, HALF * 2, HALF * 2, textures.mask)

    dxDrawText(("%d. %s"):format(math.min(4, game.phase), PHASES[math.min(4, game.phase)]:upper()),
        VCX - HALF + 16 * scale, VCY - HALF + 8 * scale, VCX + HALF, VCY - HALF + 36 * scale,
        tocolor(200, 200, 200, 220), 1.1 * scale, "default-bold", "left", "center")
end

-- Horizontal gauge with a green zone, a red zone and a marker
local function drawGauge(value, min, max, zoneLo, zoneHi, dangerFrom, lockFrac)
    local x, y, w, h = GAUGE_X, GAUGE_Y, GAUGE_W, GAUGE_H
    local function px(v) return x + (math.max(min, math.min(max, v)) - min) / (max - min) * w end

    dxDrawRectangle(x - 3 * scale, y - 3 * scale, w + 6 * scale, h + 6 * scale, tocolor(0, 0, 0, 170))
    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 30))
    dxDrawRectangle(px(zoneLo), y, px(zoneHi) - px(zoneLo), h, rgba(COLOR_GOOD, 120))
    if dangerFrom then
        dxDrawRectangle(px(dangerFrom), y, x + w - px(dangerFrom), h, rgba(COLOR_BAD, 130))
    end
    if lockFrac and lockFrac > 0 then
        dxDrawRectangle(px(zoneLo), y + h - 4 * scale, (px(zoneHi) - px(zoneLo)) * math.min(1, lockFrac), 4 * scale,
            tocolor(255, 255, 255, 230))
    end
    local mx = px(value)
    local inside = value >= zoneLo and value <= zoneHi
    dxDrawRectangle(mx - 3 * scale, y - 6 * scale, 6 * scale, h + 12 * scale,
        rgba((dangerFrom and value >= dangerFrom) and COLOR_BAD or (inside and COLOR_GOOD or COLOR_TEXT)))
end

-- Phase 2 gauge: progress through the cords, with trauma/oesophagus warnings
local function drawPassGauge()
    local x, y, w, h = GAUGE_X, GAUGE_Y, GAUGE_W, GAUGE_H
    dxDrawRectangle(x - 3 * scale, y - 3 * scale, w + 6 * scale, h + 6 * scale, tocolor(0, 0, 0, 170))
    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255, 30))
    dxDrawRectangle(x, y, w * math.min(1, game.progress), h, rgba(COLOR_GOOD, 200))
    if game.trauma > 0 then
        dxDrawRectangle(x, y + h - 5 * scale, w * math.min(1, game.trauma), 5 * scale, rgba(COLOR_WARN, 230))
    end
    if game.eso > 0 then
        dxDrawRectangle(x, y, w * math.min(1, game.eso), 5 * scale, rgba(COLOR_BAD, 230))
    end

    local warning
    if game.holdAction then
        if game.region == "esophagus" then warning = { "That's the oesophagus!", COLOR_BAD }
        elseif game.region == "tissue" then warning = { "Pushing against tissue", COLOR_WARN }
        elseif not game.cordsOpen then warning = { "Cords closed - wait", COLOR_WARN } end
    end
    if warning then
        dxDrawText(warning[1], x, y - 30 * scale, x + w, y - 6 * scale, rgba(warning[2]), 1.2 * scale,
            "default-bold", "center", "center")
    end
end

local function drawBottom()
    local phase = game.phase
    if phase == 1 then
        drawGauge(game.lift, 0, 1, game.options.liftMin, game.options.liftMax, AIRWAY.LIFT_TOOTH,
            game.liftHold / AIRWAY.LIFT_HOLD)
    elseif phase == 2 then
        drawPassGauge()
    elseif phase == 3 then
        drawGauge(game.depth, 15, 27, AIRWAY.DEPTH_MIN, AIRWAY.DEPTH_MAX, AIRWAY.DEPTH_BRONCHUS,
            game.lockTime / AIRWAY.LOCK_TIME)
    elseif phase == 4 then
        drawGauge(game.cuff, 0, 45, AIRWAY.CUFF_MIN, AIRWAY.CUFF_MAX, AIRWAY.CUFF_BURST,
            game.lockTime / AIRWAY.LOCK_TIME)
    end

    if phase <= 4 then
        local hint = HINTS[phase]
        if #game.blood > 0 then hint = hint .. "   |   hold E - suction" end
        shadowText(hint, GAUGE_X - 100 * scale, GAUGE_Y + GAUGE_H + 10 * scale, GAUGE_X + GAUGE_W + 100 * scale,
            GAUGE_Y + GAUGE_H + 40 * scale, rgba(COLOR_TEXT, 235), 1.15 * scale, "center", "center")
    end
end

-- Pulse oximeter pleth curve, 0..1
local function pleth(p)
    if p < 0.12 then return p / 0.12 end
    local v = math.exp(-(p - 0.12) * 4.5)
    if p > 0.35 and p < 0.5 then v = v + 0.12 * math.sin((p - 0.35) / 0.15 * math.pi) end
    return v
end

-- Capnography curve, 0..1
local function capno(p)
    if p < 0.08 then return p / 0.08 * 0.9 end
    if p < 0.5 then return 0.9 + (p - 0.08) * 0.2 end
    if p < 0.56 then return 1 - (p - 0.5) / 0.06 end
    return 0
end

local function drawWave(x, y, w, h, fn, t, speed, color)
    local n = 48
    local lastX, lastY
    for i = 0, n do
        local k = i / n
        local px, py = x + k * w, y + h - fn(((t - (1 - k) * 2.5) * speed) % 1) * h
        if lastX then dxDrawLine(lastX, lastY, px, py, color, 2 * scale) end
        lastX, lastY = px, py
    end
end

local function drawPanel(now, t)
    local x, y, w, h = PANEL_X, PANEL_Y, PANEL_W, PANEL_H
    local pad = 16 * scale
    local ix, iw = x + pad, w - pad * 2
    dxDrawRectangle(x, y, w, h, tocolor(10, 12, 16, 215))
    dxDrawRectangle(x, y, w, 4 * scale, rgba(COLOR_BAD, 220))

    dxDrawText("INTUBATION", ix, y + 10 * scale, ix + iw, y + 40 * scale, tocolor(255, 255, 255, 240),
        1.4 * scale, "default-bold", "left", "center")
    dxDrawText(game.options.difficulty:upper(), ix, y + 10 * scale, ix + iw, y + 40 * scale,
        tocolor(170, 170, 170, 220), 1.0 * scale, "default-bold", "right", "center")

    -- SpO2 + pleth
    local tt = math.max(0, game.finalTime or t)
    local spo2 = game.spo2
    local color = spo2 >= 90 and COLOR_GOOD or (spo2 >= 85 and COLOR_WARN or COLOR_BAD)
    local blink = spo2 < 85 and not game.resultTick and (now % 600) < 300
    local sy = y + 52 * scale
    dxDrawText("SpO2", ix, sy, ix + iw, sy + 20 * scale, tocolor(160, 160, 160, 220), 1.0 * scale, "default-bold", "left", "top")
    dxDrawText(("%d%%"):format(math.floor(spo2 + 0.5)), ix, sy + 14 * scale, ix + iw, sy + 70 * scale,
        rgba(color, blink and 110 or 255), 3.0 * scale, "default-bold", "left", "center")
    local hr = game.options.liveSpO2 and tonumber(isElement(game.ped) and getElementData(game.ped, AIRWAY.HR_DATA))
    hr = math.floor(hr or (92 + (game.options.spo2Start - spo2) * 3))
    dxDrawText(("HR %d"):format(hr), ix, sy, ix + iw, sy + 20 * scale, tocolor(120, 255, 140, 220),
        1.0 * scale, "default-bold", "right", "top")
    drawWave(ix + iw * 0.45, sy + 26 * scale, iw * 0.55, 38 * scale, pleth, tt, hr / 60, rgba(COLOR_INFO, 220))

    -- time + mistakes
    local my = sy + 90 * scale
    dxDrawText(("Time  %.1f s"):format(tt), ix, my, ix + iw, my + 24 * scale, rgba(COLOR_TEXT, 230),
        1.1 * scale, "default-bold", "left", "center")
    dxDrawText("Mistakes", ix, my + 28 * scale, ix + iw, my + 52 * scale, rgba(COLOR_TEXT, 230),
        1.1 * scale, "default-bold", "left", "center")
    local box = 16 * scale
    for i = 1, game.options.maxMistakes + 1 do
        local bx = ix + iw - i * (box + 6 * scale)
        local used = i <= game.mistakes
        local last = i == game.options.maxMistakes + 1
        dxDrawRectangle(bx, my + 32 * scale, box, box, used and rgba(COLOR_BAD) or tocolor(255, 255, 255, last and 20 or 45))
        if last and not used then
            dxDrawText("!", bx, my + 32 * scale, bx + box, my + 32 * scale + box, rgba(COLOR_BAD, 200),
                0.9 * scale, "default-bold", "center", "center")
        end
    end

    -- checklist
    local cy = my + 70 * scale
    for i, name in ipairs(PHASES) do
        local rowY = cy + (i - 1) * 30 * scale
        local done = game.phase > i
        local current = game.phase == i
        dxDrawRectangle(ix, rowY + 5 * scale, box, box,
            done and rgba(COLOR_GOOD) or (current and tocolor(255, 255, 255, 200) or tocolor(255, 255, 255, 40)))
        dxDrawText(name, ix + box + 10 * scale, rowY, ix + iw, rowY + 26 * scale,
            done and rgba(COLOR_GOOD, 230) or (current and tocolor(255, 255, 255, 250) or tocolor(150, 150, 150, 200)),
            1.05 * scale, "default-bold", "left", "center")
    end

    -- capnography: flat until the tube is confirmed
    local capY = y + h - 70 * scale
    dxDrawText("EtCO2", ix, capY - 22 * scale, ix + iw, capY, tocolor(160, 160, 160, 220), 1.0 * scale,
        "default-bold", "left", "center")
    local secured = game.reason == "intubated"
    dxDrawText(secured and ("%d mmHg"):format(game.etco2) or "-- mmHg", ix, capY - 22 * scale, ix + iw, capY,
        tocolor(255, 230, 90, 230), 1.0 * scale, "default-bold", "right", "center")
    dxDrawRectangle(ix, capY, iw, 52 * scale, tocolor(255, 255, 255, 12))
    if secured then
        drawWave(ix, capY + 6 * scale, iw, 40 * scale, capno, (now - game.resultTick) / 1000, 0.4, tocolor(255, 230, 90, 230))
    else
        dxDrawLine(ix, capY + 46 * scale, ix + iw, capY + 46 * scale, tocolor(255, 230, 90, 140), 2 * scale)
    end
end

local function drawOverlays(now, t)
    if game.toast and not game.resultTick then
        local age = now - game.toast.tick
        if age < 1300 then
            local alpha = math.min(1, (1300 - age) / 300)
            local ty = VCY - HALF - 30 * scale
            shadowText(game.toast.text, VCX - HALF, ty - 20 * scale, VCX + HALF, ty + 20 * scale,
                rgba(game.toast.color, 255 * alpha), 1.8 * scale, "center", "center", alpha)
        end
    end

    if t < 0 then
        local n = math.ceil(-t)
        local k = 1 - (-t - (n - 1))
        dxDrawRectangle(VCX - R, VCY - 70 * scale, R * 2, 150 * scale, tocolor(0, 0, 0, 120))
        shadowText(tostring(n), VCX - R, VCY - 70 * scale, VCX + R, VCY + 30 * scale,
            tocolor(255, 255, 255, 255 * (1 - k * 0.6)), (4 - k) * scale, "center", "center")
        shadowText("Pre-oxygenated. Get ready.", VCX - R, VCY + 30 * scale, VCX + R, VCY + 70 * scale,
            tocolor(220, 220, 220, 230), 1.3 * scale, "center", "center")
    end

    if game.resultTick then
        local k = math.min(1, (now - game.resultTick) / 250)
        local title, color, sub
        if game.reason == "intubated" then
            title, color = "AIRWAY SECURED", COLOR_GOOD
            sub = ("Score %d   |   %.1f s   |   %d mistake%s"):format(airwayScore(game.finalTime, game.mistakes),
                game.finalTime, game.mistakes, game.mistakes == 1 and "" or "s")
        elseif game.reason == "desaturated" then
            title, color, sub = "PATIENT DESATURATED", COLOR_BAD, "Too slow - the SpO2 fell below " .. AIRWAY.FAIL_SPO2 .. "%"
        else
            title, color, sub = "PROCEDURE FAILED", COLOR_BAD, "Too many mistakes"
        end
        dxDrawRectangle(VCX - HALF, VCY - 70 * scale, HALF * 2, 140 * scale, tocolor(0, 0, 0, 170 * k))
        shadowText(title, VCX - HALF, VCY - 60 * scale, VCX + HALF, VCY + 10 * scale, rgba(color, 255 * k),
            (2.6 + (1 - k)) * scale, "center", "center", k)
        shadowText(sub, VCX - HALF, VCY + 10 * scale, VCX + HALF, VCY + 55 * scale, tocolor(230, 230, 230, 255 * k),
            1.3 * scale, "center", "center", k)
    end
end

-- SpO2 from the patient's element data (medic system), or the fallback simulation
updateSpO2 = function(t)
    local spo2
    if game.options.liveSpO2 then
        spo2 = airwayGetPatientSpO2(game.ped) or game.spo2 -- keep the last value if the data vanishes
    else
        spo2 = airwaySpO2(game.options, t)
    end
    game.spo2 = spo2
    game.minSpO2 = math.min(game.minSpO2, spo2)
end

render = function()
    ensureTextures()
    local now = getTickCount()
    local dt = math.min(0.1, (now - game.lastTick) / 1000)
    game.lastTick = now

    if not game.resultTick then
        game.t = (now - game.playTick) / 1000
        updateSpO2(game.t) -- live data is shown during the countdown too
        if game.t >= 0 then
            updateBlood(dt, game.t)
            updatePhase(dt, game.t)
            if not game.resultTick and game.spo2 <= AIRWAY.FAIL_SPO2 then
                if not game.options.liveSpO2 then game.t = airwayTimeLimit(game.options) end
                endGame("desaturated")
            end
        end
    end

    local t = game.t
    drawView(now, math.max(0, t))
    drawBottom()
    drawPanel(now, t)
    drawOverlays(now, t)

    if game.resultTick and now - game.resultTick >= AIRWAY.RESULT_TIME * 1000 then
        finish(game.reason, true)
    elseif not game.resultTick and not game.sessionId and t >= AIRWAY.MAX_TIME then
        finish("timeout", false) -- server-started games are timed out by the server
    end
end

local function begin(ped, options, sessionId)
    if game then return false end
    if ped ~= nil and (not isElement(ped) or ped == localPlayer) then return false end
    ensureTextures()

    local now = getTickCount()
    options = airwayNormalizeOptions(options)
    local spo2 = airwayGetPatientSpO2(ped)
    if not sessionId then options.liveSpO2 = spo2 ~= nil end -- server-started: the server decided
    spo2 = spo2 or options.spo2Start
    game = {
        sessionId = sessionId,
        options = options,
        spo2 = spo2, minSpO2 = spo2,
        ped = ped,
        playTick = now + AIRWAY.COUNTDOWN * 1000,
        lastTick = now,
        t = -AIRWAY.COUNTDOWN,
        phase = 1,
        mistakes = 0,
        details = { teeth = 0, trauma = 0, esophageal = 0, bronchus = 0, cuff = 0 },
        lift = 0, liftHold = 0,
        progress = 0, trauma = 0, eso = 0,
        depth = AIRWAY.DEPTH_START, cuff = 0, lockTime = 0,
        blood = {}, nextBlood = 1.5,
        aimX = HALF, aimY = HALF + 0.45 * R,
        baseX = HALF, baseY = HALF + 0.45 * R,
        etco2 = math.random(33, 42),
    }

    lockControls()
    if not isCursorShowing() then
        showCursor(true)
        game.cursorShown = true
    end
    setCursorAlpha(0)
    setCursorPosition(math.floor(VCX), math.floor(VCY + 0.45 * R))

    if ped then
        placeAtHead(ped)
        if sessionId then
            -- server-started: the server plays the animation so everyone sees it
            triggerServerEvent("mg_airway:ready", resourceRoot, sessionId)
        else
            game.localAnim = true
            setPedAnimation(localPlayer, AIRWAY.ANIM_BLOCK, AIRWAY.ANIM_NAME, -1, true, false, false, false)
        end
    end

    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientKey", root, onKey)
    return true
end

-- Local game, the server is not involved (the animation is only visible to this client).
-- ped is optional; its SpO2 is read from the AIRWAY.SPO2_DATA element data if it has one.
-- options: { difficulty = "normal", spo2Start, spo2Drain, maxMistakes, blood }
function startAirwayGame(ped, options)
    return begin(ped, options, nil)
end

-- Aborts the current game. onClientAirwayGameFinish fires with reason "cancelled".
-- A server-started game should be stopped from the server instead.
function stopAirwayGame()
    if not game then return false end
    finish("cancelled", false)
    return true
end

function isAirwayGameActive()
    return game ~= nil
end

addEventHandler("mg_airway:start", resourceRoot, function(sessionId, options, ped)
    if game then finish("cancelled", false) end
    begin(ped, options, sessionId)
end)

addEventHandler("mg_airway:stop", resourceRoot, function()
    finish("cancelled", false)
end)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    if game and not game.sessionId then finish("died", false) end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if game then finish("cancelled", false) end
end)
