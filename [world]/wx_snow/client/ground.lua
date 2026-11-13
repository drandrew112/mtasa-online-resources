-- wx_snow :: ground snow (DESIGN.md 3)
--
-- One layered shader per SNOW.CATEGORIES entry (same fx, other parameters). The generic one
-- takes "*", every other category takes its textures away from the generic one and from the
-- categories before it, so a texture never gets two of our layers. EXCLUDE is removed from all.
-- The shaders exist while there is something to draw (level / coverage / wet > 0, quality not
-- off). In an interior (int ~= 0, same texture names as outside) coverage and wet are set to 0,
-- so the layers clip every pixel; the shaders stay, so stepping outside shows the snow at once.
-- maps_loader indoor zones are masked per pixel (boxes), the world around them stays snowy.

GROUND = {
    shaders = {},            -- category index -> shader
    grass = nil,
    noise = nil,
    attached = false,
    error = nil,             -- "unsupported" when the fx cannot be created (no ps_3_0)
    technique = nil,
    grassMode = "keep",
    variant = SNOW.SHADER,   -- "v2" (fx/snow_world.fx) | "v1" (fx/snow_world_v1.fx), /snow shader
}

local last = {}  -- category index -> last parameter key (skip unchanged dxSetShaderValue)

local function destroyAll()
    for i, sh in pairs(GROUND.shaders) do
        if isElement(sh) then destroyElement(sh) end
        GROUND.shaders[i] = nil
    end
    if isElement(GROUND.grass) then destroyElement(GROUND.grass) end
    GROUND.grass = nil
    GROUND.grassKey = nil
    GROUND.attached = false
    GROUND.grassMode = "keep"
end

-- a category without a shader (lowSkip on Low quality): its textures get no snow at all, so the
-- generic "*" shader gives them up as well
local function applyPatterns()
    local cats = SNOW.CATEGORIES
    for i, cat in ipairs(cats) do
        local sh = GROUND.shaders[i]
        for _, pat in ipairs(cat.patterns) do
            if sh then
                engineApplyShaderToWorldTexture(sh, pat)
                -- earlier categories (generic first) give these textures up
                for j = 1, i - 1 do
                    if GROUND.shaders[j] then engineRemoveShaderFromWorldTexture(GROUND.shaders[j], pat) end
                end
            elseif GROUND.shaders[1] then
                engineRemoveShaderFromWorldTexture(GROUND.shaders[1], pat)
            end
        end
    end
    for i in ipairs(cats) do
        if GROUND.shaders[i] then
            for _, ex in ipairs(SNOW.EXCLUDE) do engineRemoveShaderFromWorldTexture(GROUND.shaders[i], ex) end
        end
    end
end

-- F1 distance tiers (Low quality: closer)
local function setLod(sh)
    local L = SNOW.LOD
    local k = CS.quality == "low" and L.LOW_SCALE or 1
    dxSetShaderValue(sh, "gLodRoof", L.roof[1] * k, L.roof[2] * k)
    dxSetShaderValue(sh, "gLodRoad", L.road[1] * k, L.road[2] * k)
    dxSetShaderValue(sh, "gLodNoise", L.noise[1] * k, L.noise[2] * k, L.noise[3] * k)
end

local function shaderFile()
    return GROUND.variant == "v1" and "fx/snow_world_v1.fx" or "fx/snow_world.fx"
end

local FAR = { -99999, -99999, -99999 }
local FAR2 = { -99998, -99998, -99998 }

local function setBoxes(sh)
    for i = 0, 3 do
        local b = CS.nearBoxes[i + 1]
        if b then
            dxSetShaderValue(sh, "gBox" .. i .. "Min", b[1], b[2], b[3])
            -- the top 0.25 m stays outside, so a roof right on the box top keeps its snow
            dxSetShaderValue(sh, "gBox" .. i .. "Max", b[4], b[5], b[6] - 0.25)
        else
            dxSetShaderValue(sh, "gBox" .. i .. "Min", FAR[1], FAR[2], FAR[3])
            dxSetShaderValue(sh, "gBox" .. i .. "Max", FAR2[1], FAR2[2], FAR2[3])
        end
    end
end

local function refreshBoxes()
    for _, sh in pairs(GROUND.shaders) do setBoxes(sh) end
end

