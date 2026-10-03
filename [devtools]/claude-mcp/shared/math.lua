-- Shared vector / rotation helpers.
--
-- MTA rotation convention used everywhere in the bridge:
--   rotation.z ("heading") in degrees, 0 = facing north (+Y), increasing
--   COUNTER-clockwise: 90 = west (-X), 180 = south, 270 = east (+X).
--   forward(h) = (-sin h, cos h), right(h) = (cos h, sin h).
--   Vehicles: rotation.x = pitch (+ nose up), rotation.y = roll (+ right side down).
--   Peds: only rotation.z is meaningful.
--   Objects: rotation.z rotates the model's own +Y axis; which side of a model
--   is its "front" depends on the model.

M = {}

local rad, deg, sin, cos, atan2, sqrt, floor = math.rad, math.deg, math.sin, math.cos, math.atan2 or math.atan, math.sqrt, math.floor

function M.round(v, d)
    local m = 10 ^ (d or 3)
    v = tonumber(v) or 0
    if v ~= v then return 0 end
    return floor(v * m + 0.5) / m
end

function M.vec(x, y, z, d)
    return { x = M.round(x, d), y = M.round(y, d), z = M.round(z, d) }
end

-- normalise to [0, 360)
function M.norm(a)
    a = (tonumber(a) or 0) % 360
    if a < 0 then a = a + 360 end
    return a
end

-- signed smallest difference b - a in (-180, 180]
function M.angleDiff(a, b)
    local d = M.norm(b) - M.norm(a)
    if d > 180 then d = d - 360 elseif d <= -180 then d = d + 360 end
    return d
end

function M.forward(h)
    local r = rad(h)
    return -sin(r), cos(r)
end

function M.right(h)
    local r = rad(h)
    return cos(r), sin(r)
end

-- MTA heading (rotation.z) that faces along (dx, dy)
function M.headingFromVector(dx, dy)
    if dx == 0 and dy == 0 then return 0 end
    return M.norm(deg(atan2(-dx, dy)))
end

function M.headingTo(x1, y1, x2, y2)
    return M.headingFromVector(x2 - x1, y2 - y1)
end

-- compass bearing (clockwise from north) of an MTA heading
function M.compassBearing(h)
    return M.norm(360 - M.norm(h))
end

local COMPASS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
function M.compass(h)
    local b = M.compassBearing(h)
    return COMPASS[floor((b + 22.5) / 45) % 8 + 1]
end

-- local offset (right, forward, up) around a position with a heading -> world
function M.offset(x, y, z, h, ox, oy, oz)
    local rx, ry = M.right(h)
    local fx, fy = M.forward(h)
    return x + rx * (ox or 0) + fx * (oy or 0), y + ry * (ox or 0) + fy * (oy or 0), z + (oz or 0)
end

-- world point -> local (right, forward) relative to position + heading
function M.toLocal(x, y, h, px, py)
    local dx, dy = px - x, py - y
    local rx, ry = M.right(h)
    local fx, fy = M.forward(h)
    return dx * rx + dy * ry, dx * fx + dy * fy
end

function M.dist2D(x1, y1, x2, y2)
    return sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

function M.dist3D(x1, y1, z1, x2, y2, z2)
    return sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2)
end

-- describes where point B is relative to an observer at A facing heading h
function M.relation(ax, ay, az, h, bx, by, bz)
    local lr, fb = M.toLocal(ax, ay, h, bx, by)
    local bearing = M.headingTo(ax, ay, bx, by)
    local rel = M.angleDiff(h, bearing) -- + = to the left (CCW)
    local side
    local a = math.abs(rel)
    if a <= 30 then side = "front"
    elseif a >= 150 then side = "behind"
    elseif rel > 0 then side = (a < 60 and "front-left") or (a > 120 and "back-left") or "left"
    else side = (a < 60 and "front-right") or (a > 120 and "back-right") or "right" end
    return {
        distance = M.round(M.dist3D(ax, ay, az or 0, bx, by, bz or 0), 2),
        distance2D = M.round(M.dist2D(ax, ay, bx, by), 2),
        heightDiff = M.round((bz or 0) - (az or 0), 2),
        localRight = M.round(lr, 2), localForward = M.round(fb, 2),
        bearingHeading = M.round(bearing, 1),
        compass = M.compass(bearing),
        relativeAngle = M.round(rel, 1),
        side = side,
    }
end

-- rotation matrix rows for MTA's default (ZXY) Euler order: right, forward, up
function M.matrix(rx, ry, rz)
    rx, ry, rz = rad(rx or 0), rad(ry or 0), rad(rz or 0)
    local sx, cx, sy, cy, sz, cz = sin(rx), cos(rx), sin(ry), cos(ry), sin(rz), cos(rz)
    return {
        { cz * cy - sz * sx * sy, cz * sy * sx + cy * sz, -cx * sy },
        { -cx * sz, cz * cx, sx },
        { sz * sx * cy + cz * sy, sy * sz - cz * cy * sx, cx * cy },
    }
