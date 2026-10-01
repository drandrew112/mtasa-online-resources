-- Home: shift summary, active case, cases closed during this shift.

local s = Gfx.s

Pages.home = {}

function Pages.home.draw(x, y, w, h)
    local u, t = State.unit, State.task
    local pad = s(18)
    local ix, iw = x + pad, w - pad - s(6)
    local cy = y + s(14)

    Gfx.text("Home", ix, cy, iw, s(26), Theme.text, Gfx.font(15, true))
    local crew = {}
    for _, m in ipairs(u.members) do crew[#crew + 1] = (m.name:gsub("#%x%x%x%x%x%x", "")) end
    Gfx.text(Gfx.fit("Shift since " .. State.formatClock(u.startedAt) .. "  ·  Crew: " .. table.concat(crew, ", "), iw, Gfx.font(9)),
        ix, cy + s(24), iw, s(18), Theme.dim, Gfx.font(9))

    -- active case ------------------------------------------------------------
    cy = cy + s(56)
    Gfx.label("ACTIVE CASE", ix, cy, iw)
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
        Gfx.text("Open  ›", ix, cy, iw - s(16), cardH, Theme.dim, Gfx.font(10, true), "right")
        Gfx.hit(ix, cy, iw, cardH, function() Tablet.setPage("case") end)
    else
        Gfx.round(ix, cy, iw, cardH, s(8), Theme.panel)
        Gfx.text("No active case. Waiting for dispatch.", ix, cy, iw, cardH, Theme.faint, Gfx.font(10), "center")
    end

    -- closed cases -----------------------------------------------------------
    cy = cy + cardH + s(20)
    local closed = u.closedTasks or {}
    Gfx.label(string.format("CLOSED CASES THIS SHIFT (%d)", #closed), ix, cy, iw)
    cy = cy + s(20)

    local listH = y + h - cy - s(14)
    Gfx.round(ix, cy, iw, listH, s(8), Theme.panel)
    if #closed == 0 then
        Gfx.text("No closed cases yet.", ix, cy, iw, listH, Theme.faint, Gfx.font(10), "center")
        return
    end

    local rowH = s(34)
    local visible = math.floor((listH - s(8)) / rowH)
    local offset = Gfx.getScroll("closed", #closed - visible)
    Gfx.scrollArea("closed", ix, cy, iw, listH)

    -- newest first
    for i = 1 + offset, math.min(#closed, offset + visible) do
        local c = closed[#closed - i + 1]
        local ry = cy + s(4) + (i - 1 - offset) * rowH
        if (i - offset) % 2 == 0 then Gfx.rect(ix + s(4), ry, iw - s(8), rowH, tocolor(255, 255, 255, 6)) end
        Gfx.text("#" .. c.id, ix + s(12), ry, s(44), rowH, Theme.dim, Gfx.font(9, true))
        Gfx.priorityBadge(ix + s(56), ry + (rowH - s(18)) / 2, s(28), s(18), c.priority ~= 0 and c.priority or nil)
        local tw = iw - s(250)
        Gfx.text(Gfx.fit(c.title, tw, Gfx.font(10)), ix + s(94), ry, tw, rowH, Theme.text, Gfx.font(10))
        Gfx.text(Gfx.fit(c.zone, s(110), Gfx.font(9)), ix + iw - s(160), ry, s(110), rowH, Theme.dim, Gfx.font(9))
        Gfx.text(State.formatClock(c.closedAt), ix, ry, iw - s(12), rowH, Theme.dim, Gfx.font(9, true), "right")
    end
end
