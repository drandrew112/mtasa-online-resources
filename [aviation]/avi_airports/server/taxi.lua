-- Taxi routing over the taxiway polylines of an airport. Nodes = taxiway points (points closer
-- than AP.JOIN_DIST merge into one junction), edges = consecutive points. Every runway centre line
-- is an extra chain (thresholds + the taxiway points lying on it), more expensive to use.
-- A route starts / ends at the nearest point of the nearest edge, so gates and aircraft positions
-- do not have to be graph nodes. Route corners are rounded (AP.TURN_RADIUS), like the drawn taxiways.

local graphs = {}   -- [icao] = { nodes = { {x, y} }, edges = { {a, b, cost, len} }, adj = { [i] = { {to, cost} } } }

local function dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function addNode(g, x, y)
    for i, n in ipairs(g.nodes) do
        if dist(n[1], n[2], x, y) <= AP.JOIN_DIST then return i end
    end
    g.nodes[#g.nodes + 1] = { x, y }
    g.adj[#g.nodes] = {}
    return #g.nodes
end

local function addEdge(g, a, b, factor)
    if a == b then return end
    local len = dist(g.nodes[a][1], g.nodes[a][2], g.nodes[b][1], g.nodes[b][2])
    local cost = len * (factor or 1)
    g.edges[#g.edges + 1] = { a, b, cost, len }
    table.insert(g.adj[a], { b, cost })
    table.insert(g.adj[b], { a, cost })
end

-- share of the piece a -> b inside a runway zone (half width + 5 m, 30 m past the ends)
local function inRunwayShare(a, ax, ay, bx, by)
    local inside = 0
    for k = 0, 9 do
        local f = (k + 0.5) / 10
        local x, y = ax + (bx - ax) * f, ay + (by - ay) * f
        for _, rw in ipairs(a.runways) do
            local e1, e2 = rw.ends[1], rw.ends[2]
            local dx, dy = e2.x - e1.x, e2.y - e1.y
            local len = math.sqrt(dx * dx + dy * dy)
            local rx, ry = x - e1.x, y - e1.y
            local t = (rx * dx + ry * dy) / len
            if math.abs(rx * dy - ry * dx) / len <= (tonumber(rw.width) or 30) / 2 + 5 and t >= -30 and t <= len + 30 then
                inside = inside + 1
                break
            end
        end
    end
    return inside / 10
end

local function build(a)
    local g = { nodes = {}, edges = {}, adj = {} }
    for _, tw in ipairs(a.taxiways) do
        local prev
        for _, p in ipairs(tw.points or {}) do
            local i = addNode(g, p[1], p[2])
            -- crossing a runway costs like taxiing on it: routes go round the runway ends when they can
            if prev then
                local n1, n2 = g.nodes[prev], g.nodes[i]
                addEdge(g, prev, i, 1 + inRunwayShare(a, n1[1], n1[2], n2[1], n2[2]) * (AP.RUNWAY_TAXI_COST - 1))
            end
            prev = i
        end
    end
    -- runway chains
    for _, rw in ipairs(a.runways) do
        local e1, e2 = rw.ends[1], rw.ends[2]
        local dx, dy = e2.x - e1.x, e2.y - e1.y
        local len = math.sqrt(dx * dx + dy * dy)
        local ux, uy = dx / len, dy / len
        local half = (tonumber(rw.width) or 30) / 2 + 2
        local chain = {}
        for i, n in ipairs(g.nodes) do
            local rx, ry = n[1] - e1.x, n[2] - e1.y
            local t = rx * ux + ry * uy
            local off = math.abs(-rx * uy + ry * ux)
            if off <= half and t >= -AP.RUNWAY_CHAIN_EXT and t <= len + AP.RUNWAY_CHAIN_EXT then chain[#chain + 1] = { i, t } end
        end
        chain[#chain + 1] = { addNode(g, e1.x, e1.y), 0 }
        chain[#chain + 1] = { addNode(g, e2.x, e2.y), len }
        table.sort(chain, function(p, q) return p[2] < q[2] end)
        for k = 2, #chain do addEdge(g, chain[k - 1][1], chain[k][1], AP.RUNWAY_TAXI_COST) end
    end
    return g
end

function buildTaxiGraphs()
    graphs = {}
    for icao, a in pairs(AIRPORTS) do graphs[icao] = build(a) end
end

-- nearest point on any edge: edge index, projected x, y, distance, t (0..1 from a to b)
local function nearestEdge(g, x, y)
    local best, bx, by, bd, bt
    for i, e in ipairs(g.edges) do
        local a, b = g.nodes[e[1]], g.nodes[e[2]]
        local dx, dy = b[1] - a[1], b[2] - a[2]
        local l2 = dx * dx + dy * dy
        local t = l2 > 0 and math.max(0, math.min(1, ((x - a[1]) * dx + (y - a[2]) * dy) / l2)) or 0
        local px, py = a[1] + dx * t, a[2] + dy * t
        local d = dist(px, py, x, y)
        if not bd or d < bd then best, bx, by, bd, bt = i, px, py, d, t end
    end
    return best, bx, by, bd, bt
end

local function dijkstra(g, starts)
    local d, prev, done = {}, {}, {}
    for node, c in pairs(starts) do d[node] = c end
    while true do
        local u, du
        for node, c in pairs(d) do
            if not done[node] and (not du or c < du) then u, du = node, c end
        end
        if not u then break end
        done[u] = true
        for _, nb in ipairs(g.adj[u]) do
            local v, c = nb[1], du + nb[2]
            if not d[v] or c < d[v] then d[v], prev[v] = c, u end
        end
    end
    return d, prev
end

-- route from (fx, fy) to (tx, ty) over the taxiways of icao: list of {x, y} incl. both ends
function findTaxiRoute(icao, fx, fy, tx, ty)
    local g = graphs[icao and tostring(icao):upper()]
    if not g or #g.edges == 0 then return { { fx, fy }, { tx, ty } } end
    local se, sx, sy, _, st = nearestEdge(g, fx, fy)
    local te, ex, ey, _, tt = nearestEdge(g, tx, ty)
    local sEdge, tEdge = g.edges[se], g.edges[te]

    if se == te then
        return { { fx, fy }, { sx, sy }, { ex, ey }, { tx, ty } }
    end

    -- the partial first / last edge costs as much per metre as the whole edge (a runway more)
    local sa, sb = sEdge[1], sEdge[2]
    local starts = {
        [sa] = sEdge[3] * st,
        [sb] = sEdge[3] * (1 - st),
    }
    local d, prev = dijkstra(g, starts)
    local ta, tb = tEdge[1], tEdge[2]
    local ca = d[ta] and d[ta] + tEdge[3] * tt
    local cb = d[tb] and d[tb] + tEdge[3] * (1 - tt)
    local last
    if ca and (not cb or ca <= cb) then last = ta elseif cb then last = tb end
    if not last then return { { fx, fy }, { tx, ty } } end

    local chain = {}
    local n = last
    while n do
        table.insert(chain, 1, n)
        n = prev[n]
    end
    local out = { { fx, fy }, { sx, sy } }
    for _, i in ipairs(chain) do out[#out + 1] = { g.nodes[i][1], g.nodes[i][2] } end
    out[#out + 1] = { ex, ey }
    out[#out + 1] = { tx, ty }
    -- drop zero-length steps
    local clean = { out[1] }
    for i = 2, #out do
        local p, q = clean[#clean], out[i]
        if dist(p[1], p[2], q[1], q[2]) > 0.5 then clean[#clean + 1] = q end
    end
    return roundCorners(clean)
end

-- ---------------------------------------------------------------- rounded corners
local function bezier(ax, ay, cx, cy, bx, by, t)
    local u = 1 - t
    return u * u * ax + 2 * u * t * cx + t * t * bx, u * u * ay + 2 * u * t * cy + t * t * by
end

-- corner at b between a -> b -> c: tangent points + curve points (nil = no rounding needed)
local function cornerCurve(a, b, c, radius, steps)
    local l1, l2 = dist(a[1], a[2], b[1], b[2]), dist(b[1], b[2], c[1], c[2])
    if l1 < 0.5 or l2 < 0.5 then return nil end
    local d1x, d1y = (b[1] - a[1]) / l1, (b[2] - a[2]) / l1
    local d2x, d2y = (c[1] - b[1]) / l2, (c[2] - b[2]) / l2
    if d1x * d2x + d1y * d2y > 0.985 then return nil end          -- (almost) straight on
    local r = math.min(radius, l1 * 0.45, l2 * 0.45)
    local p1 = { b[1] - d1x * r, b[2] - d1y * r }
    local p2 = { b[1] + d2x * r, b[2] + d2y * r }
    local pts = { p1 }
    for k = 1, steps - 1 do
        local x, y = bezier(p1[1], p1[2], b[1], b[2], p2[1], p2[2], k / steps)
        pts[#pts + 1] = { x, y }
    end
    pts[#pts + 1] = p2
    return pts
end

-- a polyline with every corner replaced by a curve
function roundCorners(pts, radius)
    if #pts < 3 then return pts end
    local out = { pts[1] }
    for i = 2, #pts - 1 do
        local curve = cornerCurve(pts[i - 1], pts[i], pts[i + 1], radius or AP.TURN_RADIUS, 6)
        if curve then
            for _, p in ipairs(curve) do out[#out + 1] = p end
        else
            out[#out + 1] = pts[i]
        end
    end
    out[#out + 1] = pts[#pts]
    return out
end

-- Drawn taxiways (a.taxiDraw = { {x1, y1, x2, y2} }): a junction of exactly two pieces (a bend, or
-- one taxiway continuing as another) becomes a curve; where three or more meet, the straight
-- pieces stay and every corner between neighbouring pieces gets a fillet curve.
local function buildDraw(a)
    local nodes, edges = {}, {}
    local function node(x, y)
        for i, n in ipairs(nodes) do
            if dist(n[1], n[2], x, y) <= AP.JOIN_DIST then return i end
        end
        nodes[#nodes + 1] = { x, y, inc = {} }
        return #nodes
    end
    for _, tw in ipairs(a.taxiways) do
        local prev
        for _, p in ipairs(tw.points or {}) do
            local i = node(p[1], p[2])
            if prev and prev ~= i then
                edges[#edges + 1] = { prev, i, trim = { [prev] = 0, [i] = 0 } }
                table.insert(nodes[prev].inc, #edges)
                table.insert(nodes[i].inc, #edges)
            end
            prev = i
        end
    end
    local out = {}
    local function polyline(pts)
        for k = 2, #pts do out[#out + 1] = { pts[k - 1][1], pts[k - 1][2], pts[k][1], pts[k][2] } end
    end
    local function other(e, n) return e[1] == n and e[2] or e[1] end
    for ni, n in ipairs(nodes) do
        if #n.inc == 2 then
            local e1, e2 = edges[n.inc[1]], edges[n.inc[2]]
            local curve = cornerCurve(nodes[other(e1, ni)], n, nodes[other(e2, ni)], AP.TURN_RADIUS, 6)
            if curve then
                e1.trim[ni] = dist(curve[1][1], curve[1][2], n[1], n[2])
                e2.trim[ni] = dist(curve[#curve][1], curve[#curve][2], n[1], n[2])
                polyline(curve)
            end
        elseif #n.inc >= 3 then
            -- pieces sorted by direction; fillet between neighbours closer than 150 degrees
            local dirs = {}
            for _, ei in ipairs(n.inc) do
                local o = nodes[other(edges[ei], ni)]
                dirs[#dirs + 1] = { o = o, ang = math.atan2(o[2] - n[2], o[1] - n[1]) }
            end
            table.sort(dirs, function(p, q) return p.ang < q.ang end)
            for k = 1, #dirs do
                local d1, d2 = dirs[k], dirs[k % #dirs + 1]
                local gap = (d2.ang - d1.ang) % (2 * math.pi)
                if gap > 0.2 and gap < math.rad(150) then
                    local curve = cornerCurve(d1.o, n, d2.o, AP.TURN_RADIUS * 0.7, 5)
                    if curve then polyline(curve) end
                end
            end
        end
    end
    for _, e in ipairs(edges) do
        local p, q = nodes[e[1]], nodes[e[2]]
        local l = dist(p[1], p[2], q[1], q[2])
        if l > 0 then
            local t1, t2 = e.trim[e[1]] / l, 1 - e.trim[e[2]] / l
            if t2 > t1 then
                out[#out + 1] = { p[1] + (q[1] - p[1]) * t1, p[2] + (q[2] - p[2]) * t1,
                    p[1] + (q[1] - p[1]) * t2, p[2] + (q[2] - p[2]) * t2 }
            end
        end
    end
    for _, l in ipairs(out) do
        for k = 1, 4 do l[k] = math.floor(l[k] * 10 + 0.5) / 10 end
    end
    return out
end

function buildTaxiDraw()
    for _, a in pairs(AIRPORTS) do a.taxiDraw = buildDraw(a) end
end
