if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Home: shift summary, active case, cases closed during this shift.

local s = Gfx.s

Pages.home = {}

-- Requests picker (drawn by the tablet over the page while Tablet.picker is set): for now only the break.
local function drawRequestsPicker(sx, sy, sw, sh)
    local u = State.unit
    if not u then Tablet.picker = nil return end
    Gfx.hit(0, 0, Gfx.screenW, Gfx.screenH, function() end)
    Gfx.round(sx, sy, sw, sh, s(8), Theme.shade)

    local w, h = s(420), s(212)
    local x, y = sx + (sw - w) / 2, sy + (sh - h) / 2
    Gfx.round(x, y, w, h, s(10), Theme.panel)
    Gfx.text(L("med_erm.break.title"), x + s(20), y + s(16), w - s(40), s(26), Theme.text, Gfx.font(13, true))
    Gfx.text(L("med_erm.break.picker_text"), x + s(20), y + s(46), w - s(40), s(40), Theme.dim, Gfx.font(10), "left", "top", true)

    local nowT = State.serverNow()
    local label, color, disabled, action = L("med_erm.break.opt_break"), Config.STATUS["break"].color, false, "erm:requestBreak"
    if u.status == "break" then
        label = L("med_erm.break.opt_end", { minutes = math.max(1, math.ceil((u.breakEnds - nowT) / 60)) })
        action = "erm:endBreak"
    elseif u.breakRequest then
        label, action = L("med_erm.break.opt_pending"), "erm:cancelBreak"
    elseif (u.breakNext or 0) > nowT then
        label = L("med_erm.break.opt_wait", { minutes = math.max(1, math.ceil((u.breakNext - nowT) / 60)) })
        disabled = true
    elseif u.status ~= "available" then
        disabled = true
    end
    Gfx.button(x + s(20), y + s(92), w - s(40), s(48), label,
        { color = color, disabled = disabled or TabletTutorial.active, font = Gfx.font(10, true) },
        function()
            Tablet.picker = nil
            Tablet.send(action)
        end)
    Gfx.button(x + s(20), y + h - s(54), w - s(40), s(38), L("common.cancel"), {}, function() Tablet.picker = nil end)
end

