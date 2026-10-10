-- Aircraft command menu (click a label or a target).
--   Airborne: cleared altitude, fly / turn left / turn right heading (hdgpicker.lua), direct to, resume own navigation, cancel direct,
--             cleared to land, transfer.
--   Airborne arrivals (approach / radar): arrival procedure (STAR + runway, the suggested one yellow).
--   Ground (tower / delivery): IFR clearance (SID, the suggested one yellow + initial level), pushback,
--             taxi (to a runway / to a stand), cross / backtrack / line up / take-off, transfer.
--   Arrivals: cleared to land, vacate via <taxiway>, go around.
--   Everyone: show / hide the route, reset the label.
-- Only the position controlling the aircraft can give clearances; everyone else sees the info.

MENU = { open = false }

local C = {
    bg     = tocolor(16, 22, 32, 245),
    border = tocolor(70, 110, 160, 255),
    head   = tocolor(24, 34, 50, 255),
    text   = tocolor(220, 228, 240, 255),
    dim    = tocolor(110, 120, 135, 255),
    hover  = tocolor(45, 75, 115, 255),
    cur    = tocolor(255, 210, 90, 255),
    rfl    = tocolor(110, 220, 140, 255),
    headTxt = tocolor(120, 170, 230, 255),
    sep    = tocolor(50, 70, 100, 255),
    req    = tocolor(255, 215, 60, 255),
}

local VISIBLE = 14

function menuClose()
    MENU = { open = false }
end

function menuOpen(id, x, y)
    MENU = { open = true, ac = id, x = x, y = y, mode = "main", scroll = 0 }
end

local function send(action, value)
    triggerServerEvent("avi:ctlCmd", resourceRoot, action, MENU.ac, value)
    menuClose()
end

local function back()
    return { label = "< Back", act = function() MENU.mode = "main" MENU.scroll = 0 end }
end

local function sub(mode)
    return function()
        MENU.mode = mode
        MENU.scroll = nil      -- the list positions itself on the current value
    end
end

-- ---------------------------------------------------------------- sub lists
local function levelItems(s, action, maxFt)
    local items = { back() }
    local cur = action == "cfl" and (s.cfl or math.floor(s.alt / CTL.LEVEL_STEP + 0.5) * CTL.LEVEL_STEP) or (s.initAlt or 4000)
    maxFt = math.max(maxFt or CTL.LEVEL_MAX, s.rfl or 0)
    for ft = maxFt, CTL.LEVEL_MIN, -CTL.LEVEL_STEP do
        local isRfl = ft == s.rfl
        items[#items + 1] = { label = ("%03d   %d ft%s"):format(ft / 100, ft, isRfl and "   RFL" or ""), current = ft == cur,
            rfl = isRfl, key = ft, act = function()
                if action == "ifr" then send("ifr", { alt = ft, sid = MENU.sid or "" }) else send(action, ft) end
            end }
    end
    return items, cur
end

-- opens the heading picker in place of the menu (right click there comes back here)
local function picker(dir)
    return function()
        local id, x, y = MENU.ac, MENU.x, MENU.y
        menuClose()
        hdgPickerOpen(id, dir, x, y)
    end
end

