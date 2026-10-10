-- Traffic targets and labels.
--   Airborne: no background. Text blue when the aircraft is yours, grey otherwise; the controlling
--   position in white. 5 lines:
--     CALLSIGN CTL ACTYPE/WAKE | ALT SPD DEST | CLEARED ALT | WAYPOINT HEADING | SQK HDG VERTICAL
--     WAYPOINT = the direct-to fix, else the procedure flown ("VINEW1A 27R", "VINEW1D 27L")
--     Hover only: the SQK line, an empty CFL ("CFL"), an empty waypoint / heading ("DCT" / "AHDG").
--     altitudes in hundreds of feet (045 = 4 500 ft), speed in knots, vertical speed in ft/min
--     hover = grey background; left-drag moves the label relative to the aircraft.
--   Ground: always a background: green = arrival, blue = departure, grey = unknown.
--     CALLSIGN (large) / SPD SQK / ACTYPE/WAKE.
--   A yellow frame = one of your aircraft is waiting for a clearance.

local C = {
    air      = tocolor(95, 170, 255, 255),
    airOther = tocolor(140, 145, 155, 255),
    ctl      = tocolor(255, 255, 255, 255),
    hover    = tocolor(70, 76, 88, 225),
    leader   = tocolor(80, 130, 200, 200),
    leaderO  = tocolor(110, 115, 125, 200),
    hist     = tocolor(70, 120, 190, 160),
    histO    = tocolor(100, 105, 115, 160),
    vector   = tocolor(90, 150, 230, 200),
    vectorO  = tocolor(120, 125, 135, 200),
    gArr     = tocolor(35, 125, 65, 235),
    gDep     = tocolor(35, 85, 165, 235),
    gUnk     = tocolor(85, 88, 95, 235),
    gText    = tocolor(240, 244, 250, 255),
    gDot     = tocolor(220, 225, 235, 255),
    select   = tocolor(255, 210, 90, 255),
    request  = tocolor(255, 215, 60, 255),
    route    = tocolor(70, 205, 110, 200),     -- green; yellow once a direct-to is issued
    routeDct = tocolor(255, 210, 60, 210),
}

LABEL_RECTS = {}    -- [id] = { x, y, w, h } of this frame (hit tests)
HOVER_ID = nil

local function vsText(vs)
    if not vs or math.abs(vs) < 100 then return "0" end
    local v = math.floor(math.abs(vs) / 100 + 0.5) * 100
    return (vs > 0 and "+" or "-") .. v
end

local function hundreds(ft)
    return ("%03d"):format(math.max(0, math.floor(ft / 100 + 0.5)))
end

local function hdg3(h)
    h = math.floor(h + 0.5) % 360
    return ("%03d"):format(h == 0 and 360 or h)
end

