-- Track geometry for rw_core: the lines of rw_customtracks (0 = main line loop, 3 = second track
-- loop). A "track position" (tp) is the distance along the line in metres. Line lengths are cached.

Track = {}

local lengths = {}
local closed = {}     -- [id] = true for loops (0, 3); open lines (Cranberry hall tracks) don't wrap
local function net() return exports.rw_customtracks end

function Track.length(id)
    if not lengths[id] then
        lengths[id] = net():lineLength(id) or 0
        for _, l in ipairs(net():getNetLines() or {}) do closed[l.id] = l.closed end
    end
    return lengths[id]
end

function Track.get(id)
    local L = Track.length(id)
    if L and L > 0 then return { id = id, len = L, closed = closed[id] and true or false } end
    return nil
end

function Track.ids() return RW.TRACKS end

function Track.norm(id, tp)
    local L = Track.length(id)
    if L <= 0 then return tp end
    if not closed[id] then return math.max(0, math.min(L, tp)) end
    tp = tp % L
    if tp < 0 then tp = tp + L end
    return tp
end

function Track.delta(id, a, b)
    local L = Track.length(id)
    local d = b - a
    if L > 0 and closed[id] then
        if d > L / 2 then d = d - L elseif d < -L / 2 then d = d + L end
    end
    return d
end

-- -> x, y, z, dirX, dirY
function Track.pointAt(id, tp) return net():linePoint(id, tp) end

function Track.headingAt(id, tp)
    local _, _, _, dx, dy = Track.pointAt(id, tp)
    return (math.deg(math.atan2(dy, dx)) - 90) % 360
end

-- -> tp, distance | nil
function Track.project(id, x, y, maxDist)
    local tp, d = net():lineProject(id, x, y, maxDist or 64)
    if not tp then return nil end
    return tp, d
end

function Track.nearest(x, y, maxDist, ids)
    local bestId, bestTp, bestD
    for _, id in ipairs(ids or RW.TRACKS) do
        local tp, d = Track.project(id, x, y, maxDist)
        if tp and (not bestD or d < bestD) then bestId, bestTp, bestD = id, tp, d end
    end
    return bestId, bestTp, bestD
end

function Track.polyline(id, a, b, step) return net():linePolyline(id, a, b, step) end

-- the network was rebuilt (edits): line lengths may have changed
addEvent("onNetNetworkRebuilt", false)
addEventHandler("onNetNetworkRebuilt", root, function() lengths = {} end)
