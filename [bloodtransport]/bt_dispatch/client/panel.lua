if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- The panel in the bottom right corner (only for players with the blood transporter right):
--   small view: service state + the tasks in transit
--   big view (J, cursor): sign on / off, wind down, tasks (route, order, hand over), incoming offer

PanelBig = false
local KEY = "j"
-- Screen rectangles of the last drawn frame, for the work_bloodtransport tutorial (getPanelLayout)
local Layout = { visible = false }
local scroll = 0
local offerIn            -- { id, till, ... } incoming handover offer

local function setBig(on)
    if on and not (TextsLoaded and HasRight()) then on = false end
    if PanelBig == on then return end
    PanelBig = on
    showCursor(on)
    scroll = 0
end

local function toggleBig()
    if isMainMenuActive() or getElementData(localPlayer, "inventoryOpen") or getElementData(localPlayer, "browserOpen") then
        if not PanelBig then return end
    end
    setBig(not PanelBig)
end
bindKey(KEY, "down", toggleBig)

addEventHandler("onClientPlayerWasted", localPlayer, function() setBig(false) end)
addEventHandler("onClientResourceStop", resourceRoot, function() if PanelBig then showCursor(false) end end)

addEvent("btd:offerIn", true)
addEventHandler("btd:offerIn", resourceRoot, function(id, info)
    offerIn = info
    offerIn.id = id
    offerIn.till = getTickCount() + (info.seconds or 20) * 1000
    pcall(function() exports.ui_core:addNotification(L("bt_dispatch.notify.title"), L("bt_dispatch.notify.offer_in",
        { unit = info.unit, name = info.name })) end)
end)
addEvent("btd:offerEnd", true)
addEventHandler("btd:offerEnd", resourceRoot, function(id)
    if offerIn and offerIn.id == id then offerIn = nil end
end)

local function send(event, ...) triggerServerEvent(event, resourceRoot, ...) end

-- ---------------------------------------------------------------------------------------------
-- Small view
-- ---------------------------------------------------------------------------------------------

local MAX_SMALL = 2

