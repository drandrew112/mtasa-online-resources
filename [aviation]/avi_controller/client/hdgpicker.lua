-- Heading picker: a compass ring around the aircraft (menu "Fly heading" / "Turn left heading" /
-- "Turn right heading"). The mouse angle around the aircraft picks the heading in 5° steps (wheel ±5°),
-- the cyan line is the predicted path: the turn arc (same model as avi_traffic: constant turn rate,
-- radius = world speed / rate) then the straight leg on the new heading, a dot every 30 s.
--   left click = send, right click / Esc = back to the command menu.
--   dir: "L" / "R" = forced turn direction, nil = the shorter way (the pilots decide).

PICK = { open = false }

local C = {
    fill    = tocolor(14, 22, 34, 140),
    ring    = tocolor(70, 110, 160, 255),
    inner   = tocolor(42, 62, 88, 255),
    tickBig = tocolor(143, 180, 224, 255),
    tick    = tocolor(74, 106, 144, 255),
    cur     = tocolor(230, 235, 242, 255),
    ahdg    = tocolor(255, 210, 90, 255),
    path    = tocolor(60, 220, 255, 255),
    pathDim = tocolor(60, 220, 255, 170),
    bg      = tocolor(16, 22, 32, 245),
    border  = tocolor(70, 160, 210, 255),
    text    = tocolor(220, 228, 240, 255),
    dim     = tocolor(170, 182, 200, 255),
    hint    = tocolor(110, 120, 135, 255),
}

local STEP = 5
local DEADZONE = 20      -- px (×U) around the aircraft: the mouse angle is not used inside
local DOT_SEC = 30       -- a dot on the path every 30 s of flight
local TITLES = { L = "TURN LEFT HEADING", R = "TURN RIGHT HEADING" }

local function norm(h)
    h = math.floor(h / STEP + 0.5) * STEP % 360
    return h == 0 and 360 or h
end

function hdgPickerOpen(id, dir, menuX, menuY)
    local e = SC.traffic[id]
    if not e then return end
    local s = e.s
    PICK = { open = true, ac = id, dir = dir, sel = norm(s.ahdg or s.hdg), menuX = menuX, menuY = menuY }
end

function hdgPickerClose()
    PICK = { open = false }
end

local function back()
    local id, x, y = PICK.ac, PICK.menuX, PICK.menuY
    hdgPickerClose()
    if id and SC.traffic[id] then menuOpen(id, x, y) end
end

-- signed turn in degrees (+ = right) from the current heading to the selected one
local function turnOf(hdg, sel, dir)
    if dir == "L" then return -((hdg - sel) % 360) end
    if dir == "R" then return (sel - hdg) % 360 end
    return (sel - hdg + 540) % 360 - 180
end

-- world unit vector of a compass heading (north = +y)
local function wdir(h)
    local r = math.rad(h)
    return math.sin(r), math.cos(r)
end