local function attach()
    if GROUND.attached or GROUND.error then return GROUND.attached end
    if not GROUND.noise then
        GROUND.noise = dxCreateTexture("tex/noise.png", "argb", true, "wrap")
    end
    if not GROUND.macro and GROUND.variant ~= "v1" then
        GROUND.macro = dxCreateTexture("tex/macro.png", "argb", true, "wrap")
    end
    for i, cat in ipairs(SNOW.CATEGORIES) do
      if not ((cat.lowSkip and (CS.quality == "low" or GROUND.noFoliage)) or (i == 1 and GROUND.noGeneric)) then
        -- priority 0, unlimited distance (far hills must be white too; cat.maxDist limits e.g. the
        -- foliage), layered, world + objects
        local maxDist = cat.maxDist or 0
        if i == 1 and GROUND.genericDist ~= nil then maxDist = GROUND.genericDist end
        local sh, tec = dxCreateShader(shaderFile(), 0, maxDist, true, "world,object")
        if not sh then
            GROUND.error = "unsupported"
            destroyAll()
            outputDebugString("[wx_snow] snow_world.fx could not be created (ps_3_0 / vs_3_0 needed)", 2)
            snowChanged("error")
            return false
        end
        GROUND.technique = tec
        GROUND.shaders[i] = sh
        dxSetShaderValue(sh, "gNoiseTex", GROUND.noise)
        ROOF.apply(sh)
        ROAD.apply(sh)
        if GROUND.variant ~= "v1" then
            setLod(sh)
            if GROUND.macro then dxSetShaderValue(sh, "gMacroTex", GROUND.macro) end
        end
      end
    end
    applyPatterns()
    GROUND.attached = true
    last = {}
    refreshBoxes()
    return true
end

function GROUND.detach()
    destroyAll()
end

-- /snowtest cost: switch parts off to see what the fixed cost is made of
function GROUND.costMode(disabled, noFoliage, genericDist, noGeneric)
    GROUND.disabled, GROUND.noFoliage = disabled and true or false, noFoliage and true or false
    GROUND.genericDist, GROUND.noGeneric = genericDist, noGeneric and true or false
    destroyAll()
    last = {}
    snowChanged("cost")
end

-- /snow shader v1|v2 (own client, for A/B measuring)
function GROUND.setVariant(v)
    if v ~= "v1" and v ~= "v2" then return false end
    if v == GROUND.variant then return true end
    GROUND.variant = v
    destroyAll()
    last = {}
    snowChanged("shader")
    return true
end

