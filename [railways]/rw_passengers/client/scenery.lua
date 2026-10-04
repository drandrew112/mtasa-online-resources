-- Window scenery: environment classes and their layer textures (far / mid / near curtains, see
-- DESIGN.md 4.2). The textures are painted procedurally into render targets the first time a
-- class is needed (deterministic random, so every passenger sees the same scenery) and copied
-- into plain textures, which survive a device reset (minimized game window).
-- A real picture can replace any layer: put textures/<class>_<layer>.png into the resource and
-- list it in meta.xml - a file wins over the painted layer.
--
-- Layer geometry (shared with shaders/windows.fx): texture x = distance along the track over
-- one period, texture y = height (top = LAYER.height metres above the rail, bottom = rail).

Scenery = {}

Scenery.LAYERS = {
    far  = { w = 1024, h = 256, period = 900, height = 80, dist = 250 },
    mid  = { w = 1024, h = 256, period = 220, height = 22, dist = 25 },
    near = { w = 1024, h = 128, period = 60,  height = 8,  dist = 3.5 },
}

-- lit window colour: the shader shows these pixels as dark glass by day and lit at night
local LAMP = { 255, 222, 120 }

------------------------------------------------------------------ classes

-- ground = colour of the ground plane, tunnel = 0..1 (tunnel wall instead of the outside)
-- far / mid / near = painter per layer (nil = empty layer)
local CLASSES = {}

-- zone (getZoneName, not city-only) -> class. Station zones: the platform replaces the near
-- layer, far / mid come from the region class.
Scenery.ZONES = {
    ["Unity Station"]       = "station:ls_city",
    ["Market Station"]      = "station_under",
    ["Cranberry Station"]   = "station_hall:sf_city",
    ["Yellow Bell Station"] = "station:lv_city",
    ["Linden Station"]      = "station:lv_city",
    -- industrial / port areas along the line
    ["Ocean Docks"] = "ls_industrial", ["Willowfield"] = "ls_industrial", ["El Corona"] = "ls_industrial",
    ["Los Santos International"] = "ls_industrial", ["Easter Basin"] = "ls_industrial",
    ["Ocean Flats"] = "ls_industrial", ["Doherty"] = "ls_industrial",
    ["LVA Freight Depot"] = "ls_industrial", ["Linden Side"] = "ls_industrial",
    -- bridges over water / valleys
    ["Garver Bridge"] = "bridge", ["Kincaid Bridge"] = "bridge", ["Gant Bridge"] = "bridge",
    ["Martin Bridge"] = "bridge", ["Fallow Bridge"] = "bridge", ["Frederick Bridge"] = "bridge",
    ["The Mako Span"] = "bridge",
}

-- city (getZoneName city-only) -> class
Scenery.CITIES = {
    ["Los Santos"]    = "ls_city",
    ["San Fierro"]    = "sf_city",
    ["Las Venturas"]  = "lv_city",
    ["Red County"]    = "countryside",
    ["Flint County"]  = "forest",
    ["Whetstone"]     = "forest",
    ["Bone County"]   = "desert",
    ["Tierra Robada"] = "desert",
}

-- world boxes that override the zone (tunnels, covered stretches): { x1, y1, x2, y2, class }
Scenery.BOXES = {
}

function Scenery.classAt(x, y, z)
    for _, b in ipairs(Scenery.BOXES) do
        if x >= b[1] and x <= b[3] and y >= b[2] and y <= b[4] then return b[5] end
    end
    local zone = getZoneName(x, y, z, false)
    if Scenery.ZONES[zone] then return Scenery.ZONES[zone] end
    return Scenery.CITIES[getZoneName(x, y, z, true)] or "countryside"
end

------------------------------------------------------------------ painting helpers

