-- Static scope layers: airspaces, airports (runways, taxiways, gates, finals), nav points.

COL = {
    bg       = tocolor(7, 13, 22, 255),
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
    taxiText = tocolor(110, 115, 125, 255),
    gate     = tocolor(95, 100, 112, 255),
    fix      = tocolor(115, 135, 165, 255),
    fixFinal = tocolor(80, 150, 110, 255),
    vor      = tocolor(150, 175, 210, 255),
    ndb      = tocolor(185, 145, 90, 255),
    navText  = tocolor(105, 125, 150, 255),
    apt      = tocolor(150, 160, 175, 255),
}

-- ---------------------------------------------------------------- primitives
function line(x1, y1, x2, y2, col, w)
    dxDrawLine(x1, y1, x2, y2, col, w or 1)
end

function dashed(x1, y1, x2, y2, col, w, dash, gap)
    dash, gap = dash or 8, gap or 6
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

function text(str, x, y, col, font, ax, ay)
    dxDrawText(str, x, y, x, y, col, 1, font, ax or "left", ay or "top", false, false, false, false, true)
end

local function polyScreen(poly)
    local pts = {}
    for i, p in ipairs(poly) do
        local x, y = w2s(p[1], p[2])
        pts[i] = { x, y }
    end
    return pts
end

