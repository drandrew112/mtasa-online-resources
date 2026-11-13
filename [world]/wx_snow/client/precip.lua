-- wx_snow :: snowfall (DESIGN.md 6)
--
-- Near flakes: static vertex batches (6 vertices per flake), all motion in fx/snow_flakes.fx.
-- Layers: cylinders around the camera with a scrolling flake texture (fx/snow_layer.fx), one
-- shader per PAIR of layers (layers 1+2, 3+4: F4, half the full screen overdraw; dx draws are
-- queued, so one shader could not carry different values for two draws).
-- Off indoors, faded out under roofs (camera check) and per flake / pixel by the roof map.

PRECIP = {
    flake = nil, layers = {}, flakeTex = nil, layerTex = nil,
    batches = nil, cylinder = nil,
    intensity = 0, drift = { 0, 0, 0 }, scroll = {}, drawn = 0, error = nil,
}

local BATCH = 400 -- flakes per draw call (6 vertices each; unpack() stays far below its limit)

local function buildFlakes(count)
    local batches = {}
    local corners = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 0 }, { 1, 1 }, { 0, 1 } }
    local batch
    for i = 1, count do
        if (i - 1) % BATCH == 0 then
            batch = {}
            batches[#batches + 1] = batch
        end
        local x, y, z = math.random(), math.random(), math.random()
        -- seeds: r = size, g = sway speed, b = density threshold / sway amount, a = drift factor
        local col = tocolor(math.random(0, 255), math.random(0, 255), math.random(0, 255), math.random(0, 255))
        for _, c in ipairs(corners) do
            batch[#batch + 1] = { x, y, z, col, c[1], c[2] }
        end
    end
    return batches
end

local function buildCylinder(segments)
    local v = {}
    local white = tocolor(255, 255, 255, 255)
    for k = 0, segments - 1 do
        local a0, a1 = k / segments * math.pi * 2, (k + 1) / segments * math.pi * 2
        local x0, y0, x1, y1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
        local u0, u1 = k / segments, (k + 1) / segments
        v[#v + 1] = { x0, y0, 0, white, u0, 0 }
        v[#v + 1] = { x1, y1, 0, white, u1, 0 }
        v[#v + 1] = { x1, y1, 1, white, u1, 1 }
        v[#v + 1] = { x0, y0, 0, white, u0, 0 }
        v[#v + 1] = { x1, y1, 1, white, u1, 1 }
        v[#v + 1] = { x0, y0, 1, white, u0, 1 }
    end
    return v
end

local function applyRoof()
    if isElement(PRECIP.flake) then ROOF.apply(PRECIP.flake) end
    for _, sh in ipairs(PRECIP.layers) do ROOF.apply(sh) end
end

local function setBoxes(sh)
    for i = 0, 1 do
        local b = CS.nearBoxes[i + 1]
        if b then
            dxSetShaderValue(sh, "gBox" .. i .. "Min", b[1], b[2], b[3])
            dxSetShaderValue(sh, "gBox" .. i .. "Max", b[4], b[5], b[6])
        else
            dxSetShaderValue(sh, "gBox" .. i .. "Min", -99999, -99999, -99999)
            dxSetShaderValue(sh, "gBox" .. i .. "Max", -99998, -99998, -99998)
        end
    end
end

local function create()
    if PRECIP.flake or PRECIP.error then return PRECIP.flake ~= nil end
    local flake = dxCreateShader("fx/snow_flakes.fx")
    if not flake then
        PRECIP.error = "unsupported"
        outputDebugString("[wx_snow] snow_flakes.fx could not be created", 2)
        return false
    end
    PRECIP.flake = flake
    PRECIP.flakeTex = dxCreateTexture("tex/flake.png", "argb", true, "clamp")
    PRECIP.layerTex = dxCreateTexture("tex/layer.png", "argb", true, "wrap")
    dxSetShaderValue(flake, "gFlakeTex", PRECIP.flakeTex)
    local box = SNOW.PRECIP.BOX
    dxSetShaderValue(flake, "gBox", box[1], box[2], box[3])
    local L = SNOW.PRECIP.LAYERS
    for i = 1, #L do PRECIP.scroll[i] = { math.random(), math.random() } end
    for pair = 1, math.ceil(#L / 2) do
        local la, lb = L[pair * 2 - 1], L[pair * 2]
        local sh = dxCreateShader("fx/snow_layer.fx")
        if sh then
            dxSetShaderValue(sh, "gLayerTex", PRECIP.layerTex)
            dxSetShaderValue(sh, "gRadius", la.r)
            dxSetShaderValue(sh, "gHeight", SNOW.PRECIP.HEIGHT[1], SNOW.PRECIP.HEIGHT[2])
            local tile = 4 / la.scale
            dxSetShaderValue(sh, "gTile", tile, tile * 1.6)
            if lb then
                local tile2 = 4 / lb.scale
                dxSetShaderValue(sh, "gRatio", lb.r / la.r)
                dxSetShaderValue(sh, "gTile2", tile2, tile2 * 1.6)
            else
                dxSetShaderValue(sh, "gRatio", 0)
            end
            PRECIP.layers[pair] = sh
        end
    end
    PRECIP.batches = PRECIP.batches or buildFlakes(SNOW.PRECIP.FLAKES.high)
    PRECIP.cylinder = PRECIP.cylinder or buildCylinder(SNOW.PRECIP.SEGMENTS)
    applyRoof()
    setBoxes(flake)
    return true
end

local function destroy()
    if isElement(PRECIP.flake) then destroyElement(PRECIP.flake) end
    for _, sh in ipairs(PRECIP.layers) do if isElement(sh) then destroyElement(sh) end end
    if isElement(PRECIP.flakeTex) then destroyElement(PRECIP.flakeTex) end
    if isElement(PRECIP.layerTex) then destroyElement(PRECIP.layerTex) end
    PRECIP.flake, PRECIP.layers, PRECIP.flakeTex, PRECIP.layerTex = nil, {}, nil, nil
end

-- wind: direction wanders slowly, gusts on top (same on every client: from the server clock)
function snowWind(p)
    local t = snowNow() + (getTickCount() % 1000) / 1000
    local angle = 0.8 + math.sin(t * 0.00031) * 1.4 + math.sin(t * 0.0021) * 0.25
    local gust = 0.5 + 0.5 * math.sin(t * 0.7) * math.sin(t * 0.23 + 1.1)
    local speed = p.wind + p.gust * gust
    return math.cos(angle) * speed, math.sin(angle) * speed, speed
end

local lastTick = getTickCount()

addEventHandler("onClientPreRender", root, function()
    local tick = getTickCount()
    local dt = math.min(0.1, (tick - lastTick) / 1000)
    lastTick = tick

    local lvl, _, p = snowCurrent()
    local target = 0
    if snowEnabled() and lvl > 0 and not CS.covered then target = p.flakes end
    -- just came outside: no fade, the snow was falling all along
    if PRECIP.wasIndoor and not CS.indoor then PRECIP.intensity = target end
    PRECIP.wasIndoor = CS.indoor
    if CS.indoor or CS.quality == "off" or PRECIP.disabled then
        PRECIP.intensity = 0
    else
        local step = dt / SNOW.PRECIP_FADE
        if PRECIP.intensity < target then
            PRECIP.intensity = math.min(target, PRECIP.intensity + step)
        else
            PRECIP.intensity = math.max(target, PRECIP.intensity - step * 1.5)
        end
    end

    PRECIP.drawn = 0
    if PRECIP.intensity < 0.005 then return end
    if not create() then return end

    local wx, wy, speed = snowWind(p)
    local d = PRECIP.drift
    d[1], d[2], d[3] = d[1] + wx * dt, d[2] + wy * dt, d[3] - p.fall * dt
    for i = 1, 3 do
        if math.abs(d[i]) > 20000 then d[i] = d[i] % SNOW.PRECIP.BOX[i] end
    end

    local day = (snowDayBrightness() - 0.82) / 0.18
    local bright = 0.5 + 0.5 * day

    -- near flakes
    local flake = PRECIP.flake
    dxSetShaderValue(flake, "gDrift", d[1], d[2], d[3])
    dxSetShaderValue(flake, "gDensity", PRECIP.intensity)
    dxSetShaderValue(flake, "gSize", p.size)
    dxSetShaderValue(flake, "gBright", bright)
    dxSetShaderValue(flake, "gSway", 0.25 + speed * 0.05)
    local count = SNOW.PRECIP.FLAKES[CS.quality] or 0
    local nBatches = math.min(#PRECIP.batches, math.ceil(count / BATCH))
    for b = 1, nBatches do
        dxDrawMaterialPrimitive3D("trianglelist", flake, false, unpack(PRECIP.batches[b]))
    end
    PRECIP.drawn = math.floor(math.min(count, nBatches * BATCH) * PRECIP.intensity)

    -- layers
    local nLayers = CS.quality == "high" and #SNOW.PRECIP.LAYERS or math.min(#SNOW.PRECIP.LAYERS, SNOW.PRECIP.LAYERS_LOW)
    local fade = math.min(1, PRECIP.intensity * 1.3)
    for pair = 1, math.ceil(nLayers / 2) do
        local sh = PRECIP.layers[pair]
        if sh then
            for k = 0, 1 do
                local i = pair * 2 - 1 + k
                local layer, sc = SNOW.PRECIP.LAYERS[i], PRECIP.scroll[i]
                if layer and i <= nLayers then
                    local tile = 4 / layer.scale
                    sc[1] = (sc[1] + speed * 0.35 * dt / tile) % 1
                    sc[2] = (sc[2] + p.fall * dt / (tile * 1.6)) % 1
                    dxSetShaderValue(sh, k == 0 and "gScroll" or "gScroll2", sc[1], sc[2])
                    dxSetShaderValue(sh, k == 0 and "gAlpha" or "gAlpha2", layer.alpha * fade)
                elseif k == 1 then
                    dxSetShaderValue(sh, "gAlpha2", 0)
                end
            end
            dxSetShaderValue(sh, "gBright", bright)
            dxDrawMaterialPrimitive3D("trianglelist", sh, false, unpack(PRECIP.cylinder))
        end
    end
end)

snowOnChange(function(reason)
    if reason == "roofmap" then return applyRoof() end
    if reason == "boxes" and isElement(PRECIP.flake) then return setBoxes(PRECIP.flake) end
    if reason == "quality" and CS.quality == "off" then destroy() end
end)

addEventHandler("onClientResourceStop", resourceRoot, destroy)
