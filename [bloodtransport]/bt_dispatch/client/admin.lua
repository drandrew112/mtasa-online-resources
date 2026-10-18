if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- /btadmin: shift and task history for admins (queries: server/admin.lua, the level is re-checked there).
-- Same layout as /ermadmin: tabs, a paged list on the left, details on the right.

AdminOpen = false
local tab = "shifts"
local lists = {
    shifts = { page = 1, search = "", filter = "all", data = nil },
    tasks = { page = 1, search = "", filter = "all", data = nil },
}
local detail, history = nil, {}
local ROW = 34

local function request(kind, params)
    triggerServerEvent("btd:admin:query", resourceRoot, kind, params or {})
end

local function loadList(t)
    local l = lists[t]
    request(t, { page = l.page, search = l.search, filter = l.filter })
end

local renderAdmin -- onClientRender handler, attached only while the window is open

local function open()
    AdminOpen = true
    addEventHandler("onClientRender", root, renderAdmin)
    showCursor(true)
    loadList(tab)
end

local function close()
    AdminOpen = false
    removeEventHandler("onClientRender", root, renderAdmin)
    detail, history = nil, {}
    showCursor(false)
end

addEvent("btd:admin:toggle", true)
addEventHandler("btd:admin:toggle", resourceRoot, function()
    if not TextsLoaded then return end
    if AdminOpen then close() else open() end
end)

addEvent("btd:admin:result", true)
addEventHandler("btd:admin:result", resourceRoot, function(kind, data)
    if kind == "shifts" or kind == "tasks" then
        lists[kind].data = data
    else
        if data and data.error then return end
        detail = { kind = kind, data = data }
    end
end)

