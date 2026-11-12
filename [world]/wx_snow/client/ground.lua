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
}

local last = {}  -- category index -> last parameter key (skip unchanged dxSetShaderValue)

local function destroyAll()
    for i, sh in pairs(GROUND.shaders) do
        if isElement(sh) then destroyElement(sh) end
        GROUND.shaders[i] = nil
    end
    if isElement(GROUND.grass) then destroyElement(GROUND.grass) end
    GROUND.grass = nil
    GROUND.attached = false
    GROUND.grassMode = "keep"
end

local function applyPatterns()
    local cats = SNOW.CATEGORIES
    for i, cat in ipairs(cats) do
        local sh = GROUND.shaders[i]
        for _, pat in ipairs(cat.patterns) do
            engineApplyShaderToWorldTexture(sh, pat)
            -- earlier categories (generic first) give these textures up
            for j = 1, i - 1 do engineRemoveShaderFromWorldTexture(GROUND.shaders[j], pat) end
        end
    end
    for i in ipairs(cats) do
        for _, ex in ipairs(SNOW.EXCLUDE) do engineRemoveShaderFromWorldTexture(GROUND.shaders[i], ex) end
    end
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
    for i in ipairs(SNOW.CATEGORIES) do
        -- priority 0, unlimited distance (far hills must be white too), layered, world + objects
        local sh, tec = dxCreateShader("fx/snow_world.fx", 0, 0, true, "world,object")
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

-- GTA grass (tx*): white / hidden per level
local function setGrass(mode)
    if mode == GROUND.grassMode then return end
    GROUND.grassMode = mode
    if mode == "keep" then
        if isElement(GROUND.grass) then destroyElement(GROUND.grass) end
        GROUND.grass = nil
        return
    end
    if not GROUND.grass then
        GROUND.grass = dxCreateShader("fx/snow_grass.fx", 5, 0, false, "world,object")
        if not GROUND.grass then return end
        for _, pat in ipairs(SNOW.GRASS_PATTERNS) do engineApplyShaderToWorldTexture(GROUND.grass, pat) end
    end
    dxSetShaderValue(GROUND.grass, "gWhite", mode == "white" and 0.85 or 0)
    dxSetShaderValue(GROUND.grass, "gHide", mode == "hide" and 1 or 0)
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


local function wanted()
    if CS.quality == "off" or GROUND.error then return false end
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
    setGrass(cov > 0.15 and p.grass or "keep")
    local bright = snowDayBrightness()
    local sparkle = CS.quality == "high" and 1 or 0
    local dbg = CS.debug and 1 or 0
    for i, cat in ipairs(SNOW.CATEGORIES) do
        local sh = GROUND.shaders[i]
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
    last = {}
    GROUND.update(true)
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- coverage changes slowly; 0.5 s steps are invisible
    setTimer(function() GROUND.update(false) end, 500, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function() destroyAll() end)
