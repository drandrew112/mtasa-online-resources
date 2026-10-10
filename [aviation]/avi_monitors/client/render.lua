-- v_monitors: draws one wall monitor into the current render target.
--   radar monitor : fixed view of the whole CTA with all traffic
--   position screen: the scope of a staffed controller (their zoom / pan / label offsets, as last
--                    reported), or NOT IN USE
-- Everything is plain dxDraw (lines, rectangles, text); the render target is only drawn when the
-- data changes (every 5 s).

MonRender = {}

local C = {
    bg       = tocolor(7, 13, 22, 255),
    off      = tocolor(9, 11, 14, 255),
    offText  = tocolor(150, 110, 40, 255),
    bezel    = tocolor(28, 31, 36, 255),
    plate    = tocolor(10, 14, 20, 255),
    plateTx  = tocolor(228, 234, 244, 255),
    plateDim = tocolor(125, 135, 150, 255),
    on       = tocolor(60, 190, 100, 255),
    idle     = tocolor(120, 55, 50, 255),
    bar      = tocolor(14, 22, 34, 255),
    barLine  = tocolor(50, 80, 120, 255),
    text     = tocolor(220, 228, 240, 255),
    dim      = tocolor(120, 132, 150, 255),
    list     = tocolor(10, 16, 26, 245),
    cta      = tocolor(55, 75, 105, 255),
    tma      = tocolor(60, 100, 140, 255),
    ctr      = tocolor(95, 145, 185, 255),
    ownFill  = tocolor(70, 120, 170, 16),
    ownLine  = tocolor(140, 190, 230, 255),
    asText   = tocolor(80, 110, 145, 255),
    runway   = tocolor(185, 190, 200, 255),
    rwText   = tocolor(170, 175, 185, 255),
    arr      = tocolor(80, 200, 120, 255),
    dep      = tocolor(90, 150, 240, 255),
    taxi     = tocolor(52, 58, 68, 255),
    gate     = tocolor(95, 100, 112, 255),
    fix      = tocolor(115, 135, 165, 255),
    fixFinal = tocolor(80, 150, 110, 255),
    vor      = tocolor(150, 175, 210, 255),
    ndb      = tocolor(185, 145, 90, 255),
    navText  = tocolor(105, 125, 150, 255),
    apt      = tocolor(150, 160, 175, 255),
    air      = tocolor(95, 170, 255, 255),
    airOther = tocolor(140, 145, 155, 255),
    ctlTx    = tocolor(255, 255, 255, 255),
    hist     = tocolor(70, 120, 190, 160),
    histO    = tocolor(100, 105, 115, 160),
    vector   = tocolor(90, 150, 230, 200),
    vectorO  = tocolor(120, 125, 135, 200),
    leader   = tocolor(80, 130, 200, 200),
    leaderO  = tocolor(110, 115, 125, 200),
    gArr     = tocolor(35, 125, 65, 235),
    gDep     = tocolor(35, 85, 165, 235),
    gUnk     = tocolor(85, 88, 95, 235),
    gText    = tocolor(240, 244, 250, 255),
}

local F
local function fonts()
    if F then return F end
    local function f(file, size)
        return dxCreateFont(file, size, false, "cleartype") or "default"
    end
    F = {
        map   = f("fonts/Roboto.ttf", 9),
        lbl   = f("fonts/RobotoB.ttf", 10),
        top   = f("fonts/RobotoB.ttf", 12),
        huge  = f("fonts/RobotoB.ttf", 46),
        plate = f("fonts/RobotoB.ttf", 40),
        small = f("fonts/Roboto.ttf", 20),
    }
    return F
end

-- ---------------------------------------------------------------- helpers
local V    -- current view transform

local function w2p(x, y)
    return V.ox + V.k * (V.csx / 2 + (x - V.vx) * V.vs), V.oy + V.k * (V.csy / 2 - (y - V.vy) * V.vs)
end

local function txt(str, x, y, col, font, ax, ay)
    dxDrawText(str, x, y, x, y, col, 1, font, ax or "left", ay or "top", false, false, false, false, true)
