-- /ermadmin panel: frame, tabs, paged lists (shifts / tasks), input.
-- Detail views (right side) live in client/admin/detail.lua.

Admin = {
    open    = false,
    tab     = "shifts",
    lists   = {
        shifts = { page = 1, search = "", filter = "all", data = nil, loading = false },
        tasks  = { page = 1, search = "", filter = "all", data = nil, loading = false },
    },
    detail  = nil,     -- { kind = "shift"|"task", id, data, loading }
    history = {},      -- previous details for "Back"
    auto    = nil,     -- { available, enabled } of med_erm_auto, nil = not received yet
}

local s = Gfx.s
local W, H = 1180, 700
local LIST_W, ROW_H = 580, 34

local FILTERS = {
    shifts = { { "all", "All" }, { "active", "On duty" }, { "ended", "Ended" } },
    tasks  = { { "all", "All" }, { "open", "Open" }, { "closed", "Closed" } },
}
local PLACEHOLDER = {
    shifts = "Search callsign, crew, plate, type...",
    tasks  = "Search #id, title, zone, caller, unit...",
}

AdminStatusColor = {
    unassigned  = { 229, 72, 77 },
    prioritized = { 255, 197, 61 },
    assigned    = { 46, 160, 67 },
    closed      = { 110, 118, 130 },
}
AdminStatusLabel = {
    unassigned = "Not assigned", prioritized = "Prioritized", assigned = "Assigned", closed = "Closed",
}

function Admin.shortDate(str)
    return (str and str ~= "") and str:sub(6, 16) or "-"
end

---------------------------------------------------------------- data

function Admin.request(kind, params)
    triggerServerEvent("erm:admin:query", resourceRoot, kind, params or {})
end

function Admin.loadList(tab)
    local L = Admin.lists[tab]
    L.loading = true
    Admin.request(tab, { page = L.page, search = L.search, filter = L.filter })
end

function Admin.openDetail(kind, id, push)
    if push ~= false and Admin.detail and not (Admin.detail.kind == kind and Admin.detail.id == id) then
        Admin.history[#Admin.history + 1] = { kind = Admin.detail.kind, id = Admin.detail.id }
    end
    Admin.detail = { kind = kind, id = id, loading = true }
    Gfx.scroll.adminDetail = 0
    Admin.request(kind, { id = id })
end

function Admin.back()
    local prev = table.remove(Admin.history)
    if prev then Admin.openDetail(prev.kind, prev.id, false) end
end

addEvent("erm:admin:result", true)
addEventHandler("erm:admin:result", resourceRoot, function(kind, data)
    if Admin.lists[kind] then
        local L = Admin.lists[kind]
        L.data, L.loading = data, false
        if data and data.page then L.page = data.page end
    elseif Admin.detail and Admin.detail.kind == kind then
        if data and (data.error or data.id == Admin.detail.id) then
            Admin.detail.data, Admin.detail.loading = data, false
        end
    end
end)

addEvent("erm:admin:denied", true)
addEventHandler("erm:admin:denied", resourceRoot, function()
    Admin.close()
    State.notify("ERM Admin", "Access denied.")
end)

addEvent("erm:admin:auto", true)
addEventHandler("erm:admin:auto", resourceRoot, function(state)
    Admin.auto = type(state) == "table" and state or nil
    if Admin.auto then Admin.auto.pending = nil end
end)

local function toggleAuto()
    local a = Admin.auto
    if not a or not a.available or a.pending then return end
    a.pending = true
    triggerServerEvent("erm:admin:autoSet", resourceRoot, not a.enabled)
end

---------------------------------------------------------------- search input

local searchToken

local function editSearch()
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then return end
    searchToken = exports.ui_core:openTextInput("Search " .. Admin.tab, 40, Admin.lists[Admin.tab].search)
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if Admin.open then
        setTimer(function() if Admin.open then showCursor(true) end end, 50, 1)
    end
    if token ~= searchToken then return end
    searchToken = nil
    if text == false then return end
    local L = Admin.lists[Admin.tab]
    L.search = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
    L.page = 1
    Admin.loadList(Admin.tab)
end)

---------------------------------------------------------------- list drawing

local function pill(text, x, y, w, h, color, dark)
    Gfx.round(x, y, w, h, h / 2, Gfx.rgb(color, 60))
    Gfx.text(text, x, y, w, h, dark and tocolor(20, 20, 20) or Gfx.rgb({
        math.min(255, color[1] + 60), math.min(255, color[2] + 60), math.min(255, color[3] + 60) }),
        Gfx.font(8, true), "center")
