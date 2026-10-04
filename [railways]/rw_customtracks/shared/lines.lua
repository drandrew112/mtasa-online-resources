-- Lines (server + client): named routes through the graph with one continuous coordinate tp
-- (metres), the "track positions" the other rw_ resources work with (rw_core keeps its old
-- (track, tp) API on top of them). Built after every Net.build.
--
-- NET.LINES[id] = { start = segment, families = { prefixes } }: walking from start@a, at every
-- node the line takes the way on whose segment id starts with one of its families (in order).
-- A segment may be on two lines (single-track stretches of the second track run on the main).

Lines = {}

local lines = {}          -- [id] = { id, pieces = { { seg, dir, tp0, len } }, len, bySeg = { [seg] = piece } }
local segLines = {}       -- [seg] = { { line, piece } }

local function family(seg, fams)
    for k, f in ipairs(fams) do
        local p = seg:match("^(%a+)")
        if p == f then return k end
    end
    return nil
end

local function straightOnLink(node, ref)
    local e = node.ends or {}
    if e[1] == ref then return e[2] elseif e[2] == ref then return e[1] end
end

-- every way on from `ref` through its node, switch states ignored -> { ref, ... }
local function waysOn(ref)
    local id, e = Net.parseRef(ref)
    local g = Net.segment(id)
    local node = g and Net.node(e == "a" and g.a or g.b)
    if not node then return {} end
    if node.type == "link" then
        local o = straightOnLink(node, ref)
        return o and { o } or {}
    elseif node.type == "switch" then
        if ref == node.trunk then return { node.normal, node.reverse } end
        return { node.trunk }
    end
    return {}
end

local function build(id, def)
    local L = { id = id, pieces = {}, len = 0, bySeg = {} }
    local seg, dir = def.start, 1
    for _ = 1, 500 do
        local g = Net.segment(seg)
        if not g then break end
        local pc = { seg = seg, dir = dir, tp0 = L.len, len = g.len }
        L.pieces[#L.pieces + 1] = pc
        L.bySeg[seg] = pc
        L.len = L.len + g.len
        local ref = seg .. "@" .. (dir > 0 and "b" or "a")
        local best, bestRank
        for _, o in ipairs(waysOn(ref)) do
            local nid = Net.parseRef(o)
            local rank = nid and family(nid, def.families)
            if rank and (not bestRank or rank < bestRank) then best, bestRank = o, rank end
        end
        if not best then break end
        local nid, ne = Net.parseRef(best)
        if nid == def.start then L.closed = true break end
        if L.bySeg[nid] then break end
        seg, dir = nid, ne == "a" and 1 or -1
    end
    lines[id] = L
    for _, pc in ipairs(L.pieces) do
        segLines[pc.seg] = segLines[pc.seg] or {}
        table.insert(segLines[pc.seg], { line = id, piece = pc })
    end
end

function Lines.build()
    lines, segLines = {}, {}
    for id, def in pairs(NET.LINES or {}) do build(id, def) end
end

function Lines.get(id) return lines[id] end
function Lines.ids()
    local t = {}
    for id in pairs(lines) do t[#t + 1] = id end
    table.sort(t)
    return t
end
function Lines.length(id) local L = lines[id] return L and L.len or 0 end
function Lines.isClosed(id) local L = lines[id] return L and L.closed or false end

function Lines.norm(id, tp)
    local L = lines[id]
    if not L then return tp end
    if L.closed then tp = tp % L.len if tp < 0 then tp = tp + L.len end return tp end
    if tp < 0 then return 0 elseif tp > L.len then return L.len end
    return tp
end

function Lines.delta(id, a, b)
    local L = lines[id]
    local d = b - a
    if L and L.closed then
        if d > L.len / 2 then d = d - L.len elseif d < -L.len / 2 then d = d + L.len end
    end
    return d
end

-- line tp -> seg, s, dir (dir = +1 when the line runs towards the segment's b end)
function Lines.toNet(id, tp)
    local L = lines[id]
    if not L or #L.pieces == 0 then return nil end
    tp = Lines.norm(id, tp)
    local lo, hi = 1, #L.pieces
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if L.pieces[mid].tp0 <= tp then lo = mid else hi = mid - 1 end
    end
    local pc = L.pieces[lo]
    local d = math.min(pc.len, math.max(0, tp - pc.tp0))
    return pc.seg, pc.dir > 0 and d or pc.len - d, pc.dir
end

-- network position -> { { line, tp, dir } } (dir = +1: the segment's +s runs with the line)
function Lines.fromNet(seg, s)
    local t = {}
    for _, e in ipairs(segLines[seg] or {}) do
        local pc = e.piece
        t[#t + 1] = { line = e.line, tp = pc.tp0 + (pc.dir > 0 and s or pc.len - s), dir = pc.dir }
    end
    return t
end

function Lines.onLine(id, seg) local L = lines[id] return L and L.bySeg[seg] ~= nil end

-- world point -> x, y, z, dirX, dirY (unit, increasing tp)
function Lines.pointAt(id, tp)
    local seg, s, dir = Lines.toNet(id, tp)
    if not seg then return 0, 0, 0, 1, 0 end
    local x, y, z, tx, ty = Net.pointAt(seg, s)
    return x, y, z, tx * dir, ty * dir
end

-- nearest point of the line to (x, y[, z]) -> tp, distance
function Lines.project(id, x, y, maxDist, z)
    local L = lines[id]
    if not L then return nil end
    local seg, s, d = Net.project(x, y, z, maxDist or 50, L.bySeg)
    if not seg then return nil end
    local pc = L.bySeg[seg]
    return pc.tp0 + (pc.dir > 0 and s or pc.len - s), d
end

function Lines.polyline(id, a, b, step)
    local pts = {}
    local d = Lines.delta(id, a, b)
    local n = math.max(1, math.ceil(math.abs(d) / (step or 10)))
    for k = 0, n do
        local x, y, z = Lines.pointAt(id, a + d * k / n)
        pts[#pts + 1] = { x, y, z }
    end
    return pts
end
