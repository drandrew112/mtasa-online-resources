-- Ped traffic (server): sidewalk walkers around players in built-up areas, and the removal of walkers / adopted
-- drivers nobody needs any more. Scripted peds are never touched here.
--
-- Built-up area = at least SETTLEMENT_MIN metres of navmesh sidewalk (WALK_KINDS edges) within SETTLEMENT_RADIUS of
-- the player. Density = sidewalk length near the player / SIDEWALK_PER_PED, capped by MAX_PER_PLAYER. Players share
-- one budget: a spawn point must be under the cap of every player near it.

PedTraffic = { enabled = AIPEDS.TRAFFIC_ENABLED, cache = {} }   -- cache[player] = { x, y, z, t, edges, total, local, target }

local T = AIPEDS
local random, sqrt, floor = math.random, math.sqrt, math.floor

local function nightFactor()
    local h = getTime()
    if T.NIGHT_FROM > T.NIGHT_TO then
        if h >= T.NIGHT_FROM or h < T.NIGHT_TO then return T.NIGHT_FACTOR end
    elseif h >= T.NIGHT_FROM and h < T.NIGHT_TO then
        return T.NIGHT_FACTOR
    end
    return 1
end

-- sidewalks around the player (cached until it moves EDGE_CACHE_MOVE or the cache gets old)
local function areaOf(pl, now)
    local c = PedTraffic.cache[pl.el]
    if c and now - c.t < T.EDGE_CACHE_AGE and (c.x - pl.x) ^ 2 + (c.y - pl.y) ^ 2 < T.EDGE_CACHE_MOVE ^ 2 then return c end
    local edges = Nav.edgesNear(pl.x, pl.y, pl.z, T.SPAWN_MAX_DIST + 10)
    local settle, spawnable = 0, 0
    for _, e in ipairs(edges) do
        if e.distance <= T.SETTLEMENT_RADIUS then settle = settle + e.length end
        spawnable = spawnable + e.length
    end
    c = { x = pl.x, y = pl.y, z = pl.z, t = now, edges = edges, settle = settle, total = spawnable }
    if settle < T.SETTLEMENT_MIN then
        c.target = 0
    else
        c.target = math.min(T.MAX_PER_PLAYER, floor(spawnable / T.SIDEWALK_PER_PED * nightFactor() + 0.5))
    end
    PedTraffic.cache[pl.el] = c
    return c
end

-- traffic walkers within r of a point
local function countNear(x, y, r, kinds)
    local n, r2 = 0, r * r
    for _, p in pairs(Peds.list) do
        if (not kinds or kinds[p.kind]) and (p.x - x) ^ 2 + (p.y - y) ^ 2 <= r2 then n = n + 1 end
    end
    return n
end

local WALKERS = { traffic = true }

local function pickEdge(edges, total)
    local r = random() * total
    for _, e in ipairs(edges) do
        r = r - e.length
        if r <= 0 then return e end
    end
    return edges[#edges]
end

local function trySpawn(pl, players, now)
    local area = areaOf(pl, now)
    if area.target <= 0 or #area.edges == 0 then return end
    if countNear(pl.x, pl.y, T.SPAWN_MAX_DIST, WALKERS) >= area.target then return end
    local e = pickEdge(area.edges, area.total)
    if not e or e.kind ~= "sidewalk" then return end   -- never start on a crossing
    local u = random()
    local x, y, z = e.x1 + (e.x2 - e.x1) * u, e.y1 + (e.y2 - e.y1) * u, e.z1 + (e.z2 - e.z1) * u
    local dMe = sqrt((x - pl.x) ^ 2 + (y - pl.y) ^ 2)
    if dMe > T.SPAWN_MAX_DIST then return end
    for _, o in ipairs(players) do
        local d2 = (x - o.x) ^ 2 + (y - o.y) ^ 2
        if d2 < T.SPAWN_MIN_DIST ^ 2 then return end
        -- the shared budget: every player near the point must still be under its own cap
        if d2 < T.SPAWN_MAX_DIST ^ 2 and o ~= pl then
            local oa = PedTraffic.cache[o.el]
            local cap = oa and oa.target or T.MAX_PER_PLAYER
            if countNear(o.x, o.y, T.SPAWN_MAX_DIST, WALKERS) >= cap then return end
        end
    end
    if Views.anySees(players, x, y, z + 1, T.SPAWN_VISIBLE_MIN, now) then return end
    if countNear(x, y, T.AREA_RADIUS) >= T.AREA_MAX then return end

    -- walking direction: towards a or b at random; the walk continues from that node
    local fromA = random() < 0.5
    local node, prev = fromA and e.b or e.a, fromA and e.a or e.b
    local walk = Nav.randomWalk(x, y, z, T.WALK_LENGTH, { node = node, prev = prev })
    if not walk or not walk.points or #walk.points < 2 then return end
    -- start point in front of the first node: shift crossings by one
    table.insert(walk.points, 1, { x, y, z })
    if walk.widths then table.insert(walk.widths, 1, e.width) end
    table.insert(walk.nodes, 1, prev)
    for _, c in ipairs(walk.crossings or {}) do c.index = c.index + 1 end

    local gz = Nav.ground(x, y, z, 3) or z
    local tx, ty = walk.points[2][1], walk.points[2][2]
    local rot = math.deg(math.atan2(-(tx - x), ty - y))
    local p = Peds.create(Peds.randomSkin(), x, y, gz + 1.0, "traffic", { rot = rot })
    if not p then return end
    Peds.setBehaviour(p, "civilian", { task = "wander", taskOpts = { walk = walk } })
end

-- players: { { el, x, y, z }, ... } in dimension 0 / interior 0
function PedTraffic.spawn(players, now)
    if not PedTraffic.enabled or not Nav.available() then return end
    if Peds.byKind.traffic >= T.MAX_TRAFFIC then return end
    for _, pl in ipairs(players) do
        for _ = 1, T.SPAWN_PER_PLAYER do
            if Peds.byKind.traffic >= T.MAX_TRAFFIC then return end
            trySpawn(pl, players, now)
        end
    end
end

-- walkers and adopted drivers: removed far from every player, or unseen for CULL_AFTER (not while fighting)
function PedTraffic.cull(players, now)
    for _, p in pairs(Peds.list) do
        if p.kind ~= "scripted" and p.behaviour ~= "exiting" then
            local near, seen = math.huge, false
            local dim = getElementDimension(p.el)
            for _, pl in ipairs(players) do
                if dim == 0 then
                    local d2 = (pl.x - p.x) ^ 2 + (pl.y - p.y) ^ 2
                    if d2 < near then near = d2 end
                end
            end
            near = sqrt(near)
            if near > T.DESPAWN_DIST then
                Peds.remove(p, "culled")
            else
                for _, pl in ipairs(players) do
                    if Views.playerSees(pl.el, p.x, p.y, p.z + 1, now) then seen = true; break end
                end
                local fighting = p.behaviour == "enemy" and p.b.target
                if seen or fighting or near <= T.CULL_MIN_DIST then
                    p.seenAt = now
                elseif now - p.seenAt > T.CULL_AFTER and not p.dead then
                    Peds.remove(p, "culled")
                end
            end
        end
    end
end

function PedTraffic.clear()
    for _, p in pairs(Peds.list) do
        if p.kind == "traffic" then Peds.remove(p, "cleared") end
    end
end

addEventHandler("onPlayerQuit", root, function() PedTraffic.cache[source] = nil end)