end
Admin.pill = pill

local SHIFT_COLS = {
    { "#", 0, 46 }, { "UNIT", 46, 124 }, { "STARTED", 170, 110 }, { "DURATION", 280, 84 },
    { "CREW", 364, 56 }, { "TASKS", 420, 56 }, { "STATUS", 476, 104 },
}
local TASK_COLS = {
    { "#", 0, 50 }, { "P", 50, 40 }, { "TITLE", 90, 196 }, { "STATUS", 286, 100 },
    { "ZONE", 386, 110 }, { "CREATED", 496, 84 },
}

local function col(cols, i) return s(cols[i][2]), s(cols[i][3]) end

local function drawShiftRow(r, x, y, w, h)
    local c = SHIFT_COLS
    local cx, cw
    cx, cw = col(c, 1); Gfx.text("#" .. r.id, x + cx, y, cw, h, Theme.faint, Gfx.font(9, true))
    cx, cw = col(c, 2)
    Gfx.text(r.callsign, x + cx, y, cw, h, Theme.text, Gfx.font(10, true))
    local tw = dxGetTextWidth(r.callsign, 1, Gfx.font(10, true))
    Gfx.text(r.type, x + cx + tw + s(6), y, cw - tw, h, Theme.faint, Gfx.font(8, true))
    cx, cw = col(c, 3); Gfx.text(Admin.shortDate(r.startedAt), x + cx, y, cw, h, Theme.dim, Gfx.font(9))
    cx, cw = col(c, 4); Gfx.text(State.formatDuration(r.duration), x + cx, y, cw, h, Theme.dim, Gfx.font(9))
    cx, cw = col(c, 5); Gfx.text(tostring(#r.members), x + cx, y, cw, h, Theme.dim, Gfx.font(9))
    cx, cw = col(c, 6); Gfx.text(tostring(r.tasks), x + cx, y, cw, h, Theme.dim, Gfx.font(9))
    cx, cw = col(c, 7)
    if r.live then
        local st = Config.STATUS[r.live]
        pill(st and st.label or "On duty", x + cx, y + (h - s(18)) / 2, s(92), s(18), st and st.color or { 46, 160, 67 })
    elseif r.endedAt == "" then
        pill("Open", x + cx, y + (h - s(18)) / 2, s(92), s(18), { 120, 120, 120 })
    else
        pill("Ended", x + cx, y + (h - s(18)) / 2, s(92), s(18), { 110, 118, 130 })
    end
end

local function drawTaskRow(r, x, y, w, h)
    local c = TASK_COLS
    local cx, cw
    cx, cw = col(c, 1); Gfx.text("#" .. r.id, x + cx, y, cw, h, Theme.faint, Gfx.font(9, true))
    cx, cw = col(c, 2); Gfx.priorityBadge(x + cx, y + (h - s(18)) / 2, s(30), s(18), r.priority > 0 and r.priority or nil)
    cx, cw = col(c, 3); Gfx.text(Gfx.fit(r.title, cw - s(8), Gfx.font(10)), x + cx, y, cw, h, Theme.text, Gfx.font(10))
    cx, cw = col(c, 4)
    pill(AdminStatusLabel[r.status] or r.status, x + cx, y + (h - s(18)) / 2, s(92), s(18), AdminStatusColor[r.status] or { 110, 118, 130 })
    cx, cw = col(c, 5); Gfx.text(Gfx.fit(r.zone, cw - s(8), Gfx.font(9)), x + cx, y, cw, h, Theme.dim, Gfx.font(9))
    cx, cw = col(c, 6); Gfx.text(Admin.shortDate(r.createdAt), x + cx, y, cw, h, Theme.dim, Gfx.font(9))
end

local function drawList(x, y, w, h)
    local tab = Admin.tab
    local L = Admin.lists[tab]

    -- toolbar: search + filters
    local fw = s(74)
    local sw = w - fw * 3 - s(4) * 2 - s(10)
    local hov = Gfx.hover(x, y, sw, s(34))
    Gfx.round(x, y, sw, s(34), s(6), hov and Theme.panel2 or Theme.panel)
    if L.search ~= "" then
        Gfx.text(Gfx.fit(L.search, sw - s(60), Gfx.font(10)), x + s(12), y, sw - s(60), s(34), Theme.text, Gfx.font(10))
        Gfx.button(x + sw - s(34), y + s(4), s(26), s(26), "×", { color = { 60, 68, 80 } }, function()
            L.search, L.page = "", 1
            Admin.loadList(tab)
        end)
    else
        Gfx.text(PLACEHOLDER[tab], x + s(12), y, sw - s(24), s(34), Theme.faint, Gfx.font(10))
    end
    Gfx.hit(x, y, sw - (L.search ~= "" and s(38) or 0), s(34), editSearch)

    local fx = x + sw + s(10)
    for i, f in ipairs(FILTERS[tab]) do
        local active = L.filter == f[1]
        Gfx.button(fx + (i - 1) * (fw + s(4)), y, fw, s(34), f[2], {
            color = active and { 224, 60, 49 } or { 39, 46, 55 },
            textColor = active and Theme.text or Theme.dim,
            font = Gfx.font(9, true),
        }, function()
            if L.filter ~= f[1] then
                L.filter, L.page = f[1], 1
                Admin.loadList(tab)
            end
        end)
    end

    -- table
    local ty = y + s(46)
    local cols = tab == "shifts" and SHIFT_COLS or TASK_COLS
    for _, c in ipairs(cols) do
        Gfx.text(c[1], x + s(10) + s(c[2]), ty, s(c[3]), s(20), Theme.faint, Gfx.font(8, true))
    end
    dxDrawRectangle(x, ty + s(22), w, 1, Theme.line)

    local ry = ty + s(28)
    local data = L.data
    if not data then
        Gfx.text("Loading...", x, ry, w, s(ROW_H) * 3, Theme.faint, Gfx.font(10), "center")
    elseif #(data.list or {}) == 0 then
        Gfx.text("No results.", x, ry, w, s(ROW_H) * 3, Theme.faint, Gfx.font(10), "center")
    else
        local selKind = tab == "shifts" and "shift" or "task"
        for i, r in ipairs(data.list) do
            local rowY = ry + (i - 1) * s(ROW_H)
            local selected = Admin.detail and Admin.detail.kind == selKind and Admin.detail.id == r.id
            local rhov = Gfx.hover(x, rowY, w, s(ROW_H) - s(2))
            if selected then
                Gfx.round(x, rowY, w, s(ROW_H) - s(2), s(5), tocolor(224, 60, 49, 70))
            elseif rhov then
                Gfx.round(x, rowY, w, s(ROW_H) - s(2), s(5), Theme.panel2)
            elseif i % 2 == 0 then
                Gfx.round(x, rowY, w, s(ROW_H) - s(2), s(5), tocolor(255, 255, 255, 5))
            end
            if tab == "shifts" then
                drawShiftRow(r, x + s(10), rowY, w - s(20), s(ROW_H) - s(2))
            else
                drawTaskRow(r, x + s(10), rowY, w - s(20), s(ROW_H) - s(2))
            end
            Gfx.hit(x, rowY, w, s(ROW_H) - s(2), function()
                Admin.history = {}
                Admin.openDetail(selKind, r.id, false)
            end)
        end
    end

    -- pager
    local py = y + h - s(36)
    dxDrawRectangle(x, py - s(8), w, 1, Theme.line)
    local page, pages, total = L.page, data and data.pages or 1, data and data.total or 0
    Gfx.button(x, py, s(96), s(32), "‹  Prev", { disabled = page <= 1 }, function()
        L.page = page - 1
        Admin.loadList(tab)
    end)
    Gfx.text(string.format("Page %d / %d   ·   %d result%s%s", page, pages, total, total == 1 and "" or "s",
        L.loading and "   ·   loading..." or ""), x, py, w, s(32), Theme.dim, Gfx.font(9), "center")
    Gfx.button(x + w - s(96), py, s(96), s(32), "Next  ›", { disabled = page >= pages }, function()
        L.page = page + 1
        Admin.loadList(tab)
    end)
end

---------------------------------------------------------------- frame

local function render()
    Gfx.hits, Gfx.scrollAreas = {}, {}
    Gfx.blockHover = false

    local sw, sh = Gfx.screenW, Gfx.screenH
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 150))

    local w, h = s(W), s(H)
    local x, y = (sw - w) / 2, (sh - h) / 2
    Gfx.round(x - 1, y - 1, w + 2, h + 2, s(12), Theme.edge)
    Gfx.round(x, y, w, h, s(12), Theme.bg)
    Gfx.hit(x, y, w, h, function() end)

    -- header
    local hh = s(58)
    Gfx.round(x, y, w, hh, s(12), Theme.header)
    dxDrawRectangle(x, y + hh - s(12), w, s(12), Theme.header)
    dxDrawRectangle(x, y + hh - 1, w, 1, Theme.line)
    local ls = s(30)
    Gfx.round(x + s(16), y + (hh - ls) / 2, ls, ls, s(6), Theme.accent)
    Gfx.cross(x + s(16) + s(7), y + (hh - ls) / 2 + s(7), ls - s(14), tocolor(255, 255, 255))
    Gfx.text("ERM Admin", x + s(58), y + s(9), s(200), s(22), Theme.text, Gfx.font(14, true))
    Gfx.text("Shift & task history", x + s(58), y + s(30), s(200), s(18), Theme.dim, Gfx.font(9))

    local tabs = { { "shifts", "Shifts" }, { "tasks", "Tasks" } }
    for i, t in ipairs(tabs) do
        local active = Admin.tab == t[1]
        Gfx.button(x + s(280) + (i - 1) * s(118), y + s(12), s(110), s(34), t[2], {
            color = active and { 224, 60, 49 } or { 30, 36, 43 },
            textColor = active and Theme.text or Theme.dim,
        }, function()
            if Admin.tab ~= t[1] then
                Admin.tab = t[1]
                if not Admin.lists[t[1]].data then Admin.loadList(t[1]) end
            end
        end)
    end

    -- auto dispatch switch (med_erm_auto)
    local a = Admin.auto
    local aw = s(210)
    local ax = x + w - s(52) - s(10) - aw
    local label, color = "Auto dispatch: ...", { 48, 56, 66 }
    if a and not a.available then
        label = "Auto dispatch: N/A"
    elseif a then
        label = a.enabled and "Auto dispatch: ON" or "Auto dispatch: OFF"
        color = a.enabled and { 46, 160, 67 } or { 60, 68, 80 }
    end
    Gfx.button(ax, y + s(12), aw, s(34), label, {
        color = color,
        disabled = not a or not a.available or a.pending,
        font = Gfx.font(10, true),
    }, toggleAuto)

    Gfx.button(x + w - s(52), y + s(12), s(36), s(34), "×", { color = { 30, 36, 43 }, font = Gfx.font(14, true) }, Admin.close)

    -- body
    local by, bh = y + hh + s(14), h - hh - s(28)
    local lw = s(LIST_W)
    drawList(x + s(16), by, lw, bh)

    local dx = x + s(16) + lw + s(16)
    AdminDetail.draw(dx, by, x + w - s(16) - dx, bh)
