-- Switch states from the server, and the rails of segments that have no physical rails in the
-- map (tag "drawn": crossovers, junctions): sleepers + two rails along the curve, drawn with dx.

NetClient.switches = {}    -- [group] = { state, locked, reserved owner | false, damaged }

addEvent("rw:net:switches", true)
addEventHandler("rw:net:switches", resourceRoot, function(payload)
    NetClient.switches = payload or {}
    local st = {}
    for g, e in pairs(NetClient.switches) do st[g] = e[1] end
    Net.setStates(st)
end)

local GAUGE = 1.435
local SLEEPER_STEP = 0.7
local DRAW_DIST = 160
local RAIL_Z, SLEEPER_Z = -0.03, -0.17       -- relative to the network's rail level

local white = dxCreateTexture(1, 1)
do
    local px = dxGetTexturePixels(white)
    if px then dxSetPixelColor(px, 0, 0, 255, 255, 255, 255) dxSetTexturePixels(white, px) end
end

local built = {}           -- [segId] = { cx, cy, r, rails = {...}, sleepers = {...} } per network version
local version = -1

local function hasTag(g, tag)
    for _, t in ipairs(g.tags or {}) do if t == tag then return true end end
    return false
end

local function build(id)
    local g = Net.segment(id)
    local b = { rails = {}, sleepers = {} }
    local n = math.max(2, math.floor(g.len / SLEEPER_STEP))
    local pts = {}
    for i = 0, n do
        local x, y, z, tx, ty = Net.pointAt(id, g.len * i / n)
        local l = math.sqrt(tx * tx + ty * ty)
        if l < 1e-4 then l = 1 end
        pts[i] = { x, y, z, -ty / l, tx / l }
    end
    for i = 1, n - 1 do
        local p = pts[i]
        b.sleepers[#b.sleepers + 1] = { p[1] - p[4] * 1.3, p[2] - p[5] * 1.3, p[3] + SLEEPER_Z, p[1] + p[4] * 1.3, p[2] + p[5] * 1.3, p[3] + SLEEPER_Z }
    end
    for side = -1, 1, 2 do
        local o = side * GAUGE / 2
        for i = 0, n - 1, 2 do
            local p, q = pts[i], pts[math.min(n, i + 2)]
            b.rails[#b.rails + 1] = { p[1] + p[4] * o, p[2] + p[5] * o, p[3] + RAIL_Z, q[1] + q[4] * o, q[2] + q[5] * o, q[3] + RAIL_Z }
        end
    end
    local m = pts[math.floor(n / 2)]
    b.cx, b.cy, b.r = m[1], m[2], g.len / 2
    return b
end

local function lightFactor()
    local h, m = getTime()
    local t = h + m / 60
    if t >= 7 and t <= 19 then return 1 end
    if t >= 21 or t <= 5 then return 0.45 end
    if t < 7 then return 0.45 + (t - 5) / 2 * 0.55 end
    return 1 - (t - 19) / 2 * 0.55
end

addEventHandler("onClientRender", root, function()
    if not NetClient.ready then return end
    if version ~= NetClient.version then
        version = NetClient.version
        built = {}
        for _, id in ipairs(Net.segmentIds()) do
            if hasTag(Net.segment(id), "drawn") then built[id] = false end
        end
    end
    local cx, cy = getCameraMatrix()
    local lf
    for id, b in pairs(built) do
        local g = Net.segment(id)
        if g then
            if not b then b = build(id) built[id] = b end
            local d = getDistanceBetweenPoints2D(cx, cy, b.cx, b.cy) - b.r
            if d < DRAW_DIST then
                lf = lf or lightFactor()
                local sl = tocolor(78 * lf, 62 * lf, 48 * lf, 255)
                local rl = tocolor(150 * lf, 148 * lf, 145 * lf, 255)
                if d < DRAW_DIST * 0.7 then
                    for _, s in ipairs(b.sleepers) do
                        dxDrawMaterialLine3D(s[1], s[2], s[3], s[4], s[5], s[6], white, 0.24, sl, s[1], s[2], s[3] + 10)
                    end
                end
                for _, r in ipairs(b.rails) do
                    dxDrawMaterialLine3D(r[1], r[2], r[3], r[4], r[5], r[6], white, 0.075, rl, r[1], r[2], r[3] + 10)
                end
            end
        end
    end
end)