local function rng(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function(a, b)
        s = (s * 16807) % 2147483647
        local f = (s - 1) / 2147483646
        if a then return a + (b - a) * f end
        return f
    end
end

local function col(r, g, b, a) return tocolor(r, g, b, a or 255) end
local function shade(c, k) return math.max(0, math.min(255, math.floor(c * k))) end

-- a filled ridge line: heights(x) in pixels from the bottom, drawn as 2 px columns
local function ridge(w, h, heightAt, r, g, b)
    for x = 0, w - 1, 2 do
        local hh = heightAt(x)
        dxDrawRectangle(x, h - hh, 2, hh, col(r, g, b))
    end
end

-- smooth periodic noise (sum of sines with integer frequencies -> tiles over the width)
local function wave(w, R, n)
    local parts = {}
    for i = 1, n do parts[i] = { f = math.floor(R(1, 6 * i)), p = R(0, math.pi * 2), a = R(0.4, 1) / i } end
    return function(x)
        local v = 0
        for _, q in ipairs(parts) do v = v + q.a * math.sin(q.p + q.f * 2 * math.pi * x / w) end
        return v
    end
end

local function windows(x, y, bw, bh, R, litChance, cell)
    cell = cell or 8
    for wy = y + 6, y + bh - cell, cell do
        for wx = x + 4, x + bw - 6, cell - 2 do
            if R() < litChance then
                dxDrawRectangle(wx, wy, 3, 4, col(LAMP[1], LAMP[2], LAMP[3]))
            else
                dxDrawRectangle(wx, wy, 3, 4, col(40, 48, 60, 200))
            end
        end
    end
end

-- buildings along the strip; wraps at the edge so the texture tiles
local function skyline(w, h, R, opt)
    local x = 0
    while x < w do
        local bw = math.floor(R(opt.wMin, opt.wMax))
        local bh = math.floor(R(opt.hMin, opt.hMax) * h)
        local base = opt.base or 0
        local c = R(opt.cMin, opt.cMax)
        local r, g, b = shade(opt.tint[1], c), shade(opt.tint[2], c), shade(opt.tint[3], c)
        for _, ox in ipairs({ 0, -w }) do
            dxDrawRectangle(x + ox, h - bh - base, bw, bh, col(r, g, b))
            windows(x + ox, h - bh - base, bw, bh, rng(math.floor(x * 31 + bh)), opt.lit or 0.25, opt.cell)
        end
        if x + bw > w then
            dxDrawRectangle(x - w, h - bh - base, bw, bh, col(r, g, b))
        end
        x = x + bw + math.floor(R(opt.gapMin or 0, opt.gapMax or 4))
    end
end

local function trees(w, h, R, n, opt)
    for i = 1, n do
        local x = R(0, w)
        local th = R(opt.hMin, opt.hMax) * h
        local tw = th * (opt.wk or 0.45)
        local g = R(0.75, 1.15)
        for _, ox in ipairs({ 0, -w, w }) do
            local cx = x + ox
            if opt.pine then
                for k = 0, 5 do
                    local yy = h - th + k * th / 7
                    local ww = tw * (k + 1) / 6
                    dxDrawRectangle(cx - ww / 2, yy, ww, th / 6, col(shade(opt.c[1], g), shade(opt.c[2], g), shade(opt.c[3], g)))
                end
                dxDrawRectangle(cx - 2, h - th * 0.15, 4, th * 0.15, col(70, 50, 35))
            elseif opt.palm then
                dxDrawRectangle(cx - 2, h - th, 4, th, col(110, 90, 60))
                for k = -3, 3 do
                    dxDrawRectangle(cx + k * tw / 7 - tw / 14, h - th - 4 + math.abs(k) * 3, tw / 7, 6, col(60, 110, 55))
                end
            else
                dxDrawRectangle(cx - 2, h - th * 0.35, 4, th * 0.35, col(80, 60, 40))
                dxDrawRectangle(cx - tw / 2, h - th, tw, th * 0.7, col(shade(opt.c[1], g), shade(opt.c[2], g), shade(opt.c[3], g)))
                dxDrawRectangle(cx - tw / 3, h - th - th * 0.12, tw * 0.66, th * 0.2, col(shade(opt.c[1], g * 1.1), shade(opt.c[2], g * 1.1), shade(opt.c[3], g * 1.1)))
            end
        end
    end
end

-- line-side poles + a low fence / bushes (near layer)
local function poles(w, h, R, opt)
    local n = opt.count or 2
    for i = 0, n - 1 do
        local x = (i + R(0.1, 0.9)) * w / n
        dxDrawRectangle(x - 4, h * 0.02, 8, h * 0.98, col(90, 80, 70))
        dxDrawRectangle(x - 22, h * 0.08, 44, 5, col(80, 72, 62))
    end
    -- wires
    dxDrawRectangle(0, h * 0.1, w, 2, col(30, 30, 30, 200))
    dxDrawRectangle(0, h * 0.18, w, 1, col(30, 30, 30, 160))
    if opt.fence then
        for x = 0, w - 1, 12 do dxDrawRectangle(x, h * 0.78, 2, h * 0.22, col(110, 110, 110, 230)) end
        dxDrawRectangle(0, h * 0.8, w, 2, col(120, 120, 120, 230))
    end
    if opt.bush then
        for i = 1, opt.bush do
            local x, bw = R(0, w), R(20, 70)
            local c = opt.bushC or { 70, 95, 45 }
            for _, ox in ipairs({ 0, -w }) do
                dxDrawRectangle(x + ox, h * 0.82, bw, h * 0.18, col(c[1], c[2], c[3]))
            end
        end
    end
end

-- platform for station classes (near layer): edge, columns, name boards
local function platform(w, h, R, opt)
    dxDrawRectangle(0, h * 0.62, w, h * 0.38, col(150, 148, 140))
    dxDrawRectangle(0, h * 0.62, w, 4, col(230, 200, 40))
    local step = w / 7
    for i = 0, 6 do
        local x = i * step + step * 0.3
        dxDrawRectangle(x, 0, 14, h * 0.62, col(opt.col[1], opt.col[2], opt.col[3]))
        if i % 2 == 0 then
            dxDrawRectangle(x + 30, h * 0.2, 120, 26, col(22, 70, 160))
            dxDrawText("SUNLINE RAIL", x + 30, h * 0.2, x + 150, h * 0.2 + 26, col(240, 244, 250), 1, "default-bold", "center", "center")
        end
    end
    if opt.roof then dxDrawRectangle(0, 0, w, h * 0.06, col(60, 60, 64)) end
end

------------------------------------------------------------------ class definitions

CLASSES.ls_city = {
    ground = { 0.33, 0.31, 0.28 },
    far = function(w, h, R) skyline(w, h, R, { wMin = 14, wMax = 46, hMin = 0.15, hMax = 0.85, tint = { 150, 160, 175 }, cMin = 0.6, cMax = 1, lit = 0.3, gapMax = 3 }) end,
    mid = function(w, h, R)
        skyline(w, h, R, { wMin = 40, wMax = 110, hMin = 0.25, hMax = 0.6, tint = { 200, 175, 140 }, cMin = 0.7, cMax = 1, lit = 0.2, gapMin = 10, gapMax = 60, cell = 14 })
        trees(w, h, R, 9, { palm = true, hMin = 0.55, hMax = 0.95, wk = 0.5 })
    end,
    near = function(w, h, R) poles(w, h, R, { fence = true }) end,
}
CLASSES.ls_industrial = {
    ground = { 0.30, 0.28, 0.25 },
    far = function(w, h, R)
        skyline(w, h, R, { wMin = 40, wMax = 120, hMin = 0.08, hMax = 0.3, tint = { 140, 140, 135 }, cMin = 0.6, cMax = 0.95, lit = 0.08, gapMax = 10 })
        for i = 1, 4 do                                   -- cranes
            local x = R(0, w)
            dxDrawRectangle(x, h * 0.25, 6, h * 0.75, col(170, 120, 40))
            dxDrawRectangle(x - 40, h * 0.25, 90, 5, col(170, 120, 40))
        end
    end,
    mid = function(w, h, R)
        skyline(w, h, R, { wMin = 80, wMax = 200, hMin = 0.25, hMax = 0.5, tint = { 150, 150, 145 }, cMin = 0.6, cMax = 1, lit = 0.05, gapMin = 20, gapMax = 80, cell = 20 })
        for i = 1, 10 do                                  -- containers
            local x, c = R(0, w), ({ { 160, 60, 40 }, { 40, 90, 150 }, { 60, 120, 60 }, { 170, 150, 50 } })[math.floor(R(1, 4.99))]
            dxDrawRectangle(x, h * 0.78, 70, h * 0.22, col(c[1], c[2], c[3]))
        end
    end,
    near = function(w, h, R) poles(w, h, R, { fence = true }) end,
}
CLASSES.sf_city = {
    ground = { 0.32, 0.32, 0.31 },
    far = function(w, h, R)
        local hill = wave(w, R, 3)
        ridge(w, h, function(x) return h * (0.25 + 0.12 * hill(x)) end, 95, 110, 90)
        skyline(w, h, R, { wMin = 10, wMax = 36, hMin = 0.25, hMax = 0.7, tint = { 175, 175, 185 }, cMin = 0.65, cMax = 1, lit = 0.3, gapMax = 6, base = math.floor(h * 0.2) })
    end,
    mid = function(w, h, R)
        local x = 0
        while x < w do                                    -- painted victorian rows
            local bw, bh = R(36, 60), R(0.45, 0.75) * h
            local c = ({ { 200, 170, 150 }, { 160, 190, 200 }, { 210, 200, 160 }, { 190, 150, 170 } })[math.floor(R(1, 4.99))]
            dxDrawRectangle(x, h - bh, bw, bh, col(c[1], c[2], c[3]))
            dxDrawRectangle(x, h - bh - 6, bw, 6, col(110, 90, 80))
            windows(x, h - bh, bw, bh, R, 0.2, 14)
            x = x + bw + R(0, 6)
        end
        trees(w, h, R, 5, { hMin = 0.4, hMax = 0.7, c = { 60, 95, 55 } })
    end,
    near = function(w, h, R) poles(w, h, R, { fence = true }) end,
}
CLASSES.lv_city = {
    ground = { 0.52, 0.44, 0.33 },
    far = function(w, h, R)
        skyline(w, h, R, { wMin = 20, wMax = 70, hMin = 0.1, hMax = 0.95, tint = { 190, 170, 140 }, cMin = 0.6, cMax = 1, lit = 0.45, gapMin = 4, gapMax = 40 })
    end,
    mid = function(w, h, R)
        skyline(w, h, R, { wMin = 60, wMax = 160, hMin = 0.15, hMax = 0.35, tint = { 210, 190, 150 }, cMin = 0.7, cMax = 1, lit = 0.25, gapMin = 30, gapMax = 120, cell = 16 })
        trees(w, h, R, 6, { palm = true, hMin = 0.5, hMax = 0.85, wk = 0.5 })
    end,
    near = function(w, h, R) poles(w, h, R, { fence = true }) end,
}
CLASSES.countryside = {
    ground = { 0.33, 0.38, 0.20 },
    far = function(w, h, R)
        local a, b = wave(w, R, 4), wave(w, R, 3)
        ridge(w, h, function(x) return h * (0.35 + 0.15 * a(x)) end, 110, 130, 100)
        ridge(w, h, function(x) return h * (0.18 + 0.08 * b(x)) end, 85, 115, 60)
    end,
    mid = function(w, h, R)
        trees(w, h, R, 22, { hMin = 0.35, hMax = 0.8, c = { 65, 105, 50 } })
        for x = 0, w - 1, 24 do dxDrawRectangle(x, h * 0.86, 3, h * 0.14, col(120, 95, 70)) end   -- farm fence
        dxDrawRectangle(0, h * 0.88, w, 2, col(120, 95, 70))
    end,
    near = function(w, h, R) poles(w, h, R, { bush = 10 }) end,
}
CLASSES.forest = {
    ground = { 0.22, 0.30, 0.15 },
    far = function(w, h, R)
        local a = wave(w, R, 5)
        ridge(w, h, function(x) return h * (0.55 + 0.25 * a(x)) end, 70, 95, 70)
        ridge(w, h, function(x) return h * (0.3 + 0.1 * a(w - x)) end, 45, 75, 40)
    end,
    mid = function(w, h, R) trees(w, h, R, 45, { pine = true, hMin = 0.5, hMax = 1.0, wk = 0.4, c = { 40, 80, 40 } }) end,
    near = function(w, h, R)
        poles(w, h, R, { bush = 14, bushC = { 45, 75, 35 } })
        trees(w, h, R, 3, { pine = true, hMin = 0.8, hMax = 1.0, wk = 0.35, c = { 35, 70, 35 } })
    end,
}
CLASSES.desert = {
    ground = { 0.62, 0.50, 0.34 },
    far = function(w, h, R)
        local a = wave(w, R, 4)
        ridge(w, h, function(x) local v = a(x) return h * (0.2 + 0.25 * math.max(0, v)) end, 170, 120, 85)   -- mesas
        ridge(w, h, function(x) return h * (0.1 + 0.04 * a(w - x)) end, 190, 150, 105)
    end,
    mid = function(w, h, R)
        for i = 1, 12 do                                  -- cacti
            local x, ch = R(0, w), R(0.3, 0.7) * h
            dxDrawRectangle(x, h - ch, 6, ch, col(80, 110, 60))
            dxDrawRectangle(x - 10, h - ch * 0.7, 10, 5, col(80, 110, 60))
            dxDrawRectangle(x - 10, h - ch * 0.95, 5, ch * 0.3, col(80, 110, 60))
        end
        for i = 1, 8 do                                   -- rocks
            local x, rw = R(0, w), R(20, 60)
            dxDrawRectangle(x, h - rw * 0.4, rw, rw * 0.4, col(150, 110, 80))
        end
    end,
    near = function(w, h, R) poles(w, h, R, { bush = 5, bushC = { 130, 120, 70 } }) end,
}
CLASSES.bridge = {
    ground = { 0.14, 0.28, 0.38 },          -- water far below
    groundDepth = 25,                        -- the ground plane is this much lower
    far = function(w, h, R)
        local a = wave(w, R, 3)
        ridge(w, h, function(x) return h * (0.12 + 0.06 * a(x)) end, 110, 125, 120)
    end,
    near = function(w, h, R)                 -- truss
        for x = 0, w - 1, 64 do
            dxDrawRectangle(x, 0, 10, h, col(110, 80, 60))
            dxDrawLine(x, 0, x + 64, h, col(110, 80, 60), 6)
        end
        dxDrawRectangle(0, h * 0.75, w, 6, col(110, 80, 60))
        dxDrawRectangle(0, 0, w, 6, col(110, 80, 60))
    end,
}
CLASSES.tunnel = { ground = { 0.08, 0.08, 0.08 }, tunnel = 1 }
CLASSES.station_under = {
    ground = { 0.1, 0.1, 0.1 }, tunnel = 0.85,
    near = function(w, h, R) platform(w, h, R, { col = { 170, 165, 150 }, roof = true }) end,
}

-- composite station classes: "station:<region>", "station_hall:<region>"
local function stationClass(id)
    local kind, region = id:match("^(station[_%a]*):(.+)$")
    if not kind or not CLASSES[region] then return nil end
    local base = CLASSES[region]
    return {
        ground = { 0.5, 0.49, 0.46 },
        tunnel = kind == "station_hall" and 0.35 or 0,
        far = base.far, farSeed = region, mid = base.mid, midSeed = region,
        near = function(w, h, R) platform(w, h, R, { col = { 120, 125, 135 }, roof = kind == "station_hall" }) end,
    }
end

local function def(id) return CLASSES[id] or stationClass(id) or CLASSES.countryside end

------------------------------------------------------------------ texture cache

local cache = {}          -- [classId] = { far, mid, near, ground, groundDepth, tunnel }
local queue = {}          -- class ids waiting to be painted (painted inside onClientRender)
local empty

local function emptyTexture()
    -- a blank texture is fully transparent: the shader shows nothing for that layer
    if not empty then empty = dxCreateTexture(2, 2) or nil end
    return empty
end

local function seedOf(s)
    local n = 7
    for i = 1, #s do n = (n * 131 + s:byte(i)) % 2147483647 end
    return n
end

local function fileLayer(id, layer)
    local path = ("textures/%s_%s.png"):format(id:gsub(":", "_"), layer)
    if fileExists(path) then return dxCreateTexture(path, "argb", true, "wrap") end
end

local function paint(id, layer, painter, seedName)
    local L = Scenery.LAYERS[layer]
    local f = fileLayer(id, layer)
    if f then return f end
    if not painter then return emptyTexture() end
    local rt = dxCreateRenderTarget(L.w, L.h, true)
    if not rt then return emptyTexture() end
    dxSetRenderTarget(rt, true)
    painter(L.w, L.h, rng(seedOf((seedName or id) .. layer)))
    dxSetRenderTarget()
    local px = dxGetTexturePixels(rt)
    destroyElement(rt)
    local tex = px and dxCreateTexture(px, "argb", true, "wrap")
    return tex or emptyTexture()
end

local function build(id)
    local d = def(id)
    cache[id] = {
        far  = paint(id, "far",  d.far,  d.farSeed),
        mid  = paint(id, "mid",  d.mid,  d.midSeed),
        near = paint(id, "near", d.near),
        ground = d.ground or { 0.3, 0.3, 0.3 },
        groundDepth = d.groundDepth or 0,
        tunnel = d.tunnel or 0,
    }
end

-- the textures of a class, or nil while it is still being painted (next frame)
function Scenery.get(id)
    if cache[id] then return cache[id] end
    queue[id] = true
    return nil
end

addEventHandler("onClientRender", root, function()
    local id = next(queue)
    if not id then return end
    queue[id] = nil
    if not cache[id] then build(id) end      -- one class per frame
end, true, "high")

function Scenery.clear()
    for _, c in pairs(cache) do
        for _, k in ipairs({ "far", "mid", "near" }) do
            if isElement(c[k]) and c[k] ~= empty then destroyElement(c[k]) end
        end
    end
    cache = {}
end
