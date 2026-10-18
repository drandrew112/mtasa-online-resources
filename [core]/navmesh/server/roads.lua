-- Road network (data/runtime/roads.nav): nodes, links (carriageways), lanes, lane connections, signal groups.
-- Lane-level A* for the vehicle profiles of NAV.VEHICLE.

Roads = {
    -- nodes
    nx = {}, ny = {}, nz = {}, ngps = {}, nfl = {}, byGps = {},
    -- links
    ka = {}, kb = {}, kclass = {}, kfl = {}, kab = {}, kba = {}, kmed = {}, klen = {},
    -- lanes
    alink = {}, afrom = {}, ato = {}, aidx = {}, acount = {}, aleft = {}, aright = {}, afl = {},
    ax1 = {}, ay1 = {}, az1 = {}, ax2 = {}, ay2 = {}, az2 = {}, alen = {}, anext = {}, aprev = {},
    -- connections
    cfrom = {}, cto = {}, cnode = {}, cturn = {}, csig = {}, cvmax = {}, clen = {}, cb = {},
    -- signal groups
    sx = {}, sy = {}, sz = {}, sphases = {}, snodes = {}, sgroupOf = {},
    laneCount = 0, connCount = 0, nodeCount = 0, linkCount = 0, groupCount = 0,
    index = nil, ready = false,
}
local R = Roads
local tonumber, sqrt, floor, huge = tonumber, math.sqrt, math.floor, math.huge
local bitAnd = bitAnd

