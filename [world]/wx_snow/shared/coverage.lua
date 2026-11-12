-- wx_snow :: coverage math (server + client agree on it, so only level changes are synced)
--
-- A state is { level = 0..5, from = coverage when it changed, at = unix seconds of the change }.
-- The ground coverage moves from `from` toward the level's cover at ACCUM_MIN / MELT_MIN speed.

function snowCoverageAt(state, now)
    if type(state) ~= "table" then return 0 end
    local p = snowLevelParams(state.level)
    local target = p.cover
    local from = tonumber(state.from) or 0
    local dt = math.max(0, (tonumber(now) or 0) - (tonumber(state.at) or 0))
    if target >= from then
        return math.min(target, from + dt / (SNOW.ACCUM_MIN * 60))
    end
    return math.max(target, from - dt / (SNOW.MELT_MIN * 60))
end

-- seconds until the coverage reaches its target (0 = there)
function snowCoverageEta(state, now)
    local p = snowLevelParams(state.level)
    local cur = snowCoverageAt(state, now)
    local diff = math.abs(p.cover - cur)
    if diff < 0.0005 then return 0 end
    return diff * (p.cover > cur and SNOW.ACCUM_MIN or SNOW.MELT_MIN) * 60
end

-- new state for a level change at `now`, starting from the current coverage of `old`
function snowStateChange(old, level, now, instant)
    local p, lvl = snowLevelParams(level)
    local from = instant and p.cover or snowCoverageAt(old, now)
    return { level = lvl, from = from, at = now }
end

-- small deterministic hash -> 0..1 (dynamic weeks)
local function hash01(a, b)
    local h = (math.floor(a) * 73856093 + math.floor(b) * 19349663) % 2147483647
    h = (h * 48271) % 2147483647
    h = (h * 48271) % 2147483647
    return h / 2147483647
end

-- dynamic week level: base level moved by one of DYNAMIC_STEPS per segment (never below 1, so a snow
-- week always snows a bit). base 0 stays 0.
function snowDynamicLevel(base, weekStart, now)
    base = math.floor(tonumber(base) or 0)
    if base <= 0 then return 0 end
    local seg = math.floor(math.max(0, now - (weekStart or 0)) / (SNOW.DYNAMIC_SEGMENT_H * 3600))
    local steps = SNOW.DYNAMIC_STEPS
    local step = steps[math.floor(hash01(weekStart or 0, seg) * #steps) + 1] or 0
    return math.max(1, math.min(SNOW.MAX_LEVEL, base + step)), seg
end
