-- wx_snow :: fog, colour grading, wind sound (DESIGN.md 7)
--
-- Fog: drawdistance:setFogOverride("wx_snow", m) (drawdistance re-applies its own fog every 2 s,
-- a plain setFogDistance would be overwritten); without drawdistance setFogDistance directly.
-- Colour: shader_colors:pushColorOverride("wx_snow", level.grade). Both only outdoors.

ENV = { fog = nil, fogApplied = nil, grade = nil, sound = nil, volume = 0 }

local running = snowResourceRunning

local function setFog(distance)
    if ENV.fogApplied == distance then return end
    ENV.fogApplied = distance
    if running("drawdistance") then
        pcall(function() exports.drawdistance:setFogOverride("wx_snow", distance or false) end)
    elseif distance then
        setFogDistance(distance)
    else
        resetFogDistance()
    end
end

-- fadeMs: slow for a level change, quick when going in / out
local function setGrade(level, grade, fadeMs)
    if not running("shader_colors") then ENV.grade = nil return end
    local key = grade and level or nil
    if ENV.grade == key then return end
    ENV.grade = key
    if grade then
        pcall(function() exports.shader_colors:pushColorOverride("wx_snow", grade, 10, fadeMs) end)
    else
        pcall(function() exports.shader_colors:removeColorOverride("wx_snow", fadeMs) end)
    end
end

local function update(dt)
    local lvl, _, p = snowCurrent()
    local on = snowEnabled() and lvl > 0
    local placeChanged = ENV.wasIndoor ~= CS.indoor
    ENV.wasIndoor = CS.indoor

    -- fog: glides to the target (m per second), so a level change is not a jump
    local target = on and p.fog or nil
    if target then
        -- coming outside (or snow just started): straight to the target, no visible glide
        local cur = ENV.fog or target
        local step = math.max(20, math.abs(cur - target) * 0.5) * dt
        if cur > target then cur = math.max(target, cur - step) else cur = math.min(target, cur + step) end
        ENV.fog = cur
        setFog(math.floor(cur / 5 + 0.5) * 5)
    else
        ENV.fog = nil
        setFog(nil)
    end

    setGrade(lvl, on and p.grade or nil, placeChanged and 300 or 4000)

    -- wind loop (quieter under a roof, off indoors)
    local vol = on and (p.windVol or 0) * (CS.covered and 0.45 or 1) * 0.6 or 0
    ENV.volume = ENV.volume + (vol - ENV.volume) * math.min(1, dt * 0.8)
    if ENV.volume > 0.005 then
        if not isElement(ENV.sound) then
            ENV.sound = playSound("sounds/wind_loop.wav", true)
        end
        if ENV.sound then setSoundVolume(ENV.sound, ENV.volume) end
    elseif isElement(ENV.sound) then
        destroyElement(ENV.sound)
        ENV.sound = nil
    end
end

local lastTick = getTickCount()
addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(function()
        local tick = getTickCount()
        update(math.min(1, (tick - lastTick) / 1000))
        lastTick = tick
    end, 200, 0)
end)

-- drawdistance / shader_colors restarted: send our values again
addEventHandler("onClientResourceStart", root, function(res)
    local name = getResourceName(res)
    if name == "drawdistance" then ENV.fogApplied = false end
    if name == "shader_colors" then ENV.grade = nil end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    -- overrides are dropped by drawdistance / shader_colors when we stop
    if not running("drawdistance") and ENV.fogApplied then resetFogDistance() end
end)
