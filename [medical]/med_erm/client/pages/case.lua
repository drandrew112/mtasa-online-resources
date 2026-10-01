-- Active Case: task details + response buttons.
--
--   Start Response -> En Route (lights & siren log starts)
--   End Response   -> stops the log (status: On Scene)
--   On Scene       -> stops the log, marks the scene reached
--   Handover       -> hospital handover (30 s by default, or run by an external
--                     resource), then the server frees the unit

local s = Gfx.s

Pages.case = {}

local function distanceText(t)
    local px, py = getElementPosition(localPlayer)
    local d = getDistanceBetweenPoints2D(px, py, t.x, t.y)
    if d >= 1000 then return string.format("%.2f km", d / 1000) end
    return string.format("%d m", d)
end

local function info(label, value, x, y, w)
    Gfx.label(label, x, y, w)
    Gfx.text(Gfx.fit(value, w, Gfx.font(10, true)), x, y + s(15), w, s(20), Theme.text, Gfx.font(10, true))
end

function Pages.case.draw(x, y, w, h)
    local u, t = State.unit, State.task
    local pad = s(18)
    local ix, iw = x + pad, w - pad - s(6)

    if not t then
        Gfx.text("Active Case", ix, y + s(14), iw, s(26), Theme.text, Gfx.font(15, true))
        local cy = y + h / 2 - s(30)
        dxDrawCircle(x + w / 2, cy - s(14), s(22), 0, 360, Theme.panel, Theme.panel, 24)
        Gfx.cross(x + w / 2 - s(9), cy - s(23), s(18), Theme.faint)
        Gfx.text("No active case", x, cy + s(16), w, s(24), Theme.text, Gfx.font(12, true), "center")
        Gfx.text("You will be notified when dispatch assigns a case to your unit.", x + s(30), cy + s(40), w - s(60), s(20), Theme.dim, Gfx.font(9), "center")
        return
    end

    local now = State.serverNow()
    local cy = y + s(14)

    -- title
    Gfx.priorityBadge(ix, cy + s(2), s(40), s(26), t.priority)
    Gfx.text(Gfx.fit(string.format("#%d  %s", t.id, t.title), iw - s(52), Gfx.font(14, true)),
        ix + s(52), cy, iw - s(52), s(30), Theme.text, Gfx.font(14, true))
    Gfx.text(Gfx.fit(t.zone .. "   ·   " .. distanceText(t), iw, Gfx.font(9)), ix, cy + s(32), iw, s(18), Theme.dim, Gfx.font(9))

    -- info grid
    cy = cy + s(60)
    local cw = iw / 3
    local units = {}
    for _, tu in ipairs(t.units) do units[#units + 1] = tu.callsign end
    info("RECEIVED", string.format("%s  (%s ago)", State.formatClock(t.createdAt), State.formatDuration(now - t.createdAt)), ix, cy, cw - s(10))
    info("CALLER", t.caller ~= "" and t.caller or "-", ix + cw, cy, cw - s(10))
    info("UNITS", table.concat(units, ", "), ix + cw * 2, cy, cw)

    -- description
    cy = cy + s(46)
    local btnH = s(50)
    local descH = y + h - cy - btnH - s(58)
    Gfx.round(ix, cy, iw, descH, s(8), Theme.panel)
    local font = Gfx.font(10)
    local lines = Gfx.wrap(t.description ~= "" and t.description or "No description.", iw - s(24), font)
    local lh = dxGetFontHeight(1, font) + s(2)
    local maxLines = math.floor((descH - s(16)) / lh)
    for i = 1, math.min(#lines, maxLines) do
        local line = lines[i]
        if i == maxLines and #lines > maxLines then line = Gfx.fit(line .. " …", iw - s(24), font) end
        Gfx.text(line, ix + s(12), cy + s(8) + (i - 1) * lh, iw - s(24), lh, t.description ~= "" and Theme.text or Theme.faint, font)
    end

    -- response state line
    local ly = cy + descH + s(8)
    if u.status == "handover" then
        Gfx.text(u.handoverEnds > 0 and string.format("●  Handover in progress - %d s", math.max(0, u.handoverEnds - now))
            or "●  Handover in progress",
            ix, ly, iw, s(30), Gfx.rgb(Config.STATUS.handover.color), Gfx.font(10, true))
    elseif u.responding then
        Gfx.text("●  Lights & siren active - " .. State.formatDuration(now - u.responseFrom),
            ix, ly, iw, s(30), Gfx.rgb(Config.STATUS.enroute.color), Gfx.font(10, true))
    elseif u.reachedScene then
        Gfx.text("●  On scene", ix, ly, iw, s(30), Gfx.rgb(Config.STATUS.onscene.color), Gfx.font(10, true))
    else
        Gfx.text("●  Awaiting response", ix, ly, iw, s(30), Theme.faint, Gfx.font(10, true))
    end

    -- buttons
    local by = y + h - btnH - s(16)
    local gap = s(8)
    local bw = (iw - gap * 3) / 4
    local handover = u.status == "handover"
    local buttons = {
        { "Start Response", "start",    Config.STATUS.enroute.color,  not u.responding and not handover },
        { "End Response",   "stop",     { 84, 94, 108 },              u.responding },
        { "On Scene",       "onscene",  Config.STATUS.onscene.color,  u.responding },
        { "Handover",       "handover", Config.STATUS.handover.color, u.reachedScene and not handover },
    }
    for i, b in ipairs(buttons) do
        Gfx.button(ix + (i - 1) * (bw + gap), by, bw, btnH, b[1], {
            color = b[3],
            disabled = not b[4],
            textColor = b[2] == "handover" and tocolor(25, 25, 25) or nil,
        }, function() triggerServerEvent("erm:caseAction", resourceRoot, b[2]) end)
    end
end
