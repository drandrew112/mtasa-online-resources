-- The radar scope: full-screen DX picture, top bar, traffic list, mouse handling.
--   wheel = zoom at the cursor, right drag = pan, left drag on a label = move the label,
--   left click on a label / target = command menu, the ATC marker (E) = hide / show (stays logged in).

local C = {
    bar     = tocolor(14, 22, 34, 245),
    barLine = tocolor(50, 80, 120, 255),
    text    = tocolor(220, 228, 240, 255),
    dim     = tocolor(120, 132, 150, 255),
    btn     = tocolor(30, 52, 84, 255),
    btnHov  = tocolor(50, 85, 135, 255),
    red     = tocolor(130, 45, 45, 255),
    redHov  = tocolor(175, 65, 65, 255),
    list    = tocolor(10, 16, 26, 235),
    rowHov  = tocolor(35, 55, 85, 255),
    mine    = tocolor(95, 170, 255, 255),
    other   = tocolor(110, 120, 138, 255),
    scale   = tocolor(150, 165, 185, 255),
    req     = tocolor(255, 215, 60, 255),
}

local buttons = {}
local listRows = {}
local drag      -- { kind = "pan" | "label", id, sx, sy, moved }
local prevHide

-- ---------------------------------------------------------------- open / close
function scopeShow()
    if SC.visible then return end
    SC.visible = true
    showCursor(true)
    toggleAllControls(false, true, false)
    prevHide = getElementData(localPlayer, "hideHUD")
    setElementData(localPlayer, "hideHUD", true, false)
end

function scopeHide()
    if not SC.visible then return end
    SC.visible = false
    drag = nil
    menuClose()
    hdgPickerClose()
    if not LOGIN.open then showCursor(false) end
    toggleAllControls(true, true, false)
    setElementData(localPlayer, "hideHUD", prevHide or false, false)
end

function scopeOpen()
    SC.open = true
    scopeShow()
end

function scopeClose()
    scopeHide()
    SC.open = false
    SC.pos, SC.data = nil, nil
    SC.traffic, SC.labelOffset, SC.routeShown = {}, {}, {}
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    if SC.visible then scopeHide() end
end)

-- ---------------------------------------------------------------- UI pieces
local function inside(r, x, y)
    return x and x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4]
end

