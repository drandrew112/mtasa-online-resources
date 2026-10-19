-- The player's expected route (server): spawn candidates for the spawner. Starting from the lanes
-- under the player that run along their heading, the road graph is followed forward for ROUTE_LENGTH
-- metres (every branch). Spawnable lanes on it, their oncoming lanes and the lanes feeding into them
-- at junctions form the spawn area, so new traffic only appears where the player is going. With a v_radar GPS
-- destination on the player's vehicle the navmesh route to it is followed instead of every branch.
--
-- area = { lanes = { lane, ... }, weights = { w, ... }, total, target, x, y, hx, hy, at, speed }

Route = {}

local T = TRAFFIC
local floor, min, max, sqrt, rad, sin, cos = math.floor, math.min, math.max, math.sqrt, math.rad, math.sin, math.cos
local areas = {}       -- [player] = area
local opposite = {}    -- [lane] = { lane, ... } (built when first needed)

-- unit direction (2D) and length of a lane
local function laneDir(id)
    local dx, dy = Geo.lx2[id] - Geo.lx1[id], Geo.ly2[id] - Geo.ly1[id]
    local l = sqrt(dx * dx + dy * dy)
    if l < 1e-6 then return 0, 1, 0 end
    return dx / l, dy / l, l
end

-- distance (2D) of a point from a lane and the position along it
local function laneDistance(id, x, y)
    local dx, dy, l = laneDir(id)
    local px, py = x - Geo.lx1[id], y - Geo.ly1[id]
    local s = px * dx + py * dy
    local cs = s < 0 and 0 or (s > l and l or s)
    local qx, qy = px - dx * cs, py - dy * cs
    return sqrt(qx * qx + qy * qy), cs
end