local function list(s)
    local t = {}
    for v in s:gmatch("%d+") do t[#t + 1] = tonumber(v) end
    return t
end

function Roads.load()
    local t0 = getTickCount()
    local src = readTextFile(NAV.ROADS_FILE)
    if not src then
        outputDebugString("[navmesh] missing " .. NAV.ROADS_FILE .. ", run tools/build_roads.py", 1)
        return false
    end
    local num = tonumber
    for line in src:gmatch("[^\n]+") do
        local k = line:byte(1)
        if k == 65 then       -- A lane
            local id, link, fr, to, idx, cnt, left, right, fl, x1, y1, z1, x2, y2, z2 =
                line:match("^A (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
            id = num(id)
            R.alink[id], R.afrom[id], R.ato[id] = num(link), num(fr), num(to)
            R.aidx[id], R.acount[id], R.afl[id] = num(idx), num(cnt), num(fl)
            left, right = num(left), num(right)
            if left > 0 then R.aleft[id] = left end
            if right > 0 then R.aright[id] = right end
            x1, y1, z1, x2, y2, z2 = num(x1), num(y1), num(z1), num(x2), num(y2), num(z2)
            R.ax1[id], R.ay1[id], R.az1[id], R.ax2[id], R.ay2[id], R.az2[id] = x1, y1, z1, x2, y2, z2
            R.alen[id] = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2)
            R.anext[id] = {}
            R.aprev[id] = {}
            if id > R.laneCount then R.laneCount = id end
        elseif k == 67 then   -- C connection
            local id, fr, to, node, turn, sig, vmax, len, rest =
                line:match("^C (%d+) (%d+) (%d+) (%d+) (%a) (%d) (%S+) (%S+)(.*)$")
            id = num(id)
            R.cfrom[id], R.cto[id], R.cnode[id], R.cturn[id] = num(fr), num(to), num(node), turn
            R.csig[id], R.cvmax[id], R.clen[id] = num(sig), num(vmax), num(len)
            if rest and #rest > 1 then
                local b = {}
                for v in rest:gmatch("%S+") do b[#b + 1] = num(v) end
                if #b == 6 then R.cb[id] = b end
            end
            if id > R.connCount then R.connCount = id end
        elseif k == 78 then   -- N node
            local id, x, y, z, gps, fl = line:match("^N (%d+) (%S+) (%S+) (%S+) (%d+) (%d+)")
            id = num(id)
            R.nx[id], R.ny[id], R.nz[id], R.ngps[id], R.nfl[id] = num(x), num(y), num(z), num(gps), num(fl)
            R.byGps[R.ngps[id]] = id
            if id > R.nodeCount then R.nodeCount = id end
        elseif k == 75 then   -- K link
            local id, a, b, cls, fl, ab, ba, med, len = line:match("^K (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%d+) (%S+) (%S+)")
            id = num(id)
            R.ka[id], R.kb[id], R.kclass[id], R.kfl[id] = num(a), num(b), num(cls), num(fl)
            R.kab[id], R.kba[id], R.kmed[id], R.klen[id] = num(ab), num(ba), num(med), num(len)
            if id > R.linkCount then R.linkCount = id end
        elseif k == 83 then   -- S signal group
            local id, x, y, z, ph, nodes = line:match("^S (%d+) (%S+) (%S+) (%S+) (%S+) (%S+)")
            id = num(id)
            R.sx[id], R.sy[id], R.sz[id] = num(x), num(y), num(z)
            R.sphases[id] = ph == "-" and {} or list(ph)
            R.snodes[id] = list(nodes)
            for _, n in ipairs(R.snodes[id]) do R.sgroupOf[n] = id end
            if id > R.groupCount then R.groupCount = id end
        end
    end
    for c = 1, R.connCount do
        local a, b = R.cfrom[c], R.cto[c]
        if a then
            local t = R.anext[a]; t[#t + 1] = c
            t = R.aprev[b]; t[#t + 1] = c
        end
    end
    R.index = SpatialHash.new(NAV.INDEX_CELL)
    for id = 1, R.laneCount do
        if R.ax1[id] then R.index:add(id, R.ax1[id], R.ay1[id], R.ax2[id], R.ay2[id]) end
    end
    R.ready = true
    outputDebugString(("[navmesh] roads: %d nodes, %d links, %d lanes, %d connections, %d signal groups (%d ms)")
        :format(R.nodeCount, R.linkCount, R.laneCount, R.connCount, R.groupCount, getTickCount() - t0))
    return true
end

------------------------------------------------------------------------ geometry

-- point on a lane at fraction u (0..1)
function Roads.lanePoint(id, u)
    return R.ax1[id] + (R.ax2[id] - R.ax1[id]) * u, R.ay1[id] + (R.ay2[id] - R.ay1[id]) * u,
        R.az1[id] + (R.az2[id] - R.az1[id]) * u
end

-- points of a connection curve (lane end -> next lane start), without the first point
function Roads.connPoints(c, out, steps)
    local a, b = R.cfrom[c], R.cto[c]
    local x0, y0, z0 = R.ax2[a], R.ay2[a], R.az2[a]
    local x3, y3, z3 = R.ax1[b], R.ay1[b], R.az1[b]
    local bz = R.cb[c]
    out = out or {}
    if not bz then
        out[#out + 1] = { x3, y3, z3 }
        return out
    end
    steps = steps or math.max(2, math.min(10, floor(R.clen[c] / 3)))
    for s = 1, steps do
        local t = s / steps
        local u = 1 - t
        local w0, w1, w2, w3 = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
        out[#out + 1] = { w0 * x0 + w1 * bz[1] + w2 * bz[4] + w3 * x3, w0 * y0 + w1 * bz[2] + w2 * bz[5] + w3 * y3,
            w0 * z0 + w1 * bz[3] + w2 * bz[6] + w3 * z3 }
    end
    return out
end

function Roads.laneHeading(id)
    return math.deg(math.atan2(R.ay2[id] - R.ay1[id], R.ax2[id] - R.ax1[id]))
end

-- lanes near a point, sorted by distance: { {lane, dist, u}, ... }
-- opts: radius (30), heading (deg, GTA rotZ convention: 0 = north), headingTolerance (70), maxZ (6), skipTrap
function Roads.nearestLanes(x, y, z, opts)
    opts = opts or {}
    local radius = opts.radius or 30
    local maxZ = opts.maxZ or 6
    local res, seen = {}, {}
    local hx, hy
    if opts.heading then
        local r = math.rad(opts.heading)
        hx, hy = -math.sin(r), math.cos(r)
    end
    local cosTol = math.cos(math.rad(opts.headingTolerance or 70))
    R.index:each(x, y, radius, function(id)
        if seen[id] then return end
        seen[id] = true
        if opts.skipTrap and bitAnd(R.afl[id], NAV_LF.TRAP) ~= 0 then return end
        local d, u = segDist2D(x, y, R.ax1[id], R.ay1[id], R.ax2[id], R.ay2[id])
        if d > radius then return end
        local lz = R.az1[id] + (R.az2[id] - R.az1[id]) * u
        if z and math.abs(lz - z) > maxZ then return end
        if hx then
            local dx, dy = R.ax2[id] - R.ax1[id], R.ay2[id] - R.ay1[id]
            local L = sqrt(dx * dx + dy * dy)
            if L > 0.1 and (dx * hx + dy * hy) / L < cosTol then return end
        end
        res[#res + 1] = { id, d + (z and math.abs(lz - z) * 0.5 or 0), u }
    end)
    table.sort(res, function(a, b) return a[2] < b[2] end)
    return res
end

------------------------------------------------------------------------ routing

local function laneSpeed(id)
    local k = R.alink[id]
    if bitAnd(R.kfl[k], NAV_KF.UNPAVED) ~= 0 then return NAV.SPEED_UNPAVED end
    return NAV.SPEED[R.kclass[k]] or 14
end
Roads.laneSpeed = laneSpeed

local function laneFactor(id, prof)
    local k = R.alink[id]
    local fl, f = R.kfl[k], 1
    if bitAnd(fl, NAV_KF.UNPAVED) ~= 0 then f = f * prof.unpaved end
    if bitAnd(fl, NAV_KF.EMERGENCY) ~= 0 then f = f * prof.emergencyOnly end
    local cls = R.kclass[k]
    if cls == NAV_CLASS.SERVICE then f = f * prof.service end
    if prof.avoidClass and prof.avoidClass[cls] then f = f * prof.avoidClass[cls] end
    if prof.preferClass and prof.preferClass[cls] then f = f * prof.preferClass[cls] end
    return f
end

-- time (s) of a lane from u0 to u1
local function laneTime(id, prof, u0, u1)
    return R.alen[id] * (u1 - u0) / laneSpeed(id) * laneFactor(id, prof)
end

local function connTime(c, prof)
    local b = R.cto[c]
    local v = laneSpeed(b)
    local vmax = R.cvmax[c]
    if vmax > 0 and vmax < v then v = vmax end
    local t = R.clen[c] / v + (NAV.TURN_DELAY[R.cturn[c]] or 0)
    if R.csig[c] > 0 then t = t + NAV.SIGNAL_DELAY * (prof.signalFactor or 1) end
    return t * laneFactor(b, prof)
end

local LANE_CHANGE = 3   -- s

-- A* on lanes. starts / goals: { {lane, dist, u}, ... } from nearestLanes.
-- Returns { lanes = {...}, conns = {...}, ... } via Roads.buildResult, or nil, reason
function Roads.search(starts, goals, prof, maxNodes)
    local heap = Heap.new()
    local g, came, via, closed = {}, {}, {}, {}
    local goalU = {}
    local gx, gy = 0, 0
    for _, s in ipairs(goals) do
        goalU[s[1]] = goalU[s[1]] and math.max(goalU[s[1]], s[3]) or s[3]
        local px, py = Roads.lanePoint(s[1], s[3])
        gx, gy = gx + px, gy + py
    end
    gx, gy = gx / #goals, gy / #goals
    local vmax = NAV.SPEED[1]
    local function h(id)
        local dx, dy = R.ax2[id] - gx, R.ay2[id] - gy
        return sqrt(dx * dx + dy * dy) / vmax
    end
    local startU = {}
    for _, s in ipairs(starts) do
        local id, u = s[1], s[3]
        local cost = s[2] / 5    -- off-road distance to the lane (~5 m/s)
        -- same lane start and goal ahead of it: direct
        startU[id] = u
        local c = cost + laneTime(id, prof, u, 1)
        if not g[id] or c < g[id] then
            g[id] = c
            heap:push(id, c + h(id))
        end
    end
    local best, bestCost = nil, huge
    -- a goal on a start lane ahead of the start point
    for id, u in pairs(startU) do
        local gu = goalU[id]
        if gu and gu >= u then
            local c = g[id] - laneTime(id, prof, gu, 1)
            if c < bestCost then best, bestCost = id, c end
        end
    end
    local n, maxN = 0, maxNodes or NAV.ROAD_MAX_NODES
    while heap.n > 0 do
        local id, f = heap:pop()
        if f >= bestCost then break end
        if not closed[id] then
            closed[id] = true
            n = n + 1
            if n > maxN then return nil, "search_limit" end
            if n % 500 == 0 then Nav.budget() end
            local gid = g[id]
            -- reaching a goal lane through its start (not as start lane)
            local gu = goalU[id]
            if gu and came[id] ~= nil then   -- entered at its start (a start lane itself is handled above)
                local c = gid - laneTime(id, prof, gu, 1)
                if c < bestCost then best, bestCost = id, c end
            end
            local nx = R.anext[id]
            for i = 1, #nx do
                local c = nx[i]
                local b = R.cto[c]
                if not closed[b] then
                    local ng = gid + connTime(c, prof) + laneTime(b, prof, 0, 1)
                    if not g[b] or ng < g[b] then
                        g[b], came[b], via[b] = ng, id, c
                        heap:push(b, ng + h(b))
                    end
                end
            end
            -- lane changes within the carriageway (the turn connections start from specific lanes)
            for _, nb in ipairs({ R.aleft[id], R.aright[id] }) do
                if nb and not closed[nb] then
                    local ng = gid + LANE_CHANGE
                    if not g[nb] or ng < g[nb] then
                        g[nb], came[nb], via[nb] = ng, id, false
                        heap:push(nb, ng + h(nb))
                    end
                end
            end
        end
    end
    if not best then return nil, "no_route" end
    -- unwind
    local lanes, conns = {}, {}
    local cur = best
    while cur do
        table.insert(lanes, 1, cur)
        table.insert(conns, 1, via[cur] or false)
        cur = came[cur]
    end
    return { lanes = lanes, conns = conns, startU = startU[lanes[1]] or 0, goalU = goalU[best], cost = bestCost, expanded = n }
end

-- route geometry + instructions
function Roads.buildResult(r, x1, y1, z1, x2, y2, z2)
    local pts, info = {}, {}
    local dist, time = 0, 0
    local instr = {}
    local function add(x, y, z, kind)
        local last = pts[#pts]
        if last then
            local d = sqrt((x - last[1]) ^ 2 + (y - last[2]) ^ 2 + (z - last[3]) ^ 2)
            if d < 0.05 then return end
            dist = dist + d
        end
        pts[#pts + 1] = { x, y, z }
        info[#info + 1] = kind
    end
    local lanes, conns = r.lanes, r.conns
    -- lane fractions: a lane change (conns[i] == false) happens over the last 30 m of the lane before it
    local U0, U1 = {}, {}
    for i = 1, #lanes do U0[i], U1[i] = 0, 1 end
    U0[1] = r.startU
    U1[#lanes] = math.max(r.goalU, #lanes == 1 and r.startU or 0)
    for i = 2, #lanes do
        if conns[i] == false then
            local prev = lanes[i - 1]
            local u = math.max(U0[i - 1], 1 - math.min(1, 30 / math.max(R.alen[prev], 1)))
            U1[i - 1], U0[i] = u, u
        end
    end
    for i, id in ipairs(lanes) do
        local u0, u1 = U0[i], math.max(U1[i], U0[i])
        local c = conns[i]
        if c then
            local cp = Roads.connPoints(c)
            local turn = R.cturn[c]
            local node = R.cnode[c]
            local fromCls, toCls = R.kclass[R.alink[R.cfrom[c]]], R.kclass[R.alink[R.cto[c]]]
            local kind
            if fromCls == NAV_CLASS.HIGHWAY and toCls == NAV_CLASS.RAMP then kind = "exit"
            elseif fromCls == NAV_CLASS.RAMP and toCls == NAV_CLASS.HIGHWAY then kind = "merge"
            elseif bitAnd(R.nfl[node], NAV_NF.JUNCTION) ~= 0 and turn ~= "S" then
                kind = turn == "L" and "left" or turn == "R" and "right" or "uturn"
            end
            if kind then
                instr[#instr + 1] = { type = kind, distance = dist, x = R.nx[node], y = R.ny[node], z = R.nz[node],
                    node = node, gps = R.ngps[node] }
            end
            for _, p in ipairs(cp) do add(p[1], p[2], p[3], c) end
        end
        local ax, ay, az = Roads.lanePoint(id, u0)
        add(ax, ay, az, id)
        local bx, by, bz = Roads.lanePoint(id, u1)
        add(bx, by, bz, id)
        time = time + R.alen[id] * (u1 - u0) / laneSpeed(id)
    end
    instr[#instr + 1] = { type = "arrive", distance = dist, x = x2, y = y2, z = z2 }
    return {
        points = pts, lanes = lanes, connections = conns, instructions = instr,
        length = dist, time = time, cost = r.cost, expanded = r.expanded,
    }
end

-- gps node ids (v_radar vehiclenodes: area * 65536 + index) along a route
function Roads.routeGpsNodes(lanes)
    local out, last = {}, nil
    for _, id in ipairs(lanes) do
        for _, n in ipairs({ R.afrom[id], R.ato[id] }) do
            if n ~= last then out[#out + 1] = R.ngps[n]; last = n end
        end
    end
    return out
end
