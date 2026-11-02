-- police_system / modules/mdc/client/pages/lists.lua
-- Calls (Respond / Close), Pursuits (Join), Wanted (the temporary GTA wanted levels with their reasons; gone when they
-- end), Penal code (the current amounts, quick help during a stop).

local MDC = POL.mdc
local C = POL.colors

local function header(x, y, w, title, hint)
    W.text(title, x, y, w, POL.px(30), C.white, 15, true)
    if hint then W.text(hint, x, y + POL.px(28), w, POL.px(20), C.dim, 9) end
    return y + POL.px(hint and 56 or 40)
end

-- Calls: the list (phone / scene / agency calls, texts in the reader's language), a click opens the detail panel:
-- the call, the mandatory "secure the scene" block of an unsafe scene (threats, Report scene safe) and the text
-- channels (Call = the units on it, Inter-agency = + the EMS crews of the linked ERM task).
local CS = { selected = nil, channel = "call" }

local function duration(sec)
    sec = math.max(0, math.floor(sec or 0))
    return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function kindBadges(c, bx, by)
    local x = bx
    if c.kind == "scene" then x = x + W.badge(L.upper(L("police_system.mdc.kind_scene")), x, by, C.accentDim) + POL.px(4)
    elseif c.kind == "agency" then x = x + W.badge("EMS", x, by, tocolor(46, 140, 90, 255)) + POL.px(4) end
    if c.safety == "unsafe" then x = x + W.badge(L.upper(L("police_system.mdc.badge_secure")), x, by, C.red) + POL.px(4)
    elseif c.safety == "safe" then x = x + W.badge(L.upper(L("police_system.mdc.badge_safe")), x, by, tocolor(40, 140, 80, 255)) + POL.px(4) end
    return x - bx
end

local function threatText(t)
    local role = L("police_system.mdc.threat_" .. tostring(t.role))
    if (t.weapon or 0) ~= 0 then role = role .. ", " .. (getWeaponNameFromID(t.weapon) or tostring(t.weapon)) end
    return role
end

local function drawSafety(d, x, y, w)
    local s = d.safetyInfo
    if not s then return y end
    if s.state == "safe" then
        W.text(L("police_system.mdc.safe_line", { callsign = s.by or "-", time = POL.clock(s.since or 0),
            how = L(s.auto and "police_system.mdc.safe_auto" or "police_system.mdc.safe_reported") }), x, y, w, POL.px(22), C.green, 10, true)
        return y + POL.px(28)
    end
    local threats = s.threats or {}
    local h = POL.px(96) + #threats * POL.px(24)
    dxDrawRectangle(x, y, w, h, tocolor(235, 64, 64, 30))
    dxDrawRectangle(x, y, w, POL.px(2), C.red)
    dxDrawRectangle(x, y + h - POL.px(2), w, POL.px(2), C.red)
    W.text(L.upper(L("police_system.mdc.secure_title")), x + POL.px(10), y + POL.px(6), w - POL.px(20), POL.px(22), tocolor(255, 120, 120, 255), 11, true)
    local wait = s.emsWaitingSince and duration(getRealTime().timestamp - s.emsWaitingSince) or "-"
    W.text(L("police_system.mdc.secure_text", { wait = wait }), x + POL.px(10), y + POL.px(28), w - POL.px(20), POL.px(36), C.text, 9, false, "left", "top", true, true)
    local ty = y + POL.px(64)
    for _, t in ipairs(threats) do
        dxDrawRectangle(x + POL.px(10), ty, w - POL.px(20), POL.px(22), tocolor(0, 0, 0, 70))
        W.text(threatText(t), x + POL.px(18), ty, w - POL.px(140), POL.px(22), C.text, 9)
        local active = t.status == "active"
        W.text(L.upper(L("police_system.mdc.threat_status_" .. tostring(t.status))), x, ty, w - POL.px(18), POL.px(22),
            active and tocolor(255, 120, 120, 255) or C.green, 9, true, "right")
        ty = ty + POL.px(24)
    end
    local near = (d.distance or 9999) <= (s.radius or 40)
    local blocked = not near and "police_system.mdc.safe_need_scene" or (s.activeNear and "police_system.mdc.safe_need_clear") or nil
    W.button("cs:safe", x + POL.px(10), ty + POL.px(2), POL.px(190), POL.px(26), L("police_system.mdc.report_safe"), function()
        MDC.call("callReportSafe", { id = d.id }, function() MDC.load() end)
    end, "primary", blocked ~= nil)
    if blocked then W.text(L(blocked, { radius = s.radius or 40 }), x + POL.px(210), ty + POL.px(2), w - POL.px(220), POL.px(26), C.dim, 9) end
    return y + h + POL.px(8)
end

local function drawChat(d, x, y, w, h)
    local linked = d.ermTask and true or false
    if CS.channel == "agency" and not linked then CS.channel = "call" end
    local tabs = { { "call", L("police_system.mdc.channel_call", { id = d.id }) } }
    if linked then tabs[2] = { "agency", L("police_system.mdc.channel_agency") } end
    local tx = x
    for _, t in ipairs(tabs) do
        local tw = dxGetTextWidth(t[2], 1, POL.font(9, true)) + POL.px(24)
        W.button("ct:" .. t[1], tx, y, tw, POL.px(26), t[2], function() CS.channel = t[1]; MDC.mark() end, CS.channel == t[1] and "active" or nil)
        tx = tx + tw + POL.px(4)
    end
    local ly, inputH = y + POL.px(32), POL.px(30)
    local listH = h - (ly - y) - inputH - POL.px(8)
    dxDrawRectangle(x, ly, w, listH, tocolor(0, 0, 0, 60))
    local rowH = POL.px(20)
    local rows = {}
    for _, m in ipairs(d.messages or {}) do
        if m.channel == CS.channel then rows[#rows + 1] = m end
    end
    local visible = math.floor((listH - POL.px(8)) / rowH)
    local first = math.max(1, #rows - visible + 1)
    if #rows == 0 then W.text(L("police_system.mdc.channel_empty"), x, ly, w, listH, C.dim, 9, false, "center") end
    for i = first, #rows do
        local m = rows[i]
        local ry = ly + POL.px(4) + (i - first) * rowH
        local color = m.kind == "pd" and C.accentDim or m.kind == "ems" and tocolor(46, 140, 90, 255) or C.panel2
        local tag = m.kind == "pd" and L("police_system.mdc.tag_police") or m.kind == "ems" and "EMS" or L("police_system.mdc.tag_system")
        local bw = W.badge(L.upper(tag), x + POL.px(6), ry + POL.px(1), color, 7)
        local line = (m.kind == "sys" and "" or (m.from .. ": ")) .. m.text
        W.text(POL.clock(m.at) .. "  " .. line, x + POL.px(12) + bw, ry, w - bw - POL.px(18), rowH, m.kind == "sys" and C.dim or C.text, 9)
    end
    local iy = ly + listH + POL.px(8)
    local field = W.field("cl:msg", x, iy, w - POL.px(96), inputH,
        L(CS.channel == "agency" and "police_system.mdc.write_agency" or "police_system.mdc.write_call"), { max = 300 })
    W.button("cl:send", x + w - POL.px(90), iy, POL.px(90), inputH, L("police_system.mdc.send"), function()
        local text = field:getText()
        if text:gsub("%s", "") == "" then return end
        MDC.call("callMessage", { id = d.id, channel = CS.channel, text = text }, function(ok)
            if ok then field:setText("") end
            MDC.load()
        end)
    end, "primary")
end

local function drawDetail(d, x, y, w, h)
    local lw = math.floor(w * 0.53)
    local rw = w - lw - POL.px(12)
    dxDrawRectangle(x, y, lw, h, C.panel)
    dxDrawRectangle(x + lw + POL.px(12), y, rw, h, C.panel)
    local ix, iw = x + POL.px(12), lw - POL.px(24)
    local cy = y + POL.px(10)
    W.text("#" .. d.id .. "  " .. tostring(d.title), ix, cy, iw - POL.px(30), POL.px(24), C.white, 12, true)
    W.button("cd:x", x + lw - POL.px(34), cy, POL.px(26), POL.px(24), "✕", function() CS.selected = nil; MDC.data.callDetail = nil; MDC.mark() end, "ghost")
    cy = cy + POL.px(28)
    local src = L("police_system.mdc.source_" .. tostring(d.kind))
    local meta = L("police_system.mdc.detail_meta", { time = POL.clock(d.at), zone = d.zone, source = src, priority = d.priority or 2 })
    W.text(meta, ix, cy, iw, POL.px(18), C.dim, 9)
    cy = cy + POL.px(20)
    if d.ermTask then
        W.text(L("police_system.mdc.ems_link", { id = d.ermTask }), ix, cy, iw, POL.px(18), tocolor(110, 215, 130, 255), 9, true)
        cy = cy + POL.px(20)
    end
    if (d.description or "") ~= "" then
        W.text(d.description, ix, cy, iw, POL.px(54), C.text, 9, false, "left", "top", true, true)
        cy = cy + POL.px(58)
    end
    cy = drawSafety(d, ix, cy, iw)
    drawChat(d, x + lw + POL.px(24), y + POL.px(10), rw - POL.px(24), h - POL.px(20))
end

MDC.pages.calls = {
    load = function()
        MDC.call("calls", {}, function(d) MDC.data.calls = d or {} end)
        if CS.selected then
            MDC.call("callDetail", { id = CS.selected }, function(d) MDC.data.callDetail = d or nil end)
        end
    end,
    draw = function(x, y, w, h)
        local cy = header(x, y, w, L("police_system.mdc.menu_calls"), L("police_system.mdc.calls_hint"))
        local rows = {}
        for _, c in ipairs(MDC.data.calls or {}) do
            rows[#rows + 1] = { data = c, cells = { "#" .. c.id, POL.clock(c.at), c.name,
                function(bx, by, bw, bh)
                    local off = kindBadges(c, bx, by + (bh - POL.px(18)) / 2)
                    W.text(tostring(c.title) .. (c.description ~= "" and (" — " .. tostring(c.description)) or ""), bx + off, by, bw - off, bh, C.text, 9)
                end,
                c.zone, L("police_system.mdc.call_" .. c.status), table.concat(c.units or {}, ", "),
                function(bx, by, bw, bh)
                    if c.status ~= "closed" then
                        W.button("cr" .. c.id, bx, by + POL.px(3), bw * 0.48, bh - POL.px(6), L("police_system.mdc.respond"),
                            function() MDC.call("callRespond", { id = c.id }, function() MDC.load() end) end, "primary")
                        W.button("cc" .. c.id, bx + bw * 0.52, by + POL.px(3), bw * 0.48, bh - POL.px(6), L("police_system.mdc.close"),
                            function() MDC.call("callClose", { id = c.id }, function() MDC.load() end) end, nil, c.safety == "unsafe")
                    end
                end }, colors = { nil, C.dim, nil, nil, C.dim, c.status == "open" and C.yellow or C.dim } }
        end
        local detail = CS.selected and MDC.data.callDetail
        if detail and detail.id ~= CS.selected then detail = nil end
        local tableH = detail and math.floor((y + h - cy) * 0.38) or (y + h - cy)
        W.table("calls", x, cy, w, tableH, { { "#", 0.5 }, { L("police_system.mdc.col_time"), 0.7 }, { L("police_system.mdc.col_caller"), 1.4 },
            { L("police_system.mdc.col_title"), 4 }, { L("police_system.mdc.col_area"), 1.6 }, { L("police_system.mdc.col_status"), 1 },
            { L("police_system.mdc.col_units"), 1 }, { "", 2 } }, rows, function(r)
                CS.selected = r.data.id
                MDC.call("callDetail", { id = r.data.id }, function(d) MDC.data.callDetail = d or nil end)
            end, POL.px(34))
        if detail then drawDetail(detail, x, cy + tableH + POL.px(10), w, y + h - (cy + tableH + POL.px(10))) end
    end,
}

MDC.pages.pursuits = {
    load = function() MDC.call("pursuits", {}, function(d) MDC.data.pursuits = d or {} end) end,
    draw = function(x, y, w, h)
        local cy = header(x, y, w, L("police_system.mdc.menu_pursuits"), L("police_system.mdc.pursuits_hint"))
        local rows = {}
        local now = getRealTime().timestamp
        for _, p in ipairs(MDC.data.pursuits or {}) do
            local mins = math.floor((now - (p.since or now)) / 60)
            local secs = (now - (p.since or now)) % 60
            rows[#rows + 1] = { cells = { p.name, function(bx, by) W.stars(p.level, bx, by + POL.px(4), 9) end,
                (p.vehicle or "-") .. (p.plate and (" · " .. p.plate) or ""),
                table.concat(p.units or {}, ", ") .. (p.ai > 0 and (" + " .. L("police_system.mdc.ai_units", { count = p.ai })) or ""),
                ("%02d:%02d"):format(mins, secs), p.zone .. (p.phase == "evading" and (" · " .. L("police_system.mdc.evading")) or ""),
                function(bx, by, bw, bh)
                    W.button("pj" .. p.id, bx, by + POL.px(3), bw, bh - POL.px(6), L("police_system.mdc.join"),
                        function() MDC.call("pursuitJoin", { id = p.id }, function() MDC.load() end) end, "danger")
                end } }
        end
        W.table("pursuits", x, cy, w, y + h - cy, { { L("police_system.mdc.col_suspect"), 2 }, { L("police_system.mdc.col_level"), 1.4 },
            { L("police_system.mdc.col_vehicle"), 2 }, { L("police_system.mdc.col_units"), 2.4 }, { L("police_system.mdc.col_duration"), 0.8 },
            { L("police_system.mdc.col_area"), 2 }, { "", 1 } }, rows, nil, POL.px(34))
    end,
}

MDC.pages.wanted = {
    load = function() MDC.call("wanted", {}, function(d) MDC.data.wanted = d or {} end) end,
    draw = function(x, y, w, h)
        local cy = header(x, y, w, L("police_system.mdc.menu_wanted"), L("police_system.mdc.wanted_hint"))
        local rows = {}
        for _, p in ipairs(MDC.data.wanted or {}) do
            local reasons = {}
            for _, r in ipairs(p.reasons or {}) do reasons[#reasons + 1] = L(wantedReasonKey(r)) end
            rows[#rows + 1] = { cells = { p.name, function(bx, by) W.stars(p.level, bx, by + POL.px(4), 9) end,
                table.concat(reasons, ", "), L("police_system.mdc.phase_" .. tostring(p.phase)), p.zone },
                colors = { nil, nil, nil, p.phase == "evading" and C.yellow or C.dim } }
        end
        W.table("wanted", x, cy, w, y + h - cy, { { L("police_system.mdc.col_name"), 2 }, { L("police_system.mdc.col_level"), 1.4 },
            { L("police_system.mdc.col_reasons"), 4 }, { L("police_system.mdc.col_phase"), 1.2 }, { L("police_system.mdc.col_area"), 2 } }, rows)
    end,
}

MDC.pages.penal = {
    load = function() MDC.call("penal", {}, function(d) MDC.data.penal = d or {} end) end,
    draw = function(x, y, w, h)
        local cy = header(x, y, w, L("police_system.mdc.menu_penal"), L("police_system.mdc.penal_hint"))
        local rows = {}
        for _, c in ipairs(MDC.data.penal or {}) do
            rows[#rows + 1] = { cells = { L.upper(L(btkCategoryKey(c.id))), "", "", "" }, colors = { C.accent } }
            for _, it in ipairs(c.items) do
                local flags = {}
                if it.arrestable then flags[#flags + 1] = L("police_system.mdc.arrestable") end
                if it.warrant then flags[#flags + 1] = L("police_system.mdc.warrant_minutes", { minutes = it.minutes }) end
                rows[#rows + 1] = { cells = { "   " .. L(btkKey(it.id)), it.warning and L("police_system.mdc.warning_only") or POL.money(it.amount),
                    it.amount ~= it.default and not it.warning and (L("police_system.mdc.default") .. " " .. POL.money(it.default)) or "",
                    table.concat(flags, " · ") }, colors = { C.text, C.white, C.dim, C.dim } }
            end
        end
        W.table("penal", x, cy, w, y + h - cy, { { L("police_system.mdc.col_item"), 4 }, { L("police_system.mdc.col_amount"), 1.2, "right" },
            { "", 1.4 }, { "", 2.4 } }, rows, nil, POL.px(26))
    end,
}
