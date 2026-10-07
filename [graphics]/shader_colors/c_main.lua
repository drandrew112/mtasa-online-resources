-- shader_colors / c_main.lua
--
-- Lifecycle of the full-screen grading pass. The shader and the screen source
-- exist only while the final parameters differ from neutral (preset "off" and
-- no override = nothing allocated, nothing drawn).

local SHADER_FILE         = "fx/colorgrade.fx"
local NIGHT_CHECK_MS      = 1000
local WATCHDOG_MS         = 5000
local VRAM_MARGIN_MB      = 32 -- must stay free on top of the screen source
local VRAM_CRITICAL_MB    = 16 -- running: drop the effect below this
local LUMA                = { 0.2126, 0.7152, 0.0722 }
local CHAT_PREFIX         = "#3fa9f5[Színkorrekció] #ffffff"

PRESET_FADE_MS = 800

-- shared with c_api.lua
Settings  = { preset = DEFAULT_PRESET, intensity = DEFAULT_INTENSITY }
Overrides = {}               -- id -> { params, priority, order, resource, weight, from, to, start, duration }
Status    = "idle"           -- idle | active | unsupported | lowmem
Technique = nil
Split     = false
NightWeight = 0

local NEUTRAL_C = completeParams(nil)
local screenW, screenH = guiGetScreenSize()
local shader, screenSource
local shown = NEUTRAL_C
local forceUpload = false
local animating = false
local fadeFrom, fadeStart, fadeDuration = nil, 0, PRESET_FADE_MS
local sortedOverrides = {}
local render

--------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------

local function smooth(k)
    return k * k * (3 - 2 * k)
end

local function luma(v)
    return v[1] * LUMA[1] + v[2] * LUMA[2] + v[3] * LUMA[3]
end

local function notify(text)
    outputChatBox(CHAT_PREFIX .. text, 255, 255, 255, true)
end

local function computeNightWeight()
    if getElementInterior(localPlayer) ~= 0 then return 0 end
    local h, m = getTime()
    local t = h + m / 60
    local function ramp(x, a, b)
        local k = math.max(0, math.min(1, (x - a) / (b - a)))
        return 0.5 - 0.5 * math.cos(k * math.pi)
    end
    if t >= 12 then return ramp(t, 20, 22) end
    return 1 - ramp(t, 5, 7)
end

--------------------------------------------------------------------------------
-- overrides
--------------------------------------------------------------------------------