-- spawnable lanes running the other way next to a lane (the other carriageway)
local function oppositeOf(id)
    local o = opposite[id]
    if o then return o end
    o = {}
    local dx, dy, l = laneDir(id)
    local mx, my = (Geo.lx1[id] + Geo.lx2[id]) / 2, (Geo.ly1[id] + Geo.ly2[id]) / 2
    for _, c in ipairs(Net.cellsAround(mx, my, l / 2 + 30)) do
        for _, other in ipairs(c.lanes) do
            if other ~= id then
                local ox, oy = laneDir(other)
                if ox * dx + oy * dy < -0.7 then
                    local cx, cy = (Geo.lx1[other] + Geo.lx2[other]) / 2, (Geo.ly1[other] + Geo.ly2[other]) / 2
                    local px, py = cx - Geo.lx1[id], cy - Geo.ly1[id]
                    local along = px * dx + py * dy
                    local side = math.abs(px * dy - py * dx)
                    if side < 22 and along > -10 and along < l + 10
                        and math.abs(((Geo.lz1[other] + Geo.lz2[other]) - (Geo.lz1[id] + Geo.lz2[id])) / 2) < 6 then
                        o[#o + 1] = other
                    end
                end
            end
        end
    end
    opposite[id] = o
    return o
end

-- heading (unit 2D or nil) and speed of a player
local function headingOf(p, now)
    local el = getPedOccupiedVehicle(p.el) or p.el
    local vx, vy = getElementVelocity(el)
    vx, vy = (vx or 0) * 50, (vy or 0) * 50
    local speed = sqrt(vx * vx + vy * vy)
    if speed >= T.STILL_SPEED then return vx / speed, vy / speed, speed end
    if el ~= p.el then
        local _, _, rz = getElementRotation(el)
        local a = rad(rz)
        return -sin(a), cos(a), speed
    end
    local v = Views.of(p.el, now)
    if v then
        local l = sqrt(v.fx * v.fx + v.fy * v.fy)
        if l > 0.1 then return v.fx / l, v.fy / l, speed end
    end
    return nil, nil, speed
end

-- lanes the route starts on: { [lane] = start distance (negative: the part behind the player) }
local function startLanes(x, y, z, hx, hy)
    local starts, best = {}, math.huge
    local cand = {}
    for _, c in ipairs(Net.cellsAround(x, y, T.ROUTE_START_RADIUS)) do
        for _, id in ipairs(c.lanes) do
            local d, s = laneDistance(id, x, y)
            local lz = Geo.lz1[id] + (Geo.lz2[id] - Geo.lz1[id]) * (Geo.llen[id] > 0 and s / Geo.llen[id] or 0)
            if d <= T.ROUTE_START_RADIUS and math.abs(lz - z) < 8 then
                local dx, dy = laneDir(id)
                if not hx or dx * hx + dy * hy > 0.5 then
                    cand[#cand + 1] = { id, d, s }
                    if d < best then best = d end
                end
            end
        end
    end
    -- the carriageway the player is on (all its lanes), not every road around
    for _, c in ipairs(cand) do
        if c[2] <= best + 12 then starts[c[1]] = -c[3] end
    end
    if next(starts) then return starts end
    -- off-road / no lane along the heading: the nearest road, both ways
    cand, best = {}, math.huge
    for _, c in ipairs(Net.cellsAround(x, y, T.ROUTE_FALLBACK_RADIUS)) do
        for _, id in ipairs(c.lanes) do
            local d = laneDistance(id, x, y)
            if d <= T.ROUTE_FALLBACK_RADIUS and math.abs((Geo.lz1[id] + Geo.lz2[id]) / 2 - z) < 30 then
                cand[#cand + 1] = { id, d }
                if d < best then best = d end
            end
        end
    end
    for _, c in ipairs(cand) do
        if c[2] <= best + 25 then starts[c[1]] = c[2] end
    end
    return starts
end

-- follows the road graph forward from the start lanes; returns { [lane] = distance of its start }
local function walk(starts)
    local dist, queue, head = {}, {}, 1
    for id, d in pairs(starts) do
        dist[id] = d
        queue[#queue + 1] = id
    end
    local visited = 0
    while queue[head] and visited < T.ROUTE_MAX_LANES do
        local id = queue[head]
        head = head + 1
        visited = visited + 1
        local fl = Net.lflags[id] or 0
        local stop = bitAnd(fl, LF_ROADBLOCK + LF_TRAP + LF_PARKING) ~= 0
        local endDist = dist[id] + (Geo.llen[id] or 0)
        if not stop and endDist < T.ROUTE_LENGTH then
            for _, c in ipairs(Net.lnext[id] or {}) do
                local to = Net.cto[c]
                local nd = endDist + (Geo.isCurve(c) and Geo.length(-c) or 0)
                if to and nd < T.ROUTE_LENGTH and (not dist[to] or nd < dist[to]) then
                    dist[to] = nd
                    queue[#queue + 1] = to
                end
            end
        end
    end
    return dist
end

------------------------------------------------------------------------ GPS destination (navmesh route)

-- A player whose vehicle has a v_radar destination (elementData gpsDestination = { x, y }) goes along its navmesh
-- route: the spawn area follows that route instead of every branch ahead.
-- gps[player] = { dx, dy, lanes, conns, at, pending, retry } (Navmesh.track state)
local gps = {}

local function gpsDestination(p)
    local veh = getPedOccupiedVehicle(p.el)
    if not veh or getPedOccupiedVehicleSeat(p.el) ~= 0 then return nil end
    local d = getElementData(veh, "gpsDestination")
    if type(d) ~= "table" or not tonumber(d[1]) or not tonumber(d[2]) then return nil end
    return tonumber(d[1]), tonumber(d[2]), veh
end

-- { [lane] = distance of its start } along the GPS route ahead of the player, or nil (no destination / off route)
local function gpsDist(p, now)
    local dx, dy, veh = gpsDestination(p)
    if not dx then
        gps[p.el] = nil
        return nil
    end
    local g = gps[p.el]
    if not g or g.dx ~= dx or g.dy ~= dy then
        g = { dx = dx, dy = dy }
        gps[p.el] = g
    end
    local _, _, rz = getElementRotation(veh)
    local found, foundS = Navmesh.track(g, p.x, p.y, p.z, rz, dx, dy, nil, "car", now, T.GPS_RETRY)
    if not found then return nil end
    local lanes, dist = g.lanes, {}
    local d = -foundS
    for i = found, #lanes do
        local id = lanes[i]
        if d >= T.ROUTE_LENGTH then break end
        if not dist[id] then dist[id] = d end
        -- the other lanes of the carriageway
        for _, side in ipairs({ "lleft", "lright" }) do
            local n, guard = Net[side][id], 0
            while n and guard < 6 do
                if not dist[n] then dist[n] = d end
                n, guard = Net[side][n], guard + 1
            end
        end
        local c = g.conns[i + 1]
        if c then
            d = d + (Geo.llen[id] or 0) + (Geo.isCurve(c) and Geo.length(-c) or 0)
        end
    end
    return dist
end

local function build(p, hx, hy, speed, now)
    local dist = gpsDist(p, now) or walk(startLanes(p.x, p.y, p.z, hx, hy))
    local area = { lanes = {}, weights = {}, total = 0, x = p.x, y = p.y, hx = hx, hy = hy, speed = speed,
                   at = now + T.ROUTE_REFRESH }
    local added = {}
    local function add(id)
        local w = Net.spawnable[id]
        if w and not added[id] then
            added[id] = true
            local n = #area.lanes + 1
            area.lanes[n], area.weights[n] = id, w
            area.total = area.total + w
        end
    end
    for id in pairs(dist) do
        add(id)
        for _, o in ipairs(oppositeOf(id)) do add(o) end
        -- traffic joining the route at the junction ahead
        for _, c in ipairs(Net.lnext[id] or {}) do
            local to = Net.cto[c]
            for _, ic in ipairs(Net.lprev[to] or {}) do
                local from = Net.cfrom[ic]
                if from and from ~= id and not dist[from] then add(from) end
            end
        end
    end
    -- fewer vehicles while the player stands
    local f = T.STILL_FACTOR + (1 - T.STILL_FACTOR) * min(1, max(0, speed - T.STILL_SPEED) / (T.FULL_SPEED - T.STILL_SPEED))
    area.factor = f
    area.target = floor(min(T.MAX_PER_PLAYER, area.total / T.LANE_PER_VEHICLE) * f + 0.5)
    return area
end

-- the spawn area of a player (cached, rebuilt when they moved / turned / changed speed class)
function Route.areaOf(p, now)
    local hx, hy, speed = headingOf(p, now)
    local a = areas[p.el]
    if a and now < a.at then return a end
    if a then
        local moved = (a.x - p.x) ^ 2 + (a.y - p.y) ^ 2 > T.ROUTE_REFRESH_MOVE ^ 2
        local turned = (hx == nil) ~= (a.hx == nil) or (hx and a.hx and hx * a.hx + hy * a.hy < 0.85)
        local still = speed < T.STILL_SPEED
        local speedChanged = still ~= (a.speed < T.STILL_SPEED) or math.abs(speed - a.speed) > 4
        if not moved and not turned and not speedChanged then
            a.at = now + T.ROUTE_REFRESH
            return a
        end
    end
    a = build(p, hx, hy, speed, now)
    areas[p.el] = a
    return a
end

function Route.pick(area)
    local r = math.random() * area.total
    local lanes, ws = area.lanes, area.weights
    for i = 1, #lanes do
        r = r - ws[i]
        if r <= 0 then return lanes[i] end
    end
    return lanes[#lanes]
end

function Route.cleanup()
    for pl in pairs(areas) do
        if not isElement(pl) then areas[pl] = nil end
    end
    for pl in pairs(gps) do
        if not isElement(pl) then gps[pl] = nil end
    end
end

addEventHandler("onPlayerQuit", root, function() areas[source] = nil; gps[source] = nil end)
