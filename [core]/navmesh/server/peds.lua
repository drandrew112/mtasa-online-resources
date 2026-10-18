-- Ped path graph (data/runtime/peds.nav): GTA ped nodes, edges with kind (sidewalk / path / crossing / lit crossing).

Peds = {
    nx = {}, ny = {}, nz = {}, nw = {}, nflood = {}, nfl = {},
    ea = {}, eb = {}, ekind = {}, elen = {}, egroup = {}, ephase = {},
    adj = {},          -- [node] = { edge, ... }
    nodeCount = 0, edgeCount = 0, index = nil, ready = false,
}
local P = Peds
local tonumber, sqrt, huge = tonumber, math.sqrt, math.huge

function Peds.load()
    local t0 = getTickCount()
    local src = readTextFile(NAV.PEDS_FILE)
    if not src then
        outputDebugString("[navmesh] missing " .. NAV.PEDS_FILE .. ", run tools/build_peds.py", 1)
        return false
    end
    local num = tonumber
    for line in src:gmatch("[^\n]+") do
        local k = line:byte(1)
        if k == 78 then
            local id, x, y, z, w, flood, fl = line:match("^N (%d+) (%S+) (%S+) (%S+) (%S+) (%d+) (%d+)")
            id = num(id)
            P.nx[id], P.ny[id], P.nz[id], P.nw[id] = num(x), num(y), num(z), num(w)
            P.nflood[id], P.nfl[id] = num(flood), num(fl)
            P.adj[id] = {}
            if id > P.nodeCount then P.nodeCount = id end
        elseif k == 69 then
            local a, b, kind, len, group, phase = line:match("^E (%d+) (%d+) (%d+) (%S+) (%d+) (%d+)")
            local e = P.edgeCount + 1
            P.edgeCount = e
            a, b = num(a), num(b)
            P.ea[e], P.eb[e], P.ekind[e], P.elen[e] = a, b, num(kind), num(len)
            P.egroup[e], P.ephase[e] = num(group), num(phase)
            local t = P.adj[a]; t[#t + 1] = e
            t = P.adj[b]; t[#t + 1] = e
        end
    end
    P.index = SpatialHash.new(NAV.INDEX_CELL)
    for e = 1, P.edgeCount do
        P.index:add(e, P.nx[P.ea[e]], P.ny[P.ea[e]], P.nx[P.eb[e]], P.ny[P.eb[e]])
    end
    P.ready = true
    outputDebugString(("[navmesh] peds: %d nodes, %d edges (%d ms)"):format(P.nodeCount, P.edgeCount, getTickCount() - t0))
    return true
end

function Peds.other(e, n) return P.ea[e] == n and P.eb[e] or P.ea[e] end

-- nearest nodes to a point: { {node, dist}, ... } sorted, max count
function Peds.nearestNodes(x, y, z, radius, count, maxDz)
    local res, seen = {}, {}
    maxDz = maxDz or 5
    P.index:each(x, y, radius, function(e)
        for _, n in ipairs({ P.ea[e], P.eb[e] }) do
            if not seen[n] then
                seen[n] = true
                local d = sqrt((P.nx[n] - x) ^ 2 + (P.ny[n] - y) ^ 2)
                if d <= radius and (not z or math.abs(P.nz[n] - z) <= maxDz) then res[#res + 1] = { n, d } end
            end
        end
    end)
    table.sort(res, function(a, b) return a[2] < b[2] end)
    while count and #res > count do res[#res] = nil end
    return res
end

-- nearest edge: edge, dist, u, x, y, z
function Peds.nearestEdge(x, y, z, radius, kinds)
    local best, bd, bu
    P.index:each(x, y, radius or 40, function(e)
        if kinds and not kinds[P.ekind[e]] then return end
        local a, b = P.ea[e], P.eb[e]
        local d, u = segDist2D(x, y, P.nx[a], P.ny[a], P.nx[b], P.ny[b])
        if z then d = d + math.abs(P.nz[a] + (P.nz[b] - P.nz[a]) * u - z) end
        if not bd or d < bd then best, bd, bu = e, d, u end
    end)
    if not best then return nil end
    local a, b = P.ea[best], P.eb[best]
    return best, bd, bu, P.nx[a] + (P.nx[b] - P.nx[a]) * bu, P.ny[a] + (P.ny[b] - P.ny[a]) * bu, P.nz[a] + (P.nz[b] - P.nz[a]) * bu
end

local function edgeCost(e, role)
    local k = P.ekind[e]
    local c = P.elen[e] * (role.kind[k] or 1)
    if k == NAV_PED_KIND.LIT then c = c + (role.lightWait or 0) end
    return c
end

-- A* on the graph. starts / goals: { {node, initialCost}, ... }
-- returns nodes, edges, cost  or nil, reason
function Peds.search(starts, goals, role, maxNodes)
    local goalCost = {}
    local gx, gy = 0, 0
    for _, s in ipairs(goals) do
        goalCost[s[1]] = math.min(goalCost[s[1]] or huge, s[2])
        gx, gy = gx + P.nx[s[1]], gy + P.ny[s[1]]
    end
    gx, gy = gx / #goals, gy / #goals
    local wmin = math.min(unpack(role.kind))
    local function h(n) return sqrt((P.nx[n] - gx) ^ 2 + (P.ny[n] - gy) ^ 2) * wmin * 0.8 end
    local heap = Heap.new()
    local g, came, via, closed = {}, {}, {}, {}
    for _, s in ipairs(starts) do
        if not g[s[1]] or s[2] < g[s[1]] then
            g[s[1]] = s[2]
            heap:push(s[1], s[2] + h(s[1]))
        end
    end
    local best, bestCost = nil, huge
    local n, maxN = 0, maxNodes or 60000
    while heap.n > 0 do
        local node, f = heap:pop()
        if f >= bestCost then break end
        if not closed[node] then
            closed[node] = true
            n = n + 1
            if n > maxN then return nil, "search_limit" end
            if n % 500 == 0 then Nav.budget() end
            local gn = g[node]
            if goalCost[node] and gn + goalCost[node] < bestCost then best, bestCost = node, gn + goalCost[node] end
            for _, e in ipairs(P.adj[node]) do
                local o = Peds.other(e, node)
                if not closed[o] then
                    local ng = gn + edgeCost(e, role)
                    if not g[o] or ng < g[o] then
                        g[o], came[o], via[o] = ng, node, e
                        heap:push(o, ng + h(o))
                    end
                end
            end
        end
    end
    if not best then return nil, "no_route" end
    local nodes, edges = {}, {}
    local cur = best
    while cur do
        table.insert(nodes, 1, cur)
        if via[cur] then table.insert(edges, 1, via[cur]) end
        cur = came[cur]
    end
    return nodes, edges, bestCost, n
end

-- random walk along the graph (wandering peds): nodes list of about `length` metres, never straight back
function Peds.randomWalk(startNode, length, role)
    local nodes, edges = { startNode }, {}
    local cur, prev, dist = startNode, nil, 0
    local kinds = role and role.kind
    while dist < length do
        local opts = {}
        for _, e in ipairs(P.adj[cur]) do
            local o = Peds.other(e, cur)
            if o ~= prev then
                local w = kinds and 1 / (kinds[P.ekind[e]] or 1) or 1
                opts[#opts + 1] = { e, o, w }
            end
        end
        if #opts == 0 then
            if not prev then break end
            for _, e in ipairs(P.adj[cur]) do opts[#opts + 1] = { e, Peds.other(e, cur), 1 } end
        end
        local sum = 0
        for _, o in ipairs(opts) do sum = sum + o[3] end
        local r, pick = math.random() * sum, opts[#opts]
        for _, o in ipairs(opts) do
            r = r - o[3]
            if r <= 0 then pick = o; break end
        end
        edges[#edges + 1] = pick[1]
        nodes[#nodes + 1] = pick[2]
        dist = dist + P.elen[pick[1]]
        prev, cur = cur, pick[2]
    end
    return nodes, edges, dist
end