function rebuildOverrideOrder()
    sortedOverrides = {}
    for _, o in pairs(Overrides) do
        sortedOverrides[#sortedOverrides + 1] = o
    end
    table.sort(sortedOverrides, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a.order < b.order
    end)
end

function startOverrideFade(o, to, ms)
    o.from, o.to, o.start = o.weight, to, getTickCount()
    o.duration = math.max(0, tonumber(ms) or 500)
    if o.duration == 0 then o.weight = to end
end

-- Advances override weights; drops fully faded-out ones. Returns true while any moves.
local function stepOverrides(now)
    local moving, removed = false, false
    for id, o in pairs(Overrides) do
        if o.weight ~= o.to then
            local k = (now - o.start) / o.duration
            if k >= 1 then
                o.weight = o.to
            else
                o.weight = o.from + (o.to - o.from) * smooth(k)
                moving = true
            end
        end
        if o.to == 0 and o.weight == 0 then
            Overrides[id] = nil
            removed = true
        end
    end
    if removed then rebuildOverrideOrder() end
    return moving
end

--------------------------------------------------------------------------------
-- parameter pipeline
--------------------------------------------------------------------------------

local function computeTarget()
    local day, night = presetDayNight(Settings.preset)
    local p = lerpParams(day, night, NightWeight)
    p = lerpParams(NEUTRAL_C, p, Settings.intensity / 100)
    for _, o in ipairs(sortedOverrides) do
        if o.weight > 0 then
            p = overlayParams(p, o.params, o.weight)
        end
    end
    return p
end

local function upload(p)
    local t, g = p.temperature, p.tint
    local bal = { 1 + 0.1 * t, 1 + 0.06 * g, 1 - 0.1 * t }
    local e = math.max(0, p.exposure) / luma(bal)
    dxSetShaderValue(shader, "gBalance", bal[1] * e, bal[2] * e, bal[3] * e)

    local black = math.max(0, math.min(0.5, p.black))
    local white = math.max(black + 0.05, math.min(1.5, p.white))
    dxSetShaderValue(shader, "gLevels", black, 1 / (white - black))
    dxSetShaderValue(shader, "gContrast", math.max(-1, math.min(1.5, p.contrast)))

    local ll = luma(p.lift)
    dxSetShaderValue(shader, "gLift", p.lift[1] - ll, p.lift[2] - ll, p.lift[3] - ll)
    local gl = luma(p.gain)
    if gl <= 0.01 then gl = 1 end
    dxSetShaderValue(shader, "gGain", p.gain[1] / gl, p.gain[2] / gl, p.gain[3] / gl)

    dxSetShaderValue(shader, "gSaturation", math.max(0, p.saturation))
    dxSetShaderValue(shader, "gVibrance", p.vibrance)
end

--------------------------------------------------------------------------------
-- GPU resources
--------------------------------------------------------------------------------

local function freeVRAM()
    return tonumber(dxGetStatus().VideoMemoryFreeForMTA) or 0
end

local function destroyResources()
    if shader then removeEventHandler("onClientHUDRender", root, render) end
    if isElement(shader) then destroyElement(shader) end
    if isElement(screenSource) then destroyElement(screenSource) end
    shader, screenSource, Technique = nil, nil, nil
    if Status == "active" then Status = "idle" end
end

local function disable(reason)
    destroyResources()
    if Status == reason then return end
    Status = reason
    if reason == "unsupported" then
        notify("A videokártyád nem támogatja a színkorrekciót, ezért ki lett kapcsolva.")
    else
        notify("Kevés a szabad videómemória, ezért a színkorrekció ki lett kapcsolva. A grafikai beállítás módosításakor újra megpróbálja.")
    end
end

local function createResources()
    if (tonumber(dxGetStatus().VideoCardPSVersion) or 0) < 2 then
        return disable("unsupported")
    end
    local needMB = screenW * screenH * 4 / 1048576
    if freeVRAM() < needMB + VRAM_MARGIN_MB then
        return disable("lowmem")
    end

    local s, tech = dxCreateShader(SHADER_FILE)
    if not s then
        return disable("unsupported")
    end
    local src = dxCreateScreenSource(screenW, screenH)
    if not src then
        destroyElement(s)
        return disable("lowmem")
    end

    shader, screenSource, Technique = s, src, tech
    dxSetShaderValue(shader, "gScreen", screenSource)
    dxSetShaderValue(shader, "gSplit", Split and 0.5 or -1)
    forceUpload = true
    Status = "active"
    addEventHandler("onClientHUDRender", root, render, false, "high")
end

--------------------------------------------------------------------------------
-- refresh
--------------------------------------------------------------------------------

-- Recomputes the parameters and (de)allocates / uploads as needed.
function refresh()
    local now = getTickCount()
    local moving = stepOverrides(now)
    local value = computeTarget()

    if fadeFrom then
        local k = (now - fadeStart) / fadeDuration
        if k >= 1 then
            fadeFrom = nil
        else
            value = lerpParams(fadeFrom, value, smooth(k))
            moving = true
        end
    end
    animating = moving

    -- a running fade needs the render loop to drive it, even from/to neutral
    local needed = moving or not paramsEqual(value, NEUTRAL_C)
    if needed then
        if not shader and Status ~= "unsupported" and Status ~= "lowmem" then
            createResources()
        end
        if shader and (forceUpload or not paramsEqual(value, shown)) then
            upload(value)
            forceUpload = false
        end
    elseif shader then
        destroyResources()
    end
    shown = value
end

-- Cross-fades from what is on screen now to the new target.
function beginFade(ms)
    fadeFrom = shown
    fadeStart = getTickCount()
    fadeDuration = math.max(1, tonumber(ms) or PRESET_FADE_MS)
end

-- A settings change clears a low-memory shutdown so the effect retries.
function retryAvailability()
    if Status == "lowmem" then Status = "idle" end
end

function setSplit(on)
    Split = on and true or false
    if shader then dxSetShaderValue(shader, "gSplit", Split and 0.5 or -1) end
end

--------------------------------------------------------------------------------
-- render / timers
--------------------------------------------------------------------------------

render = function()
    if animating then refresh() end
    if not shader then return end

    dxUpdateScreenSource(screenSource, true)
    dxDrawImage(0, 0, screenW, screenH, shader)

    if Split then
        local x = screenW / 2
        dxDrawLine(x, 0, x, screenH, tocolor(255, 255, 255, 170), 2)
        dxDrawText("ORIGINAL", 0, 20, x - 20, 40, tocolor(255, 255, 255, 220), 1.2, "default-bold", "right")
        dxDrawText("GRADED", x + 20, 20, screenW, 40, tocolor(255, 255, 255, 220), 1.2, "default-bold", "left")
    end
end

setTimer(function()
    local nw = computeNightWeight()
    if math.abs(nw - NightWeight) > 0.0005 then
        NightWeight = nw
        if not animating then refresh() end
    end
end, NIGHT_CHECK_MS, 0)

setTimer(function()
    local w, h = guiGetScreenSize()
    if w ~= screenW or h ~= screenH then
        screenW, screenH = w, h
        if shader then
            destroyResources()
            refresh()
        end
    end
    if shader and freeVRAM() < VRAM_CRITICAL_MB then
        disable("lowmem")
    end
end, WATCHDOG_MS, 0)

addEventHandler("onClientResourceStart", resourceRoot, function()
    NightWeight = computeNightWeight()
    refresh()
end)

addEventHandler("onClientResourceStop", resourceRoot, destroyResources)
