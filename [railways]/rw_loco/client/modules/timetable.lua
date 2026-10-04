-- Timetable module (every locomotive): the left panel (toggle LOCO.KEYS.timetable) to pick a
-- service and follow its stops, and a small always-on display above the minimap with the
-- essentials (next stop, delay, signal in front, Sifa). Picking a service needs the railway
-- role; rw_timetable checks it again. The running service comes from the lead's
-- "rw.service" element data (rw_timetable keeps it up to date).

local M = {}
local open = false
local list, listAccess, listTick = nil, true, 0
local syncTick, syncView = 0, nil
local sig = { id = nil, name = nil, aspect = nil, dist = nil, t = 0 }
local scroll = 0

local ASPECT_COLOR = { [0] = { 235, 60, 50 }, [1] = { 245, 195, 40 }, [2] = { 50, 220, 110 } }
local C = {
    bg = tocolor(14, 19, 28, 235), head = tocolor(30, 70, 140, 255), line = tocolor(46, 58, 80, 255),
    text = tocolor(235, 240, 250), muted = tocolor(150, 162, 182), green = tocolor(60, 210, 120),
    red = tocolor(240, 80, 70), yellow = tocolor(245, 200, 60), row = tocolor(24, 32, 46, 255),
    rowHover = tocolor(34, 52, 82, 255), next = tocolor(30, 58, 100, 255),
}

local function ttRoot()
    local r = getResourceFromName("rw_timetable")
    return r and getResourceState(r) == "running" and getResourceRootElement(r)
end