end

local function line(x1, y1, x2, y2, col, w)
    dxDrawLine(x1, y1, x2, y2, col, w or 1)
end

local function dashed(x1, y1, x2, y2, col, w, dash, gap)
    local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
    if len < 1 then return end
    local ux, uy = (x2 - x1) / len, (y2 - y1) / len
    local d = 0
    while d < len do
        local e = math.min(len, d + dash)
        dxDrawLine(x1 + ux * d, y1 + uy * d, x1 + ux * e, y1 + uy * e, col, w or 1)
        d = e + gap
    end
end

local function polyPts(poly)
    local pts = {}
    for i, p in ipairs(poly) do
        local x, y = w2p(p[1], p[2])
        pts[i] = { x, y }
    end
    return pts
end

local function fillPoly(pts, col)
    local cx, cy = 0, 0
    for _, p in ipairs(pts) do cx, cy = cx + p[1], cy + p[2] end
    cx, cy = cx / #pts, cy / #pts
    local v = { { cx, cy, col } }
    for _, p in ipairs(pts) do v[#v + 1] = { p[1], p[2], col } end
    v[#v + 1] = { pts[1][1], pts[1][2], col }
    dxDrawPrimitive("trianglefan", false, unpack(v))
end

local function inPoly(x, y, poly)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

local function navPoint(static, id)
    if not id then return end
    for _, key in ipairs({ "fixes", "vors", "ndbs" }) do
        for _, p in ipairs(static.nav[key] or {}) do
            if p.id == id then return p end
        end
    end
end

-- bounding box of the CTA (the fixed radar view / fallback view)
local ctaBox
local function ctaOf(static)
    if static.ctaBox then return static.ctaBox end
    local b = { math.huge, math.huge, -math.huge, -math.huge }
    for _, a in ipairs(static.airspaces or {}) do
        if a.type == "CTA" then
            for _, p in ipairs(a.polygon) do
                b[1], b[2] = math.min(b[1], p[1]), math.min(b[2], p[2])
                b[3], b[4] = math.max(b[3], p[1]), math.max(b[4], p[2])
            end
        end
    end
    if b[1] == math.huge then b = { -3500, -3500, 3500, 3500 } end
    static.ctaBox = b
    return b
end

local function fitView(static, W, H)
    local b = ctaOf(static)
    local w, h = (b[3] - b[1]) * 1.06, (b[4] - b[2]) * 1.06
    return { x = (b[1] + b[3]) / 2, y = (b[2] + b[4]) / 2, scale = math.min(W / w, H / h) }
end

-- ---------------------------------------------------------------- layers
local function ownAirspaceId(pos, static)
    if not pos then return end
    if pos.type == "TWR" then return pos.airport .. "_CTR" end
    if pos.type == "APP" then return pos.airport .. "_TMA" end
    for _, a in ipairs(static.airspaces) do
        if a.type == "CTA" then return a.id end
    end
end

local function drawAirspaces(static, pos)
    local own = ownAirspaceId(pos, static)
    local order = { CTA = 1, TMA = 2, CTR = 3 }
    local list = {}
    for _, a in ipairs(static.airspaces or {}) do list[#list + 1] = a end
    table.sort(list, function(a, b) return (order[a.type] or 0) < (order[b.type] or 0) end)
    for _, a in ipairs(list) do
        local pts = polyPts(a.polygon)
        if a.id == own then fillPoly(pts, C.ownFill) end
        local col = a.id == own and C.ownLine or (a.type == "CTR" and C.ctr or (a.type == "TMA" and C.tma or C.cta))
        for i = 1, #pts do
            local p, q = pts[i], pts[i % #pts + 1]
            if a.type == "CTA" or a.id == own then
                line(p[1], p[2], q[1], q[2], col, a.id == own and 2 or 1)
            else
                dashed(p[1], p[2], q[1], q[2], col, 1, 10, 6)
            end
        end
        local top = pts[1]
        for _, p in ipairs(pts) do if p[2] < top[2] then top = p end end
        local lim = ("%s  %s-%s"):format(a.name or a.id, a.floor == 0 and "SFC" or tostring(a.floor),
            a.ceiling >= 18000 and ("FL" .. math.floor(a.ceiling / 100)) or tostring(a.ceiling))
        txt(lim, top[1] + 6, top[2] + 4, C.asText, F.map)
    end
end

local function drawAirports(static, runways)
    local s = V.vs
    local q = V.k * V.u
    for icao, a in pairs(static.airports or {}) do
        local rw = runways and runways[icao]
        local arrId, depId = rw and rw.arr, rw and rw.dep
        if s >= 0.15 then
            local tw = math.max(1, 16 * s * V.k)
            for _, t in ipairs(a.taxiways or {}) do
                local prev
                for _, p in ipairs(t.points or {}) do
                    local x, y = w2p(p[1], p[2])
                    if prev then line(prev[1], prev[2], x, y, C.taxi, tw) end
                    prev = { x, y }
                end
            end
        end
        for _, r in ipairs(a.runways or {}) do
            local e1, e2 = r.ends[1], r.ends[2]
            local x1, y1 = w2p(e1.x, e1.y)
            local x2, y2 = w2p(e2.x, e2.y)
            line(x1, y1, x2, y2, C.runway, math.max(3, (r.width or 30) * s * V.k))
            for _, e in ipairs(r.ends) do
                local h = math.rad(e.hdg)
                local ux, uy = math.sin(h), -math.cos(h)
                local ex, ey = w2p(e.x, e.y)
                local isArr, isDep = e.ident == arrId, e.ident == depId
                local col = isArr and C.arr or (isDep and C.dep or C.rwText)
                if s >= 0.08 then txt(e.ident, ex - ux * 18, ey - uy * 18, col, F.map, "center", "center") end
                if isArr then
                    local f = navPoint(static, e.final)
                    if f then
                        local fx, fy = w2p(f.x, f.y)
                        dashed(ex, ey, fx, fy, C.arr, 1, 6, 6)
                    end
                end
                if isDep and s >= 0.08 then line(ex, ey, ex + ux * 28, ey + uy * 28, C.dep, 2) end
            end
        end
        if s >= 0.225 then
            local g = math.max(3, 9 * s * V.k)
            for _, gt in ipairs(a.gates or {}) do
                local x, y = w2p(gt.x, gt.y)
                dxDrawRectangle(x - g / 2, y - g / 2, g, g, C.gate)
            end
        end
        if s < 0.25 then
            local x, y = w2p(a.arp[1], a.arp[2])
            txt(icao, x + 10, y + 8, C.apt, F.map)
        end
    end
end

local function triangle(x, y, r, col)
    line(x, y - r, x + r * 0.87, y + r * 0.5, col)
    line(x + r * 0.87, y + r * 0.5, x - r * 0.87, y + r * 0.5, col)
    line(x - r * 0.87, y + r * 0.5, x, y - r, col)
end

local function drawNav(static)
    local nav = static.nav or {}
    local r = 5
    for _, f in ipairs(nav.fixes or {}) do
        if f.kind ~= "final" or V.vs >= 0.12 then
            local x, y = w2p(f.x, f.y)
            local col = f.kind == "final" and C.fixFinal or C.fix
            triangle(x, y, r, col)
            txt(f.id, x + r + 3, y - r - 2, C.navText, F.map)
        end
    end
    for _, v in ipairs(nav.vors or {}) do
        local x, y = w2p(v.x, v.y)
        for i = 0, 5 do
            local a1, a2 = math.rad(i * 60), math.rad((i + 1) * 60)
            line(x + math.cos(a1) * 7, y + math.sin(a1) * 7, x + math.cos(a2) * 7, y + math.sin(a2) * 7, C.vor)
        end
        txt(v.id, x + 10, y - 9, C.vor, F.map)
    end
    for _, n in ipairs(nav.ndbs or {}) do
        local x, y = w2p(n.x, n.y)
        for i = 0, 9 do
            local a = math.rad(i * 36)
            dxDrawRectangle(x + math.cos(a) * 6 - 1, y + math.sin(a) * 6 - 1, 2, 2, C.ndb)
        end
        txt(n.id, x + 10, y - 9, C.ndb, F.map)
    end
end

-- ---------------------------------------------------------------- traffic
local function hundreds(ft) return ("%03d"):format(math.max(0, math.floor(ft / 100 + 0.5))) end
local function hdg3(h)
    h = math.floor(h + 0.5) % 360
    return ("%03d"):format(h == 0 and 360 or h)
end

local function drawAir(s, mine, h, off, compact)
    local x, y = w2p(s.x, s.y)
    local col = mine and C.air or C.airOther
    for _, p in ipairs(h or {}) do
        local hx, hy = w2p(p[1], p[2])
        dxDrawRectangle(hx - 1.5, hy - 1.5, 3, 3, mine and C.hist or C.histO)
    end
    local hr = math.rad(s.hdg)
    local len = (s.ws or 0) * 60 * V.vs * V.k
    line(x, y, x + math.sin(hr) * len, y - math.cos(hr) * len, mine and C.vector or C.vectorO, 1)
    local r = 4
    line(x - r, y - r, x + r, y - r, col, 1.5)
    line(x + r, y - r, x + r, y + r, col, 1.5)
    line(x + r, y + r, x - r, y + r, col, 1.5)
    line(x - r, y + r, x - r, y - r, col, 1.5)

    -- label lines (no hover state on a wall screen)
    local lines
    if compact then
        lines = { s.cs, ("%s %03d"):format(hundreds(s.alt), math.floor(s.spd + 0.5)) }
    else
        lines = { { s.cs .. " ", (s.ctl or "----") .. " ", s.type .. "/" .. s.wake },
            ("%s %03d %s"):format(hundreds(s.alt), math.floor(s.spd + 0.5), s.arr) }
        if s.cfl then lines[#lines + 1] = hundreds(s.cfl) end
        if s.dct or s.ahdg then
            local parts = {}
            if s.dct then parts[#parts + 1] = s.dct end
            if s.ahdg then parts[#parts + 1] = hdg3(s.ahdg) end
            lines[#lines + 1] = table.concat(parts, " ")
        end
    end
    local fh = dxGetFontHeight(1, F.lbl)
    local w = 0
    for _, l in ipairs(lines) do
        local lw
        if type(l) == "table" then
            lw = 0
            for _, g in ipairs(l) do lw = lw + dxGetTextWidth(g, 1, F.lbl) end
        else
            lw = dxGetTextWidth(l, 1, F.lbl)
        end
        w = math.max(w, lw)
    end
    local lh = fh * #lines
    local dx, dy = 14, -lh - 8
    if off then dx, dy = off[1] * V.k * V.u, off[2] * V.k * V.u end
    local rx, ry = x + dx, y + dy
    -- leader line to the nearest label edge
    local ax = math.max(rx, math.min(rx + w, x))
    local ay = math.max(ry, math.min(ry + lh, y))
    if (ax - x) ^ 2 + (ay - y) ^ 2 > 36 then line(x, y, ax, ay, mine and C.leader or C.leaderO, 1) end
    for i, l in ipairs(lines) do
        local ly = ry + (i - 1) * fh
        if type(l) == "table" then
            local lx = rx
            for gi, g in ipairs(l) do
                txt(g, lx, ly, gi == 2 and C.ctlTx or col, F.lbl)
                lx = lx + dxGetTextWidth(g, 1, F.lbl)
            end
        else
            txt(l, rx, ly, col, F.lbl)
        end
    end
end

local function drawGround(s, off)
    local x, y = w2p(s.x, s.y)
    dxDrawRectangle(x - 2.5, y - 2.5, 5, 5, C.gText)
    local fh = dxGetFontHeight(1, F.map)
    local l1, l2 = s.cs, s.type .. "/" .. s.wake
    local w = math.max(dxGetTextWidth(l1, 1, F.map), dxGetTextWidth(l2, 1, F.map)) + 8
    local rx, ry = x + 8, y - fh * 2 - 6
    if off then rx, ry = x + off[1] * V.k * V.u, y + off[2] * V.k * V.u end
    local bg = s.dir == "arr" and C.gArr or (s.dir == "dep" and C.gDep or C.gUnk)
    line(x, y, math.max(rx, math.min(rx + w, x)), math.max(ry, math.min(ry + fh * 2 + 4, y)), bg, 1)
    dxDrawRectangle(rx, ry, w, fh * 2 + 4, bg)
    txt(l1, rx + 4, ry + 2, C.gText, F.map)
    txt(l2, rx + 4, ry + 2 + fh, C.gText, F.map)
end

local function drawTraffic(data, posId, offs, compact)
    local list = {}
    for _, s in ipairs(data.traffic or {}) do
        if not (s.gnd and V.vs < 0.2) then list[#list + 1] = s end
    end
    table.sort(list, function(a, b)
        if a.gnd ~= b.gnd then return a.gnd end
        return a.id < b.id
    end)
    for _, s in ipairs(list) do
        local off = offs and offs[s.id] or offs and offs[tostring(s.id)]
        if s.gnd then drawGround(s, off)
        else drawAir(s, posId ~= nil and s.ctl == posId, data.hist and data.hist[s.id], off, compact) end
    end
end

-- ---------------------------------------------------------------- bars / lists
local function utc()
    local t = getRealTime(getRealTime().timestamp, false)
    return ("%02d:%02d:%02dZ"):format(t.hour, t.minute, t.second)
end

local function runwayText(data, airport)
    local parts = {}
    local icaos = {}
    for icao in pairs(data.runways or {}) do icaos[#icaos + 1] = icao end
    table.sort(icaos)
    for _, icao in ipairs(icaos) do
        if not airport or airport == icao then
            local r = data.runways[icao]
            parts[#parts + 1] = ("%s ARR %s DEP %s"):format(icao, tostring(r.arr), tostring(r.dep))
        end
    end
    local w = data.wind or { dir = 0, speed = 0 }
    parts[#parts + 1] = ("WIND %03d/%02d"):format(w.dir, w.speed)
    return table.concat(parts, "    ")
end

local function topBar(W, title, sub, mid, right)
    local h = 30
    dxDrawRectangle(0, 0, W, h, C.bar)
    line(0, h, W, h, C.barLine)
    txt(title, 10, h / 2, C.air, F.top, "left", "center")
    local x = 10 + dxGetTextWidth(title, 1, F.top) + 12
    txt(sub, x, h / 2, C.dim, F.map, "left", "center")
    txt(mid, W - 150, h / 2, C.text, F.map, "right", "center")
    txt(right, W - 10, h / 2, C.text, F.top, "right", "center")
end

local function drawOwnList(W, H, data, posId, k)
    local lw = 520 * k * V.u
    local x, top = W - lw, 31
    dxDrawRectangle(x, top, lw, H - top, C.list)
    line(x, top, x, H, C.barLine)
    local fh = dxGetFontHeight(1, F.map) + 3
    local own = {}
    for _, s in ipairs(data.traffic or {}) do
        if s.ctl == posId then own[#own + 1] = s end
    end
    table.sort(own, function(a, b) return a.cs < b.cs end)
    txt(("CONTROLLED  (%d)"):format(#own), x + 8, top + 4, C.text, F.lbl)
    local y = top + 4 + dxGetFontHeight(1, F.lbl) + 4
    local cols = { 0, 0.30, 0.52, 0.72 }
    for i, name in ipairs({ "CS", "TYPE", "ALT", "CFL" }) do txt(name, x + 8 + cols[i] * lw, y, C.dim, F.map) end
    y = y + fh
    local maxRows = math.floor((H - y) / fh)
    for i, s in ipairs(own) do
        if i > maxRows then break end
        local alt = s.gnd and s.phase:upper():sub(1, 7) or hundreds(s.alt)
        local vals = { s.cs, s.type .. "/" .. s.wake, alt, s.cfl and hundreds(s.cfl) or "-" }
        for ci, v in ipairs(vals) do txt(v, x + 8 + cols[ci] * lw, y, C.air, F.map) end
        y = y + fh
    end
end

-- ---------------------------------------------------------------- monitor
local function plate(W, SH, H, id, sub, inUse)
    dxDrawRectangle(0, SH, W, H - SH, C.plate)
    dxDrawRectangle(0, SH, W, 3, C.bezel)
    dxDrawRectangle(0, SH + 3, 14, H - SH - 3, inUse and C.on or C.idle)
    local fhP = dxGetFontHeight(1, F.plate)
    txt(id, 34, SH + (H - SH) * 0.5 - fhP * 0.62, inUse and C.plateTx or C.plateDim, F.plate, "left", "center")
    txt(sub, 34, SH + (H - SH) * 0.5 + fhP * 0.55, C.plateDim, F.small, "left", "center")
end

local function bezel(W, SH)
    local t = 6
    dxDrawRectangle(0, 0, W, t, C.bezel)
    dxDrawRectangle(0, SH - t, W, t, C.bezel)
    dxDrawRectangle(0, 0, t, SH, C.bezel)
    dxDrawRectangle(W - t, 0, t, SH, C.bezel)
end

local function setView(vx, vy, vs, csx, csy, W, SH)
    local k = math.min(W / csx, SH / csy)
    V = { vx = vx, vy = vy, vs = vs, csx = csx, csy = csy, k = k,
        ox = (W - csx * k) / 2, oy = (SH - csy * k) / 2,
        u = math.max(0.75, math.min(1.5, csy / 1080)) }
end

function MonRender.monitor(m, data, static, W, SH, H)
    fonts()
    dxSetBlendMode("blend")
    local pos = m.pos
    local staffedName = pos and data.staffed and data.staffed[pos.id]

    if m.kind == "radar" then
        dxDrawRectangle(0, 0, W, SH, C.bg)
        local v = fitView(static, W, SH)
        setView(v.x, v.y, v.scale, W, SH, W, SH)
        drawAirspaces(static, nil)
        drawAirports(static, data.runways)
        drawNav(static)
        drawTraffic(data, nil, nil, true)
        local n = 0
        for _, s in ipairs(data.traffic or {}) do if not s.gnd then n = n + 1 end end
        topBar(W, "RADAR", "San Andreas - all traffic", ("%d airborne"):format(n), utc())
        bezel(W, SH)
        plate(W, SH, H, "AREA RADAR", "San Andreas - fixed view", true)
        return
    end

    if not pos or not staffedName then
        dxDrawRectangle(0, 0, W, SH, C.off)
        txt("NOT IN USE", W / 2, SH / 2, C.offText, F.huge, "center", "center")
        bezel(W, SH)
        plate(W, SH, H, pos and pos.id or "-", pos and pos.name or "no position assigned", false)
        return
    end

    dxDrawRectangle(0, 0, W, SH, C.bg)
    local view = data.views and data.views[pos.id]
    local csx, csy, vx, vy, vs = SCR_FALLBACK_W, SCR_FALLBACK_H, 0, 0, 0.1
    if view then
        csx, csy, vx, vy, vs = view.sx, view.sy, view.x, view.y, view.scale
    else
        local fv = fitView(static, W, SH)
        csx, csy, vx, vy, vs = W, SH, fv.x, fv.y, fv.scale
    end
    setView(vx, vy, vs, csx, csy, W, SH)
    -- offsets were stored divided by the scope unit; V.u restores them
    drawAirspaces(static, pos)
    drawAirports(static, data.runways)
    drawNav(static)
    drawTraffic(data, pos.id, view and view.off, false)
    if view and view.showList then drawOwnList(W, SH, data, pos.id, V.k) end
    topBar(W, pos.id, staffedName, runwayText(data, pos.airport), utc())
    bezel(W, SH)
    plate(W, SH, H, pos.id, pos.name .. "  -  " .. staffedName, true)
end

SCR_FALLBACK_W, SCR_FALLBACK_H = 1920, 1080
