-- The track network (server + client): segments joined by nodes, built from the raw data of
-- the network files. A network position is (seg, s, dir): s = metres from the segment's `a` end
-- (3D arc length), dir = +1 towards the `b` end, -1 towards `a`.
--
-- Raw data (one table per file, see data/network/*.json):
--   segments = { { id, kind, name, a, b, tags, pts = { {x,y,z}, ... } } }
--   nodes    = { { id, type = link|switch|buffer, ends = { "SEG@a", ... },        (link / buffer)
--                  trunk, normal, reverse, group, spring } }                      (switch)
--   groups   = { { id, name, nodes = { nodeId, ... }, spring } }   (a switch: its nodes move together)
--   crossings = { { segA, segB } }        diamond crossings (no node, a train runs straight on)

Net = {}

local sqrt, floor, huge = math.sqrt, math.floor, math.huge

local segs, nodes, groups, crossings = {}, {}, {}, {}
local segList = {}                -- ids, sorted
local grid = {}                   -- [cellKey] = { seg, i, seg, i, ... } (span i -> i + 1)
local states = {}                 -- [group id] = "normal" | "reverse"
local CELL = NET.CELL

local function cellKey(cx, cy) return cx * 100000 + cy end

-- "SEG@a" -> "SEG", "a"
function Net.parseRef(ref)
    if type(ref) ~= "string" then return nil end
    return ref:match("^(.+)@([ab])$")
end

-- ------------------------------------------------------------------ continuation rules

-- Straight-on continuation through a node, ignoring switch states (used for end tangents):
-- link -> the other end, switch: trunk -> normal, normal / reverse -> trunk.
local function straightOn(node, ref)
    if not node then return nil end
    if node.type == "link" then
        local e = node.ends or {}
        if e[1] == ref then return e[2] elseif e[2] == ref then return e[1] end
    elseif node.type == "switch" then
        if ref == node.trunk then return node.normal end
        if ref == node.normal or ref == node.reverse then return node.trunk end
    end
    return nil
end

-- The end a train continues on after arriving at `node` through `ref`, with the current
-- switch states. Returns ref, trailed (true when it ran through a switch set the other way).
function Net.continueEnd(node, ref, stateOf)
    if not node then return nil end
    if node.type == "link" then
        return straightOn(node, ref), false
    elseif node.type == "switch" then
        local st = (stateOf and stateOf(node.group)) or states[node.group] or "normal"
        if ref == node.trunk then
            return st == "reverse" and node.reverse or node.normal, false
        -- trailing a spring switch set the other way is normal operation, not an event
        elseif ref == node.normal then
            return node.trunk, st == "reverse" and not node.spring
        elseif ref == node.reverse then
            return node.trunk, st ~= "reverse" and not node.spring
        end
    end
    return nil    -- buffer stop / open end
end

-- ------------------------------------------------------------------ build

-- control point next to the end `e` of raw segment `r` (the one a neighbour uses as ghost)
local function innerPoint(r, e)
    local pts = r.pts
    if e == "a" then return pts[2] or pts[1] end
    return pts[#pts - 1] or pts[#pts]
end

local function ghost(rawSegs, rawNodes, r, e)
    local node = rawNodes[e == "a" and r.a or r.b]
    local nref = straightOn(node, r.id .. "@" .. e)
    local nid, ne = Net.parseRef(nref)
    local nr = nid and rawSegs[nid]
    if not nr or nr == r then return nil end
    return innerPoint(nr, ne)
end

local function addToGrid(id, sg)
    local xs, ys = sg.xs, sg.ys
    for i = 1, sg.N do
        local x0, x1, y0, y1 = xs[i], xs[i + 1], ys[i], ys[i + 1]
        if x0 > x1 then x0, x1 = x1, x0 end
        if y0 > y1 then y0, y1 = y1, y0 end
        for cx = floor(x0 / CELL), floor(x1 / CELL) do
            for cy = floor(y0 / CELL), floor(y1 / CELL) do
                local k = cellKey(cx, cy)
                local list = grid[k]
                if not list then list = {} grid[k] = list end
                list[#list + 1] = id
                list[#list + 1] = i
            end
        end
    end
end

-- 2D intersection of two segments' polylines -> sA, sB, x, y (first one found)
local function intersect(A, B)
    for i = 1, A.N do
        local px, py, qx, qy = A.xs[i], A.ys[i], A.xs[i + 1], A.ys[i + 1]
        for j = 1, B.N do
            local rx, ry, sx, sy = B.xs[j], B.ys[j], B.xs[j + 1], B.ys[j + 1]
            local d = (qx - px) * (sy - ry) - (qy - py) * (sx - rx)
            if math.abs(d) > 1e-9 then
                local u = ((rx - px) * (sy - ry) - (ry - py) * (sx - rx)) / d
                local v = ((rx - px) * (qy - py) - (ry - py) * (qx - px)) / d
                if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
                    return (i - 1 + u) * A.h, (j - 1 + v) * B.h, px + (qx - px) * u, py + (qy - py) * u
                end
            end
        end
    end
end

-- files = { { file = name, segments = {...}, nodes = {...}, groups = {...}, crossings = {...} } }
function Net.build(files)
    local t0 = getTickCount()
    segs, nodes, groups, crossings, segList, grid = {}, {}, {}, {}, {}, {}
    local rawSegs, rawNodes = {}, {}
    for _, f in ipairs(files) do
        for _, r in ipairs(f.segments or {}) do r.file = f.file rawSegs[r.id] = r end
        for _, n in ipairs(f.nodes or {}) do n.file = f.file rawNodes[n.id] = n end
        for _, g in ipairs(f.groups or {}) do g.file = f.file groups[g.id] = g end
        for _, c in ipairs(f.crossings or {}) do crossings[#crossings + 1] = { a = c[1], b = c[2], file = f.file } end
    end
    nodes = rawNodes

    for id, r in pairs(rawSegs) do
        if type(r.pts) == "table" and #r.pts >= 2 then
            local g = Geometry.build(r.pts, ghost(rawSegs, rawNodes, r, "a"), ghost(rawSegs, rawNodes, r, "b"), NET.STEP, NET.DENSE)
            g.id, g.kind, g.name, g.tags, g.a, g.b, g.file, g.raw = id, r.kind or "other", r.name, r.tags or {}, r.a, r.b, r.file, r
            segs[id] = g
            segList[#segList + 1] = id
            addToGrid(id, g)
        else
            if DEBUG_ENABLED then outputDebugString("[rw_customtracks] segment " .. tostring(id) .. " has fewer than 2 points", 2) end
        end
    end
    table.sort(segList)

    for _, c in ipairs(crossings) do
        local A, B = segs[c.a], segs[c.b]
        if A and B then c.sa, c.sb, c.x, c.y = intersect(A, B) end
    end

    if Lines then Lines.build() end

    -- default switch states (keep the current ones across rebuilds)
    for gid in pairs(groups) do states[gid] = states[gid] or "normal" end
    for _, n in pairs(nodes) do
        if n.type == "switch" and n.group and not groups[n.group] then
            groups[n.group] = { id = n.group, name = n.group, nodes = { n.id } }
            states[n.group] = states[n.group] or "normal"
        end
    end
    return getTickCount() - t0
end

-- ------------------------------------------------------------------ queries

function Net.segment(id) return segs[id] end
function Net.node(id) return nodes[id] end
function Net.group(id) return groups[id] end
function Net.segmentIds() return segList end
function Net.nodes() return nodes end
function Net.groups() return groups end
function Net.crossings() return crossings end
function Net.length(id) local g = segs[id] return g and g.len or 0 end

function Net.getState(gid) return states[gid] or "normal" end
function Net.setState(gid, st) states[gid] = (st == "reverse") and "reverse" or "normal" end
function Net.getStates() return states end
function Net.setStates(t) for k, v in pairs(t or {}) do states[k] = v end end

-- point at s on a segment -> x, y, z, tx, ty, tz (unit tangent towards b)
function Net.pointAt(id, s)
    local g = segs[id]
    if not g then return nil end
    if s < 0 then s = 0 elseif s > g.len then s = g.len end
    local f = s / g.h
    local i = floor(f)
    if i >= g.N then i = g.N - 1 end
    f = f - i
    i = i + 1
    local xs, ys, zs = g.xs, g.ys, g.zs
    local x0, y0, z0 = xs[i], ys[i], zs[i]
    local ex, ey, ez = xs[i + 1] - x0, ys[i + 1] - y0, zs[i + 1] - z0
    local l = sqrt(ex * ex + ey * ey + ez * ez)
    if l < 1e-6 then l = 1 end
    return x0 + ex * f, y0 + ey * f, z0 + ez * f, ex / l, ey / l, ez / l
end

-- curve radius (2D) around s, measured over +-span metres
function Net.radiusAt(id, s, span)
    local g = segs[id]
    if not g then return huge end
    span = span or 5
    local a = math.max(0, s - span)
    local b = math.min(g.len, s + span)
    local x1, y1 = Net.pointAt(id, a)
    local x2, y2 = Net.pointAt(id, (a + b) / 2)
    local x3, y3 = Net.pointAt(id, b)
    return Geometry.radius(x1, y1, x2, y2, x3, y3)
end

-- gradient (dz / ds) around s
function Net.gradeAt(id, s, span)
    local g = segs[id]
    if not g then return 0 end
    span = span or 5
    local a = math.max(0, s - span)
    local b = math.min(g.len, s + span)
    if b - a < 0.01 then return 0 end
    local _, _, za = Net.pointAt(id, a)
    local _, _, zb = Net.pointAt(id, b)
    return (zb - za) / (b - a)
end

-- Nearest network point to (x, y[, z]) within maxDist -> seg, s, distance.
-- With z, the 3D distance decides (tracks above each other: bridges, tunnels).
-- only = { [segId] = true } limits the search to those segments.
function Net.project(x, y, z, maxDist, only)
    maxDist = maxDist or CELL
    local r = math.ceil(maxDist / CELL)
    local cx, cy = floor(x / CELL), floor(y / CELL)
    local bestSeg, bestS, bestD = nil, nil, huge
    for ox = -r, r do
        for oy = -r, r do
            local list = grid[cellKey(cx + ox, cy + oy)]
            if list then
                for k = 1, #list, 2 do
                  if not only or only[list[k]] then
                    local g = segs[list[k]]
                    local i = list[k + 1]
                    local x0, y0, z0 = g.xs[i], g.ys[i], g.zs[i]
                    local ex, ey = g.xs[i + 1] - x0, g.ys[i + 1] - y0
                    local l2 = ex * ex + ey * ey
                    local f = 0
                    if l2 > 0 then
                        f = ((x - x0) * ex + (y - y0) * ey) / l2
                        if f < 0 then f = 0 elseif f > 1 then f = 1 end
                    end
                    local qx, qy = x0 + ex * f, y0 + ey * f
                    local d2 = (x - qx) ^ 2 + (y - qy) ^ 2
                    if z then d2 = d2 + (z - (z0 + (g.zs[i + 1] - z0) * f)) ^ 2 end
                    if d2 < bestD then bestD, bestSeg, bestS = d2, list[k], (i - 1 + f) * g.h end
                  end
                end
            end
        end
    end
    if not bestSeg then return nil end
    local d = sqrt(bestD)
    if d > maxDist then return nil end
    return bestSeg, bestS, d
end

-- Moves `ds` (>= 0) metres from (seg, s) in direction dir through the nodes with the current
-- switch states (or stateOf(group)). Returns seg, s, dir, left, passed, stop:
--   left   = metres that could not be travelled (stopped at a buffer / open end)
--   passed = { { node, from, to, trailed }, ... } nodes crossed, in order
--   stop   = node id (or "open") where it stopped, nil otherwise
function Net.advance(seg, s, dir, ds, stateOf)
    local passed = {}
    for _ = 1, 1000 do
        local g = segs[seg]
        if not g then return seg, s, dir, ds, passed, "open" end
        local room = dir > 0 and g.len - s or s
        if ds <= room then
            return seg, s + dir * ds, dir, 0, passed
        end
        ds = ds - room
        local e = dir > 0 and "b" or "a"
        local nodeId = dir > 0 and g.b or g.a
        local node = nodes[nodeId]
        local nref, trailed = Net.continueEnd(node, seg .. "@" .. e, stateOf)
        local nid, ne = Net.parseRef(nref)
        if not nid or not segs[nid] then
            return seg, dir > 0 and g.len or 0, dir, ds, passed, nodeId or "open"
        end
        passed[#passed + 1] = { node = nodeId, from = seg .. "@" .. e, to = nref, trailed = trailed }
        seg = nid
        if ne == "a" then s, dir = 0, 1 else s, dir = segs[nid].len, -1 end
    end
    return seg, s, dir, ds, passed, "loop"
end

-- calls fn(segId, i) for every span (sample i -> i + 1) in the grid cells around (x, y).
-- A span crossing a cell border may come twice.
function Net.forSpansNear(x, y, radius, fn)
    local r = math.ceil(radius / CELL)
    local cx, cy = floor(x / CELL), floor(y / CELL)
    for ox = -r, r do
        for oy = -r, r do
            local list = grid[cellKey(cx + ox, cy + oy)]
            if list then
                for k = 1, #list, 2 do fn(list[k], list[k + 1]) end
            end
        end
    end
end

-- the ends meeting at a node (all roles) -> { ref, ... }
function Net.nodeEnds(node)
    if not node then return {} end
    if node.type == "switch" then
        local t = {}
        for _, k in ipairs({ "trunk", "normal", "reverse" }) do if node[k] then t[#t + 1] = node[k] end end
        return t
    end
    return node.ends or {}
end

-- world point of a segment end "SEG@a"
function Net.endPoint(ref)
    local id, e = Net.parseRef(ref)
    local g = id and segs[id]
    if not g then return nil end
    local s = e == "a" and 0 or g.len
    return Net.pointAt(id, s)
end

function Net.summary()
    local total, byKind = 0, {}
    for _, id in ipairs(segList) do
        local g = segs[id]
        total = total + g.len
        byKind[g.kind] = (byKind[g.kind] or 0) + g.len
    end
    local nn, ng = 0, 0
    for _ in pairs(nodes) do nn = nn + 1 end
    for _ in pairs(groups) do ng = ng + 1 end
    return { segments = #segList, nodes = nn, groups = ng, crossings = #crossings, length = total, byKind = byKind }
end
