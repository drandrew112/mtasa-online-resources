-- Boat path graph (data/runtime/boats.nav, GTA boat path nodes): plain undirected graph.

Boats = { nx = {}, ny = {}, nz = {}, nw = {}, adj = {}, nodeCount = 0, edges = {}, index = nil, ready = false }
local B = Boats
local sqrt, huge = math.sqrt, math.huge

function Boats.load()
    local src = readTextFile(NAV.BOATS_FILE)
    if not src then return false end
    for line in src:gmatch("[^\n]+") do
        local k = line:byte(1)
        if k == 78 then
            local id, x, y, z, w = line:match("^N (%d+) (%S+) (%S+) (%S+) (%S+)")
            id = tonumber(id)
            B.nx[id], B.ny[id], B.nz[id], B.nw[id] = tonumber(x), tonumber(y), tonumber(z), tonumber(w)
            B.adj[id] = {}
            if id > B.nodeCount then B.nodeCount = id end
        elseif k == 69 then
            local a, b = line:match("^E (%d+) (%d+)")
            a, b = tonumber(a), tonumber(b)
            local t = B.adj[a]; t[#t + 1] = b
            t = B.adj[b]; t[#t + 1] = a
            B.edges[#B.edges + 1] = { a, b }
        end
    end
    B.index = SpatialHash.new(100)
    for id = 1, B.nodeCount do
        if B.nx[id] then B.index:add(id, B.nx[id], B.ny[id]) end
    end
    B.ready = true
    outputDebugString(("[navmesh] boats: %d nodes, %d edges"):format(B.nodeCount, #B.edges))
    return true
end

function Boats.nearest(x, y, radius)
    local best, bd
    B.index:each(x, y, radius or 300, function(id)
        local d = sqrt((B.nx[id] - x) ^ 2 + (B.ny[id] - y) ^ 2)
        if not bd or d < bd then best, bd = id, d end
    end)
    return best, bd
end

function Boats.search(a, b)
    local heap = Heap.new()
    local g, came, closed = { [a] = 0 }, {}, {}
    local function h(n) return sqrt((B.nx[n] - B.nx[b]) ^ 2 + (B.ny[n] - B.ny[b]) ^ 2) end
    heap:push(a, h(a))
    while heap.n > 0 do
        local n = heap:pop()
        if n == b then break end
        if not closed[n] then
            closed[n] = true
            for _, o in ipairs(B.adj[n]) do
                local ng = g[n] + sqrt((B.nx[n] - B.nx[o]) ^ 2 + (B.ny[n] - B.ny[o]) ^ 2)
                if not g[o] or ng < g[o] then
                    g[o], came[o] = ng, n
                    heap:push(o, ng + h(o))
                end
            end
        end
    end
    if not g[b] then return nil end
    local nodes, cur = {}, b
    while cur do table.insert(nodes, 1, cur); cur = came[cur] end
    return nodes, g[b]
end