local function drawSmall()
    local w = S(390)
    local transit = {}
    for _, t in ipairs(State.tasks) do
        if t.status == "transit" then transit[#transit + 1] = t end
    end
    local rows = math.min(#transit, MAX_SMALL)
    local h = S(72) + (State.onDuty and (S(26) + rows * S(52) + (#transit > MAX_SMALL and S(20) or 0) + S(8)) or S(44))
    local x, y = SW - w - S(30), SH - h - S(24)
    Layout.small = { x, y, w, h }
    Round(x, y, w, h, S(8), RGB(COL.bg))
    dxDrawRectangle(x, y, w, S(4), RGB(COL.acc))
    dxDrawRectangle(x, y + S(4), w, S(66), RGB(COL.head))
    Text(L("bt_dispatch.panel.title"), x + S(18), y + S(12), w, S(16), RGB(COL.muted), 9, true)
    local expandW = TextWidth(L("bt_dispatch.panel.expand"), 10)
    local keyW = TextWidth(KEY:upper(), 10, true) + S(14)
    local kx = x + w - S(18) - expandW - S(8) - keyW
    Round(kx, y + S(10), keyW, S(20), S(4), RGB(COL.key))
    Text(KEY:upper(), kx, y + S(10), keyW, S(20), tocolor(30, 24, 10), 10, true, "center")
    Text(L("bt_dispatch.panel.expand"), x, y + S(10), w - S(18), S(20), RGB(COL.muted), 10, false, "right")
    if State.onDuty then
        Text(State.unit or "", x + S(18), y + S(34), w, S(28), RGB(COL.text), 15, true)
        local ux = x + S(18) + TextWidth(State.unit or "", 15, true) + S(12)
        Chip(ux, y + S(38), L(State.windDown and "bt_dispatch.panel.winding_down" or "bt_dispatch.panel.on_duty"),
            State.windDown and COL.warn or COL.good, 9)
        local yy = y + S(80)
        Text(L("bt_dispatch.panel.in_transit"), x + S(18), yy, w, S(18), RGB(COL.muted), 8, true)
        Text(tostring(#transit), x, yy, w - S(18), S(18), RGB(COL.muted), 8, true, "right")
        yy = yy + S(22)
        for i = 1, rows do
            local t = transit[i]
            Round(x + S(12), yy, w - S(24), S(46), S(6), RGB(COL.tile))
            local code, col = TaskTile(t)
            Round(x + S(18), yy + S(7), S(32), S(32), S(6), RGB(col))
            Text(code, x + S(18), yy + S(7), S(32), S(32), tocolor(255, 255, 255), 10, true, "center")
            Text(FitText("\226\134\146 " .. t.toName, w - S(190), 10, true), x + S(58), yy + S(5), w - S(190), S(20), RGB(COL.text), 10, true)
            Text(TaskWhat(t), x + S(58), yy + S(24), w - S(190), S(18), RGB(COL.muted), 9)
            Chip(x + w - S(20), yy + S(14), L("bt_dispatch.status.transit"), COL.warn, 8, true)
            yy = yy + S(52)
        end
        if #transit > MAX_SMALL then
            Text(L("bt_dispatch.panel.more", { count = #transit - MAX_SMALL }), x + S(18), yy - S(2), w, S(18), RGB(COL.muted), 9)
        end
    else
        Text(L("bt_dispatch.panel.off_duty"), x + S(18), y + S(34), w, S(28), RGB(COL.muted), 15, true)
        Text(L("bt_dispatch.panel.off_duty_hint"), x + S(18), y + S(76), w - S(36), S(30), RGB(COL.muted), 9)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Big view
-- ---------------------------------------------------------------------------------------------

local function counts()
    local c = { transit = 0, waiting = 0 }
    for _, t in ipairs(State.tasks) do
        if c[t.status] then c[t.status] = c[t.status] + 1 end
    end
    return c
end

local function drawRow(x, y, w, t, mode)
    local rh = S(66)
    local transit = mode == "transit"
    local rect = { row = { x, y, w, rh }, status = t.status, routeOn = t.route == true }
    Layout.tasks[tostring(t.id)] = rect
    Round(x, y, w, rh, S(6), RGB(COL.tile))
    if transit then
        for _, r in ipairs({ { x, y, w, S(1) }, { x, y + rh - S(1), w, S(1) }, { x, y, S(1), rh }, { x + w - S(1), y, S(1), rh } }) do
            dxDrawRectangle(r[1], r[2], r[3], r[4], RGB(COL.warn))
        end
    end
    local code, col = TaskTile(t)
    Round(x + S(34), y + S(15), S(36), S(36), S(6), RGB(mode == "done" and t.status == "cancelled" and COL.off or col))
    Text(code, x + S(34), y + S(15), S(36), S(36), tocolor(255, 255, 255), 11, true, "center")
    if mode == "wait" then
        Text("\226\139\174\226\139\174", x + S(6), y, S(22), rh, RGB(COL.off), 12, true, "center")
    end
    local what = TaskWhat(t)
    Text(what, x + S(82), y + S(9), w, S(22), RGB(COL.text), 12, true)
    local tag, tagCol = TaskTag(t)
    Chip(x + S(82) + TextWidth(what, 12, true) + S(12), y + S(11), tag, tagCol, 8)
    local route = FitText(t.fromName .. " \226\134\146 " .. t.toName, w - S(330), 10)
    Text(route, x + S(82), y + S(34), w, S(20), RGB(COL.muted), 10)
    Text("T-" .. t.id, x + S(82) + TextWidth(route, 10) + S(12), y + S(34), S(80), S(20), RGB(COL.off), 9)

    local bx = x + w - S(12)
    if mode == "done" then
        Chip(bx, y + S(8), L("bt_dispatch.status." .. t.status), STATUS_COLOR[t.status] or COL.off, 8, true)
        Text(L("bt_dispatch.panel.disappears", { s = t.doneIn or 0 }), x, y + S(34), w - S(12), S(20), RGB(COL.off), 9, false, "right")
        return
    end
    Chip(bx, y + S(8), L("bt_dispatch.status." .. t.status), STATUS_COLOR[t.status] or COL.muted, 8, true)
    local routeLabel = L(t.route and "bt_dispatch.panel.route_on" or "bt_dispatch.panel.route")
    local rw = math.max(S(124), TextWidth(routeLabel, 9, true) + S(24))
    rect.route = { bx - rw, y + S(33), rw, S(24) }
    Button(bx - rw, y + S(33), rw, S(24), routeLabel,
        t.route and "good" or "normal", function() send("btd:route", t.id) end, 9)
    if mode == "wait" then
        local canHand = State.nearby and not State.offered
        local handLabel = canHand and L("bt_dispatch.panel.hand_over_to", { unit = State.nearby.unit }) or L("bt_dispatch.panel.hand_over")
        local hw = math.max(S(104), TextWidth(handLabel, 9, true) + S(24))
        rect.hand = { bx - rw - S(6) - hw, y + S(33), hw, S(24) }
        rect.order = { x + S(4), y + S(4), S(26), rh - S(8) }
        Button(bx - rw - S(6) - hw, y + S(33), hw, S(24),
            handLabel,
            canHand and "blue" or "off", function() send("btd:offer", t.id) end, 9)
        Button(x + S(4), y + S(4), S(26), S(26), "\226\150\178", "normal", function() send("btd:move", t.id, -1) end, 8)
        Button(x + S(4), y + rh - S(30), S(26), S(26), "\226\150\188", "normal", function() send("btd:move", t.id, 1) end, 8)
    end
end

local function drawBig()
    local w = S(860)
    local h = math.min(S(760), SH - S(60))
    local x, y = SW - w - S(30), SH - h - S(30)
    Layout.box = { x, y, w, h }
    Round(x, y, w, h, S(10), RGB(COL.bg))
    dxDrawRectangle(x, y, w, S(4), RGB(COL.acc))
    dxDrawRectangle(x, y + S(4), w, S(80), RGB(COL.head))
    Text(L("bt_dispatch.panel.title"), x + S(22), y + S(14), w, S(16), RGB(COL.muted), 9, true)
    Text(State.onDuty and State.unit or L("bt_dispatch.panel.off_duty"), x + S(22), y + S(34), w, S(34), State.onDuty and RGB(COL.text) or RGB(COL.muted), 20, true)
    if State.onDuty then
        local ux = x + S(22) + TextWidth(State.unit or "", 20, true) + S(14)
        local chipW = Chip(ux, y + S(42), L(State.windDown and "bt_dispatch.panel.winding_down" or "bt_dispatch.panel.on_duty"), State.windDown and COL.warn or COL.good, 10)
        local who = (State.name or "") .. "  \194\183  " .. FormatSeconds((State.since or 0) + StateAge())
        Text(who, ux + chipW + S(12), y + S(42), S(300), S(22), RGB(COL.muted), 10)
        local wdLabel = State.windDown and L("bt_dispatch.panel.wind_down_on") or L("bt_dispatch.panel.wind_down_off")
        local soLabel = L("bt_dispatch.panel.sign_off")
        local soW = math.max(S(130), TextWidth(soLabel, 10, true) + S(32))
        local wdW = math.max(S(158), TextWidth(wdLabel, 10, true) + S(32))
        Layout.windDown = { x + w - soW - S(34) - wdW - S(8), y + S(24), wdW, S(34) }
        Layout.signOff = { x + w - soW - S(34), y + S(24), soW, S(34) }
        Button(x + w - soW - S(34) - wdW - S(8), y + S(24), wdW, S(34),
            wdLabel,
            State.windDown and "warn" or "normal", function() send("btd:windDown", not State.windDown) end, 10)
        Button(x + w - soW - S(34), y + S(24), soW, S(34), soLabel, "primary", function() send("btd:signOff") end, 10)
    else
        Layout.signOn = { x + w - S(164), y + S(24), S(130), S(34) }
        Button(x + w - S(164), y + S(24), S(130), S(34), L("bt_dispatch.panel.sign_on"), "primary", function() send("btd:signOn") end, 10)
        Text(L("bt_dispatch.panel.sign_on_hint"), x + S(22), y + S(92), w - S(44), S(40), RGB(COL.muted), 10)
        return
    end
    local keyW = TextWidth(KEY:upper(), 9, true) + S(12)
    Round(x + w - keyW - S(8), y + S(8), keyW, S(18), S(4), RGB(COL.key))
    Text(KEY:upper(), x + w - keyW - S(8), y + S(8), keyW, S(18), tocolor(30, 24, 10), 9, true, "center")

    -- stats
    local c = counts()
    local sy = y + S(96)
    local stats = {
        { L("bt_dispatch.panel.stat_delivered"), tostring(State.delivered or 0), COL.good },
        { L("bt_dispatch.panel.stat_in_transit"), tostring(c.transit), COL.warn },
        { L("bt_dispatch.panel.stat_waiting"), tostring(c.waiting), COL.blue },
        { L("bt_dispatch.panel.stat_pay"), Money(State.pay or 0), COL.text },
    }
    local sw2 = (w - S(44) - S(30)) / 4
    Layout.stats = { x + S(22), sy, w - S(44), S(52) }
    for i, s in ipairs(stats) do
        local sx = x + S(22) + (i - 1) * (sw2 + S(10))
        Round(sx, sy, sw2, S(52), S(6), RGB(COL.tile))
        Text(s[1], sx + S(12), sy + S(6), sw2, S(16), RGB(COL.muted), 8, true)
        Text(s[2], sx + S(12), sy + S(22), sw2, S(26), RGB(s[3]), 15, true)
    end
    local top = sy + S(64)

    -- incoming handover offer
    if offerIn then
        local left = math.max(0, math.ceil((offerIn.till - getTickCount()) / 1000))
        if left <= 0 then offerIn = nil
        else
            Round(x + S(22), top, w - S(44), S(54), S(6), RGB(COL.warn, 30))
            Text(L("bt_dispatch.panel.offer_title", { unit = offerIn.unit, name = offerIn.name }), x + S(36), top + S(6), w, S(20), RGB(COL.warn), 10, true)
            Text(TaskWhat(offerIn) .. "  \194\183  " .. offerIn.fromName .. " \226\134\146 " .. offerIn.toName, x + S(36), top + S(28), w - S(300), S(20), RGB(COL.text), 9)
            local id = offerIn.id
            Button(x + w - S(262), top + S(12), S(90), S(30), L("bt_dispatch.panel.accept"), "good", function() send("btd:answer", id, true) offerIn = nil end, 10)
            Button(x + w - S(162), top + S(12), S(90), S(30), L("bt_dispatch.panel.decline"), "normal", function() send("btd:answer", id, false) offerIn = nil end, 10)
            Text(left .. "s", x + w - S(66), top, S(40), S(54), RGB(COL.muted), 9, true, "center")
            top = top + S(64)
        end
    end

    -- list: sections and rows, scrolled by whole entries
    local entries = {}
    local groups = { transit = {}, wait = {}, done = {} }
    for _, t in ipairs(State.tasks) do
        if t.status == "transit" then groups.transit[#groups.transit + 1] = t
        elseif t.status == "waiting" then groups.wait[#groups.wait + 1] = t
        else groups.done[#groups.done + 1] = t end
    end
    local function section(title, n, mode, list)
        if #list == 0 and mode ~= "wait" and mode ~= "transit" then return end
        entries[#entries + 1] = { kind = "section", title = title, n = #list }
        for _, t in ipairs(list) do entries[#entries + 1] = { kind = "row", t = t, mode = mode } end
        if #list == 0 then entries[#entries + 1] = { kind = "empty" } end
    end
    section(L("bt_dispatch.panel.sec_transit"), 0, "transit", groups.transit)
    section(L("bt_dispatch.panel.sec_waiting"), 0, "wait", groups.wait)
    section(L("bt_dispatch.panel.sec_done"), 0, "done", groups.done)

    local yy, bottom = top, y + h - S(12)
    local first = math.max(1, math.min(scroll + 1, #entries))
    for i = first, #entries do
        local e = entries[i]
        local eh = e.kind == "row" and S(72) or (e.kind == "section" and S(26) or S(34))
        if yy + eh > bottom then break end
        if e.kind == "section" then
            Text(e.title, x + S(22), yy, w, S(20), RGB(COL.muted), 8, true)
            Text(tostring(e.n), x, yy, w - S(22), S(20), RGB(COL.off), 8, true, "right")
        elseif e.kind == "empty" then
            Text(L("bt_dispatch.panel.none"), x + S(22), yy, w, S(26), RGB(COL.off), 10)
        else
            drawRow(x + S(22), yy, w - S(44), e.t, e.mode)
        end
        yy = yy + eh
    end
    if #entries > 0 then PanelMaxScroll = #entries end
    PanelBox = { x, y, w, h }
end

addEventHandler("onClientKey", root, function(key, press)
    if not PanelBig or not press then return end
    if key == "mouse_wheel_down" then scroll = math.min((PanelMaxScroll or 1) - 1, scroll + 1)
    elseif key == "mouse_wheel_up" then scroll = math.max(0, scroll - 1) end
end)

addEventHandler("onClientRender", root, function()
    Layout = { visible = false, big = false, tasks = {} }
    if not (TextsLoaded and HasRight()) then
        if PanelBig then setBig(false) end
        return
    end
    if getElementData(localPlayer, "inventoryOpen") or getElementData(localPlayer, "browserOpen") then
        if PanelBig then setBig(false) end
        return
    end
    if AdminOpen then return end
    Hits = {}
    Layout.visible, Layout.big = true, PanelBig
    if PanelBig then drawBig() else drawSmall() end
end)

-- { visible, big, small, box, signOn, signOff, windDown, stats = rect, tasks = { [id] = { row, route,
-- hand, order = rect, status, routeOn } } } (task ids as strings), rect = { x, y, w, h }; only what the last frame drew
function getPanelLayout()
    return Layout
end