end

-- 8 world corners of a local bounding box under a position + rotation
function M.boxCorners(px, py, pz, rx, ry, rz, minX, minY, minZ, maxX, maxY, maxZ)
    local m = M.matrix(rx, ry, rz)
    local out = {}
    for _, lx in ipairs({ minX, maxX }) do
        for _, ly in ipairs({ minY, maxY }) do
            for _, lz in ipairs({ minZ, maxZ }) do
                out[#out + 1] = {
                    px + lx * m[1][1] + ly * m[2][1] + lz * m[3][1],
                    py + lx * m[1][2] + ly * m[2][2] + lz * m[3][2],
                    pz + lx * m[1][3] + ly * m[2][3] + lz * m[3][3],
                }
            end
        end
    end
    return out
end

-- Separating-axis test of two oriented boxes.
-- box = { c = {x,y,z}, axes = { {..},{..},{..} } (unit), half = {hx,hy,hz} }
-- -> overlapping (bool), penetration depth estimate (m, along the best axis)
local function dot(a, b) return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function cross(a, b) return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] } end

function M.obb(px, py, pz, rx, ry, rz, minX, minY, minZ, maxX, maxY, maxZ)
    local m = M.matrix(rx, ry, rz)
    local cxl, cyl, czl = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
    local c = {
        px + cxl * m[1][1] + cyl * m[2][1] + czl * m[3][1],
        py + cxl * m[1][2] + cyl * m[2][2] + czl * m[3][2],
        pz + cxl * m[1][3] + cyl * m[2][3] + czl * m[3][3],
    }
    return { c = c, axes = { m[1], m[2], m[3] }, half = { (maxX - minX) / 2, (maxY - minY) / 2, (maxZ - minZ) / 2 } }
end

function M.obbOverlap(a, b)
    local t = { b.c[1] - a.c[1], b.c[2] - a.c[2], b.c[3] - a.c[3] }
    local axes = {}
    for i = 1, 3 do axes[#axes + 1] = a.axes[i]; axes[#axes + 1] = b.axes[i] end
    for i = 1, 3 do
        for j = 1, 3 do
            local c = cross(a.axes[i], b.axes[j])
            if dot(c, c) > 1e-6 then
                local l = sqrt(dot(c, c))
                axes[#axes + 1] = { c[1] / l, c[2] / l, c[3] / l }
            end
        end
    end
    local minPen = math.huge
    for _, L in ipairs(axes) do
        local ra = a.half[1] * math.abs(dot(a.axes[1], L)) + a.half[2] * math.abs(dot(a.axes[2], L)) + a.half[3] * math.abs(dot(a.axes[3], L))
        local rb = b.half[1] * math.abs(dot(b.axes[1], L)) + b.half[2] * math.abs(dot(b.axes[2], L)) + b.half[3] * math.abs(dot(b.axes[3], L))
        local pen = ra + rb - math.abs(dot(t, L))
        if pen < 0 then return false, 0 end
        if pen < minPen then minPen = pen end
    end
    return true, minPen
end

-- gap between two OBBs projected on the ground plane (approximate clearance, m; 0 = touching/overlap)
function M.obbClearance2D(a, b)
    local best = math.huge
    local function corners(o)
        local out = {}
        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                out[#out + 1] = {
                    o.c[1] + o.axes[1][1] * o.half[1] * sx + o.axes[2][1] * o.half[2] * sy,
                    o.c[2] + o.axes[1][2] * o.half[1] * sx + o.axes[2][2] * o.half[2] * sy,
                }
            end
        end
        return out
    end
    local function pointInside(o, p)
        local d = { p[1] - o.c[1], p[2] - o.c[2] }
        local u = d[1] * o.axes[1][1] + d[2] * o.axes[1][2]
        local v = d[1] * o.axes[2][1] + d[2] * o.axes[2][2]
        return math.abs(u) <= o.half[1] and math.abs(v) <= o.half[2]
    end
    local function segDist(p, a1, a2)
        local vx, vy = a2[1] - a1[1], a2[2] - a1[2]
        local wx, wy = p[1] - a1[1], p[2] - a1[2]
        local l2 = vx * vx + vy * vy
        local t = l2 > 0 and math.max(0, math.min(1, (wx * vx + wy * vy) / l2)) or 0
        return M.dist2D(p[1], p[2], a1[1] + vx * t, a1[2] + vy * t)
    end
    local ca, cb = corners(a), corners(b)
    local order = { 1, 2, 4, 3 }
    for _, p in ipairs(ca) do if pointInside(b, p) then return 0 end end
    for _, p in ipairs(cb) do if pointInside(a, p) then return 0 end end
    for _, set in ipairs({ { ca, cb }, { cb, ca } }) do
        local pts, poly = set[1], set[2]
        for _, p in ipairs(pts) do
            for i = 1, 4 do
                local d = segDist(p, poly[order[i]], poly[order[i % 4 + 1]])
                if d < best then best = d end
            end
        end
    end
    return best
end