function Pages.home.draw(x, y, w, h)
    local u, t = State.unit, State.task
    local pad = s(18)
    local ix, iw = x + pad, w - pad * 2
    local cy = y + s(14)

    Gfx.text(L("med_erm.home.home"), ix, cy, iw, s(26), Theme.text, Gfx.font(15, true))
    Gfx.button(ix + iw - s(120), cy - s(2), s(120), s(28), L("med_erm.break.request"),
        { color = { 56, 132, 244 }, font = Gfx.font(9, true) }, function() Tablet.picker = drawRequestsPicker end)
    local crew = {}
    for _, m in ipairs(u.members) do
        local name = m.name:gsub("#%x%x%x%x%x%x", "")
        local c = Competency.of(m.player)
        crew[#crew + 1] = c and (name .. " (" .. c.short .. ")") or name
    end
    Gfx.text(Gfx.fit(L("med_erm.home.shift_since_crew", { started_at = State.formatClock(u.startedAt), started_at2 = State.formatDuration(State.serverNow() - u.startedAt), crew = table.concat(crew, ", ") }), iw, Gfx.font(9)),
        ix, cy + s(24), iw, s(18), Theme.dim, Gfx.font(9))

    if u.unqualified then
        Gfx.text(Gfx.fit(L("med_erm.competency.home_unqualified", { type = u.type }), iw, Gfx.font(9, true)),
            ix, cy + s(40), iw, s(16), tocolor(255, 130, 110), Gfx.font(9, true))
    end

    -- active case ------------------------------------------------------------
    cy = cy + s(56)
    Gfx.label(L("med_erm.home.active_case"), ix, cy, iw)
    cy = cy + s(20)
    local cardH = s(66)
    if t then
        local hov = Gfx.hover(ix, cy, iw, cardH)
        Gfx.round(ix, cy, iw, cardH, s(8), hov and Theme.panel2 or Theme.panel)
        dxDrawRectangle(ix, cy + s(10), s(3), cardH - s(20), Gfx.rgb(Config.PRIORITY_COLORS[t.priority] or { 120, 120, 120 }))
        Gfx.priorityBadge(ix + s(16), cy + s(12), s(34), s(22), t.priority)
        Gfx.text(Gfx.fit(string.format("#%d  %s", t.id, t.title), iw - s(140), Gfx.font(12, true)),
            ix + s(60), cy + s(10), iw - s(140), s(26), Theme.text, Gfx.font(12, true))
        Gfx.text(Gfx.fit(t.zone, iw - s(80), Gfx.font(9)), ix + s(60), cy + s(34), iw - s(80), s(20), Theme.dim, Gfx.font(9))
        Gfx.text(L("med_erm.home.open"), ix, cy, iw - s(16), cardH, Theme.dim, Gfx.font(10, true), "right")
        Gfx.hit(ix, cy, iw, cardH, function() Tablet.setPage("case") end)
    else
        Gfx.round(ix, cy, iw, cardH, s(8), Theme.panel)
        Gfx.text(L("med_erm.home.no_active_case_waiting_for_dispatch"), ix, cy, iw, cardH, Theme.faint, Gfx.font(10), "center")
    end

    -- closed cases -----------------------------------------------------------
    cy = cy + cardH + s(20)
    -- recent events: closed cases + fines from the supervisor, oldest first (drawn newest first)
    local closed = {}
    for _, c in ipairs(u.closedTasks or {}) do closed[#closed + 1] = { at = c.closedAt, case = c } end
    for _, f in ipairs(u.fines or {}) do closed[#closed + 1] = { at = f.at, fine = f } end
    table.sort(closed, function(a, b) return (a.at or 0) < (b.at or 0) end)
    Gfx.label(L("med_erm.home.closed_cases_this_shift", { closed = #closed }), ix, cy, iw)
    cy = cy + s(20)

    local listH = y + h - cy - s(14)
    Gfx.round(ix, cy, iw, listH, s(8), Theme.panel)
    if #closed == 0 then
        Gfx.text(L("med_erm.home.no_closed_cases_yet"), ix, cy, iw, listH, Theme.faint, Gfx.font(10), "center")
        return
    end

    local rowH = s(34)
    local visible = math.floor((listH - s(8)) / rowH)
    local offset = Gfx.getScroll("closed", #closed - visible)
    Gfx.scrollArea("closed", ix, cy, iw, listH)

    -- newest first
    for i = 1 + offset, math.min(#closed, offset + visible) do
        local ev = closed[#closed - i + 1]
        local c, f = ev.case, ev.fine
        local ry = cy + s(4) + (i - 1 - offset) * rowH
        if (i - offset) % 2 == 0 then Gfx.rect(ix + s(4), ry, iw - s(8), rowH, tocolor(255, 255, 255, 6)) end
        if f then
            local red = tocolor(255, 130, 110)
            Gfx.text(L("med_erm.home.fine_tag"), ix + s(12), ry, s(70), rowH, red, Gfx.font(9, true))
            local tw = iw - s(250)
            Gfx.text(Gfx.fit(L(f.label) .. " (" .. tostring(f.by) .. ")", tw, Gfx.font(10)), ix + s(94), ry, tw, rowH, Theme.text, Gfx.font(10))
            Gfx.text("-" .. tostring(f.amount) .. " $", ix + iw - s(160), ry, s(110), rowH, red, Gfx.font(9, true))
        else
            Gfx.text("#" .. c.id, ix + s(12), ry, s(44), rowH, Theme.dim, Gfx.font(9, true))
            Gfx.priorityBadge(ix + s(56), ry + (rowH - s(18)) / 2, s(28), s(18), c.priority ~= 0 and c.priority or nil)
            local tw = iw - s(250)
            Gfx.text(Gfx.fit(c.title, tw, Gfx.font(10)), ix + s(94), ry, tw, rowH, Theme.text, Gfx.font(10))
            Gfx.text(Gfx.fit(c.zone, s(110), Gfx.font(9)), ix + iw - s(160), ry, s(110), rowH, Theme.dim, Gfx.font(9))
        end
        Gfx.text(State.formatClock(ev.at), ix, ry, iw - s(12), rowH, Theme.dim, Gfx.font(9, true), "right")
    end
end
