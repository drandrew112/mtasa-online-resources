-- Active Case: task details + response / case buttons.
--
--   Start Response -> En Route (lights & siren log starts)
--   End Response   -> stops the log
--   Leave Case     -> the unit leaves the task (only while another unit stays on it)
--   Close Case     -> closes the task with a reason (false call, broken scene, ...)
--
-- On Scene is set by the server when the unit reaches the scene, the handover
-- is started by the hospital.

local s = Gfx.s

Pages.case = {}

local reasonToken, reasonTask

local function askCloseReason(t)
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then return end
    reasonTask = t.id
    reasonToken = exports.ui_core:openTextInput(string.format("Reason for closing case #%d", t.id), 90, "")
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= reasonToken then return end
    reasonToken = nil
    local t = State.task
    if not text or not t or t.id ~= reasonTask then return end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text < 3 then
        State.notify("EMS Tablet", "Give a reason for closing the case.")
        return
    end
    Tablet.confirm = {
        title = string.format("Close case #%d?", t.id),
        text  = "Reason: " .. text,
        label = "Close Case",
        action = function() triggerServerEvent("erm:closeCase", resourceRoot, text) end,
    }
end)

local function askLeave(t)
    Tablet.confirm = {
        title = string.format("Leave case #%d?", t.id),
        text  = "Your unit will be released from the case. The other units stay on it.",
        label = "Leave Case",
        action = function() triggerServerEvent("erm:leaveCase", resourceRoot) end,
    }
end

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
    local ix, iw = x + pad, w - pad * 2

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
        { "Start Response", Config.STATUS.enroute.color, not u.responding and not handover,
            function() triggerServerEvent("erm:caseAction", resourceRoot, "start") end },
        { "End Response", { 84, 94, 108 }, u.responding,
            function() triggerServerEvent("erm:caseAction", resourceRoot, "stop") end },
        { "Leave Case", { 48, 56, 66 }, #t.units > 1 and not handover,
            function() askLeave(t) end },
        { "Close Case", { 200, 50, 45 }, not handover,
            function() askCloseReason(t) end },
    }
    for i, b in ipairs(buttons) do
        Gfx.button(ix + (i - 1) * (bw + gap), by, bw, btnH, b[1], { color = b[2], disabled = not b[3] }, b[4])
    end
end
