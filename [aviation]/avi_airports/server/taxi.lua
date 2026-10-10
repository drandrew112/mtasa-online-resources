-- Taxi routing over the taxiway polylines of an airport. Nodes = taxiway points (points closer
-- than AP.JOIN_DIST merge into one junction), edges = consecutive points. Every runway centre line
-- is an extra chain (thresholds + the taxiway points lying on it), more expensive to use.
-- A route starts / ends at the nearest point of the nearest edge, so gates and aircraft positions
-- do not have to be graph nodes.

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

local function build(a)
    local g = { nodes = {}, edges = {}, adj = {} }
    for _, tw in ipairs(a.taxiways) do
        local prev
        for _, p in ipairs(tw.points or {}) do
            local i = addNode(g, p[1], p[2])
            if prev then addEdge(g, prev, i) end
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
            if off <= half and t >= -60 and t <= len + 60 then chain[#chain + 1] = { i, t } end
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

    local sa, sb = sEdge[1], sEdge[2]
    local starts = {
        [sa] = sEdge[4] * st,
        [sb] = sEdge[4] * (1 - st),
    }
    local d, prev = dijkstra(g, starts)
    local ta, tb = tEdge[1], tEdge[2]
    local ca = d[ta] and d[ta] + tEdge[4] * tt
    local cb = d[tb] and d[tb] + tEdge[4] * (1 - tt)
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
    return clean
end
