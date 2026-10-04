-- Segment geometry (server + client): centripetal Catmull-Rom spline through the control
-- points, resampled uniformly by 3D arc length, so a point at distance s is an O(1) lookup.

Geometry = {}

local sqrt, max, ceil, floor = math.sqrt, math.max, math.ceil, math.floor

local function dist(a, b)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    return sqrt(dx * dx + dy * dy + dz * dz)
end

-- knot step of the centripetal parametrisation (alpha 0.5)
local function knot(a, b)
    return max(dist(a, b), 1e-4) ^ 0.5
end

local function lerp(a, b, ta, tb, t)
    local u = (t - ta) / (tb - ta)
    return a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u
end

-- point of the span p1 -> p2 (p0, p3 = neighbours) at parameter t in [t1, t2] (Barry-Goldman)
local function span(p0, p1, p2, p3, t0, t1, t2, t3, t)
    local a1 = { lerp(p0, p1, t0, t1, t) }
    local a2 = { lerp(p1, p2, t1, t2, t) }
    local a3 = { lerp(p2, p3, t2, t3, t) }
    local b1 = { lerp(a1, a2, t0, t2, t) }
    local b2 = { lerp(a2, a3, t1, t3, t) }
    return lerp(b1, b2, t1, t2, t)
end

-- pts = control points { {x,y,z}, ... } (>= 2); ghostA / ghostB = the point before the first /
-- after the last one (neighbour segment through the node) or nil (straight extension).
-- step = resampling step. Returns { N, h, len, xs, ys, zs } with N + 1 samples (1-based),
-- sample i at s = (i - 1) * h.
function Geometry.build(pts, ghostA, ghostB, step, dense)
    local n = #pts
    local P = {}
    P[1] = ghostA or { 2 * pts[1][1] - pts[2][1], 2 * pts[1][2] - pts[2][2], 2 * pts[1][3] - pts[2][3] }
    for i = 1, n do P[i + 1] = pts[i] end
    P[n + 2] = ghostB or { 2 * pts[n][1] - pts[n - 1][1], 2 * pts[n][2] - pts[n - 1][2], 2 * pts[n][3] - pts[n - 1][3] }

    -- dense evaluation
    local dx, dy, dz = {}, {}, {}
    local m = 0
    for k = 2, n do
        local p0, p1, p2, p3 = P[k - 1], P[k], P[k + 1], P[k + 2]
        local t0 = 0
        local t1 = t0 + knot(p0, p1)
        local t2 = t1 + knot(p1, p2)
        local t3 = t2 + knot(p2, p3)
        local cnt = max(1, ceil(dist(p1, p2) / dense))
        for j = 0, cnt - 1 do
            m = m + 1
            if j == 0 then
                dx[m], dy[m], dz[m] = p1[1], p1[2], p1[3]
            else
                dx[m], dy[m], dz[m] = span(p0, p1, p2, p3, t0, t1, t2, t3, t1 + (t2 - t1) * j / cnt)
            end
        end
    end
    m = m + 1
    dx[m], dy[m], dz[m] = pts[n][1], pts[n][2], pts[n][3]

    -- cumulative 3D length
    local cum = { 0 }
    for i = 2, m do
        local ex, ey, ez = dx[i] - dx[i - 1], dy[i] - dy[i - 1], dz[i] - dz[i - 1]
        cum[i] = cum[i - 1] + sqrt(ex * ex + ey * ey + ez * ez)
    end
    local len = cum[m]

    -- uniform resampling
    local N = max(1, floor(len / step + 0.5))
    local h = len / N
    local xs, ys, zs = {}, {}, {}
    local j = 1
    for i = 0, N do
        local s = i * h
        while j < m - 1 and cum[j + 1] < s do j = j + 1 end
        local segLen = cum[j + 1] - cum[j]
        local u = segLen > 0 and (s - cum[j]) / segLen or 0
        if u < 0 then u = 0 elseif u > 1 then u = 1 end
        xs[i + 1] = dx[j] + (dx[j + 1] - dx[j]) * u
        ys[i + 1] = dy[j] + (dy[j + 1] - dy[j]) * u
        zs[i + 1] = dz[j] + (dz[j + 1] - dz[j]) * u
    end
    xs[N + 1], ys[N + 1], zs[N + 1] = pts[n][1], pts[n][2], pts[n][3]
    return { N = N, h = h, len = len, xs = xs, ys = ys, zs = zs }
end

-- radius of the circle through three 2D points (huge for a straight line)
function Geometry.radius(x1, y1, x2, y2, x3, y3)
    local a = sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    local b = sqrt((x3 - x2) ^ 2 + (y3 - y2) ^ 2)
    local c = sqrt((x3 - x1) ^ 2 + (y3 - y1) ^ 2)
    local cross = math.abs((x2 - x1) * (y3 - y1) - (y2 - y1) * (x3 - x1))
    if cross < 1e-6 then return math.huge end
    return a * b * c / (2 * cross)
end