-- GTA grass (tx*): white / hidden per level
-- Frost follows the ground coverage (white blades on bare ground looked wrong): about 1.1 x the
-- coverage up to 0.8, level "hide" shrinks the blades away between coverage 0.6 and 0.8 (buried).
-- (2026-11-13 later: still too bright in game -> cap 0.6, factor 0.85, darker frost in snow_grass.fx)
local GRASS_WHITE_MAX, GRASS_WHITE_K = 0.6, 0.85
local function smooth01(a, b, x)
    local t = math.max(0, math.min(1, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)
end

local function setGrass(mode, cov, warm)
    if mode == "keep" or cov < 0.03 then
        GROUND.grassMode = "keep"
        if isElement(GROUND.grass) then destroyElement(GROUND.grass) end
        GROUND.grass = nil
        return
    end
    if not GROUND.grass then
        GROUND.grass = dxCreateShader("fx/snow_grass.fx", 5, 0, false, "world,object")
        if not GROUND.grass then return end
        for _, pat in ipairs(SNOW.GRASS_PATTERNS) do engineApplyShaderToWorldTexture(GROUND.grass, pat) end
    end
    local white = math.min(GRASS_WHITE_MAX, cov * GRASS_WHITE_K)
    local hide = mode == "hide" and smooth01(0.6, 0.8, cov) or 0
    local key = ("%.3f|%.3f|%.2f"):format(white, hide, warm)
    GROUND.grassMode = mode
    if GROUND.grassKey == key then return end
    GROUND.grassKey = key
    dxSetShaderValue(GROUND.grass, "gWhite", white)
    dxSetShaderValue(GROUND.grass, "gHide", hide)
    dxSetShaderValue(GROUND.grass, "gSunWarm", warm)
end

-- 0..1 brightness of the snow by game hour (GTA's vertex light already darkens at night;
-- this only takes the edge off the white at dusk)
function snowDayBrightness()
    local h, m = getTime()
    local t = h + m / 60
    if t >= 7 and t <= 19 then return 1 end
    if t >= 22 or t <= 4.5 then return 0.82 end
    if t < 7 then return 0.82 + (t - 4.5) / 2.5 * 0.18 end
    return 1 - (t - 19) / 3 * 0.18
end


-- sun direction (world, towards the sun; the moon at night), sunrise / sunset warmth and the horizon
-- colour the wet roads mirror. Only the look of the v2 shader uses them.
local function skyParams()
    local h, m = getTime()
    local t = h + m / 60
    local day = t >= 6 and t <= 18
    local ang = (t - 6) / 12 * math.pi
    local el = day and math.max(0.12, math.sin(ang)) or 0.4
    local az = day and ang or 1.2
    local ce = math.sqrt(math.max(0, 1 - el * el))
    local warm = math.max(0, 1 - math.abs(t - 6.5) / 1.3, 1 - math.abs(t - 18.5) / 1.8)
    local r, g, b = 200, 215, 235
    local ok, _, _, _, r2, g2, b2 = pcall(getSkyGradient)
    if ok and r2 then r, g, b = r2, g2, b2 end
    return math.cos(az) * ce, math.sin(az) * ce, el, warm, r / 255, g / 255, b / 255
end

local function wanted()
    if CS.quality == "off" or GROUND.error or GROUND.disabled then return false end
    local lvl, cov, p = snowCurrent()
    return lvl > 0 or cov > 0.001 or (p.wet or 0) > 0
end

function GROUND.update(force)
    if not wanted() then
        if GROUND.attached then GROUND.detach() end
        return
    end
    if not GROUND.attached and not attach() then return end

    local lvl, cov, p = snowCurrent()
    local wet = p.wet
    if CS.interior then cov, wet = 0, 0 end
    GROUND.active = cov > 0.001 or wet > 0
    local bright = snowDayBrightness()
    local sparkle = CS.quality == "high" and 1 or 0
    local dbg = CS.debug and 1 or 0
    local sx, sy, sz, warm, skr, skg, skb = skyParams()
    local skyKey = ("%.2f|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f"):format(sx, sy, sz, warm, skr, skg, skb)
    local skyChanged = force or skyKey ~= last.sky
    last.sky = skyKey
    setGrass(p.grass, cov, warm)
    for i, cat in ipairs(SNOW.CATEGORIES) do
      local sh = GROUND.shaders[i]
      if sh then
        if skyChanged and GROUND.variant ~= "v1" then
            dxSetShaderValue(sh, "gSunDir", sx, sy, sz)
            dxSetShaderValue(sh, "gSunWarm", warm)
            dxSetShaderValue(sh, "gSky", skr, skg, skb)
        end
        local c = math.max(0, math.min(1, cov * cat.mult))
        local key = ("%.4f|%.3f|%.3f|%d|%d"):format(c, wet, bright, sparkle, dbg)
        if force or last[i] ~= key then
            last[i] = key
            dxSetShaderValue(sh, "gCoverage", c)
            dxSetShaderValue(sh, "gWet", wet)
            -- more snow -> it also stays on steeper surfaces
            dxSetShaderValue(sh, "gUpLo", cat.upLo - 0.22 * c)
            dxSetShaderValue(sh, "gUpHi", cat.upHi - 0.12 * c)
            dxSetShaderValue(sh, "gRoad", cat.road)
            dxSetShaderValue(sh, "gSparkle", sparkle)
            dxSetShaderValue(sh, "gBright", bright)
            dxSetShaderValue(sh, "gDebug", CS.interior and 0 or dbg)
            dxSetShaderValue(sh, "gDebugColor", cat.debug[1], cat.debug[2], cat.debug[3])
        end
      end
    end
end

snowOnChange(function(reason)
    if reason == "boxes" then return refreshBoxes() end
    if reason == "roofmap" then
        for _, sh in pairs(GROUND.shaders) do ROOF.apply(sh) end
        return
    end
    if reason == "roadmap" then
        for _, sh in pairs(GROUND.shaders) do ROAD.apply(sh) end
        return
    end
    -- quality changes the shader set (Low has no foliage layer) and the LOD distances
    if reason == "quality" then destroyAll() end
    last = {}
    GROUND.update(true)
end)

SNOW_COMMANDS.shader = function(a)
    local ok = GROUND.setVariant(a.value)
    outputConsole(("[wx_snow] ground shader: %s%s"):format(tostring(GROUND.variant), ok and "" or " (usage: /snow shader v1|v2)"))
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- coverage changes slowly; 0.5 s steps are invisible
    setTimer(function() GROUND.update(false) end, 500, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function() destroyAll() end)
