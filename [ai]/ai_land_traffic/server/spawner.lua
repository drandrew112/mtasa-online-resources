-- Spawning and despawning (server). New traffic only appears on the player's expected route
-- (server/route.lua), out of close view, up to a density target that drops while the player stands.
-- Vehicles beyond DESPAWN_RADIUS of every player, or that no player's camera sees, disappear.

Spawner = {}

local T = TRAFFIC
local random = math.random

local nearBuf = {}

local function isFree(x, y, z)
    for i = #nearBuf, 1, -1 do nearBuf[i] = nil end
    if #Agents.near(x, y, T.SPAWN_GAP, nearBuf) > 0 then return false end
    for i = #nearBuf, 1, -1 do nearBuf[i] = nil end
    local gap2 = T.SPAWN_GAP * T.SPAWN_GAP
    for _, o in ipairs(Obstacles.near(x, y, T.SPAWN_GAP, nearBuf)) do
        if (o.x - x) ^ 2 + (o.y - y) ^ 2 < gap2 and math.abs(o.z - z) < 6 then return false end
    end
    return true
end

local function trySpawn(p, area, minDist, visibleMin, players, now)
    local lane = Route.pick(area)
    if not lane then return false end
    local len = Geo.length(lane)
    local s = 1 + random() * (len - 2)
    local x, y, z = Geo.pose(lane, s, 0)
    if not x then return false end
    local dx, dy = x - p.x, y - p.y
    if dx * dx + dy * dy > T.SIM_RADIUS * T.SIM_RADIUS then return false end
    local min2 = minDist * minDist
    for _, q in ipairs(players) do
        if (x - q.x) ^ 2 + (y - q.y) ^ 2 + ((z - q.z) * 0.5) ^ 2 < min2 then return false end
    end
    local seen = Views.nearestSeeing(players, x, y, z + 1, now)
    if seen and seen < visibleMin then return false end
    if not isFree(x, y, z) then return false end
    local ag = Agents.spawn(lane, s, (Net.lspeed[lane] or T.SPEED_ROAD) * 0.6)
    return ag ~= nil
end

local countBuf = {}

function Spawner.update(players, now)
    if not Traffic.enabled then return end
    for _, p in ipairs(players) do
        if Agents.count >= T.MAX_AGENTS then return end
        local area = Route.areaOf(p, now)
        if area.target > 0 and #area.lanes > 0 then
            for i = #countBuf, 1, -1 do countBuf[i] = nil end
            local count = #Agents.near(p.x, p.y, T.SIM_RADIUS, countBuf)
            if count < area.target then
                local empty = count < area.target * 0.4
                local minDist = empty and T.SPAWN_MIN_DIST_EMPTY or T.SPAWN_MIN_DIST
                local visibleMin = empty and T.SPAWN_MIN_DIST or T.SPAWN_VISIBLE_MIN
                local made = 0
                for _ = 1, T.SPAWN_PER_PLAYER * 3 do
                    if made >= T.SPAWN_PER_PLAYER or count + made >= area.target then break end
                    if trySpawn(p, area, minDist, visibleMin, players, now) then made = made + 1 end
                end
            end
        end
    end
end

function Spawner.cleanup(players, now)
    local d2 = T.DESPAWN_RADIUS * T.DESPAWN_RADIUS
    local cull2 = T.CULL_MIN_DIST * T.CULL_MIN_DIST
    for _, ag in pairs(Agents.list) do
        local best = math.huge
        for _, p in ipairs(players) do
            local d = (ag.x - p.x) ^ 2 + (ag.y - p.y) ^ 2
            if d < best then best = d end
        end
        if best > d2 then
            Agents.destroy(ag)
        elseif ag.atEnd and ag.v < 0.1 and best > 80 * 80 then
            Agents.destroy(ag)
        elseif ag.stopSince and now - ag.stopSince > 120000 and best > 150 * 150 then
            Agents.destroy(ag)
        elseif Views.anySees(players, ag.x, ag.y, ag.z + 1, now) then
            ag.hiddenSince = nil
        else
            -- behind / beside every camera: gone once it stayed out of sight for a while
            ag.hiddenSince = ag.hiddenSince or now
            if best > cull2 and now - ag.hiddenSince >= T.CULL_AFTER then Agents.destroy(ag) end
        end
    end
    Route.cleanup()
end