local function directItems(s)
    local items = { back() }
    local seen = {}
    for _, id in ipairs(s.route or {}) do
        if not seen[id] then
            seen[id] = true
            items[#items + 1] = { label = id .. "   (flight plan)", act = function() send("dct", id) end }
        end
    end
    -- arrival final fix
    local a = airportOf(s.arr)
    local rw = SC.data.runways and SC.data.runways[s.arr]
    if a and rw then
        for _, r in ipairs(a.runways or {}) do
            for _, e in ipairs(r.ends or {}) do
                if e.ident == rw.arr and e.final and not seen[e.final] then
                    seen[e.final] = true
                    items[#items + 1] = { label = e.final .. "   (final " .. e.ident .. ")", act = function() send("dct", e.final) end }
                end
            end
        end
    end
    -- nearest other points
    local near = {}
    for _, key in ipairs({ "fixes", "vors", "ndbs" }) do
        for _, p in ipairs(SC.data.nav[key] or {}) do
            if not seen[p.id] then near[#near + 1] = { p = p, d = (p.x - s.x) ^ 2 + (p.y - s.y) ^ 2 } end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    for i = 1, math.min(8, #near) do
        local p = near[i].p
        items[#items + 1] = { label = p.id .. "   " .. fmtNm(math.sqrt(near[i].d)), act = function() send("dct", p.id) end }
    end
    items[#items + 1] = { label = "Type a waypoint...", act = function()
        local id = MENU.ac
        menuClose()
        askWaypoint(id)
    end }
    return items
end

-- SIDs / STARs of an airport as "<ID> <RWY>": the runway in use first, the suggested procedure on top
-- (yellow). pick(spec) is called with the chosen "<ID> <RWY>".
local function procedureItems(icao, ptype, rwyInUse, suggested, current, pick, noneLabel)
    local items = { back() }
    local list = {}
    for _, p in ipairs(SC.data.nav.procedures or {}) do
        if p.airport == icao and p.type == ptype then
            for ident in pairs(p.runways or {}) do
                ident = tostring(ident)
                local spec = p.id .. " " .. ident
                local sug = p.id == suggested and ident == rwyInUse
                list[#list + 1] = { spec = spec, sug = sug, inUse = ident == rwyInUse,
                    order = (sug and "0" or "1") .. (ident == rwyInUse and "0" or "1") .. ident .. p.id }
            end
        end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    for _, it in ipairs(list) do
        local spec = it.spec
        items[#items + 1] = { label = spec .. (it.sug and "   (suggested)" or (it.inUse and "" or "   (runway not in use)")),
            request = it.sug, current = spec == current, act = function() pick(spec) end }
    end
    if noneLabel then items[#items + 1] = { label = noneLabel, act = function() pick("") end } end
    return items
end

local function sidItems(s)
    local rw = SC.data.runways and SC.data.runways[s.dep]
    return procedureItems(s.dep, "SID", rw and rw.dep, s.sugSid, s.proc, function(spec)
        MENU.sid = spec
        MENU.mode = "ifr"
        MENU.scroll = nil
    end, "No SID (own navigation)")
end

local function starItems(s)
    local rw = SC.data.runways and SC.data.runways[s.arr]
    return procedureItems(s.arr, "STAR", rw and rw.arr, s.sugStar, s.proc, function(spec)
        send("star", spec)
    end)
end

local function transferItems(s)
    local items = { back() }
    for _, p in ipairs(SC.data.positions or {}) do
        if p.id ~= s.ctl then
            local who = SC.staffed[p.id]
            items[#items + 1] = { label = "Transfer to " .. p.id .. (who and ("   " .. who) or "   (closed)"),
                disabled = not who, act = function() send("xfer", p.id) end }
        end
    end
    return items
end

local function runwayItems(s)
    local items = { back() }
    local a = airportOf(s.apt or s.dep)
    local rw = SC.data.runways and SC.data.runways[s.apt or s.dep]
    for _, r in ipairs(a and a.runways or {}) do
        for _, e in ipairs(r.ends or {}) do
            local inUse = rw and e.ident == rw.dep
            items[#items + 1] = { label = "Taxi to runway " .. e.ident .. (inUse and "   (in use)" or ""), current = inUse,
                act = function() send("taxi", e.ident) end }
        end
    end
    return items
end

local function standItems(s)
    local items = { back(), { label = "Taxi to any free stand", act = function() send("taxi", "") end } }
    local a = airportOf(s.apt or s.arr)
    -- stands taken by other aircraft on the ground
    local taken = {}
    for _, e in pairs(SC.traffic) do
        if e.s.gnd and e.s.gate and e.s.apt == (s.apt or s.arr) and e.s.id ~= s.id then taken[e.s.gate] = e.s.cs end
    end
    for _, g in ipairs(a and a.gates or {}) do
        local busy = taken[g.id]
        items[#items + 1] = { label = "Taxi to stand " .. g.id .. (busy and ("   (" .. busy .. ")") or ""), disabled = busy ~= nil,
            act = function() send("taxi", g.id) end }
    end
    return items
end

-- runway exits of the arrival runway (taxiway points inside its zone), in landing order
local function vacateItems(s)
    local items = { back() }
    local a = airportOf(s.arr)
    local rws = SC.data.runways and SC.data.runways[s.arr]
    local ident = s.rwy or (rws and rws.arr)
    if not a or not ident then return items end
    for _, r in ipairs(a.runways or {}) do
        for ei, e in ipairs(r.ends or {}) do
            if e.ident == ident then
                local o = r.ends[3 - ei]
                local dx, dy = o.x - e.x, o.y - e.y
                local len = math.sqrt(dx * dx + dy * dy)
                local ux, uy = dx / len, dy / len
                local half = (r.width or 30) / 2 + 5
                local exits, seen = {}, {}
                for _, tw in ipairs(a.taxiways or {}) do
                    for _, p in ipairs(tw.points or {}) do
                        local rx, ry = p[1] - e.x, p[2] - e.y
                        local t = rx * ux + ry * uy
                        if math.abs(rx * uy - ry * ux) <= half and t >= -30 and t <= len + 30 and not seen[tw.id] then
                            seen[tw.id] = true
                            exits[#exits + 1] = { id = tw.id, t = t }
                        end
                    end
                end
                table.sort(exits, function(p, q) return p.t < q.t end)
                for _, x in ipairs(exits) do
                    items[#items + 1] = { label = ("Vacate via %s   %s from threshold"):format(x.id, fmtNm(math.max(0, x.t))),
                        current = s.vacateVia == x.id, act = function() send("vacate", x.id) end }
                end
            end
        end
    end
    return items
end

-- ---------------------------------------------------------------- main list
-- The actions are grouped into categories (headers). On the ground the whole flow of the
-- aircraft is listed in order: the step it is at now is active, the others are greyed out.
local function mainItems(s, mine)
    local cats, order = {}, {}
    local function add(cat, label, act, enabled, request)
        if not cats[cat] then
            cats[cat] = {}
            order[#order + 1] = cat
        end
        table.insert(cats[cat], { label = label, act = act, disabled = not enabled, request = request })
    end
    local p = s.phase
    local air = p == "air" or p == "final"
    local hasApt = airportOf(s.arr) ~= nil
    local twr = mine and SC.pos and SC.pos.type == "TWR"
    local vacateLabel = "Vacate via  >" .. (s.vacateVia and ("   (" .. s.vacateVia .. ")") or "")

    if air then
        local vec = mine and p == "air"
        local posType = SC.pos and SC.pos.type
        add("LEVEL & ROUTE", "Cleared altitude  >", sub("cfl"), vec)
        add("LEVEL & ROUTE", "Fly heading  >", picker(nil), vec)
        add("LEVEL & ROUTE", "Turn left heading  >", picker("L"), vec)
        add("LEVEL & ROUTE", "Turn right heading  >", picker("R"), vec)
        add("LEVEL & ROUTE", "Direct to  >", sub("dct"), vec)
        if hasApt and (posType == "APP" or posType == "CTR") then
            add("LEVEL & ROUTE", "Arrival procedure  >" .. (s.proc and ("   (" .. s.proc .. ")") or ""), sub("star"), vec,
                s.req == "STAR")
        end
        if s.ahdg then add("LEVEL & ROUTE", "Resume own navigation", function() send("nohdg") end, mine) end
        if s.dct then add("LEVEL & ROUTE", "Cancel direct " .. s.dct, function() send("nodct") end, mine) end
        if hasApt then
            add("APPROACH & LANDING", s.landClr and "Cleared to land (given)" or "Cleared to land",
                function() send("land") end, twr and not s.landClr, s.req == "LAND")
            add("APPROACH & LANDING", vacateLabel, sub("vacate"), twr)
            add("APPROACH & LANDING", "Go around", function() send("goaround") end, mine and (p == "final" or s.req == "LAND"))
        end
    elseif s.dir == "arr" then
        add("RUNWAY", vacateLabel, sub("vacate"), twr and p == "landing")
        add("RUNWAY", "Cross runway " .. tostring(s.holdRwy or ""), function() send("cross") end,
            twr and p == "hold" and s.req == "CROSS", p == "hold" and s.req == "CROSS")
        add("GROUND", "Taxi to stand  >", sub("stand"), twr and (p == "landing" or p == "vacate" or p == "vacated"),
            s.req == "TAXI")
    else
        local holdTO = p == "hold" and s.req == "T/O"
        add("DELIVERY", s.ifr and ("IFR clearance (given, %s %03d)"):format(s.proc or "no SID", (s.initAlt or 0) / 100)
            or "IFR clearance  >", sub("sid"), twr and p == "gate" and not s.ifr, s.req == "IFR")
        add("GROUND", "Pushback approved", function() send("push") end, twr and p == "gate" and s.ifr and s.req == "PUSH",
            s.req == "PUSH")
        add("GROUND", "Taxi  >", sub("rwy"), twr and s.req == "TAXI", s.req == "TAXI")
        add("RUNWAY", "Cross runway " .. (p == "hold" and s.req == "CROSS" and tostring(s.holdRwy) or ""),
            function() send("cross") end, twr and p == "hold" and s.req == "CROSS", p == "hold" and s.req == "CROSS")
        add("RUNWAY", "Backtrack runway " .. (p == "hold" and s.req == "BKTRK" and tostring(s.holdRwy) or ""),
            function() send("backtrack") end, twr and p == "hold" and s.req == "BKTRK", p == "hold" and s.req == "BKTRK")
        add("RUNWAY", "Line up and wait " .. tostring(s.rwy or ""), function() send("lineup") end, twr and holdTO)
        add("RUNWAY", "Cleared for take-off " .. tostring(s.rwy or ""), function() send("takeoff") end,
            twr and (holdTO or (p == "lined" and s.req == "T/O")), holdTO or (p == "lined" and s.req == "T/O"))
    end

    add("COORDINATION", "Transfer to  >", sub("xfer"), mine)
    add("DISPLAY", SC.routeShown[MENU.ac] and "Hide route" or "Show route", function()
        SC.routeShown[MENU.ac] = not SC.routeShown[MENU.ac] or nil
        menuClose()
    end, true)
    add("DISPLAY", "Reset label position", function()
        SC.labelOffset[MENU.ac] = nil
        menuClose()
    end, true)
    add("DISPLAY", "Close", menuClose, true)

    local items = {}
    for _, cat in ipairs(order) do
        items[#items + 1] = { label = cat, header = true, disabled = true }
        for _, it in ipairs(cats[cat]) do items[#items + 1] = it end
    end
    return items
end

local function infoLines(s)
    local a = airportOf(s.arr)
    local dest = s.arr
    if a and not s.gnd then dest = dest .. "  " .. fmtNm(math.sqrt((a.arp[1] - s.x) ^ 2 + (a.arp[2] - s.y) ^ 2)) end
    local status = s.gnd and (s.phase .. (s.gate and (" " .. s.gate) or "")) or s.phase
    if s.req and isMine(s) then status = status .. "   needs: " .. s.req end
    return {
        ("%s  %s/%s  SQK %s"):format(s.cs, s.type, s.wake, s.sqk or "----"),
        ("%s > %s   %s"):format(s.dep, dest, status),
        "Route: " .. ((s.route and #s.route > 0) and table.concat(s.route, " ") or "-"),
        "Procedure: " .. (s.proc or "-") .. ((s.sugSid or s.sugStar) and ("   suggested: " .. (s.sugSid or s.sugStar)) or ""),
        "Controlled by: " .. (s.ctl or "nobody") .. (isMine(s) and "  (you)" or ""),
    }
end

local function centred(items, cur)
    if MENU.scroll == nil then
        local idx = 2
        for i, it in ipairs(items) do if it.key == cur then idx = i end end
        MENU.scroll = math.max(0, math.min(#items - VISIBLE, idx - math.floor(VISIBLE / 2)))
    end
    return items
end

local function currentItems(s, mine)
    local m = MENU.mode
    if m == "cfl" then return centred(levelItems(s, "cfl")) end
    if m == "ifr" then return centred(levelItems(s, "ifr", 10000)) end
    if m == "sid" then MENU.scroll = MENU.scroll or 0 return sidItems(s) end
    if m == "star" then MENU.scroll = MENU.scroll or 0 return starItems(s) end
    if m == "dct" then MENU.scroll = MENU.scroll or 0 return directItems(s) end
    if m == "xfer" then MENU.scroll = MENU.scroll or 0 return transferItems(s) end
    if m == "rwy" then MENU.scroll = MENU.scroll or 0 return runwayItems(s) end
    if m == "stand" then MENU.scroll = MENU.scroll or 0 return standItems(s) end
    if m == "vacate" then MENU.scroll = MENU.scroll or 0 return vacateItems(s) end
    return mainItems(s, mine)
end

-- ---------------------------------------------------------------- drawing / input
function drawMenu(mx, my)
    if not MENU.open then return end
    local e = SC.traffic[MENU.ac]
    if not e then menuClose() return end
    local s, mine = e.s, isMine(e.s)
    local items = currentItems(s, mine)
    local info = infoLines(s)
    local w = 320 * U
    local ih = 22 * U
    local lh = dxGetFontHeight(1, F.ui)
    local headH = lh * #info + 10 * U
    local visible = MENU.mode == "main" and #items or VISIBLE      -- the main list always shows whole
    MENU.scroll = math.min(MENU.scroll or 0, math.max(0, #items - visible))
    local first = MENU.scroll + 1
    local last = math.min(#items, first + visible - 1)
    local h = headH + (last - first + 1) * ih + 6 * U
    local x = math.min(MENU.x, SC.sx - w - 8)
    local y = math.min(MENU.y, SC.sy - h - 8)
    MENU.rect = { x, y, w, h }
    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, w, headH, C.head)
    line(x, y, x + w, y, C.border)
    line(x, y + h, x + w, y + h, C.border)
    line(x, y, x, y + h, C.border)
    line(x + w, y, x + w, y + h, C.border)
    for i, l in ipairs(info) do
        dxDrawText(l, x + 8 * U, y + 5 * U + (i - 1) * lh, x + w - 8 * U, y + 5 * U + i * lh, i == 1 and C.text or C.dim,
            1, i == 1 and F.uiB or F.ui, "left", "top", true)
    end
    MENU.items = {}
    local iy = y + headH + 3 * U
    for i = first, last do
        local it = items[i]
        local r = { x + 3 * U, iy, w - 6 * U, ih }
        if it.header then
            -- category header: accent text + separator line
            if i > first then line(r[1] + 4 * U, r[2] + 2 * U, r[1] + r[3] - 4 * U, r[2] + 2 * U, C.sep) end
            dxDrawText(it.label, r[1] + 4 * U, r[2] + 2 * U, r[1] + r[3], r[2] + r[4], C.headTxt, 1, F.map, "left", "center", true)
        end
        local hover = not it.disabled and mx and mx >= r[1] and mx <= r[1] + r[3] and my >= r[2] and my <= r[2] + r[4]
        if hover then dxDrawRectangle(r[1], r[2], r[3], r[4], C.hover) end
        local col = it.disabled and C.dim or ((it.current or it.request) and C.cur or (it.rfl and C.rfl or C.text))
        if not it.header then
            dxDrawText(it.label, r[1] + 14 * U, r[2], r[1] + r[3], r[2] + r[4], col, 1, F.ui, "left", "center", true)
        end
        MENU.items[#MENU.items + 1] = { rect = r, item = it }
        iy = iy + ih
    end
    if #items > visible then
        dxDrawText(("%d-%d / %d  (wheel)"):format(first, last, #items), x, y + h - 2, x + w - 6 * U, y + h - 2,
            C.dim, 1, F.map, "right", "bottom")
    end
end

-- true when the click was used by the menu
function menuClick(mx, my)
    if not MENU.open or not MENU.rect then return false end
    local r = MENU.rect
    if mx < r[1] or mx > r[1] + r[3] or my < r[2] or my > r[2] + r[4] then return false end
    for _, b in ipairs(MENU.items or {}) do
        local q = b.rect
        if mx >= q[1] and mx <= q[1] + q[3] and my >= q[2] and my <= q[2] + q[4] then
            if not b.item.disabled then b.item.act() end
            return true
        end
    end
    return true
end

function menuScroll(dir)
    if not MENU.open or MENU.mode == "main" then return false end
    MENU.scroll = math.max(0, (MENU.scroll or 0) + dir)
    return true
end

-- typed waypoint (ui_core text input)
local pending
function waypointInputOpen()
    return pending ~= nil
end

function askWaypoint(id)
    local res = getResourceFromName("ui_core")
    if not (res and getResourceState(res) == "running") then return end
    pending = { token = exports.ui_core:openTextInput("Direct to (FIX / VOR / NDB)", 8, ""), ac = id }
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, txt)
    if not pending or token ~= pending.token then return end
    local id = pending.ac
    pending = nil
    if txt and txt ~= "" then
        triggerServerEvent("avi:ctlCmd", resourceRoot, "dct", id, txt:upper())
    end
end)
