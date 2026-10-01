-- /ermadmin detail pane: shift and task views.
--
-- A view is built as a list of fixed-height items ({ h, draw, click }) every
-- frame and scrolled in steps; only items fully inside the pane are drawn.

AdminDetail = {}

local s = Gfx.s
local STEP = 40

local items
local function add(h, draw, click)
    items[#items + 1] = { h = s(h), draw = draw, click = click }
end

---------------------------------------------------------------- building blocks

local function gap(h) add(h, function() end) end

local function section(label)
    add(34, function(x, y, w, h)
        Gfx.text(label, x, y + s(10), w, s(20), Theme.faint, Gfx.font(8, true))
        dxDrawRectangle(x, y + h - s(2), w, 1, Theme.line)
    end)
end

-- pairs: { {label, value}, ... } in two columns
local function kvGrid(pairs)
    for i = 1, #pairs, 2 do
        local a, b = pairs[i], pairs[i + 1]
        add(44, function(x, y, w, h)
            local cw = (w - s(16)) / 2
            for j, kv in ipairs({ a, b }) do
                if kv then
                    local cx = x + (j - 1) * (cw + s(16))
                    Gfx.text(kv[1], cx, y + s(4), cw, s(16), Theme.faint, Gfx.font(8, true))
                    Gfx.text(Gfx.fit(kv[2] ~= "" and kv[2] or "-", cw, Gfx.font(10, true)), cx, y + s(20), cw, s(20),
                        kv[3] or Theme.text, Gfx.font(10, true))
                end
            end
        end)
    end
end

local function paragraph(text, width, color)
    local font = Gfx.font(10)
    for _, line in ipairs(Gfx.wrap(text, width, font)) do
        add(20, function(x, y, w, h)
            Gfx.text(line, x, y, w, h, color or Theme.text, font)
        end)
    end
end

local function note(text)
    add(30, function(x, y, w, h)
        Gfx.text(text, x, y, w, h, Theme.faint, Gfx.font(9))
    end)
end

-- Clickable two-line row.
local function linkRow(line1, line2, click, badge)
    add(48, function(x, y, w, h, hov)
        Gfx.round(x, y + s(2), w, h - s(4), s(6), hov and Theme.panel2 or tocolor(255, 255, 255, 6))
        local tx = x + s(12)
        if badge then
            Gfx.priorityBadge(tx, y + s(8), s(30), s(18), badge > 0 and badge or nil)
            tx = tx + s(40)
        end
        Gfx.text(Gfx.fit(line1, x + w - tx - s(40), Gfx.font(10, true)), tx, y + s(6), x + w - tx - s(40), s(20), Theme.text, Gfx.font(10, true))
        Gfx.text(Gfx.fit(line2, w - s(64), Gfx.font(9)), x + s(12), y + s(26), w - s(64), s(18), Theme.dim, Gfx.font(9))
        if click then Gfx.text("›", x, y, w - s(14), h, Theme.faint, Gfx.font(14, true), "right") end
    end, click)
end

local function header(title, sub, pillText, pillColor, badge)
    add(62, function(x, y, w, h)
        local tx = x
        if badge ~= nil then
            Gfx.priorityBadge(x, y + s(8), s(40), s(26), badge > 0 and badge or nil)
            tx = x + s(52)
        end
        local pw = pillText and s(110) or 0
        Gfx.text(Gfx.fit(title, x + w - tx - pw - s(10), Gfx.font(15, true)), tx, y + s(4), x + w - tx - pw, s(32), Theme.text, Gfx.font(15, true))
        Gfx.text(sub, x, y + s(38), w, s(18), Theme.dim, Gfx.font(9))
        if pillText then Admin.pill(pillText, x + w - s(104), y + s(10), s(104), s(22), pillColor) end
    end)
end

---------------------------------------------------------------- shift view

local function buildShift(d)
    local live = d.live
    local pillText, pillColor = "Ended", { 110, 118, 130 }
    if live then
        local st = Config.STATUS[live.status]
        pillText, pillColor = "On duty · " .. (st and st.label or live.status), st and st.color or { 46, 160, 67 }
    end
    header(d.callsign .. "  ·  " .. d.type, string.format("Shift #%d   ·   Plate %s", d.id, d.plate ~= "" and d.plate or "-"),
        pillText, pillColor)
    gap(6)
    kvGrid({
        { "STARTED", d.startedAt },
        { "ENDED", d.endedAt ~= "" and d.endedAt or (live and "still on duty" or "-") },
        { "DURATION", State.formatDuration(d.duration) },
        { "CLOSED TASKS", tostring(d.closed) },
    })
    if live and live.task and live.task > 0 then
        kvGrid({ { "CURRENT TASK", "#" .. live.task } })
    end

    section(string.format("CREW (%d)", #d.members))
    if #d.members == 0 then note("No members recorded.") end
    for _, name in ipairs(d.members) do
        add(26, function(x, y, w, h)
            dxDrawCircle(x + s(6), y + h / 2, s(3), 0, 360, Theme.accent, Theme.accent, 10)
            Gfx.text(name, x + s(18), y, w - s(18), h, Theme.text, Gfx.font(10))
        end)
    end

    section(string.format("TASKS IN THIS SHIFT (%d)", #d.tasks))
    if #d.tasks == 0 then note("The unit did not work on any task.") end
    for _, t in ipairs(d.tasks) do
        local times = (t.assignedAt ~= "" and Admin.shortDate(t.assignedAt) or "?") .. "  →  "
            .. (t.releasedAt ~= "" and Admin.shortDate(t.releasedAt) or "now")
        local line2 = string.format("%s   ·   %s   ·   %s", times, t.outcome ~= "" and t.outcome or "-",
            AdminStatusLabel[t.status] or t.status)
        linkRow(string.format("#%d  %s", t.id, t.title), line2, function() Admin.openDetail("task", t.id) end, t.priority)
    end
end

---------------------------------------------------------------- task view

local function buildTask(d, width)
    header(string.format("#%d  %s", d.id, d.title), d.zone,
        AdminStatusLabel[d.status] or d.status, AdminStatusColor[d.status] or { 110, 118, 130 }, d.priority)
    gap(6)
    kvGrid({
        { "CALLER", d.caller },
        { "SOURCE", d.source ~= "" and d.source or "Web / dispatcher" },
        { "POSITION", string.format("%.1f, %.1f, %.1f", d.x, d.y, d.z) },
        { "PRIORITY", d.priority > 0 and ("P" .. d.priority) or "not set" },
    })

    section("TIMELINE")
    kvGrid({
        { "CREATED", d.createdAt },
        { "PRIORITIZED", d.prioritizedAt },
        { "FIRST ASSIGNED", d.assignedAt },
        { "CLOSED", d.closedAt },
    })
    if d.closeReason ~= "" then kvGrid({ { "CLOSE REASON", d.closeReason } }) end

    section("DESCRIPTION")
    if d.description ~= "" then paragraph(d.description, width) else note("No description.") end

    section(string.format("UNITS (%d)", #d.links))
    if #d.links == 0 then
        if #d.unitLog > 0 then
            paragraph(table.concat(d.unitLog, ", "), width, Theme.dim)
        else
            note("No unit was assigned.")
        end
    end
    for _, l in ipairs(d.links) do
        local line2 = string.format("Shift #%d   ·   %s  →  %s   ·   %s", l.shift,
            Admin.shortDate(l.assignedAt), l.releasedAt ~= "" and Admin.shortDate(l.releasedAt) or "now",
            l.outcome ~= "" and l.outcome or "-")
        linkRow(l.callsign .. (l.type ~= "" and ("  ·  " .. l.type) or ""), line2, function()
            Admin.openDetail("shift", l.shift)
        end)
    end

    section(string.format("LIGHTS & SIREN   ·   total %s", State.formatDuration(d.responseTotal)))
    if #d.responseLog == 0 then note("Not used.") end
    for _, e in ipairs(d.responseLog) do
        add(26, function(x, y, w, h)
            Gfx.text(e.unit, x, y, s(90), h, Theme.text, Gfx.font(10, true))
            Gfx.text(Admin.shortDate(e.start) .. "  →  " .. (e.stop ~= "" and Admin.shortDate(e.stop) or "active"),
                x + s(90), y, w - s(170), h, Theme.dim, Gfx.font(9))
            Gfx.text(State.formatDuration(e.duration), x, y, w, h, Gfx.rgb(Config.STATUS.enroute.color), Gfx.font(10, true), "right")
        end)
    end

    if d.meta ~= "" then
        section("META (automation data)")
        paragraph(d.meta, width, Theme.dim)
    end
end

---------------------------------------------------------------- pane

function AdminDetail.draw(x, y, w, h)
    Gfx.round(x, y, w, h, s(10), Theme.panel)
    local det = Admin.detail
    if not det then
        Gfx.text("Select a shift or a task to see its details.", x, y, w, h, Theme.faint, Gfx.font(10), "center")
        return
    end

    -- top bar
    local pad = s(18)
    local barH = s(40)
    if #Admin.history > 0 then
        Gfx.button(x + pad, y + s(10), s(84), s(28), "‹  Back", { font = Gfx.font(9, true) }, Admin.back)
    end
    Gfx.text(det.kind == "shift" and "SHIFT DETAILS" or "TASK DETAILS", x, y + s(10), w - pad, s(28),
        Theme.faint, Gfx.font(8, true), "right")

    local ax, ay, aw, ah = x + pad, y + barH + s(8), w - pad * 2, h - barH - s(16)
    if det.loading or not det.data then
        Gfx.text("Loading...", ax, ay, aw, ah, Theme.faint, Gfx.font(10), "center")
        return
    end
    if det.data.error then
        Gfx.text(det.data.error, ax, ay, aw, ah, Theme.faint, Gfx.font(10), "center")
        return
    end

    items = {}
    if det.kind == "shift" then buildShift(det.data) else buildTask(det.data, aw) end

    local total = 0
    for _, it in ipairs(items) do total = total + it.h end
    local maxSteps = math.max(0, math.ceil((total - ah) / s(STEP)))
    local offset = Gfx.getScroll("adminDetail", maxSteps) * s(STEP)
    Gfx.scrollArea("adminDetail", x, y, w, h)

    local cy = ay - offset
    for _, it in ipairs(items) do
        if cy >= ay - 1 and cy + it.h <= ay + ah + 1 then
            local hov = it.click and Gfx.hover(ax, cy, aw, it.h)
            it.draw(ax, cy, aw, it.h, hov)
            if it.click then Gfx.hit(ax, cy, aw, it.h, it.click) end
        end
        cy = cy + it.h
    end

    -- scrollbar
    if maxSteps > 0 then
        local trackH = ah
        local thumbH = math.max(s(30), trackH * ah / total)
        local thumbY = ay + (trackH - thumbH) * (offset / (maxSteps * s(STEP)))
        dxDrawRectangle(x + w - s(8), ay, s(3), trackH, Theme.panel2)
        dxDrawRectangle(x + w - s(8), thumbY, s(3), thumbH, Theme.line)
    end
end
