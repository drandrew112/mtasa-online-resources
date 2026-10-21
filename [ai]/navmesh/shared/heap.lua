-- Binary min-heap of (key, priority) pairs for the A* searches.

Heap = {}
Heap.__index = Heap

function Heap.new()
    return setmetatable({ k = {}, p = {}, n = 0 }, Heap)
end

function Heap:push(key, pri)
    local k, p = self.k, self.p
    local i = self.n + 1
    self.n = i
    while i > 1 do
        local parent = (i - i % 2) / 2
        if p[parent] <= pri then break end
        k[i], p[i] = k[parent], p[parent]
        i = parent
    end
    k[i], p[i] = key, pri
end

function Heap:pop()
    local n = self.n
    if n == 0 then return nil end
    local k, p = self.k, self.p
    local topK, topP = k[1], p[1]
    local lastK, lastP = k[n], p[n]
    k[n], p[n] = nil, nil
    n = n - 1
    self.n = n
    if n > 0 then
        local i = 1
        while true do
            local c = i * 2
            if c > n then break end
            if c < n and p[c + 1] < p[c] then c = c + 1 end
            if p[c] >= lastP then break end
            k[i], p[i] = k[c], p[c]
            i = c
        end
        k[i], p[i] = lastK, lastP
    end
    return topK, topP
end

-- spatial hash of points / segments for nearest queries
SpatialHash = {}
SpatialHash.__index = SpatialHash

function SpatialHash.new(cell)
    return setmetatable({ cell = cell, cells = {} }, SpatialHash)
end

local floor = math.floor
function SpatialHash:key(x, y)
    return floor(x / self.cell) * 100000 + floor(y / self.cell)
end

function SpatialHash:add(id, x1, y1, x2, y2)
    x2, y2 = x2 or x1, y2 or y1
    local c = self.cell
    for gx = floor(math.min(x1, x2) / c), floor(math.max(x1, x2) / c) do
        for gy = floor(math.min(y1, y2) / c), floor(math.max(y1, y2) / c) do
            local key = gx * 100000 + gy
            local t = self.cells[key]
            if not t then t = {}; self.cells[key] = t end
            t[#t + 1] = id
        end
    end
end

-- calls fn(id) once per id in the cells touching the radius (ids can repeat across cells: dedupe in fn)
function SpatialHash:each(x, y, r, fn)
    local c = self.cell
    for gx = floor((x - r) / c), floor((x + r) / c) do
        for gy = floor((y - r) / c), floor((y + r) / c) do
            local t = self.cells[gx * 100000 + gy]
            if t then
                for i = 1, #t do fn(t[i]) end
            end
        end
    end
end

-- distance from point to segment in 2D, returns d, u (0..1 along the segment)
function segDist2D(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local L2 = dx * dx + dy * dy
    local u = 0
    if L2 > 1e-9 then
        u = ((px - ax) * dx + (py - ay) * dy) / L2
        if u < 0 then u = 0 elseif u > 1 then u = 1 end
    end
    local qx, qy = ax + dx * u - px, ay + dy * u - py
    return math.sqrt(qx * qx + qy * qy), u
end

function readTextFile(path)
    local f = fileOpen(path, true)
    if not f then return nil end
    local s = fileRead(f, fileGetSize(f))
    fileClose(f)
    return s
end