local function showDetail(kind, id)
    if detail then history[#history + 1] = detail end
    detail = nil
    request(kind, { id = id })
end

local function back()
    detail = table.remove(history)
end

---------------------------------------------------------------- search

local searchToken
local function editSearch()
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then return end
    searchToken = exports.ui_core:openTextInput(L("bt_dispatch.admin.search"), 40, lists[tab].search)
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if AdminOpen then setTimer(function() if AdminOpen then showCursor(true) end end, 50, 1) end
    if token ~= searchToken then return end
    searchToken = nil
    if text == false then return end
    local l = lists[tab]
    l.search = (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
    l.page = 1
    loadList(tab)
end)

---------------------------------------------------------------- drawing

local function shortDate(s) return (s and s ~= "") and s:sub(6, 16) or "-" end
local function hm(sec)
    sec = tonumber(sec) or 0
    return ("%02d:%02d"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60)
end

local function whatOf(t)
    local key
    if t.type == "lab_sample" then key = "bt_dispatch.what.lab_sample"
    elseif t.type == "urgent_medicine" then key = "bt_dispatch.what.urgent_medicine"
    else key = "bt_dispatch.what." .. tostring(t.product) end
    local s = L(key)
    if t.group and t.group ~= "" then s = s .. " " .. t.group end
    return s .. "  \195\151" .. tostring(t.units or 1)
end

local function statusChip(x, y, status, right)
    return Chip(x, y, L("bt_dispatch.status." .. status), STATUS_COLOR[status] or COL.off, 8, right)
end

local function kv(x, y, w, key, value)
    Text(key, x, y, S(110), S(22), RGB(COL.muted), 9)
    Text(FitText(tostring(value), w - S(120), 9, true), x + S(110), y, w - S(110), S(22), RGB(COL.text), 9, true)
end

local function drawShiftDetail(x, y, w, d)
    Text(L("bt_dispatch.admin.shift_title", { id = d.id, unit = d.unit }), x + S(18), y + S(10), w, S(30), RGB(COL.text), 14, true)
    local live = d.live
    Chip(x + w - S(18), y + S(16), live and L("bt_dispatch.admin.live") or L("bt_dispatch.admin.ended"), live and COL.good or COL.off, 9, true)
    local rows = {
        { L("bt_dispatch.admin.driver"), d.player .. " (" .. d.account .. ")" },
        { L("bt_dispatch.admin.started"), d.startedAt },
        { L("bt_dispatch.admin.ended_at"), d.endedAt ~= "" and (d.endedAt .. "  \194\183  " .. L("bt_dispatch.reason." .. (d.reason ~= "" and d.reason or "off"))) or "-" },
        { L("bt_dispatch.admin.duration"), hm(d.duration) },
        { L("bt_dispatch.admin.counts"), L("bt_dispatch.admin.counts_value", { delivered = d.delivered, transit = d.inTransit, cancelled = d.cancelled }) },
        { L("bt_dispatch.admin.pay"), Money(d.pay) },
    }
    for i, r in ipairs(rows) do kv(x + S(18), y + S(48) + (i - 1) * S(24), w - S(36), r[1], r[2]) end
    local ty = y + S(48) + #rows * S(24) + S(12)
    Text(L("bt_dispatch.admin.tasks_log"), x + S(18), ty, w, S(18), RGB(COL.muted), 8, true)
    ty = ty + S(22)
    for i, t in ipairs(d.tasks) do
        if ty + S(32) > y + S(470) then break end
        Round(x + S(14), ty, w - S(28), S(30), S(4), RGB(COL.tile2))
        Text("T-" .. t.id, x + S(24), ty, S(70), S(30), RGB(COL.text), 9, true)
        Text(FitText(whatOf(t), w - S(280), 9), x + S(90), ty, w - S(280), S(30), RGB(COL.text), 9)
        local oc = t.outcome ~= "" and t.outcome or t.status
        statusChip(x + w - S(24), ty + S(6), oc == "handed_over" and "cancelled" or oc, true)
        Hit(x + S(14), ty, w - S(28), S(30), function() showDetail("task", t.id) end)
        ty = ty + S(36)
    end
end

local function drawTaskDetail(x, y, w, d)
    Text("T-" .. d.id .. "  " .. whatOf(d), x + S(18), y + S(10), w - S(120), S(30), RGB(COL.text), 14, true)
    statusChip(x + w - S(18), y + S(16), d.status, true)
    local rows = {
        { L("bt_dispatch.admin.from"), d.fromName }, { L("bt_dispatch.admin.to"), d.toName },
        { L("bt_dispatch.admin.type"), L("bt_dispatch.type." .. d.type) .. (d.urgency ~= "" and ("  \194\183  " .. L("bt_dispatch.urgency." .. d.urgency)) or "") },
        { L("bt_dispatch.admin.source"), d.source }, { L("bt_dispatch.admin.created"), d.createdAt },
    }
    for i, r in ipairs(rows) do kv(x + S(18), y + S(48) + (i - 1) * S(24), w - S(36), r[1], r[2]) end
    local ty = y + S(48) + #rows * S(24) + S(10)
    Text(L("bt_dispatch.admin.history"), x + S(18), ty, w, S(18), RGB(COL.muted), 8, true)
    ty = ty + S(20)
    for _, l in ipairs(d.log) do
        if ty > y + S(380) then break end
        Text(shortDate(l.at):sub(7), x + S(18), ty, S(60), S(20), RGB(COL.muted), 9)
        local ev = L("bt_dispatch.event." .. l.event)
        Text(ev .. (l.info ~= "" and ("  " .. l.info) or ""), x + S(84), ty, w - S(100), S(20), RGB(COL.text), 9)
        ty = ty + S(21)
    end
    ty = math.max(ty + S(8), y + S(300))
    Text(L("bt_dispatch.admin.given_to"), x + S(18), ty, w, S(18), RGB(COL.muted), 8, true)
    ty = ty + S(20)
    for _, s in ipairs(d.shifts) do
        if ty > y + S(480) then break end
        Round(x + S(14), ty, w - S(28), S(28), S(4), RGB(COL.tile2))
        Text(s.unit .. "  \194\183  " .. s.player, x + S(24), ty, w - S(160), S(28), RGB(COL.text), 9)
        Text(s.outcome ~= "" and s.outcome or "-", x, ty, w - S(24), S(28), RGB(COL.muted), 9, false, "right")
        local sid = s.shiftId
        Hit(x + S(14), ty, w - S(28), S(28), function() showDetail("shift", sid) end)
        ty = ty + S(32)
    end
end

local function drawAdmin()
    Hits = {}
    local W, H = S(1180), S(700)
    local x, y = (SW - W) / 2, (SH - H) / 2
    Round(x, y, W, H, S(10), tocolor(16, 18, 24, 245))
    dxDrawRectangle(x, y, W, S(5), RGB(COL.acc))
    dxDrawRectangle(x, y + S(5), W, S(55), RGB(COL.head))
    Text(L("bt_dispatch.admin.title"), x + S(22), y + S(5), S(300), S(55), RGB(COL.text), 15, true)
    Button(x + S(330), y + S(16), S(100), S(30), L("bt_dispatch.admin.tab_shifts"), tab == "shifts" and "primary" or "normal",
        function() tab, detail, history = "shifts", nil, {} loadList(tab) end, 10)
    Button(x + S(440), y + S(16), S(100), S(30), L("bt_dispatch.admin.tab_tasks"), tab == "tasks" and "primary" or "normal",
        function() tab, detail, history = "tasks", nil, {} loadList(tab) end, 10)
    Button(x + W - S(70), y + S(16), S(54), S(30), "ESC", "normal", close, 9)
    local inst = lists[tab].data and lists[tab].data.instance
    if inst then Text(FitText(inst, S(300), 10), x + W - S(390), y + S(5), S(310), S(55), RGB(COL.muted), 10, true, "right") end

    local l = lists[tab]
    local lw = S(580)
    local sy = y + S(72)
    Round(x + S(16), sy, lw - S(250), S(40), S(6), RGB(COL.tile))
    Text(l.search ~= "" and FitText(l.search, lw - S(290), 10) or L("bt_dispatch.admin.search_hint"), x + S(28), sy, lw - S(270), S(40),
        l.search ~= "" and RGB(COL.text) or RGB(COL.off), 10)
    Hit(x + S(16), sy, lw - S(250), S(40), editSearch)
    local filters = tab == "shifts" and { { "all", "bt_dispatch.admin.f_all" }, { "active", "bt_dispatch.admin.f_active" }, { "ended", "bt_dispatch.admin.f_ended" } }
        or { { "all", "bt_dispatch.admin.f_all" }, { "open", "bt_dispatch.admin.f_open" }, { "closed", "bt_dispatch.admin.f_closed" } }
    for i, f in ipairs(filters) do
        Button(x + S(16) + lw - S(240) + (i - 1) * S(80), sy + S(6), S(74), S(28), L(f[2]), l.filter == f[1] and "primary" or "normal",
            function() l.filter, l.page = f[1], 1 loadList(tab) end, 9)
    end

    local ty = sy + S(52)
    local cols = tab == "shifts"
        and { { 14, "bt_dispatch.admin.c_unit" }, { 112, "bt_dispatch.admin.c_driver" }, { 272, "bt_dispatch.admin.c_started" }, { 382, "bt_dispatch.admin.c_time" }, { 452, "bt_dispatch.admin.c_tasks" } }
        or { { 14, "bt_dispatch.admin.c_id" }, { 74, "bt_dispatch.admin.c_cargo" }, { 214, "bt_dispatch.admin.c_route" }, { 424, "bt_dispatch.admin.c_unit" } }
    for _, c in ipairs(cols) do Text(L(c[2]), x + S(16) + S(c[1]), ty, S(120), S(16), RGB(COL.muted), 8, true) end
    ty = ty + S(20)
    if l.data then
        for _, r in ipairs(l.data.list) do
            local sel = detail and ((tab == "shifts" and detail.kind == "shift" and detail.data.id == r.id) or (tab == "tasks" and detail.kind == "task" and detail.data.id == r.id))
            Round(x + S(16), ty, lw, S(ROW), S(4), RGB(sel and COL.tile2 or COL.tile))
            local rx = x + S(16)
            if tab == "shifts" then
                Text(r.unit, rx + S(14), ty, S(100), S(ROW), RGB(COL.text), 10, true)
                Text(FitText(r.player, S(150), 10), rx + S(112), ty, S(160), S(ROW), RGB(COL.text), 10)
                Text(shortDate(r.startedAt), rx + S(272), ty, S(110), S(ROW), RGB(COL.muted), 9)
                Text(hm(r.duration), rx + S(382), ty, S(70), S(ROW), RGB(COL.muted), 9)
                Text(r.delivered .. " / " .. r.tasks, rx + S(452), ty, S(70), S(ROW), RGB(COL.text), 9)
                Chip(rx + lw - S(10), ty + S(8), r.live and L("bt_dispatch.admin.live") or L("bt_dispatch.admin.ended"), r.live and COL.good or COL.off, 8, true)
                local id = r.id
                Hit(rx, ty, lw, S(ROW), function() history, detail = {}, nil showDetail("shift", id) end)
            else
                Text("T-" .. r.id, rx + S(14), ty, S(60), S(ROW), RGB(COL.text), 10, true)
                Text(FitText(whatOf(r), S(135), 9), rx + S(74), ty, S(140), S(ROW), RGB(COL.text), 9)
                Text(FitText(r.fromName .. " \226\134\146 " .. r.toName, S(200), 8), rx + S(214), ty, S(205), S(ROW), RGB(COL.muted), 8)
                Text(r.unit, rx + S(424), ty, S(80), S(ROW), RGB(COL.muted), 9)
                statusChip(rx + lw - S(10), ty + S(8), r.status, true)
                local id = r.id
                Hit(rx, ty, lw, S(ROW), function() history, detail = {}, nil showDetail("task", id) end)
            end
            ty = ty + S(ROW + 4)
        end
        local by = y + H - S(46)
        Button(x + S(16), by, S(70), S(30), L("bt_dispatch.admin.prev"), l.data.page > 1 and "normal" or "off", function() l.page = l.page - 1 loadList(tab) end, 10)
        Button(x + S(16) + lw - S(70), by, S(70), S(30), L("bt_dispatch.admin.next"), l.data.page < l.data.pages and "normal" or "off", function() l.page = l.page + 1 loadList(tab) end, 10)
        Text(L("bt_dispatch.admin.page", { page = l.data.page, pages = l.data.pages, total = l.data.total }), x + S(16), by, lw, S(30), RGB(COL.muted), 9, false, "center")
    else
        Text(L("bt_dispatch.admin.loading"), x + S(16), ty, lw, S(30), RGB(COL.muted), 10)
    end

    -- detail
    local dx = x + S(16) + lw + S(14)
    local dw = W - lw - S(46)
    Round(dx, sy, dw, H - S(88), S(8), RGB(COL.tile))
    if #history > 0 then Button(dx + dw - S(150), sy + S(44), S(70), S(24), "\226\128\185 " .. L("bt_dispatch.admin.back"), "normal", back, 9) end
    if detail then
        if detail.kind == "shift" then drawShiftDetail(dx, sy, dw, detail.data) else drawTaskDetail(dx, sy, dw, detail.data) end
    else
        Text(L("bt_dispatch.admin.pick"), dx + S(18), sy + S(18), dw - S(36), S(30), RGB(COL.muted), 10)
    end
end

renderAdmin = function()
    if TextsLoaded then drawAdmin() end
end

addEventHandler("onClientClick", root, function(button, state)
    if not AdminOpen or button ~= "left" or state ~= "down" then return end
    local cx, cy = getCursorPosition()
    if not cx then return end
    cx, cy = cx * SW, cy * SH
    for i = #Hits, 1, -1 do
        local h = Hits[i]
        if InBox(cx, cy, h.x, h.y, h.w, h.h) then h.fn() return end
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if AdminOpen and press and key == "escape" then
        cancelEvent()
        close()
    end
end)
