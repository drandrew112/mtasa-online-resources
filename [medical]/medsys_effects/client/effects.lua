-- The local player's own condition (from the server, see server/state.lua):
--   consciousness: dazed vignette + camera shake, unconscious / clinical death blackout + control lock
--   vitals: pain (red pulse), bleeding (blood at the edges), low SpO2 (tunnel), blood loss (pale)
--   injuries: disabled controls (MEDFX_INJURY_EFFECTS), a flash when a new injury arrives
-- The test module can lay a preview over the real state (medfxSetPreview).

local screenW, screenH = guiGetScreenSize()
local scale = math.max(0.65, screenH / 1080)

local real          -- last payload from the server, nil = healthy
local preview       -- test overlay (same fields), nil = none
local current = {}  -- real + preview merged
local deathTick     -- getTickCount() when the resuscitation window ends
local hitTick       -- getTickCount() of the last injury flash
local fonts

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------

local disabled = {} -- control -> true (disabled by us)

local function applyControls(wanted)
    for control in pairs(disabled) do
        if not wanted[control] then
            toggleControl(control, true)
            disabled[control] = nil
        end
    end
    for control in pairs(wanted) do
        -- a control another script has already disabled stays theirs
        if not disabled[control] and isControlEnabled(control) then
            toggleControl(control, false)
            disabled[control] = true
        end
    end
end

-- other scripts toggle controls too, ours are re-applied
setTimer(function()
    for control in pairs(disabled) do
        if isControlEnabled(control) then toggleControl(control, false) end
    end
end, 500, 0)

local function wantedControls()
    local wanted = {}
    local stateDef = MEDFX_STATES[current.status]
    if stateDef then
        if stateDef.lock then
            for _, control in ipairs(MEDFX_LOCK_CONTROLS) do wanted[control] = true end
        end
        for _, control in ipairs(stateDef.controls or {}) do wanted[control] = true end
    end
    for _, control in ipairs(current.controls or {}) do wanted[control] = true end
    return wanted
end

---------------------------------------------------------------------------
-- Camera shake
---------------------------------------------------------------------------

local shakeLevel = 0

local function updateShake()
    local level = 0
    local stateDef = MEDFX_STATES[current.status]
    if stateDef and stateDef.shake then level = stateDef.shake end
    local ps = MEDFX_SCREEN.painShake
    if (current.pain or 0) >= ps.from and not (stateDef and stateDef.lock) then
        level = math.max(level, ps.level)
    end
    local hit = MEDFX_SCREEN.hit
    if hitTick and getTickCount() - hitTick < hit.shakeTime then level = math.max(level, hit.shake) end
    if level ~= shakeLevel then
        shakeLevel = level
        setCameraShakeLevel(level)
    end
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function strength(value, from, to)
    if not value then return 0 end
    local t = (value - from) / (to - from)
    return math.max(0, math.min(1, t))
end

-- Soft frame along the screen edges: `bands` strips, fading inwards. depth = fraction of the height.
local function drawEdges(r, g, b, alpha, depth)
    if alpha < 1 then return end
    local bands = 12
    local size = screenH * depth / bands
    for i = 1, bands do
        local a = alpha * (1 - (i - 1) / bands) ^ 2
        local o = (i - 1) * size
        local color = tocolor(r, g, b, a)
        dxDrawRectangle(o, o, screenW - o * 2, size, color)                         -- top
        dxDrawRectangle(o, screenH - o - size, screenW - o * 2, size, color)        -- bottom
        dxDrawRectangle(o, o + size, size, screenH - (o + size) * 2, color)         -- left
        dxDrawRectangle(screenW - o - size, o + size, size, screenH - (o + size) * 2, color) -- right
    end
end

-- 0-1, a double heartbeat ("lub-dub")
local function heartbeat(now, period)
    local p = (now % period) / period
    return math.max(math.exp(-((p - 0.05) / 0.05) ^ 2), 0.6 * math.exp(-((p - 0.25) / 0.05) ^ 2))
end

local function ensureFonts()
    if fonts then return end
    fonts = {
        title = dxCreateFont("assets/fonts/RobotoB.ttf", math.floor(34 * scale), false, "cleartype") or "default-bold",
        sub = dxCreateFont("assets/fonts/Roboto.ttf", math.floor(14 * scale), false, "cleartype") or "default",
    }
end

local function drawBlackout(def, now)
    ensureFonts()
    dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, 235))
    local sub = def.sub
    if sub:find("%%") then
        local left = deathTick and math.max(0, math.ceil((deathTick - now) / 1000)) or 0
        sub = sub:format(math.floor(left / 60), left % 60)
    end
    local color = def.red and tocolor(235, 70, 70) or tocolor(235, 238, 245)
    dxDrawText(def.title, 0, 0, screenW, screenH - 40 * scale, color, 1, fonts.title, "center", "center")
    dxDrawText(sub, 0, 60 * scale, screenW, screenH, tocolor(160, 165, 175), 1, fonts.sub, "center", "center")
