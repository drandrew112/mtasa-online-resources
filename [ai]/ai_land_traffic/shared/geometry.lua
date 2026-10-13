-- Road geometry (shared): lanes and curved junction connections from data/runtime/geo.dat.
-- Server and client run the exact same pose code, so a vehicle's (segment, s, lateral) state maps
-- to the same world position everywhere.
--
-- Segment code: a positive number is a lane id, a negative number is a curved connection (-id).
-- Connections without a curve (touching lanes) are never segments: vehicles go lane -> lane.

Geo = {
    lx1 = {}, ly1 = {}, lz1 = {}, lx2 = {}, ly2 = {}, lz2 = {}, llen = {},
    cfrom = {}, cto = {}, c1x = {}, c1y = {}, c1z = {}, c2x = {}, c2y = {}, c2z = {},
    clen = {}, clut = {},
    loaded = false, lanes = 0, curves = 0,
}

local G = Geo
local sqrt, floor = math.sqrt, math.floor
local LUT_STEPS = 10

local function laneLength(id)
    local dx, dy, dz = G.lx2[id] - G.lx1[id], G.ly2[id] - G.ly1[id], G.lz2[id] - G.lz1[id]
    return sqrt(dx * dx + dy * dy + dz * dz)
end

local function bezier(id, t)
    local f, e = G.cfrom[id], G.cto[id]
    local x0, y0, z0 = G.lx2[f], G.ly2[f], G.lz2[f]
    local x3, y3, z3 = G.lx1[e], G.ly1[e], G.lz1[e]
    local x1, y1, z1, x2, y2, z2 = G.c1x[id], G.c1y[id], G.c1z[id], G.c2x[id], G.c2y[id], G.c2z[id]
    local u = 1 - t
    local a, b, c, d = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
    local x = a * x0 + b * x1 + c * x2 + d * x3
    local y = a * y0 + b * y1 + c * y2 + d * y3
    local z = a * z0 + b * z1 + c * z2 + d * z3
    -- derivative
    local da, db, dc = 3 * u * u, 6 * u * t, 3 * t * t
    local tx = da * (x1 - x0) + db * (x2 - x1) + dc * (x3 - x2)
    local ty = da * (y1 - y0) + db * (y2 - y1) + dc * (y3 - y2)
    local tz = da * (z1 - z0) + db * (z2 - z1) + dc * (z3 - z2)
    return x, y, z, tx, ty, tz
end

-- cumulative arc length table, built when the curve is first used
local function curveLut(id)
    local lut = G.clut[id]
    if lut then return lut end
    lut = { 0 }
    local px, py, pz = bezier(id, 0)
    local total = 0
    for i = 1, LUT_STEPS do
        local x, y, z = bezier(id, i / LUT_STEPS)
        total = total + sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
        lut[i + 1] = total
        px, py, pz = x, y, z
    end
    G.clut[id] = lut
    G.clen[id] = total
    return lut
end

function Geo.length(code)
    if code > 0 then return G.llen[code] or 0 end
    local id = -code
    if not G.clen[id] then curveLut(id) end
    return G.clen[id] or 0
end

-- connection id of a curve between two lanes, if any (fromLane end -> toLane start)
function Geo.isCurve(id) return G.cfrom[id] ~= nil end

-- world pose: x, y, z (road surface at the lane centre + lateral), fx, fy, fz (unit forward)
function Geo.pose(code, s, lat)
    lat = lat or 0
    local x, y, z, tx, ty, tz
    if code > 0 then
        local len = G.llen[code]
        if not len then return nil end
        local t = len > 0 and s / len or 0
        local x1, y1, z1 = G.lx1[code], G.ly1[code], G.lz1[code]
        tx, ty, tz = G.lx2[code] - x1, G.ly2[code] - y1, G.lz2[code] - z1
        x, y, z = x1 + tx * t, y1 + ty * t, z1 + tz * t
    else
        local id = -code
        if not G.cfrom[id] then return nil end
        local lut = curveLut(id)
        local total = lut[LUT_STEPS + 1]
        local t
        if s <= 0 or total <= 0 then t = 0
        elseif s >= total then t = 1
        else
            local i = 1
            while lut[i + 1] < s do i = i + 1 end
            local seg = lut[i + 1] - lut[i]
            t = (i - 1 + (seg > 0 and (s - lut[i]) / seg or 0)) / LUT_STEPS
        end
        x, y, z, tx, ty, tz = bezier(id, t)
    end
    local l = sqrt(tx * tx + ty * ty + tz * tz)
    if l < 1e-6 then tx, ty, tz, l = 0, 1, 0, 1 end
    tx, ty, tz = tx / l, ty / l, tz / l
    if lat ~= 0 then
        local h = sqrt(tx * tx + ty * ty)
        if h > 1e-6 then
            x, y = x + ty / h * lat, y - tx / h * lat
        end
    end
    return x, y, z, tx, ty, tz
