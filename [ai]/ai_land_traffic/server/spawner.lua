-- Spawning and despawning (server). Traffic only exists within SIM_RADIUS of active players; each
-- player's surroundings are filled up to a density target from the lane length around them.

Spawner = {}

local T = TRAFFIC
local random, floor, min, sqrt = math.random, math.floor, math.min, math.sqrt
local targets = {}   -- [player] = { target, cells, total, at }

local function areaOf(p, now)
    local t = targets[p.el]
    if t and now < t.at and (t.x - p.x) ^ 2 + (t.y - p.y) ^ 2 < 40 * 40 then return t end
    local cells = Net.cellsAround(p.x, p.y, T.SIM_RADIUS)
    local total = 0
    for _, c in ipairs(cells) do total = total + c.length end
    t = { cells = cells, total = total, x = p.x, y = p.y, at = now + 2000,
          target = min(T.MAX_PER_PLAYER, floor(total / T.LANE_PER_VEHICLE)) }
    targets[p.el] = t
    return t
end

local function pickLane(area)
    local r = random() * area.total
    for _, c in ipairs(area.cells) do
        r = r - c.length
        if r <= 0 then return c.lanes[random(#c.lanes)] end
    end
    local c = area.cells[#area.cells]
    return c and c.lanes[random(#c.lanes)]
end

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

local function trySpawn(p, area, minDist, players)
    local lane = pickLane(area)
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
    if not isFree(x, y, z) then return false end
    local ag = Agents.spawn(lane, s, (Net.lspeed[lane] or T.SPEED_ROAD) * 0.6)
    return ag ~= nil
end

local countBuf = {}

function Spawner.update(players, now)
    if not Traffic.enabled then return end
    for _, p in ipairs(players) do
        if Agents.count >= T.MAX_AGENTS then return end
        local area = areaOf(p, now)
        if area.target > 0 and #area.cells > 0 then
            for i = #countBuf, 1, -1 do countBuf[i] = nil end
            local count = #Agents.near(p.x, p.y, T.SIM_RADIUS, countBuf)
            if count < area.target then
                local minDist = count < area.target * 0.4 and T.SPAWN_MIN_DIST_EMPTY or T.SPAWN_MIN_DIST
                local made = 0
                for _ = 1, T.SPAWN_PER_PLAYER * 3 do
                    if made >= T.SPAWN_PER_PLAYER or count + made >= area.target then break end
                    if trySpawn(p, area, minDist, players) then made = made + 1 end
                end
            end
        end
    end
end

function Spawner.cleanup(players, now)
    local d2 = T.DESPAWN_RADIUS * T.DESPAWN_RADIUS
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
        end
    end
    for pl in pairs(targets) do
        if not isElement(pl) then targets[pl] = nil end
    end
end