-- predicted path in world metres: the turn arc, then the point where the straight leg starts
local function predictPath(s, diff)
    local pts = { { s.x, s.y } }
    if diff == 0 then return pts end
    local rate = (SC.data and SC.data.turnRate) or 6
    local r = (s.ws or 0) / math.rad(rate)
    if r <= 0 then return pts end
    local side = diff > 0 and 1 or -1
    local px, py = wdir(s.hdg + 90 * side)
    local cx, cy = s.x + px * r, s.y + py * r
    local n = math.max(6, math.ceil(math.abs(diff) / 3))
    for i = 1, n do
        local vx, vy = wdir(s.hdg + diff * i / n - 90 * side)
        pts[#pts + 1] = { cx + vx * r, cy + vy * r }
    end
    return pts
end

local function triangle(x, y, ux, uy, size, col)
    -- tip at (x, y) on the ring, pointing inwards (u = outward screen direction)
    local px, py = -uy, ux
    local bx, by = x + ux * size * 1.6, y + uy * size * 1.6
    dxDrawPrimitive("trianglelist", false,
        { x, y, col }, { bx + px * size, by + py * size, col }, { bx - px * size, by - py * size, col })
end

local function ringCircle(x, y, r, col, w, segs)
    segs = segs or 72
    local lx, ly = x, y - r
    for i = 1, segs do
        local a = math.rad(i * 360 / segs)
        local nx, ny = x + math.sin(a) * r, y - math.cos(a) * r
        dxDrawLine(lx, ly, nx, ny, col, w or 1)
        lx, ly = nx, ny
    end
end

function drawHdgPicker(mx, my)
    if not PICK.open then return end
    local e = SC.traffic[PICK.ac]
    if not e or not isMine(e.s) or e.s.phase ~= "air" then hdgPickerClose() return end
    local s = e.s
    local cx, cy = w2s(trafficPos(e))
    local R = 150 * U

    -- the mouse picks the heading (only when it moved, so wheel steps stay until the next move)
    if mx and (mx ~= PICK.lmx or my ~= PICK.lmy) then
        PICK.lmx, PICK.lmy = mx, my
        local dx, dy = mx - cx, my - cy
        if dx * dx + dy * dy > (DEADZONE * U) ^ 2 then
            PICK.sel = norm(math.deg(math.atan2(dx, -dy)))
        end
    end
    local sel = PICK.sel
    local diff = turnOf(s.hdg, sel % 360, PICK.dir)

    -- dial
    dxDrawCircle(cx, cy, R, 0, 360, C.fill, C.fill, 64)
    ringCircle(cx, cy, R, C.ring, 1.5)
    ringCircle(cx, cy, R - 26 * U, C.inner, 1, 48)
    for a = 0, 355, STEP do
        local ux, uy = math.sin(math.rad(a)), -math.cos(math.rad(a))
        local big = a % 30 == 0
        local len = (big and 14 or (a % 10 == 0 and 8 or 4)) * U
        dxDrawLine(cx + ux * R, cy + uy * R, cx + ux * (R - len), cy + uy * (R - len), big and C.tickBig or C.tick,
            big and 1.5 or 1)
        if big then
            text(a == 0 and "N" or ("%03d"):format(a), cx + ux * (R + 16 * U), cy + uy * (R + 16 * U), C.tickBig, F.map,
                "center", "center")
        end
    end
    -- current heading (white) and the heading already assigned (yellow), outside the ring
    local function marker(h, col)
        local ux, uy = math.sin(math.rad(h)), -math.cos(math.rad(h))
        triangle(cx + ux * (R + 2 * U), cy + uy * (R + 2 * U), ux, uy, 6 * U, col)
    end
    if s.ahdg and s.ahdg % 360 ~= s.hdg % 360 then marker(s.ahdg, C.ahdg) end
    marker(s.hdg, C.cur)

    -- predicted path: arc (world scale), straight leg to the ring, dashed beyond
    local pts = predictPath(s, diff)
    local spts = {}
    for i, p in ipairs(pts) do spts[i] = { w2s(p[1], p[2]) } end
    local sx, sy = math.sin(math.rad(sel)), -math.cos(math.rad(sel))
    local ex, ey = spts[#spts][1], spts[#spts][2]
    local bx, by = ex - cx, ey - cy
    local B, Cc = bx * sx + by * sy, bx * bx + by * by - R * R
    local t = Cc < 0 and (-B + math.sqrt(B * B - Cc)) or 0
    local endX, endY = ex + sx * t, ey + sy * t
    for i = 2, #spts do line(spts[i - 1][1], spts[i - 1][2], spts[i][1], spts[i][2], C.path, 2.5) end
    line(ex, ey, endX, endY, C.path, 2.5)
    dashed(endX, endY, endX + sx * 60 * U, endY + sy * 60 * U, C.pathDim, 1.2, 5 * U, 4 * U)

    -- a dot every 30 s along the path (world metres)
    local ws = s.ws or 0
    if ws > 0 then
        local wsx, wsy = wdir(sel)
        local last = pts[#pts]
        local farLen = math.sqrt((endX - ex) ^ 2 + (endY - ey) ^ 2) / VIEW.scale + 60 * U / VIEW.scale
        local seq = {}
        for i, p in ipairs(pts) do seq[i] = p end
        seq[#seq + 1] = { last[1] + wsx * farLen, last[2] + wsy * farLen }
        local step, acc, nxt = ws * DOT_SEC, 0, ws * DOT_SEC
        for i = 2, #seq do
            local x1, y1, x2, y2 = seq[i - 1][1], seq[i - 1][2], seq[i][1], seq[i][2]
            local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
            while len > 0 and acc + len >= nxt do
                local f = (nxt - acc) / len
                local px, py = w2s(x1 + (x2 - x1) * f, y1 + (y2 - y1) * f)
                dxDrawCircle(px, py, 2.6 * U, 0, 360, C.path, C.path, 10)
                nxt = nxt + step
            end
            acc = acc + len
        end
    end

    -- selected heading on the ring
    dxDrawCircle(cx + sx * R, cy + sy * R, 6 * U, 0, 360, C.bg, C.bg, 16)
    ringCircle(cx + sx * R, cy + sy * R, 6 * U, C.path, 2, 16)

    -- readout next to the mouse (or next to the ring point when the mouse is elsewhere)
    local rx, ry = mx or (cx + sx * (R + 40 * U)), my or (cy + sy * (R + 40 * U))
    local w, h = 170 * U, 46 * U
    local bx0 = math.min(rx + 16 * U, SC.sx - w - 8)
    local by0 = ry + 14 * U
    if by0 + h > SC.sy - 8 then by0 = ry - h - 14 * U end
    dxDrawRectangle(bx0, by0, w, h, C.bg)
    line(bx0, by0, bx0 + w, by0, C.border)
    line(bx0, by0 + h, bx0 + w, by0 + h, C.border)
    line(bx0, by0, bx0, by0 + h, C.border)
    line(bx0 + w, by0, bx0 + w, by0 + h, C.border)
    text(("HDG %03d"):format(sel), bx0 + 10 * U, by0 + 5 * U, C.path, F.gndCs)
    local turn = diff > 0 and "RIGHT" or (diff < 0 and "LEFT" or "STRAIGHT")
    local rate = (SC.data and SC.data.turnRate) or 6
    text(("%s %d°  ·  %d s"):format(turn, math.abs(diff), math.floor(math.abs(diff) / rate + 0.5)),
        bx0 + 10 * U, by0 + 26 * U, C.dim, F.ui)

    -- title + help under the top bar
    local title = (TITLES[PICK.dir] or "FLY HEADING") .. "   " .. tostring(s.cs)
    local help = "LMB select  ·  RMB / Esc back  ·  Wheel ±5°"
    local tw = math.max(dxGetTextWidth(title, 1, F.uiB), dxGetTextWidth(help, 1, F.map)) + 24 * U
    local tx, ty = (SC.sx - (SC.showList and LIST_W or 0)) / 2 - tw / 2, 42 * U
    dxDrawRectangle(tx, ty, tw, 38 * U, C.bg)
    line(tx, ty + 38 * U, tx + tw, ty + 38 * U, C.border)
    text(title, tx + tw / 2, ty + 4 * U, C.text, F.uiB, "center")
    text(help, tx + tw / 2, ty + 22 * U, C.hint, F.map, "center")
end

-- every click is the picker's while it is open
function hdgPickerClick(btn, state)
    if not PICK.open then return false end
    if state ~= "down" then return true end
    if btn == "left" then
        local id, sel, dir = PICK.ac, PICK.sel, PICK.dir
        hdgPickerClose()
        triggerServerEvent("avi:ctlCmd", resourceRoot, "hdg", id, { hdg = sel, dir = dir })
    elseif btn == "right" then
        back()
    end
    return true
end

-- dir: +1 = 5° right (clockwise), -1 = 5° left
function hdgPickerScroll(dir)
    if not PICK.open then return false end
    PICK.sel = norm(PICK.sel + dir * STEP)
    return true
end

function hdgPickerKey(key)
    if not PICK.open or key ~= "escape" then return false end
    back()
    return true
end