-- each line = list of { text, colour } segments (nil colour = the label colour).
-- Without hover only the filled-in items show: no CFL line without a cleared level, no
-- waypoint / heading line when both are empty, the SQK line never.
local function airLines(s, hovered)
    local lines = {
        { { s.cs .. " " }, { (s.ctl or "----") .. " ", C.ctl }, { s.type .. "/" .. s.wake } },
        { { ("%s %03d %s"):format(hundreds(s.alt), math.floor(s.spd + 0.5), s.arr) } },
    }
    if s.cfl then lines[#lines + 1] = { { hundreds(s.cfl) } }
    elseif hovered then lines[#lines + 1] = { { "CFL" } } end
    -- waypoint field: direct-to fix, else the procedure flown (SID / STAR + runway)
    local wp = s.dct or s.proc
    local ahdg = s.ahdg and ((s.ahdgDir or "") .. hdg3(s.ahdg))      -- L / R while a forced turn lasts
    if hovered then
        lines[#lines + 1] = { { (wp or "DCT") .. " " .. (ahdg or "AHDG") } }
    elseif wp or s.ahdg then
        local parts = {}
        if wp then parts[#parts + 1] = wp end
        if ahdg then parts[#parts + 1] = ahdg end
        lines[#lines + 1] = { { table.concat(parts, " ") } }
    end
    if hovered then
        lines[#lines + 1] = { { ("%s %s %s"):format(s.sqk or "----", hdg3(s.hdg), vsText(s.vs)) } }
    end
    return lines
end

local function lineWidth(segs, font)
    local w = 0
    for _, g in ipairs(segs) do w = w + dxGetTextWidth(g[1], 1, font) end
    return w
end

local function drawSegs(segs, x, y, col, font)
    for _, g in ipairs(segs) do
        text(g[1], x, y, g[2] or col, font)
        x = x + dxGetTextWidth(g[1], 1, font)
    end
end

local function frame(r, col)
    line(r[1], r[2], r[1] + r[3], r[2], col, 1)
    line(r[1] + r[3], r[2], r[1] + r[3], r[2] + r[4], col, 1)
    line(r[1] + r[3], r[2] + r[4], r[1], r[2] + r[4], col, 1)
    line(r[1], r[2] + r[4], r[1], r[2], col, 1)
end

-- point on the rectangle edge closest to (px, py)
local function rectAnchor(r, px, py)
    local x = math.max(r[1], math.min(r[1] + r[3], px))
    local y = math.max(r[2], math.min(r[2] + r[4], py))
    return x, y
end

local function defaultOffset(s)
    if s.gnd then return 10 * U, -44 * U end
    return 18 * U, -70 * U
end

local function waiting(s)
    return isMine(s) and s.req and s.ready
end

local function drawAir(id, e, x, y, hovered, selected)
    local s = e.s
    local mine = isMine(s)
    local col = mine and C.air or C.airOther

    -- history dots, speed vector, symbol
    for _, h in ipairs(e.hist) do
        local hx, hy = w2s(h[1], h[2])
        dxDrawRectangle(hx - 1.5, hy - 1.5, 3, 3, mine and C.hist or C.histO)
    end
    local hr = math.rad(s.hdg)
    if SC.vectorStep > 0 then
        local len = SC.vectorStep * CTL.VECTOR_STEP_NM * M_PER_NM * VIEW.scale
        line(x, y, x + math.sin(hr) * len, y - math.cos(hr) * len, mine and C.vector or C.vectorO, 1)
    end
    local r = 4 * U
    local scol = selected and C.select or col
    line(x - r, y - r, x + r, y - r, scol, 1.5)
    line(x + r, y - r, x + r, y + r, scol, 1.5)
    line(x + r, y + r, x - r, y + r, scol, 1.5)
    line(x - r, y + r, x - r, y - r, scol, 1.5)

    -- label
    local lines = airLines(s, hovered)
    local fh = dxGetFontHeight(1, F.label)
    local w = 0
    for _, l in ipairs(lines) do w = math.max(w, lineWidth(l, F.label)) end
    local pad = 3 * U
    local off = SC.labelOffset[id]
    local dx, dy = defaultOffset(s)
    if off then dx, dy = off[1], off[2] end
    local rect = { x + dx - pad, y + dy - pad, w + pad * 2, fh * #lines + pad * 2 }
    LABEL_RECTS[id] = rect
    if hovered then dxDrawRectangle(rect[1], rect[2], rect[3], rect[4], C.hover) end
    if waiting(s) then frame(rect, C.request) end
    local ax, ay = rectAnchor(rect, x, y)
    if (ax - x) ^ 2 + (ay - y) ^ 2 > (r + 2) ^ 2 then line(x, y, ax, ay, mine and C.leader or C.leaderO, 1) end
    for i, l in ipairs(lines) do
        drawSegs(l, rect[1] + pad, rect[2] + pad + (i - 1) * fh, selected and C.select or col, F.label)
    end
end

local function drawGround(id, e, x, y, hovered, selected)
    local s = e.s
    dxDrawRectangle(x - 2.5 * U, y - 2.5 * U, 5 * U, 5 * U, selected and C.select or C.gDot)

    local l1 = s.cs
    local l2 = ("%d  %s"):format(math.floor(s.spd + 0.5), s.sqk or "----")
    local l3 = s.type .. "/" .. s.wake
    local h1, h2 = dxGetFontHeight(1, F.gndCs), dxGetFontHeight(1, F.gndSm)
    local w = math.max(dxGetTextWidth(l1, 1, F.gndCs), dxGetTextWidth(l2, 1, F.gndSm), dxGetTextWidth(l3, 1, F.gndSm))
    local pad = 4 * U
    local off = SC.labelOffset[id]
    local dx, dy = defaultOffset(s)
    if off then dx, dy = off[1], off[2] end
    local rect = { x + dx, y + dy, w + pad * 2, h1 + h2 * 2 + pad * 1.5 }
    LABEL_RECTS[id] = rect
    local bg = s.dir == "arr" and C.gArr or (s.dir == "dep" and C.gDep or C.gUnk)
    local ax, ay = rectAnchor(rect, x, y)
    line(x, y, ax, ay, bg, 1)
    dxDrawRectangle(rect[1], rect[2], rect[3], rect[4], bg)
    if waiting(s) then
        frame(rect, C.request)
    elseif hovered or selected then
        frame(rect, selected and C.select or C.gText)
    end
    text(l1, rect[1] + pad, rect[2] + pad * 0.5, C.gText, F.gndCs)
    text(l2, rect[1] + pad, rect[2] + pad * 0.5 + h1, C.gText, F.gndSm)
    text(l3, rect[1] + pad, rect[2] + pad * 0.5 + h1 + h2, C.gText, F.gndSm)
end

-- flight plan routes switched on in the menu: aircraft - DCT - remaining fixes - final fix - threshold
function routePoints(s)
    local pts = {}
    if s.dct then
        local p = navById(s.dct)
        if p then pts[#pts + 1] = { p.x, p.y, p.id } end
    end
    for _, id in ipairs(s.route or {}) do
        local p = navById(id)
        if p then pts[#pts + 1] = { p.x, p.y, p.id } end
    end
    local a = airportOf(s.arr)
    local rw = SC.data.runways and SC.data.runways[s.arr]
    if a and rw and not s.gnd then
        for _, r in ipairs(a.runways or {}) do
            for _, e in ipairs(r.ends or {}) do
                if e.ident == rw.arr then
                    local f = navById(e.final)
                    if f then pts[#pts + 1] = { f.x, f.y, f.id } end
                    pts[#pts + 1] = { e.x, e.y, s.arr .. " " .. e.ident }
                end
            end
        end
    end
    return pts
end

function drawRoutes()
    for id in pairs(SC.routeShown) do
        local e = SC.traffic[id]
        if e then
            local col = e.s.dct and C.routeDct or C.route
            local px, py = w2s(trafficPos(e))
            for _, p in ipairs(routePoints(e.s)) do
                local x, y = w2s(p[1], p[2])
                dashed(px, py, x, y, col, 1.5, 10, 5)
                dxDrawRectangle(x - 2.5, y - 2.5, 5, 5, col)
                px, py = x, y
            end
        else
            SC.routeShown[id] = nil
        end
    end
end

-- draw order: ground first, then airborne; a dragged / hovered label last (on top)
function drawTraffic(mx, my)
    LABEL_RECTS = {}
    local list = {}
    for id, e in pairs(SC.traffic) do
        if not (e.s.gnd and VIEW.scale < CTL.GROUND_MIN_SCALE) then list[#list + 1] = id end
    end
    table.sort(list, function(a, b)
        local ga, gb = SC.traffic[a].s.gnd, SC.traffic[b].s.gnd
        if ga ~= gb then return ga end
        if a == HOVER_ID then return false end
        if b == HOVER_ID then return true end
        return a < b
    end)
    local selected = MENU and MENU.open and MENU.ac
    for _, id in ipairs(list) do
        local e = SC.traffic[id]
        local wx, wy = trafficPos(e)
        local x, y = w2s(wx, wy)
        if e.s.gnd then drawGround(id, e, x, y, id == HOVER_ID, id == selected)
        else drawAir(id, e, x, y, id == HOVER_ID, id == selected) end
    end
    -- hover for the next frame: the top-most label under the cursor
    HOVER_ID = nil
    if mx then
        for i = #list, 1, -1 do
            local r = LABEL_RECTS[list[i]]
            if r and mx >= r[1] and mx <= r[1] + r[3] and my >= r[2] and my <= r[2] + r[4] then
                HOVER_ID = list[i]
                break
            end
        end
    end
end

-- aircraft symbol under the cursor (clicking the target itself, not the label)
function targetAt(mx, my)
    local best, bestD
    for id, e in pairs(SC.traffic) do
        if not (e.s.gnd and VIEW.scale < CTL.GROUND_MIN_SCALE) then
            local x, y = w2s(trafficPos(e))
            local d = (x - mx) ^ 2 + (y - my) ^ 2
            if d <= (9 * U) ^ 2 and (not bestD or d < bestD) then best, bestD = id, d end
        end
    end
    return best
end

-- label drag: offset = label position relative to the target
function moveLabel(id, dx, dy)
    local e = SC.traffic[id]
    if not e then return end
    local off = SC.labelOffset[id]
    if not off then
        local ox, oy = defaultOffset(e.s)
        off = { ox, oy }
        SC.labelOffset[id] = off
    end
    off[1], off[2] = off[1] + dx, off[2] + dy
end
