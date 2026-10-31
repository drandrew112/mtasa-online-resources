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

MDC.pages.calls = {
    load = function() MDC.call("calls", {}, function(d) MDC.data.calls = d or {} end) end,
    draw = function(x, y, w, h)
        local cy = header(x, y, w, L("police_system.mdc.menu_calls"), L("police_system.mdc.calls_hint"))
        local rows = {}
        for _, c in ipairs(MDC.data.calls or {}) do
            rows[#rows + 1] = { cells = { "#" .. c.id, POL.clock(c.at), c.name, c.title .. (c.description ~= "" and (" — " .. c.description) or ""),
                c.zone, L("police_system.mdc.call_" .. c.status), table.concat(c.units or {}, ", "),
                function(bx, by, bw, bh)
                    if c.status ~= "closed" then
                        W.button("cr" .. c.id, bx, by + POL.px(3), bw * 0.48, bh - POL.px(6), L("police_system.mdc.respond"),
                            function() MDC.call("callRespond", { id = c.id }, function() MDC.load() end) end, "primary")
                        W.button("cc" .. c.id, bx + bw * 0.52, by + POL.px(3), bw * 0.48, bh - POL.px(6), L("police_system.mdc.close"),
                            function() MDC.call("callClose", { id = c.id }, function() MDC.load() end) end)
                    end
                end }, colors = { nil, C.dim, nil, nil, C.dim, c.status == "open" and C.yellow or C.dim } }
        end
        W.table("calls", x, cy, w, y + h - cy, { { "#", 0.5 }, { L("police_system.mdc.col_time"), 0.7 }, { L("police_system.mdc.col_caller"), 1.4 },
            { L("police_system.mdc.col_title"), 4 }, { L("police_system.mdc.col_area"), 1.6 }, { L("police_system.mdc.col_status"), 1 },
            { L("police_system.mdc.col_units"), 1 }, { "", 2 } }, rows, nil, POL.px(34))
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