end

local function render()
    local now = getTickCount()
    local s = current
    local S = MEDFX_SCREEN
    updateShake()

    local stateDef = MEDFX_STATES[s.status]
    if stateDef and stateDef.blackout then
        drawBlackout(stateDef.blackout, now)
        return
    end

    -- blood loss: the picture goes pale
    local pale = strength(s.blood, S.blood.from, S.blood.to)
    if pale > 0 then
        dxDrawRectangle(0, 0, screenW, screenH, tocolor(150, 150, 155, S.blood.alpha * pale * 0.45))
        dxDrawRectangle(0, 0, screenW, screenH, tocolor(0, 0, 0, S.blood.alpha * pale * 0.35))
    end

    -- low SpO2: the vision narrows
    local tunnel = strength(s.spo2, S.spo2.from, S.spo2.to)
    if tunnel > 0 then
        drawEdges(0, 0, 0, S.spo2.alpha * tunnel, 0.2 + 0.25 * tunnel)
    end

    -- bleeding: blood at the edges, slow pulse
    local bleeding = s.bleeding or 0
    if bleeding > 0 then
        local alpha = S.bleeding.alpha[math.min(3, bleeding)] or 0
        drawEdges(110, 0, 0, alpha * (0.8 + 0.2 * math.sin(now / 700)), 0.12 + 0.04 * bleeding)
    end

    -- pain: red pulse with the heartbeat, faster as it grows
    local pain = strength(s.pain, S.pain.from, S.pain.to)
    if pain > 0 then
        local beat = heartbeat(now, 1100 - 450 * pain)
        drawEdges(200, 20, 20, S.pain.alpha * pain * (0.35 + 0.65 * beat), 0.1 + 0.08 * pain)
    end

    -- dazed: dark bars pulsing, red tint
    if s.status == "dazed" then
        local pulse = 70 + math.sin(now / 400) * 30
        local edge = screenH * 0.18
        dxDrawRectangle(0, 0, screenW, edge * 0.5, tocolor(0, 0, 0, pulse))
        dxDrawRectangle(0, screenH - edge * 0.5, screenW, edge * 0.5, tocolor(0, 0, 0, pulse))
        dxDrawRectangle(0, 0, screenW, screenH, tocolor(40, 0, 0, pulse * 0.35))
    end

    -- new injury: red flash
    if hitTick then
        local t = (now - hitTick) / S.hit.time
        if t < 1 then
            dxDrawRectangle(0, 0, screenW, screenH, tocolor(170, 0, 0, S.hit.alpha * (1 - t)))
        else
            hitTick = nil
        end
    end
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

local rendering = false

local function isActive()
    local s, S = current, MEDFX_SCREEN
    return MEDFX_STATES[s.status] ~= nil or hitTick ~= nil or (s.bleeding or 0) > 0
        or strength(s.pain, S.pain.from, S.pain.to) > 0 or strength(s.spo2, S.spo2.from, S.spo2.to) > 0
        or strength(s.blood, S.blood.from, S.blood.to) > 0
end

local function setRendering(on)
    if on and not rendering then
        addEventHandler("onClientRender", root, render)
    elseif not on and rendering then
        removeEventHandler("onClientRender", root, render)
        shakeLevel = -1
        updateShake()
    end
    rendering = on
end

local function rebuild()
    local merged = {}
    for k, v in pairs(real or {}) do merged[k] = v end
    local controls = {}
    for _, c in ipairs((real and real.controls) or {}) do controls[#controls + 1] = c end
    if preview then
        for k, v in pairs(preview) do merged[k] = v end
        for _, c in ipairs(preview.controls or {}) do controls[#controls + 1] = c end
    end
    merged.controls = controls
    current = merged

    applyControls(wantedControls())
    setRendering(isActive())
end

addEventHandler("medfx:state", resourceRoot, function(payload)
    real = payload
    if payload and payload.deathLeft then
        deathTick = getTickCount() + payload.deathLeft * 1000
    elseif not (preview and preview.deathLeft) then
        deathTick = nil
    end
    rebuild()
end)

function medfxHitFlash()
    hitTick = getTickCount()
    setRendering(true)
end

addEventHandler("medfx:hit", resourceRoot, medfxHitFlash)

-- the hit flash ends inside render(); stop drawing once nothing is left
setTimer(function()
    if rendering and not isActive() then setRendering(false) end
end, 1000, 0)

-- Test overlay: a table with any of status, pain, bleeding, spo2, blood, deathLeft, controls; nil clears
function medfxSetPreview(overlay)
    preview = overlay
    if overlay and overlay.deathLeft then
        deathTick = getTickCount() + overlay.deathLeft * 1000
    end
    rebuild()
end

function medfxGetPreview()
    return preview
end

-- the player is dead: the death / respawn system takes the screen
addEventHandler("onClientPlayerWasted", localPlayer, function()
    real = nil
    rebuild()
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("medfx:ready", resourceRoot)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    applyControls({})
    setCameraShakeLevel(0)
end)
