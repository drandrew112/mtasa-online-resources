-- shader_colors / c_presets.lua
--
-- Grading parameters (all optional in presets/overrides, missing = neutral):
--   exposure    brightness multiplier            1 = neutral
--   temperature -1 (cold) .. 1 (warm)            0
--   tint        -1 (magenta) .. 1 (green)        0
--   contrast    filmic S-curve strength 0..1     0
--   black       black point 0..0.2               0
--   white       white point 0.8..1               1
--   saturation  0 = greyscale                    1
--   vibrance    boosts dull colors only          0
--   lift        {r,g,b} shadow tint offsets      {0,0,0}
--   gain        {r,g,b} highlight tint           {1,1,1}

NEUTRAL = {
    exposure = 1, temperature = 0, tint = 0,
    contrast = 0, black = 0, white = 1,
    saturation = 1, vibrance = 0,
    lift = { 0, 0, 0 }, gain = { 1, 1, 1 },
}

-- How much of a preset's day look survives at full night (0 = neutral, 1 = same).
-- A preset may instead give an explicit `night` table.
NIGHT_KEEP = {
    exposure = 0.5, temperature = 0.6, tint = 0.6,
    contrast = 0.6, black = 0.4, white = 0.6,
    saturation = 0.45, vibrance = 0.5,
    lift = 0.6, gain = 0.5,
}

DEFAULT_PRESET    = "vivid"
DEFAULT_INTENSITY = 70

PRESETS = {
    { id = "off", label = "Off" },
    {
        id = "natural", label = "Natural",
        day = {
            contrast = 0.25, black = 0.03, white = 0.98,
            saturation = 1.12, vibrance = 0.3, temperature = 0.04,
        },
    },
    {
        id = "vivid", label = "Vivid",
        day = {
            exposure = 1.03, contrast = 0.5, black = 0.05, white = 0.96,
            saturation = 1.3, vibrance = 0.6,
            lift = { -0.01, 0, 0.015 }, gain = { 1.02, 1, 0.98 },
        },
    },
    {
        id = "cinematic", label = "Cinematic",
        day = {
            exposure = 0.98, contrast = 0.6, black = 0.05, white = 0.95,
            saturation = 0.95, vibrance = 0.35,
            lift = { -0.04, 0.01, 0.06 }, gain = { 1.08, 1, 0.88 },
        },
    },
    {
        id = "warm", label = "Warm",
        day = {
            temperature = 0.5, contrast = 0.35, black = 0.03, white = 0.97,
            saturation = 1.15, vibrance = 0.35, gain = { 1.05, 1, 0.93 },
        },
    },
    {
        id = "cold", label = "Cold",
        day = {
            temperature = -0.5, tint = 0.05, contrast = 0.4, black = 0.03, white = 0.97,
            saturation = 1.0, vibrance = 0.3, lift = { -0.02, 0, 0.04 },
        },
    },
}

PRESET_BY_ID = {}
for _, p in ipairs(PRESETS) do
    PRESET_BY_ID[p.id] = p
end

--------------------------------------------------------------------------------
-- parameter math
--------------------------------------------------------------------------------

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Fills every missing key from NEUTRAL; returns a new table.
function completeParams(p)
    local out = {}
    for k, v in pairs(NEUTRAL) do
        local src = p and p[k]
        if type(v) == "table" then
            src = type(src) == "table" and src or v
            out[k] = { tonumber(src[1]) or v[1], tonumber(src[2]) or v[2], tonumber(src[3]) or v[3] }
        else
            out[k] = tonumber(src) or v
        end
    end
    return out
end

-- a, b complete; t number or { key = t } table. Returns a new table.
function lerpParams(a, b, t)
    local out = {}
    for k, v in pairs(a) do
        local tk = type(t) == "table" and t[k] or t
        if type(v) == "table" then
            out[k] = { lerp(v[1], b[k][1], tk), lerp(v[2], b[k][2], tk), lerp(v[3], b[k][3], tk) }
        else
            out[k] = lerp(v, b[k], tk)
        end
    end
    return out
end

-- Overlays only the keys present in a partial table, weighted by t.
function overlayParams(base, partial, t)
    local out = completeParams(base)
    for k, v in pairs(partial) do
        local cur = out[k]
        if type(cur) == "table" and type(v) == "table" then
            for i = 1, 3 do
                local n = tonumber(v[i])
                if n then cur[i] = lerp(cur[i], n, t) end
            end
        elseif type(cur) == "number" and tonumber(v) then
            out[k] = lerp(cur, tonumber(v), t)
        end
    end
    return out
end

function paramsEqual(a, b)
    for k, v in pairs(a) do
        local w = b[k]
        if type(v) == "table" then
            for i = 1, 3 do
                if math.abs(v[i] - w[i]) > 1e-4 then return false end
            end
        elseif math.abs(v - w) > 1e-4 then
            return false
        end
    end
    return true
end

-- Complete { day, night } pair for a preset (both neutral for "off").
local cache = {}
function presetDayNight(id)
    if cache[id] then return cache[id][1], cache[id][2] end
    local p = PRESET_BY_ID[id]
    local neutral = completeParams(nil)
    local day = p and p.day and completeParams(p.day) or neutral
    local night = p and p.night and completeParams(p.night) or lerpParams(neutral, day, NIGHT_KEEP)
    cache[id] = { day, night }
    return day, night
end