local function hhmm(s)
    if not s then return "" end
    s = math.floor(s) % 86400
    return ("%02d:%02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60))
end

local function mmss(s)
    local neg = s < 0
    s = math.abs(math.floor(s))
    return (neg and "-" or "") .. ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function delayText(d)
    d = d or 0
    local m = math.floor(d / 60 + 0.5)
    if m >= 1 then return "+" .. m .. " min", C.red end
    return "on time", C.green
end

local function service()
    return isElement(Loco.lead) and getElementData(Loco.lead, "rw.service") or nil
end

-- server clock (seconds of the day): synced from the service data, the list answer and
-- an explicit request when entering the cab; falls back to the game clock (= real time)
local clockSod, clockTick = nil, 0
local function setClock(sod)
    if sod then clockSod, clockTick = sod, getTickCount() end
end

local function serverNow()
    local v = service()
    if v and v ~= syncView then
        syncView, syncTick = v, getTickCount()
        setClock(v.t)
    end
    if clockSod then return clockSod + (getTickCount() - clockTick) / 1000 end
    local h, m = getTime()
    return h * 3600 + m * 60
end

local function hhmmss(s)
    s = math.floor(s) % 86400
    return ("%02d:%02d:%02d"):format(math.floor(s / 3600), math.floor(s % 3600 / 60), s % 60)
end

addEvent("rw:tt:timeResult", true)
addEventHandler("rw:tt:timeResult", root, function(sod) setClock(sod) end)

local function requestList()
    local r = ttRoot()
    if not r then return end
    listTick = getTickCount()
    triggerServerEvent("rw:tt:list", r)
end

addEvent("rw:tt:listResult", true)
addEventHandler("rw:tt:listResult", root, function(l, access, sod)
    list, listAccess = l or {}, access
    setClock(sod)
end)

local function pollSignal()
    if getTickCount() - sig.t < 300 then return end
    sig.t = getTickCount()
    local track, _, dir, head = Loco.trackInfo()
    if not track then sig.id = nil return end
    local ok, id, name, aspect, dist = pcall(function() return exports.rw_signals:getSignalAhead(track, head, dir) end)
    if ok and id then sig.id, sig.name, sig.aspect, sig.dist = id, name, aspect, dist
    else sig.id = nil end
end

------------------------------------------------------------------ drawing helpers

local function txt(s, x, y, w, h, c, font, ax, ay, wrap)
    dxDrawText(s, x, y, x + w, y + h, c, 1, font, ax or "left", ay or "center", true, wrap or false, false, false, true)
end

local function button(x, y, w, h, label, fn, color)
    local hover = Loco.cursorIn(x, y, w, h)
    dxDrawRectangle(x, y, w, h, color or (hover and tocolor(60, 110, 200) or tocolor(40, 80, 160)))
    txt(label, x, y, w, h, C.text, Loco.font(true, 11), "center", "center")
    Loco.hit(x, y, w, h, fn)
end

------------------------------------------------------------------ mini display

local function drawMini(ctx)
    local r = ctx.L.mini
    local s = ctx.s
    local x, y, w, h = r.x, r.y, r.w, r.h
    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, 4 * s, h, C.head)
    local pad = 12 * s
    local fB, f = ctx.font(true, 12), ctx.font(false, 10)
    local v = service()
    local lineH = 21 * s
    local cy = y + 6 * s
    if v and v.status ~= "completed" then
        txt(v.trip .. "  →  " .. (v.toName or ""), x + pad, cy, w - pad * 2, lineH, C.text, fB)
        local dt, dc = delayText(v.delay)
        txt(dt, x + pad, cy, w - pad * 2, lineH, dc, fB, "right")
        cy = cy + lineH
        local st = v.stops and v.stops[v.nextStop]
        local now = serverNow()
        if st and now then
            local target = (st.state == "stopped" and st.dep) or st.arr or st.dep
            local label = st.state == "stopped" and "Dep. " or "Next: "
            local rest = target and ("  " .. hhmm(target) .. "  (" .. mmss(target - now) .. ")") or ""
            txt(label .. st.name .. rest, x + pad, cy, w - pad * 2, lineH, C.text, f)
        end
    elseif v and v.status == "completed" then
        txt(v.trip .. " completed", x + pad, cy, w - pad * 2, lineH, C.green, fB)
        cy = cy + lineH
    else
        txt("No service", x + pad, cy, w - pad * 2, lineH, C.muted, fB)
        cy = cy + lineH
        txt(("Press %s to pick a timetable"):format(LOCO.KEYS.timetable:upper()), x + pad, cy, w - pad * 2, lineH, C.muted, f)
    end
    cy = y + h - lineH * 2 - 6 * s
    -- signal in front
    if sig.id then
        local c = ASPECT_COLOR[sig.aspect] or { 120, 120, 120 }
        dxDrawCircle(x + pad + 6 * s, cy + lineH / 2, 6 * s, 0, 360, tocolor(c[1], c[2], c[3]), tocolor(255, 255, 255), 16)
        txt(("Signal %s   %d m"):format(sig.name, math.floor(sig.dist / 10 + 0.5) * 10), x + pad + 18 * s, cy, w, lineH, C.text, f)
    else
        txt("No signal ahead", x + pad, cy, w, lineH, C.muted, f)
    end
    cy = cy + lineH
    local spd = math.floor(ctx.speed() + 0.5)
    txt(spd .. " km/h", x + pad, cy, w, lineH, C.text, fB)
    -- Sifa state
    local st = Sifa and Sifa.state or "idle"
    local sc = st == "idle" and tocolor(40, 46, 58) or (st == "lamp" and tocolor(230, 230, 230) or tocolor(240, 70, 60))
    dxDrawRectangle(x + w - pad - 60 * s, cy + 2 * s, 60 * s, lineH - 4 * s, sc)
    txt("SIFA", x + w - pad - 60 * s, cy, 60 * s, lineH, st == "idle" and C.muted or tocolor(20, 20, 20), ctx.font(true, 10), "center")
end

------------------------------------------------------------------ panel

