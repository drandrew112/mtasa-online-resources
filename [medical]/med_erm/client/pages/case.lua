if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
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
    reasonToken = exports.ui_core:openTextInput(L("med_erm.case.reason_for_closing_case", { id = t.id }), 90, "")
end

addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= reasonToken then return end
    reasonToken = nil
    local t = State.task
    if not text or not t or t.id ~= reasonTask then return end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text < 3 then
        State.notify(L("med_erm.case.ems_tablet"), L("med_erm.case.give_reason_for_closing_case"))
        return
    end
    Tablet.confirm = {
        title = L("med_erm.case.close_case", { id = t.id }),
        text  = L("med_erm.case.reason", { text = text }),
        label = L("med_erm.case.close_case_2"),
        action = function() Tablet.send("erm:closeCase", text) end,
    }
end)

local function askLeave(t)
    Tablet.confirm = {
        title = L("med_erm.case.leave_case", { id = t.id }),
        text  = L("med_erm.case.your_unit_will_be_released_from"),
        label = L("med_erm.case.leave_case_2"),
        action = function() Tablet.send("erm:leaveCase") end,
    }
end

-- Backup picker (drawn by the tablet over the page while Tablet.picker is set)
local function drawBackupPicker(sx, sy, sw, sh)
    local t = State.task
    if not t then Tablet.picker = nil return end
    Gfx.hit(0, 0, Gfx.screenW, Gfx.screenH, function() end)
    Gfx.round(sx, sy, sw, sh, s(8), Theme.shade)

    local opts = Config.BACKUP_OPTIONS
    local rows = math.ceil(#opts / 2)
    local bh, gap = s(40), s(8)
    local w, h = s(420), s(122) + rows * (bh + gap) + s(46)
    local x, y = sx + (sw - w) / 2, sy + (sh - h) / 2
    Gfx.round(x, y, w, h, s(10), Theme.panel)
    Gfx.text(L("med_erm.backup.title", { id = t.id }), x + s(20), y + s(16), w - s(40), s(26), Theme.text, Gfx.font(13, true))
    Gfx.text(L("med_erm.backup.picker_text"), x + s(20), y + s(46), w - s(40), s(60), Theme.dim, Gfx.font(10), "left", "top", true)

    local bw = (w - s(40) - gap) / 2
    local by = y + s(110)
    for i, o in ipairs(opts) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        Gfx.button(x + s(20) + col * (bw + gap), by + row * (bh + gap), bw, bh, L(o.label), { color = { 56, 132, 244 } }, function()
            Tablet.picker = nil
            Tablet.send("erm:requestBackup", o.id)
        end)
    end
    Gfx.button(x + s(20), y + h - s(54), w - s(40), s(38), L("common.cancel"), {}, function() Tablet.picker = nil end)
end

---------------------------------------------------------------- Request agency (server/agency.lua)

local agencyPick = { agency = "pd", reason = nil }
local noteToken

addEventHandler("ui_core:textInputResult", root, function(token, text)
    if token ~= noteToken then return end
    noteToken = nil
    if not text or not State.task then return end
    Tablet.send("erm:requestAgency", agencyPick.agency, agencyPick.reason, text)
end)

local function sendAgencyRequest()
    local reason
    for _, r in ipairs(Config.AGENCY_REASONS) do if r.id == agencyPick.reason then reason = r end end
    if not reason then
        State.notify(L("med_erm.case.ems_tablet"), L("med_erm.agency.select_reason"))
        return
    end
    Tablet.picker = nil
    if reason.note then
        noteToken = exports.ui_core:openTextInput(L("med_erm.agency.note_prompt"), 200, "")
    else
        Tablet.send("erm:requestAgency", agencyPick.agency, agencyPick.reason, "")
    end
end

local function drawAgencyPicker(sx, sy, sw, sh)
    local t = State.task
    if not t then Tablet.picker = nil return end
    Gfx.hit(0, 0, Gfx.screenW, Gfx.screenH, function() end)
    Gfx.round(sx, sy, sw, sh, s(8), Theme.shade)
    local reasons = Config.AGENCY_REASONS
    local rows = math.ceil(#reasons / 2)
    local bh, gap = s(40), s(8)
    local w, h = s(460), s(150) + s(48) + rows * (bh + gap) + s(54)
    local x, y = sx + (sw - w) / 2, sy + (sh - h) / 2
    Gfx.round(x, y, w, h, s(10), Theme.panel)
    Gfx.text(L("med_erm.agency.title", { id = t.id }), x + s(20), y + s(16), w - s(40), s(26), Theme.text, Gfx.font(13, true))
    Gfx.text(L("med_erm.agency.picker_text"), x + s(20), y + s(46), w - s(40), s(40), Theme.dim, Gfx.font(10), "left", "top", true)
    local bw = (w - s(40) - gap) / 2
    local ay = y + s(92)
    Gfx.label(L("med_erm.agency.agency_label"), x + s(20), ay, w - s(40))
    Gfx.button(x + s(20), ay + s(18), bw, s(36), L("med_erm.agency.police"),
        { color = agencyPick.agency == "pd" and { 56, 132, 244 } or { 48, 56, 66 } }, function() agencyPick.agency = "pd" end)
    Gfx.button(x + s(20) + bw + gap, ay + s(18), bw, s(36), L("med_erm.agency.fire_later"), { disabled = true }, function() end)
    local ry = ay + s(66)
    Gfx.label(L("med_erm.agency.reason_label"), x + s(20), ry, w - s(40))
    for i, r in ipairs(reasons) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        Gfx.button(x + s(20) + col * (bw + gap), ry + s(18) + row * (bh + gap), bw, bh, L(r.label),
            { color = agencyPick.reason == r.id and { 56, 132, 244 } or { 48, 56, 66 } }, function() agencyPick.reason = r.id end)
    end
    local by = y + h - s(54)
    Gfx.button(x + s(20), by, bw, s(38), L("med_erm.agency.send"), { color = { 124, 92, 230 }, disabled = not agencyPick.reason }, sendAgencyRequest)
    Gfx.button(x + s(20) + bw + gap, by, bw, s(38), L("common.cancel"), {}, function() Tablet.picker = nil end)
end

---------------------------------------------------------------- safe scene alert

function Pages.case.safetyAlert(sx, sy, sw, sh)
    local t, sf = State.task, State.safety()
    if not t or not sf or sf.state ~= "unsafe" then
        Tablet.picker, Tablet.pendingSafetyAlert = nil, false
        return
    end
    Gfx.hit(0, 0, Gfx.screenW, Gfx.screenH, function() end)
    Gfx.round(sx, sy, sw, sh, s(8), Theme.shade)
    local w, h = s(470), s(250)
    local x, y = sx + (sw - w) / 2, sy + (sh - h) / 2
    Gfx.round(x - s(2), y - s(2), w + s(4), h + s(4), s(11), Theme.accent)
    Gfx.round(x, y, w, h, s(10), Theme.bg)
    Gfx.text(L("med_erm.safety.alert_title"), x + s(20), y + s(16), w - s(40), s(26), Gfx.rgb({ 255, 120, 110 }), Gfx.font(14, true))
    Gfx.text(L("med_erm.safety.warn_text", { id = t.id, distance = Config.STAGING_MIN }), x + s(20), y + s(48), w - s(40), s(70),
        Theme.text, Gfx.font(10), "left", "top", true)
    local p = type(t.meta) == "table" and t.meta.police
    local police = type(p) == "table" and (#(p.units or {}) > 0 and L("med_erm.safety.police_units", { units = table.concat(p.units, ", ") })
        or L("med_erm.safety.police_waiting")) or "-"
    Gfx.label(L("med_erm.case.police"), x + s(20), y + s(126), w / 2 - s(30))
    Gfx.text(Gfx.fit(police, w / 2 - s(30), Gfx.font(10, true)), x + s(20), y + s(141), w / 2 - s(30), s(20), Theme.text, Gfx.font(10, true))
    Gfx.label(L("med_erm.safety.staging_label"), x + w / 2, y + s(126), w / 2 - s(20))
    Gfx.text(L(type(sf.staging) == "table" and "med_erm.safety.staging_on_map" or "med_erm.safety.staging_none", { distance = Config.STAGING_MIN }),
        x + w / 2, y + s(141), w / 2 - s(20), s(20), Theme.text, Gfx.font(10, true))
    Gfx.button(x + s(20), y + h - s(56), w - s(40), s(38), L("med_erm.safety.understood"), { color = { 56, 132, 244 } }, function()
        Tablet.picker, Tablet.pendingSafetyAlert = nil, false
    end)
end

function Tablet.showSafetyAlert(on)
    if on then
        Tablet.pendingSafetyAlert = true
        if Tablet.open and State.unit then Tablet.picker = Pages.case.safetyAlert end
    else
        Tablet.pendingSafetyAlert = false
        if Tablet.picker == Pages.case.safetyAlert then Tablet.picker = nil end
    end
end

local function safetyField(sf)
    if sf.state == "unsafe" then
        return L("med_erm.safety.field_unsafe", { distance = Config.STAGING_MIN }), { 255, 120, 110 }
    end
    return L(sf.auto and "med_erm.safety.field_safe_auto" or "med_erm.safety.field_safe",
        { callsign = sf.by or "-", time = State.formatClock(sf.since or 0) }), { 110, 215, 130 }
end

local function policeField(p)
    if p.status == "closed" then return L("med_erm.case.police_closed", { call = p.call }) end
    if #(p.units or {}) > 0 then return L("med_erm.case.police_responding", { call = p.call, units = table.concat(p.units, ", ") }) end
    return L("med_erm.case.police_requested", { call = p.call })
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
        Gfx.text(L("med_erm.case.active_case"), ix, y + s(14), iw, s(26), Theme.text, Gfx.font(15, true))
        local cy = y + h / 2 - s(30)
        dxDrawCircle(x + w / 2, cy - s(14), s(22), 0, 360, Theme.panel, Theme.panel, 24)
        Gfx.cross(x + w / 2 - s(9), cy - s(23), s(18), Theme.faint)
        Gfx.text(L("med_erm.case.no_active_case"), x, cy + s(16), w, s(24), Theme.text, Gfx.font(12, true), "center")
        Gfx.text(L("med_erm.case.you_will_be_notified_when_dispatch"), x + s(30), cy + s(40), w - s(60), s(20), Theme.dim, Gfx.font(9), "center")
        return
    end

    local now = State.serverNow()
    local cy = y + s(14)

    -- title
    Gfx.priorityBadge(ix, cy + s(2), s(40), s(26), t.priority, t.meta)
    Gfx.text(Gfx.fit(string.format("#%d  %s", t.id, t.title), iw - s(52), Gfx.font(14, true)),
        ix + s(52), cy, iw - s(52), s(30), Theme.text, Gfx.font(14, true))
    Gfx.text(Gfx.fit(t.zone .. "   ·   " .. distanceText(t), iw * 0.5, Gfx.font(9)), ix, cy + s(32), iw * 0.5, s(18), Theme.dim, Gfx.font(9))
    -- the nearest hospital: kórházi dolgozó / szabad hely (med_hospitals ER)
    local hs, hsp = HospitalParams.nearestStatus()
    if hs then
        Gfx.text(Gfx.fit(hs, iw * 0.5, Gfx.font(9, true)), ix + iw * 0.5, cy + s(32), iw * 0.5, s(18),
            (hsp and hsp.er and hsp.staff > 0) and tocolor(120, 200, 140) or Theme.faint, Gfx.font(9, true), "right")
    end

    -- info grid
    cy = cy + s(60)
    local cw = iw / 3
    local units = {}
    for _, tu in ipairs(t.units) do units[#units + 1] = tu.callsign end
    info(L("med_erm.case.received"), L("med_erm.case.ago", { created_at = State.formatClock(t.createdAt), created_at2 = State.formatDuration(now - t.createdAt) }), ix, cy, cw - s(10))
    info(L("med_erm.detail.caller"), t.caller ~= "" and t.caller or "-", ix + cw, cy, cw - s(10))
    info(L("med_erm.case.units"), table.concat(units, ", "), ix + cw * 2, cy, cw)

    -- safe scene + police (only when the case has them)
    local sf = State.safety()
    local p = type(t.meta) == "table" and type(t.meta.police) == "table" and t.meta.police or nil
    if sf or p then
        cy = cy + s(46)
        local fw = (iw - s(10)) / 2
        local fx = ix
        if sf then
            local text, color = safetyField(sf)
            Gfx.round(fx, cy, fw, s(40), s(6), sf.state == "unsafe" and tocolor(224, 60, 49, 50) or tocolor(46, 160, 67, 40))
            Gfx.label(L("med_erm.safety.field_label"), fx + s(10), cy + s(4), fw - s(20))
            Gfx.text(Gfx.fit(text, fw - s(20), Gfx.font(10, true)), fx + s(10), cy + s(18), fw - s(20), s(20), Gfx.rgb(color), Gfx.font(10, true))
            fx = fx + fw + s(10)
        end
        if p then
            Gfx.round(fx, cy, fw, s(40), s(6), Theme.panel)
            Gfx.label(L("med_erm.case.police"), fx + s(10), cy + s(4), fw - s(20))
            Gfx.text(Gfx.fit(policeField(p), fw - s(20), Gfx.font(10, true)), fx + s(10), cy + s(18), fw - s(20), s(20), Theme.text, Gfx.font(10, true))
        end
        cy = cy - s(2)
    end

    -- description
    cy = cy + s(46)
    local btnH = s(50)
    local descH = y + h - cy - btnH - s(58)
    Gfx.round(ix, cy, iw, descH, s(8), Theme.panel)
    local font = Gfx.font(10)
    local lines = Gfx.wrap(t.description ~= "" and t.description or L("med_erm.detail.no_description"), iw - s(24), font)
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
        Gfx.text(u.handoverEnds > 0 and L("med_erm.case.handover_in_progress_s", { now = math.max(0, u.handoverEnds - now) })
            or L("med_erm.case.handover_in_progress"),
            ix, ly, iw, s(30), Gfx.rgb(Config.STATUS.handover.color), Gfx.font(10, true))
    elseif u.responding then
        Gfx.text(L("med_erm.case.lights_siren_active", { response_from = State.formatDuration(now - u.responseFrom) }),
            ix, ly, iw, s(30), Gfx.rgb(Config.STATUS.enroute.color), Gfx.font(10, true))
    elseif u.reachedScene then
        Gfx.text(L("med_erm.case.on_scene"), ix, ly, iw, s(30), Gfx.rgb(Config.STATUS.onscene.color), Gfx.font(10, true))
    else
        Gfx.text(L("med_erm.case.awaiting_response"), ix, ly, iw, s(30), Theme.faint, Gfx.font(10, true))
    end

    -- backup request (SOLO / DOC: transport, BLS: advanced care)
    local rbw = s(170)
    Gfx.button(ix + iw - rbw, ly + s(2), rbw, s(30), L("med_erm.backup.request"),
        { color = { 56, 132, 244 }, disabled = u.status == "handover" or TabletTutorial.active, font = Gfx.font(9, true) },
        function() Tablet.picker = drawBackupPicker end)
    -- other agencies (the police), left of the backup button
    local linked = p and p.status ~= "closed"
    Gfx.button(ix + iw - rbw * 2 - s(8), ly + s(2), rbw, s(30), L("med_erm.agency.request"),
        { color = { 124, 92, 230 }, disabled = linked or u.status == "handover" or TabletTutorial.active, font = Gfx.font(9, true) },
        function() agencyPick.reason = nil; Tablet.picker = drawAgencyPicker end)

    -- one-button parameter card to the hospital, left of the agency button
    Gfx.button(ix + iw - rbw * 3 - s(16), ly + s(2), rbw, s(30), L("med_erm.hospital.send_params"),
        { color = { 46, 160, 67 }, disabled = TabletTutorial.active, font = Gfx.font(9, true) },
        function() HospitalParams.open() end)

    -- buttons
    local by = y + h - btnH - s(16)
    local gap = s(8)
    local bw = (iw - gap * 3) / 4
    local handover = u.status == "handover"
    local buttons = {
        { L("med_erm.case.start_response"), Config.STATUS.enroute.color, not u.responding and not handover,
            function() Tablet.send("erm:caseAction", "start") end },
        { L("med_erm.case.end_response"), { 84, 94, 108 }, u.responding,
            function() Tablet.send("erm:caseAction", "stop") end },
        { L("med_erm.case.leave_case_2"), { 48, 56, 66 }, #t.units > 1 and not handover,
            function() askLeave(t) end },
        { L("med_erm.case.close_case_2"), { 200, 50, 45 }, not handover,
            function() askCloseReason(t) end },
    }
    for i, b in ipairs(buttons) do
        Gfx.button(ix + (i - 1) * (bw + gap), by, bw, btnH, b[1], { color = b[2], disabled = not b[3] }, b[4])
    end
end