end

local function onClick(button, state, ax, ay)
    if button ~= "left" or state ~= "down" then return end
    if getElementData(localPlayer, "textInputOpen") then return end
    Gfx.click(ax, ay)
end

local function onKey(key, press)
    if not press then return end
    if key == "mouse_wheel_up" then
        Gfx.wheel(-1)
    elseif key == "mouse_wheel_down" then
        Gfx.wheel(1)
    elseif key == "backspace" and not getElementData(localPlayer, "textInputOpen") then
        Admin.back()
    end
end

function Admin.show()
    if Admin.open then return end
    if Tablet.open then Tablet.close() end
    Admin.open = true
    showCursor(true)
    addEventHandler("onClientRender", root, render)
    addEventHandler("onClientClick", root, onClick)
    addEventHandler("onClientKey", root, onKey)
    Admin.loadList(Admin.tab)
    triggerServerEvent("erm:admin:autoGet", resourceRoot)
    if Admin.detail then Admin.openDetail(Admin.detail.kind, Admin.detail.id, false) end
end

function Admin.close()
    if not Admin.open then return end
    Admin.open = false
    removeEventHandler("onClientRender", root, render)
    removeEventHandler("onClientClick", root, onClick)
    removeEventHandler("onClientKey", root, onKey)
    if not getElementData(localPlayer, "textInputOpen") then showCursor(false) end
end

addEvent("erm:admin:open", true)
addEventHandler("erm:admin:open", resourceRoot, function()
    if Admin.open then Admin.close() else Admin.show() end
end)