local function outline(pts, col, w)
    for i = 1, #pts do
        local a, b = pts[i], pts[i % #pts + 1]
        dxDrawLine(a[1], a[2], b[1], b[2], col, w or 1)
    end
end

local function fill(pts, col)
    local cx, cy = 0, 0
    for _, p in ipairs(pts) do cx, cy = cx + p[1], cy + p[2] end
    cx, cy = cx / #pts, cy / #pts
    local v = { { cx, cy, col } }
    for _, p in ipairs(pts) do v[#v + 1] = { p[1], p[2], col } end
    v[#v + 1] = { pts[1][1], pts[1][2], col }
    dxDrawPrimitive("trianglefan", false, unpack(v))
end

-- ---------------------------------------------------------------- airspaces
-- own sector: TWR -> its CTR, APP -> its TMA, CTR -> the CTA
local function ownAirspaceId()
    local p = SC.pos
    if not p then return end
    if p.type == "TWR" then return p.airport .. "_CTR" end
    if p.type == "APP" then return p.airport .. "_TMA" end
    for _, a in ipairs(SC.data.airspaces) do
        if a.type == "CTA" then return a.id end
    end
end

function drawAirspaces()
    local own = ownAirspaceId()
    -- widest first, so the smaller ones are drawn on top
    local order = { CTA = 1, TMA = 2, CTR = 3 }
    local list = {}
    for _, a in ipairs(SC.data.airspaces or {}) do list[#list + 1] = a end
    table.sort(list, function(a, b) return (order[a.type] or 0) < (order[b.type] or 0) end)
    for _, a in ipairs(list) do
        local pts = polyScreen(a.polygon)
        if a.id == own then fill(pts, COL.ownFill) end
        local col = a.id == own and COL.ownLine or (a.type == "CTR" and COL.ctr or (a.type == "TMA" and COL.tma or COL.cta))
        if a.type == "CTA" or a.id == own then
            outline(pts, col, a.id == own and 1.5 or 1)
        else
            for i = 1, #pts do
                local p, q = pts[i], pts[i % #pts + 1]
                dashed(p[1], p[2], q[1], q[2], col, 1, 10, 6)
            end
        end
        -- name + vertical limits at the top-most vertex
        local top = pts[1]
        for _, p in ipairs(pts) do if p[2] < top[2] then top = p end end
        local lim = ("%s  %s-%s"):format(a.name or a.id, a.floor == 0 and "SFC" or tostring(a.floor),
            a.ceiling >= 18000 and ("FL" .. math.floor(a.ceiling / 100)) or tostring(a.ceiling))
        text(lim, top[1] + 6, top[2] + 4, COL.asText, F.map)
    end
end

-- ---------------------------------------------------------------- airports
local function activeOf(icao)
    local r = SC.data.runways and SC.data.runways[icao]
    return r and r.arr, r and r.dep
end

function drawAirports()
    local s = VIEW.scale
    for icao, a in pairs(SC.data.airports or {}) do
        local arrId, depId = activeOf(icao)
        -- taxiways
        if s >= CTL.TAXI_MIN_SCALE then
            local tw = math.max(1, 16 * s)
            -- rounded pieces from avi_airports (taxiDraw); the plain polylines when missing
            for _, l in ipairs(a.taxiDraw or {}) do
                local x1, y1 = w2s(l[1], l[2])
                local x2, y2 = w2s(l[3], l[4])
                line(x1, y1, x2, y2, COL.taxi, tw)
            end
            for _, t in ipairs(a.taxiways or {}) do
                if not a.taxiDraw then
                    local prev
                    for _, p in ipairs(t.points or {}) do
                        local x, y = w2s(p[1], p[2])
                        if prev then line(prev[1], prev[2], x, y, COL.taxi, tw) end
                        prev = { x, y }
                    end
                end
                if s >= 0.5 and t.points and t.points[1] then
                    local mid = t.points[math.ceil(#t.points / 2)]
                    local x, y = w2s(mid[1], mid[2])
                    text(t.id, x + 4, y + 2, COL.taxiText, F.map)
                end
            end
        end
        -- runways
        for _, rw in ipairs(a.runways or {}) do
            local e1, e2 = rw.ends[1], rw.ends[2]
            local x1, y1 = w2s(e1.x, e1.y)
            local x2, y2 = w2s(e2.x, e2.y)
            line(x1, y1, x2, y2, COL.runway, math.max(3, (rw.width or 30) * s))
            for _, e in ipairs(rw.ends) do
                local h = math.rad(e.hdg)
                local ux, uy = math.sin(h), -math.cos(h)          -- roll direction on screen
                local ex, ey = w2s(e.x, e.y)
                local isArr, isDep = e.ident == arrId, e.ident == depId
                local col = isArr and COL.arr or (isDep and COL.dep or COL.rwText)
                if s >= 0.08 then
                    text(e.ident, ex - ux * 16 * U, ey - uy * 16 * U, col, F.map, "center", "center")
                end
                -- extended centre line to the final fix of the arrival runway
                if isArr then
                    local f = navById(e.final)
                    if f then
                        local fx, fy = w2s(f.x, f.y)
                        dashed(ex, ey, fx, fy, COL.arr, 1, 6, 6)
                    end
                end
                if isDep and s >= 0.08 then
                    local px, py = ex + ux * 26 * U, ey + uy * 26 * U
                    line(ex, ey, px, py, COL.dep, 2)
                end
            end
        end
        -- gates
        if s >= CTL.TAXI_MIN_SCALE * 1.5 then
            local g = math.max(3, 9 * s)
            for _, gt in ipairs(a.gates or {}) do
                local x, y = w2s(gt.x, gt.y)
                dxDrawRectangle(x - g / 2, y - g / 2, g, g, COL.gate)
                if s >= 0.45 then text(gt.id, x + g / 2 + 3, y - g / 2, COL.taxiText, F.map) end
            end
        end
        -- airport name when the field is small on screen
        if s < 0.25 then
            local x, y = w2s(a.arp[1], a.arp[2])
            text(icao, x + 10, y + 8, COL.apt, F.map)
        end
    end
end

-- ---------------------------------------------------------------- nav points
local function triangle(x, y, r, col)
    line(x, y - r, x + r * 0.87, y + r * 0.5, col)
    line(x + r * 0.87, y + r * 0.5, x - r * 0.87, y + r * 0.5, col)
    line(x - r * 0.87, y + r * 0.5, x, y - r, col)
end

local function hexagon(x, y, r, col)
    for i = 0, 5 do
        local a1, a2 = math.rad(i * 60), math.rad((i + 1) * 60)
        line(x + math.cos(a1) * r, y + math.sin(a1) * r, x + math.cos(a2) * r, y + math.sin(a2) * r, col)
    end
    dxDrawRectangle(x - 1, y - 1, 2, 2, col)
end

local function dotCircle(x, y, r, col)
    for i = 0, 9 do
        local a = math.rad(i * 36)
        dxDrawRectangle(x + math.cos(a) * r - 1, y + math.sin(a) * r - 1, 2, 2, col)
    end
    dxDrawRectangle(x - 1.5, y - 1.5, 3, 3, col)
end

function drawNav()
    local nav = SC.data.nav or {}
    local r = 5 * U
    for _, f in ipairs(nav.fixes or {}) do
        -- final + procedure fixes only when zoomed in a bit (they clutter the CTA view)
        local small = f.kind == "final" or f.kind == "proc"
        if not small or VIEW.scale >= 0.12 then
            local x, y = w2s(f.x, f.y)
            local col = small and COL.fixFinal or COL.fix
            triangle(x, y, f.kind == "proc" and r * 0.75 or r, col)
            text(f.id, x + r + 3, y - r - 2, COL.navText, F.map)
        end
    end
    for _, v in ipairs(nav.vors or {}) do
        local x, y = w2s(v.x, v.y)
        hexagon(x, y, r * 1.3, COL.vor)
        text(v.id .. (v.freq and (" " .. v.freq) or ""), x + r + 5, y - r - 2, COL.vor, F.map)
    end
    for _, n in ipairs(nav.ndbs or {}) do
        local x, y = w2s(n.x, n.y)
        dotCircle(x, y, r * 1.2, COL.ndb)
        text(n.id, x + r + 5, y - r - 2, COL.ndb, F.map)
    end
end
