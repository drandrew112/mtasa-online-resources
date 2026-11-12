-- wx_snow :: server state
--
-- Effective level = /snow global override, else the weekly value (v_weekly custom.snow,
-- { level, dynamic }), with the dynamic week variation on top. Only level changes go to the
-- clients ({ level, from, at } + the server clock); they compute the coverage themselves
-- (shared/coverage.lua).

SSTATE = {
    weekly = { level = 0, dynamic = false },
    weekStart = 0,
    override = nil,          -- { level, by }
    state = { level = 0, from = 0, at = 0 },
    ready = {},              -- player -> true (client side is up)
    weatherBefore = nil,     -- GTA weather before the snow changed it
}

local function now() return getRealTime().timestamp end

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

-------------------------------------------------------------------------------- weekly value

local function readWeekly()
    if not running("v_weekly") then
        SSTATE.weekly = { level = 0, dynamic = false }
        return
    end
    local ok, ws, data = pcall(function() return exports.v_weekly:getCurrentWeek() end)
    local v = ok and type(data) == "table" and type(data.custom) == "table" and data.custom[SNOW.WEEK_KEY] or nil
    v = type(v) == "table" and v or {}
    local _, lvl = snowLevelParams(v.level)
    SSTATE.weekly = { level = lvl, dynamic = v.dynamic == true }
    SSTATE.weekStart = ok and tonumber(ws) or 0
end

-- -> level, source ("override" | "weekly" | "dynamic")
function snowTargetLevel()
    if SSTATE.override then return SSTATE.override.level, "override" end
    local w = SSTATE.weekly
    if w.dynamic and w.level > 0 then
        return (snowDynamicLevel(w.level, SSTATE.weekStart, now())), "dynamic"
    end
    return w.level, "weekly"
end

-------------------------------------------------------------------------------- weather

local function applyWeather(level)
    local p = snowLevelParams(level)
    if p.weather then
        if SSTATE.weatherBefore == nil then SSTATE.weatherBefore = getWeather() end
        if getWeather() ~= p.weather then setWeatherBlended(p.weather) end
    elseif SSTATE.weatherBefore ~= nil then
        setWeatherBlended(SSTATE.weatherBefore)
        SSTATE.weatherBefore = nil
    end
end

-------------------------------------------------------------------------------- sync

local function payload()
    return SSTATE.state, now()
end

local function broadcast()
    local list = {}
    for p in pairs(SSTATE.ready) do
        if isElement(p) then list[#list + 1] = p else SSTATE.ready[p] = nil end
    end
    if #list > 0 then
        local st, t = payload()
        triggerClientEvent(list, "wx_snow:state", resourceRoot, st, t)
    end
end

-- re-evaluates the target level; `instant` jumps the coverage
function snowRefresh(instant)
    local level, source = snowTargetLevel()
    local t = now()
    if level ~= SSTATE.state.level or instant then
        local old = SSTATE.state
        SSTATE.state = snowStateChange(old, level, t, instant)
        outputServerLog(("[wx_snow] level %d -> %d (%s%s), coverage %.2f -> %.2f"):format(
            old.level, level, source, instant and ", instant" or "", snowCoverageAt(old, t), snowLevelParams(level).cover))
        applyWeather(level)
        broadcast()
    end
end

addEvent("wx_snow:hello", true)
addEventHandler("wx_snow:hello", resourceRoot, function()
    if not client then return end
    SSTATE.ready[client] = true
    local st, t = payload()
    triggerClientEvent(client, "wx_snow:state", resourceRoot, st, t)
end)

addEventHandler("onPlayerQuit", root, function() SSTATE.ready[source] = nil end)

-------------------------------------------------------------------------------- weekly changes

addEvent("onWeeklyChanged")
addEventHandler("onWeeklyChanged", root, function(ws)
    local before = SSTATE.weekStart
    readWeekly()
    -- a new week ends the /snow global override
    if SSTATE.override and tonumber(ws) and before ~= 0 and tonumber(ws) ~= before then
        outputServerLog("[wx_snow] new week: /snow global override cleared")
        SSTATE.override = nil
    end
    snowRefresh(false)
end)

addEventHandler("onResourceStart", root, function(res)
    if getResourceName(res) == "v_weekly" then
        setTimer(function() readWeekly(); snowRefresh(false) end, 2000, 1)
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    readWeekly()
    -- start at the weekly level's coverage (no 20 minute build-up after a restart)
    local level = snowTargetLevel()
    SSTATE.state = snowStateChange(nil, level, now(), true)
    applyWeather(level)
    -- dynamic weeks: check the segment every minute
    setTimer(function() snowRefresh(false) end, 60000, 0)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    if SSTATE.weatherBefore ~= nil then setWeather(SSTATE.weatherBefore) end
end)

-------------------------------------------------------------------------------- exports

function getSnowLevel()
    return SSTATE.state.level
end

function getSnowCoverage()
    return snowCoverageAt(SSTATE.state, now())
end

function isSnowing()
    return SSTATE.state.level > 0
end

-- level 0..5 or false/nil = clear the override (back to the weekly value)
function setSnowOverride(level, instant, by)
    if level == nil or level == false then
        SSTATE.override = nil
    else
        local _, lvl = snowLevelParams(level)
        SSTATE.override = { level = lvl, by = tostring(by or (sourceResource and getResourceName(sourceResource)) or "server") }
    end
    snowRefresh(instant == true)
    return true
end

function snowInfo()
    local level, source = snowTargetLevel()
    local t = now()
    return {
        level = SSTATE.state.level, target = level, source = source,
        coverage = snowCoverageAt(SSTATE.state, t), eta = snowCoverageEta(SSTATE.state, t),
        weekly = SSTATE.weekly.level, dynamic = SSTATE.weekly.dynamic,
        override = SSTATE.override and SSTATE.override.level or false,
        overrideBy = SSTATE.override and SSTATE.override.by or false,
        weather = getWeather(),
    }
end