local function drawPanel(ctx)
    local r = ctx.L.tt
    local s = ctx.s
    local x, y, w, h = r.x, r.y, r.w, r.h
    local pad = 14 * s
    dxDrawRectangle(x, y, w, h, C.bg)
    dxDrawRectangle(x, y, w, 34 * s, C.head)
    txt("TIMETABLE", x + pad, y, w, 34 * s, C.text, ctx.font(true, 13))
    txt(hhmmss(serverNow()), x, y, w - 40 * s, 34 * s, tocolor(255, 215, 120), ctx.font(true, 14), "right")
    button(x + w - 32 * s, y + 5 * s, 24 * s, 24 * s, "×", function() open = false end, tocolor(0, 0, 0, 0))
    local cy = y + 44 * s
    local v = service()
    local fB, f, fS = ctx.font(true, 12), ctx.font(false, 11), ctx.font(false, 9)

    if v then
        txt(v.trip, x + pad, cy, w, 26 * s, C.text, ctx.font(true, 18))
        local dt, dc = delayText(v.delay)
        txt(v.status == "completed" and "COMPLETED" or dt, x, cy, w - pad, 26 * s, v.status == "completed" and C.green or dc, ctx.font(true, 14), "right")
        cy = cy + 26 * s
        txt(v.name .. ":  " .. (v.fromName or "") .. "  →  " .. (v.toName or ""), x + pad, cy, w - pad * 2, 20 * s, C.muted, f)
        cy = cy + 28 * s

        -- current / next stop box
        local st = v.stops and v.stops[v.nextStop]
        local now = serverNow()
        if st and v.status ~= "completed" then
            dxDrawRectangle(x + pad, cy, w - pad * 2, 64 * s, C.next)
            local standing = st.state == "stopped"
            txt(standing and "AT STATION" or "NEXT STOP", x + pad + 10 * s, cy + 4 * s, w, 16 * s, tocolor(170, 195, 235), fS, "left", "top")
            txt(st.name, x + pad + 10 * s, cy + 18 * s, w, 22 * s, C.text, ctx.font(true, 14), "left", "top")
            local target = standing and st.dep or st.arr or st.dep
            if target and now then
                txt((standing and "dep " or "arr ") .. hhmm(target), x, cy + 4 * s, w - pad - 10 * s, 16 * s, C.text, fB, "right", "top")
                txt(mmss(target - now), x, cy + 20 * s, w - pad - 10 * s, 20 * s, (target - now) < 0 and C.red or C.yellow, ctx.font(true, 14), "right", "top")
            end
            if standing then
                local frac = math.min(1, (v.doorTime or 0) / (v.doorMin or 15))
                local bx, by, bw = x + pad + 10 * s, cy + 46 * s, w - pad * 2 - 20 * s
                dxDrawRectangle(bx, by, bw, 8 * s, tocolor(10, 14, 22))
                dxDrawRectangle(bx, by, bw * frac, 8 * s, frac >= 1 and C.green or C.yellow)
                local doorsTxt = Loco.doors() == "closed" and "doors closed" or "doors open"
                local side = v.side and (" - platform on the " .. v.side) or ""
                txt(doorsTxt .. side, bx, by - 14 * s, bw, 12 * s, C.muted, fS, "right", "top")
            end
            cy = cy + 74 * s
        end

        -- stop list
        local cols = { w * 0.44, w * 0.15, w * 0.15, w * 0.18 }
        local hx = x + pad
        txt("STATION", hx, cy, cols[1], 16 * s, C.muted, fS)
        txt("ARR", hx + cols[1], cy, cols[2], 16 * s, C.muted, fS)
        txt("DEP", hx + cols[1] + cols[2], cy, cols[3], 16 * s, C.muted, fS)
        txt("ACTUAL", hx + cols[1] + cols[2] + cols[3], cy, cols[4], 16 * s, C.muted, fS)
        cy = cy + 18 * s
        dxDrawRectangle(x + pad, cy, w - pad * 2, 1, C.line)
        cy = cy + 4 * s
        local n = #(v.stops or {})
        for i, st2 in ipairs(v.stops or {}) do
            local rowH = 24 * s
            if i == v.nextStop and v.status ~= "completed" then dxDrawRectangle(x + pad, cy, w - pad * 2, rowH, C.next) end
            local done = st2.state == "done" or st2.state == "skipped"
            local col = done and C.muted or C.text
            txt(st2.name, hx + 4 * s, cy, cols[1], rowH, col, f)
            txt(i > 1 and hhmm(st2.arr) or "", hx + cols[1], cy, cols[2], rowH, col, f)
            txt(i < n and hhmm(st2.dep) or "", hx + cols[1] + cols[2], cy, cols[3], rowH, col, f)
            local act, ac = "", C.text
            if st2.state == "skipped" then act, ac = "not served", C.red
            elseif st2.actDep or (i > 1 and st2.actArr) then
                local t = st2.actDep or st2.actArr
                local sched = st2.actDep and st2.dep or st2.arr
                act = hhmm(t)
                ac = (sched and t - sched >= 60) and C.red or C.green
            end
            txt(act, hx + cols[1] + cols[2] + cols[3], cy, cols[4], rowH, ac, f)
            cy = cy + rowH
        end
        if v.status ~= "completed" then
            button(x + pad, y + h - 42 * s, w - pad * 2, 30 * s, "End service", function()
                local rr = ttRoot()
                if rr then triggerServerEvent("rw:tt:end", rr) end
            end, Loco.cursorIn(x + pad, y + h - 42 * s, w - pad * 2, 30 * s) and tocolor(170, 50, 45) or tocolor(130, 40, 36))
        end
        return
    end

    -- no service: pick one
    if not ttRoot() then
        txt("Timetable service offline.", x + pad, cy, w, 20 * s, C.muted, f)
        return
    end
    if list == nil or getTickCount() - listTick > 10000 then requestList() end
    -- drop trips that passed the take deadline since the last answer (30 s before departure)
    if list then
        local now = serverNow()
        for i = #list, 1, -1 do
            local diff = (list[i].dep - now + 43200) % 86400 - 43200
            if diff < 30 then table.remove(list, i) end
        end
    end
    if not listAccess then
        txt("Railway staff only.", x + pad, cy, w - pad * 2, 22 * s, C.red, fB)
        txt("You can drive, but taking a service needs the railway role.", x + pad, cy + 24 * s, w - pad * 2, 40 * s, C.muted, f, "left", "top", true)
        return
    end
    txt("Pick a service", x + pad, cy, w, 22 * s, C.text, fB)
    button(x + w - pad - 80 * s, cy - 2 * s, 80 * s, 24 * s, "Refresh", requestList)
    cy = cy + 32 * s
    if not list or #list == 0 then
        txt(list and ("No service available from here right now. A service must be taken at least 30 s before its departure.")
            or "Loading...", x + pad, cy, w - pad * 2, 60 * s, C.muted, f, "left", "top", true)
        return
    end
    local rowH = 46 * s
    local maxRows = math.max(1, math.floor((y + h - cy - 10 * s) / (rowH + 4 * s)))
    scroll = math.max(0, math.min(scroll, #list - maxRows))
    for i = 1 + scroll, math.min(#list, scroll + maxRows) do
        local e = list[i]
        local hover = e.ok and Loco.cursorIn(x + pad, cy, w - pad * 2, rowH)
        dxDrawRectangle(x + pad, cy, w - pad * 2, rowH, hover and C.rowHover or C.row)
        dxDrawRectangle(x + pad, cy, 4 * s, rowH, e.ok and C.green or tocolor(90, 96, 110))
        txt(hhmm(e.dep) .. "   " .. e.number, x + pad + 12 * s, cy + 4 * s, w, 20 * s, e.ok and C.text or C.muted, fB, "left", "top")
        txt(e.ok and ("to " .. (e.toName or e.to) .. " - click to take it") or e.reason or "",
            x + pad + 12 * s, cy + 24 * s, w - pad * 2 - 20 * s, 18 * s, e.ok and C.muted or tocolor(200, 120, 100), fS, "left", "top")
        if e.ok then
            local tripId = e.tripId
            Loco.hit(x + pad, cy, w - pad * 2, rowH, function()
                local rr = ttRoot()
                if rr then triggerServerEvent("rw:tt:take", rr, tripId) end
                list = nil
            end)
        end
        cy = cy + rowH + 4 * s
    end
end

------------------------------------------------------------------ module

function M.render(ctx)
    pollSignal()
    if open then drawPanel(ctx) else drawMini(ctx) end
end

function M.enter()
    open, list = false, nil
    local r = ttRoot()
    if r then triggerServerEvent("rw:tt:time", r) end
end

function M.leave()
    open = false
end

addCommandHandler("rw_timetable", function()
    if not Loco.active or isChatBoxInputActive() then return end
    open = not open
    if open then list = nil end
end)
bindKey(LOCO.KEYS.timetable, "down", "rw_timetable")

bindKey("mouse_wheel_down", "down", function() if open and Loco.active then scroll = scroll + 1 end end)
bindKey("mouse_wheel_up", "down", function() if open and Loco.active then scroll = math.max(0, scroll - 1) end end)

registerLocoModule("timetable", M)
