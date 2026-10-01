-- Saját villogó fények: corona sprite-ok a lights.json pontjain, a jármű
-- elsPattern mintája szerint. A gyári GTA szirénafény helyett: nincs takarás
-- miatti eltűnés, nincs 8 pontos korlát, és a ritmus állítható.
-- A környezeti megvilágítást (envlight.lua) ugyanebből a fázisból vezéreljük.

Beacons = {}

local GLOW_TEX_SIZE = 64
local HALO_SCALE    = 2.6   -- halvány külső fény a sprite körül
local HALO_ALPHA    = 70
local CORE_SCALE    = 0.35  -- fehér, "LED" mag
local CORE_ALPHA    = 230
local CAMERA_PUSH   = 0.15  -- a sprite ennyivel a kamera felé kerül, hogy ne lógjon a karosszériába
local DRAW_DIST     = 250
local GROW_DIST     = 25    -- távolsággal nő a sprite, hogy messziről is látszódjon
local GROW_MAX_DIST = 80

local layouts  = {}   -- [model] = layout (szervertől)
local vehicles = {}   -- [veh] = { offset, on, pattern } a betöltött ELS járművekről
local preview  = nil  -- szerkesztő: { veh, layout, pattern (index | false = folyamatos) }
local glowTex  = nil
local rendering = false

------------------------------------------------------------
-- MINTÁK
------------------------------------------------------------

-- ELS_PATTERNS előfeldolgozva: groups[csoport] = { true, false, ... }
local patterns = {}
for i, p in ipairs(ELS_PATTERNS) do
    local groups = {}
    for _, g in ipairs(ELS_GROUPS) do
        if p[g] then
            local seq = {}
            for c = 1, #p[g] do
                seq[c] = p[g]:sub(c, c) == "1"
            end
            groups[g] = seq
        end
    end
    patterns[i] = { step = p.step, groups = groups }
end