local function button(r, label, mx, my, act, red)
    local hov = inside(r, mx, my)
    dxDrawRectangle(r[1], r[2], r[3], r[4], red and (hov and C.redHov or C.red) or (hov and C.btnHov or C.btn))
    dxDrawText(label, r[1], r[2], r[1] + r[3], r[2] + r[4], C.text, 1, F.uiB, "center", "center", true)
    buttons[#buttons + 1] = { rect = r, act = act }
end

local function drawTopBar(mx, my)
    local h = 34 * U
    dxDrawRectangle(0, 0, SC.sx, h, C.bar)
    line(0, h, SC.sx, h, C.barLine)
    local p = SC.pos
    dxDrawText(p.id, 12 * U, 0, 200 * U, h, C.mine, 1, F.title, "left", "center")
    local x = 12 * U + dxGetTextWidth(p.id, 1, F.title) + 12 * U
    dxDrawText(p.name, x, 0, x + 300 * U, h, C.dim, 1, F.ui, "left", "center")
    x = x + dxGetTextWidth(p.name, 1, F.ui) + 24 * U

    -- runways in use + wind (airport positions show their own, the centre all of them)
    local parts = {}
    local runways = SC.data.runways or {}
    local icaos = {}
    for icao in pairs(runways) do icaos[#icaos + 1] = icao end
    table.sort(icaos)
    for _, icao in ipairs(icaos) do
        if not p.airport or p.airport == icao then
            parts[#parts + 1] = ("%s ARR %s DEP %s"):format(icao, tostring(runways[icao].arr), tostring(runways[icao].dep))
        end
    end
    local w = SC.data.wind or { dir = 0, speed = 0 }
    parts[#parts + 1] = ("WIND %03d/%02d"):format(w.dir, w.speed)
    dxDrawText(table.concat(parts, "     "), x, 0, SC.sx - 520 * U, h, C.text, 1, F.ui, "left", "center", true)

    local t = getRealTime(getRealTime().timestamp, false)   -- UTC
    dxDrawText(("%02d:%02d:%02dZ"):format(t.hour, t.minute, t.second), SC.sx - 520 * U, 0, SC.sx - 430 * U, h,
        C.text, 1, F.uiB, "right", "center")

    local bw, bh, by = 74 * U, 24 * U, 5 * U
    -- leader line length (nm)
    local vx = SC.sx - 4 * (bw + 6 * U) - 4 * U - 6 * U - 104 * U
    button({ vx, by, 24 * U, bh }, "-", mx, my, function() SC.vectorStep = math.max(0, SC.vectorStep - 1) end)
    dxDrawText(SC.vectorStep == 0 and "Vector off" or ("Vector %.1f nm"):format(SC.vectorStep * CTL.VECTOR_STEP_NM), vx + 24 * U, 0, vx + 80 * U, h,
        C.text, 1, F.map, "center", "center", true)
    button({ vx + 80 * U, by, 24 * U, bh }, "+", mx, my, function() SC.vectorStep = math.min(CTL.VECTOR_MAX_STEPS, SC.vectorStep + 1) end)
    local bx = SC.sx - 4 * (bw + 6 * U) - 4 * U
    button({ bx, by, bw, bh }, SC.showList and "List: on" or "List: off", mx, my, function() SC.showList = not SC.showList end)
    bx = bx + bw + 6 * U
    button({ bx, by, bw, bh }, "Reset view", mx, my, resetView)
    bx = bx + bw + 6 * U
    button({ bx, by, bw, bh }, "Hide", mx, my, scopeHide)
    bx = bx + bw + 6 * U
    button({ bx, by, bw, bh }, "Logout", mx, my, function() triggerServerEvent("avi:ctlLogout", resourceRoot) end, true)
end

-- ---------------------------------------------------------------- flight lists (right side)
-- TWR / APP: Departures + Arrivals of their airport. Centre: Departures (still in the departure
-- TMA / on the ground), Arrivals (in the arrival TMA / landed), Sector (everything else airborne).
local function inPoly(x, y, poly)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > y) ~= (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

local function inTMA(s, icao)
    if not icao then return false end
    for _, a in ipairs(SC.data.airspaces or {}) do
        if a.id == icao .. "_TMA" then return inPoly(s.x, s.y, a.polygon) end
    end
    return false
end

local function listOf(s)
    local p = SC.pos
    if p.type ~= "CTR" then
        if s.dep == p.airport then return "dep" end
        if s.arr == p.airport then return "arr" end
        return nil
    end
    if s.gnd then return s.dir == "arr" and "arr" or "dep" end
    if airportOf(s.dep) and inTMA(s, s.dep) then return "dep" end
    if airportOf(s.arr) and inTMA(s, s.arr) then return "arr" end
    return "sec"
end

local function lvl(ft) return ft and ("%03d"):format(math.floor(ft / 100 + 0.5)) or "-" end

local function altCell(s)
    if s.gnd then
        if isMine(s) and s.req and s.ready then return "REQ " .. s.req, true end
        return s.phase:upper():sub(1, 7)
    end
    return lvl(s.alt)
end

local LISTS = {
    dep = { title = "DEPARTURES", cols = {
        { "CS", 62 }, { "TYPE", 54 }, { "ADEP", 40 }, { "ADES", 40 }, { "FIRST WP", 56 },
        { "ALT", 58 }, { "CFL", 34 }, { "RFL", 34 }, { "CTRL", 0 } } },
    arr = { title = "ARRIVALS", cols = {
        { "CS", 62 }, { "TYPE", 54 }, { "ADEP", 40 }, { "ADES", 40 }, { "LAST WP", 56 },
        { "ALT", 58 }, { "CFL", 34 }, { "CTRL", 0 } } },
    sec = { title = "SECTOR", cols = {
        { "CS", 62 }, { "TYPE", 54 }, { "ADEP", 40 }, { "ADES", 40 }, { "ENTRY", 50 }, { "EXIT", 50 },
        { "ALT", 40 }, { "CFL", 34 }, { "RFL", 34 }, { "CTRL", 0 } } },
}

local function rowValues(kind, s)
    local alt, req = altCell(s)
    local ctl = s.ctl and (s.ctl:gsub("_", " ")) or "-"
    local tw = s.type .. "/" .. s.wake
    if kind == "dep" then
        return { s.cs, tw, s.dep, s.arr, s.rfirst or "-", alt, lvl(s.cfl), lvl(s.rfl), ctl }, req
    elseif kind == "arr" then
        return { s.cs, tw, s.dep, s.arr, s.rlast or "-", alt, lvl(s.cfl), ctl }, req
    end
    return { s.cs, tw, s.dep, s.arr, s.rfirst or "-", s.rlast or "-", alt, lvl(s.cfl), lvl(s.rfl), ctl }, req
end

local function drawList(mx, my)
    listRows = {}
    if not SC.showList then return end
    local kinds = SC.pos.type == "CTR" and { "dep", "arr", "sec" } or { "dep", "arr" }
    local groups = { dep = {}, arr = {}, sec = {} }
    for id, e in pairs(SC.traffic) do
        local k = listOf(e.s)
        if k then table.insert(groups[k], { id = id, s = e.s }) end
    end
    local w = LIST_W
    local x, top = SC.sx - w, 34 * U + 1
    local share = (SC.sy - top) / #kinds
    local rh = dxGetFontHeight(1, F.ui) + 5 * U
    dxDrawRectangle(x, top, w, SC.sy - top, C.list)
    for li, kind in ipairs(kinds) do
        local def, rows = LISTS[kind], groups[kind]
        table.sort(rows, function(a, b)
            local ma, mb = isMine(a.s), isMine(b.s)
            if ma ~= mb then return ma end
            return a.s.cs < b.s.cs
        end)
        local y = top + (li - 1) * share
        if li > 1 then line(x, y, x + w, y, C.barLine) end
        dxDrawText(("%s  (%d)"):format(def.title, #rows), x + 8 * U, y + 2 * U, x + w, y + rh, C.text, 1, F.uiB)
        y = y + rh
        local cx = x + 6 * U
        for _, c in ipairs(def.cols) do
            dxDrawText(c[1], cx, y, cx + (c[2] > 0 and c[2] * U or w), y + rh, C.dim, 1, F.map, "left", "center", true)
            cx = cx + c[2] * U
        end
        y = y + rh
        local maxRows = math.floor((top + li * share - y) / rh)
        for i, r in ipairs(rows) do
            if i > maxRows then
                dxDrawText(("+%d more"):format(#rows - maxRows + 1), x, y - rh, x + w - 8 * U, y, C.dim, 1, F.map, "right", "center")
                break
            end
            local s = r.s
            local rect = { x, y, w, rh }
            if inside(rect, mx, my) then dxDrawRectangle(x, y, w, rh, C.rowHov) end
            local col = isMine(s) and C.mine or C.other
            local vals, req = rowValues(kind, s)
            cx = x + 6 * U
            for ci, c in ipairs(def.cols) do
                local vcol = (req and c[1] == "ALT") and C.req or col
                dxDrawText(vals[ci], cx, y, cx + (c[2] > 0 and c[2] * U - 2 or x + w - cx), y + rh, vcol, 1, F.ui, "left", "center", true)
                cx = cx + c[2] * U
            end
            listRows[#listRows + 1] = { rect = rect, id = r.id }
            y = y + rh
        end
    end
end

local function drawScaleBar()
    local nm = scaleBarLength()
    local len = nm * M_PER_NM * VIEW.scale
    local x, y = 16 * U, SC.sy - 22 * U
    line(x, y, x + len, y, C.scale, 2)
    line(x, y - 5 * U, x, y + 1, C.scale, 2)
    line(x + len, y - 5 * U, x + len, y + 1, C.scale, 2)
    text(nm .. " nm", x + len + 8 * U, y - 7 * U, C.scale, F.map)
end

local function drawCursorInfo(mx, my)
    if not mx then return end
    local wx, wy = s2w(mx, my)
    text(("X %.0f  Y %.0f"):format(wx, wy), 16 * U, SC.sy - 44 * U, C.dim, F.map)
end

-- ---------------------------------------------------------------- render
local function cursor()
    if not isCursorShowing() then return end
    local cx, cy = getCursorPosition()
    return cx * SC.sx, cy * SC.sy
end

addEventHandler("onClientRender", root, function()
    if not SC.visible or not SC.data or not F.ui then return end
    local mx, my = cursor()
    if LOGIN.open then mx, my = nil, nil end
    buttons = {}
    dxDrawRectangle(0, 0, SC.sx, SC.sy, COL.bg)
    drawAirspaces()
    drawAirports()
    drawNav()
    drawRoutes()
    local over = mx and (PICK.open or my < 34 * U or (SC.showList and mx > SC.sx - LIST_W)
        or (MENU.open and MENU.rect and inside(MENU.rect, mx, my)))
    drawTraffic((not over) and mx or nil, my)
    if drag and drag.kind == "label" then HOVER_ID = drag.id end
    drawScaleBar()
    drawCursorInfo(mx, my)
    drawList(mx, my)
    drawTopBar(mx, my)
    drawMenu(mx, my)
    drawHdgPicker(mx, my)
end)

-- ---------------------------------------------------------------- input
addEventHandler("onClientClick", root, function(btn, state, ax, ay)
    if LOGIN.open then
        if btn == "left" and state == "down" then loginClick(ax, ay) end
        return
    end
    if not SC.visible then return end
    if hdgPickerClick(btn, state) then
        drag = nil
        return
    end

    if btn == "right" then
        if state == "down" and HOVER_ID and SC.traffic[HOVER_ID] then
            SC.routeShown[HOVER_ID] = not SC.routeShown[HOVER_ID] or nil
        elseif state == "down" then drag = { kind = "pan", sx = ax, sy = ay }
        elseif drag and drag.kind == "pan" then drag = nil end
        return
    end
    if btn ~= "left" then return end

    if state == "down" then
        for _, b in ipairs(buttons) do
            if inside(b.rect, ax, ay) then b.act() return end
        end
        if menuClick(ax, ay) then return end
        for _, r in ipairs(listRows) do
            if inside(r.rect, ax, ay) then
                local e = SC.traffic[r.id]
                if e then centerOn(trafficPos(e)) end
                return
            end
        end
        if HOVER_ID then
            drag = { kind = "label", id = HOVER_ID, sx = ax, sy = ay, moved = false }
            return
        end
        local t = targetAt(ax, ay)
        if t then menuOpen(t, ax + 12 * U, ay + 12 * U) return end
        menuClose()
    else
        if drag and drag.kind == "label" then
            if not drag.moved then menuOpen(drag.id, ax + 12 * U, ay + 12 * U) end
            drag = nil
        end
    end
end)

addEventHandler("onClientCursorMove", root, function(_, _, ax, ay)
    if not SC.visible or not drag then return end
    local dx, dy = ax - drag.sx, ay - drag.sy
    if drag.kind == "pan" then
        panBy(dx, dy)
    elseif drag.kind == "label" then
        if not drag.moved and dx * dx + dy * dy < 16 then return end
        drag.moved = true
        moveLabel(drag.id, dx, dy)
    end
    drag.sx, drag.sy = ax, ay
end)

addEventHandler("onClientKey", root, function(key, press)
    if not SC.visible or not press or LOGIN.open then return end
    if hdgPickerKey(key) then
        cancelEvent()
        return
    end
    -- 0..5 (also on the numpad): leader line length in 0.1 nm steps, 0 = off
    local digit = tonumber(key:match("^num_(%d)$") or key:match("^(%d)$"))
    if digit then
        if digit <= CTL.VECTOR_MAX_STEPS and not isChatBoxInputActive() and not isConsoleActive()
                and not guiGetInputEnabled() and not waypointInputOpen() then
            SC.vectorStep = digit
            cancelEvent()
        end
        return
    end
    if key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        local dir = key == "mouse_wheel_up" and -1 or 1
        local mx, my = cursor()
        if PICK.open then
            hdgPickerScroll(-dir)
        elseif MENU.open and MENU.rect and mx and inside(MENU.rect, mx, my) then
            menuScroll(dir)
        elseif mx then
            zoomAt(mx, my, dir < 0 and 1.15 or 1 / 1.15)
        end
        cancelEvent()
    end
end)