end

-- position s along a chain of segment codes (s may run past the first segment into the others)
function Geo.poseOnChain(chain, n, s, lat)
    local i = 1
    while s < 0 and i > 1 do i = i - 1; s = s + Geo.length(chain[i]) end
    while i < n do
        local len = Geo.length(chain[i])
        if s <= len then break end
        s = s - len
        i = i + 1
    end
    local len = Geo.length(chain[i])
    if s > len then s = len elseif s < 0 then s = 0 end
    return Geo.pose(chain[i], s, lat)
end

-- Lateral manoeuvre (lane offset changes are steered, never slid): the offset follows a critically
-- damped response towards the target over the distance driven, with time constant tau = LAT_TAU / slope
-- metres. It starts with the current lateral rate (m per m), so the heading eases in and out instead of
-- jumping to a steering angle; the peak rate is about |offset change| / (e * tau). State is (lat, rate).
-- Closed form, so the server (tick by tick) and the clients (from the last record) get the same curve.
-- x < 0 runs it backwards (heading samples behind the car).
local LAT_TAU = 0.65
function Geo.latAfter(lat, rate, target, slope, x)
    local tau = LAT_TAU / slope
    local d = lat - target
    if d * d < 2.5e-5 and rate * rate < 1e-5 then return target, 0 end
    local b = rate + d / tau
    local r = d + b * x
    local e = math.exp(-x / tau)
    local nl, nr = target + r * e, (b - r / tau) * e
    if (nl - target) ^ 2 < 2.5e-5 and nr * nr < 1e-5 then return target, 0 end
    return nl, nr
end

function Geo.rotation(fx, fy, fz)
    local rz = (math.deg(math.atan2(fy, fx)) - 90) % 360
    local rx = math.deg(math.atan2(fz, sqrt(fx * fx + fy * fy)))
    return rx, 0, rz
end

-- parse geo.dat; yieldEvery > 0 yields the running coroutine every N lines (client loading)
function Geo.parse(text, yieldEvery)
    local n, tonumber = 0, tonumber
    for line in text:gmatch("[^\n]+") do
        local kind = line:sub(1, 1)
        if kind == "L" then
            local id, x1, y1, z1, x2, y2, z2 = line:match("^L (%d+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
            id = tonumber(id)
            if id then
                G.lx1[id], G.ly1[id], G.lz1[id] = tonumber(x1), tonumber(y1), tonumber(z1)
                G.lx2[id], G.ly2[id], G.lz2[id] = tonumber(x2), tonumber(y2), tonumber(z2)
                G.llen[id] = laneLength(id)
                G.lanes = G.lanes + 1
            end
        elseif kind == "C" then
            local id, f, e, x1, y1, z1, x2, y2, z2 = line:match("^C (%d+) (%d+) (%d+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
            id = tonumber(id)
            if id then
                G.cfrom[id], G.cto[id] = tonumber(f), tonumber(e)
                G.c1x[id], G.c1y[id], G.c1z[id] = tonumber(x1), tonumber(y1), tonumber(z1)
                G.c2x[id], G.c2y[id], G.c2z[id] = tonumber(x2), tonumber(y2), tonumber(z2)
                G.curves = G.curves + 1
            end
        end
        n = n + 1
        if yieldEvery and yieldEvery > 0 and n % yieldEvery == 0 then coroutine.yield() end
    end
    G.loaded = true
    return G.lanes, G.curves
end

function Geo.readFile(path)
    local f = fileOpen(path, true)
    if not f then return nil end
    local data = fileRead(f, fileGetSize(f))
    fileClose(f)
    return data
end