-- pattern = nil → folyamatosan ég (szerkesztő előnézet)
function Beacons.isGroupOn(pattern, group, t)
    if not pattern then return true end
    local seq = pattern.groups[group]
    return seq ~= nil and seq[math.floor(t / pattern.step) % #seq + 1]
end

function Beacons.toWorld(m, x, y, z)
    return m[4][1] + x * m[1][1] + y * m[2][1] + z * m[3][1],
           m[4][2] + x * m[1][2] + y * m[2][2] + z * m[3][2],
           m[4][3] + x * m[1][3] + y * m[2][3] + z * m[3][3]
end

------------------------------------------------------------
-- ELRENDEZÉSEK
------------------------------------------------------------

-- környezeti fényforrások számolása: a legtöbb pontot tartalmazó csoportok
-- színének és középpontjának átlaga, kicsit a jármű oldala felé tolva
function Beacons.prepare(layout)
    local sums, order = {}, {}
    for _, p in ipairs(layout.points) do
        local s = sums[p.group]
        if not s then
            s = { group = p.group, n = 0, x = 0, y = 0, z = 0, r = 0, g = 0, b = 0 }
            sums[p.group] = s
            order[#order + 1] = s
        end
        s.n = s.n + 1
        s.x, s.y, s.z = s.x + p.x, s.y + p.y, s.z + p.z
        s.r, s.g, s.b = s.r + p.r, s.g + p.g, s.b + p.b
    end
    table.sort(order, function(a, b) return a.n > b.n end)

    local env = {}
    for i = 1, math.min(#order, ELS_ENV.perVehicle) do
        local s = order[i]
        local x = s.x / s.n
        local side = (x > 0.05 and 1) or (x < -0.05 and -1) or 0
        env[i] = {
            group = s.group,
            x = x + side * ELS_ENV.sideOffset,
            y = s.y / s.n,
            z = s.z / s.n + ELS_ENV.heightOffset,
            r = s.r / s.n / 255, g = s.g / s.n / 255, b = s.b / s.n / 255,
        }
    end
    layout.env = env
end

function Beacons.hasLayout(model)
    return layouts[model] ~= nil
end

local function setLayout(model, layout)
    if layout then Beacons.prepare(layout) end
    layouts[model] = layout or nil
end

------------------------------------------------------------
-- RAJZOLÁS
------------------------------------------------------------

local function createGlowTexture(size)
    local tex = dxCreateTexture(size, size, "argb")
    local pixels = dxGetTexturePixels(tex)
    local c = (size - 1) / 2
    for py = 0, size - 1 do
        for px = 0, size - 1 do
            local d = math.min(1, math.sqrt((px - c) ^ 2 + (py - c) ^ 2) / c)
            dxSetPixelColor(pixels, px, py, 255, 255, 255, math.floor((1 - d) ^ 2 * 255))
        end
    end
    dxSetTexturePixels(tex, pixels)
    return tex
end

local function sprite(x, y, z, size, color)
    local h = size / 2
    dxDrawMaterialLine3D(x, y, z + h, x, y, z - h, glowTex, size, color)
end

local function drawGlow(x, y, z, size, r, g, b, cx, cy, cz)
    local dx, dy, dz = cx - x, cy - y, cz - z
    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
    if dist > DRAW_DIST or dist < 0.01 then return end

    local push = CAMERA_PUSH / dist
    x, y, z = x + dx * push, y + dy * push, z + dz * push

    local s = size * (1 + math.min(dist, GROW_MAX_DIST) / GROW_DIST)
    sprite(x, y, z, s * HALO_SCALE, tocolor(r, g, b, HALO_ALPHA))
    sprite(x, y, z, s, tocolor(r, g, b, 255))
    sprite(x, y, z, s * CORE_SCALE, tocolor(255, 255, 255, CORE_ALPHA))
end

-- a járműre érvényes elrendezés és minta, vagy nil ha nem világít
local function resolve(veh, state)
    if preview and preview.veh == veh then
        return preview.layout, preview.pattern and patterns[preview.pattern]
    end
    if state.on then
        return layouts[getElementModel(veh)], patterns[state.pattern] or patterns[1]
    end
end

local function render()
    local now = getTickCount()
    local cx, cy, cz = getCameraMatrix()
    EnvLight.begin()

    for veh, state in pairs(vehicles) do
        local layout, pattern = resolve(veh, state)
        if layout then
            local m = getElementMatrix(veh)
            local t = now + state.offset
            for _, p in ipairs(layout.points) do
                if Beacons.isGroupOn(pattern, p.group, t) then
                    local x, y, z = Beacons.toWorld(m, p.x, p.y, p.z)
                    drawGlow(x, y, z, p.size, p.r, p.g, p.b, cx, cy, cz)
                end
            end

            local vx, vy, vz = m[4][1], m[4][2], m[4][3]
            local dist = math.sqrt((vx - cx) ^ 2 + (vy - cy) ^ 2 + (vz - cz) ^ 2)
            EnvLight.consider(dist, m, layout, pattern, t)
        end
    end

    EnvLight.finish()
end

-- a render handler csak akkor fut, ha van világító jármű
local function refreshRendering()
    local needed = preview ~= nil
    if not needed then
        for _, state in pairs(vehicles) do
            if state.on then needed = true break end
        end
    end

    if needed == rendering then return end
    rendering = needed
    if needed then
        glowTex = glowTex or createGlowTexture(GLOW_TEX_SIZE)
        addEventHandler("onClientPreRender", root, render)
    else
        removeEventHandler("onClientPreRender", root, render)
        EnvLight.release()
    end
end

------------------------------------------------------------
-- JÁRMŰVEK NYILVÁNTARTÁSA
------------------------------------------------------------

local function track(veh)
    if not sirenVehicles[getElementModel(veh)] then
        vehicles[veh] = nil
        return
    end
    local state = vehicles[veh] or { offset = math.random(0, 2000) }
    state.on = getElementData(veh, "mkjState") == true
    state.pattern = getElementData(veh, "elsPattern") or 1
    vehicles[veh] = state
end

local function untrack(veh)
    vehicles[veh] = nil
    if preview and preview.veh == veh then preview = nil end
end

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then
        track(source)
        refreshRendering()
    end
end)

local function onVehicleGone()
    if vehicles[source] then
        untrack(source)
        refreshRendering()
    end
end
addEventHandler("onClientElementStreamOut", root, onVehicleGone)
addEventHandler("onClientElementDestroy", root, onVehicleGone)

addEventHandler("onClientElementModelChange", root, function()
    if getElementType(source) == "vehicle" and isElementStreamedIn(source) then
        track(source)
        refreshRendering()
    end
end)

addEventHandler("onClientElementDataChange", root, function(key)
    if (key == "mkjState" or key == "elsPattern") and vehicles[source] then
        track(source)
        refreshRendering()
    end
end)

------------------------------------------------------------
-- SZERKESZTŐ ELŐNÉZET
------------------------------------------------------------

-- pattern: ELS_PATTERNS index, vagy false = minden pont folyamatosan ég
function Beacons.setPreview(veh, layout, pattern)
    Beacons.prepare(layout)
    preview = { veh = veh, layout = layout, pattern = pattern }
    track(veh)
    refreshRendering()
end

function Beacons.clearPreview()
    preview = nil
    refreshRendering()
end

------------------------------------------------------------
-- SZERVER SZINKRON
------------------------------------------------------------

addEvent("els:layouts", true)
addEventHandler("els:layouts", resourceRoot, function(all)
    layouts = {}
    for model, layout in pairs(all) do
        setLayout(model, layout)
    end
end)

addEvent("els:layout", true)
addEventHandler("els:layout", resourceRoot, function(model, layout)
    setLayout(model, layout)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("els:requestLayouts", resourceRoot)
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        track(veh)
    end
    refreshRendering()
end)
