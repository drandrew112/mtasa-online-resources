-- police_system / modules/mdc/client/pages/overview.lua
-- Overview: the reports warning (sign-off needs them), numbers (units on duty, pursuits, wanted now, arrests today),
-- units with their status, active pursuits (Join), wanted players, calls, the own unit (log tail, adding officers).

local MDC = POL.mdc
local C = POL.colors
local addOfficer = { open = false, list = {} }

local function kpi(x, y, w, h, label, value, color)
    dxDrawRectangle(x, y, w, h, C.panel)
    dxDrawRectangle(x, y, POL.px(3), h, color or C.accent)
    W.text(L.upper(label), x + POL.px(14), y + POL.px(8), w, POL.px(18), C.dim, 8, true)
    W.text(tostring(value), x + POL.px(14), y + POL.px(26), w, h - POL.px(30), C.white, 20, true)
end

MDC.pages.overview = {
    load = function()
        MDC.call("overview", {}, function(d) if d then MDC.data.overview = d end end)
    end,
    draw = function(x, y, w, h)
        local d = MDC.data.overview
        if not d then W.text(L("police_system.mdc.loading"), x, y, w, POL.px(40), C.dim, 11) return end
        local cy = y
        if (d.pending or 0) > 0 then
            dxDrawRectangle(x, cy, w, POL.px(40), tocolor(120, 70, 20, 255))
            W.text(L("police_system.mdc.reports_waiting", { count = d.pending }), x + POL.px(14), cy, w - POL.px(200), POL.px(40), C.white, 10, true)
            W.button("ov:reports", x + w - POL.px(170), cy + POL.px(6), POL.px(160), POL.px(28), L("police_system.mdc.open_reports"),
                function() MDC.go("reports") end, "primary")
            cy = cy + POL.px(50)
        end
        local kw = (w - POL.px(30)) / 4
        local kh = POL.px(70)
        kpi(x, cy, kw, kh, L("police_system.mdc.units_on_duty"), #(d.units or {}), C.green)
        kpi(x + (kw + POL.px(10)), cy, kw, kh, L("police_system.mdc.active_pursuits"), #(d.pursuits or {}), C.red)
        kpi(x + (kw + POL.px(10)) * 2, cy, kw, kh, L("police_system.mdc.wanted_now"), #(d.wanted or {}), C.yellow)
        kpi(x + (kw + POL.px(10)) * 3, cy, kw, kh, L("police_system.mdc.arrests_today"), d.arrestsToday or 0, C.accent)
        cy = cy + kh + POL.px(12)
        local lw = math.floor(w * 0.56)
        local rw = w - lw - POL.px(12)
        local rh = y + h - cy
        -- units
        local uh = math.floor(rh * 0.55)
        local ty = W.card(x, cy, lw, uh, L("police_system.mdc.units"), tostring(#(d.units or {})))
        local rows = {}
        for _, u in ipairs(d.units or {}) do
            local st = L.upper(L("police_system.status." .. u.status))
            if u.sub then st = st .. " · " .. L.upper(L("police_system.status.sub_" .. u.sub)) end
            rows[#rows + 1] = { cells = { u.callsign, table.concat(u.members or {}, ", "), st, u.zone },
                                colors = { nil, nil, POL.statusColor(u.status) } }
        end
        W.table("ov:units", x, ty, lw, cy + uh - ty, { { L("police_system.mdc.col_unit"), 1 }, { L("police_system.mdc.col_officers"), 3 },
            { L("police_system.mdc.col_status"), 2.4 }, { L("police_system.mdc.col_area"), 2 } }, rows)
        -- own unit: log + adding officers
        local oy = cy + uh + POL.px(10)
        local oh = y + h - oy
        local u = POL.unit
        local ly = W.card(x, oy, lw, oh, L("police_system.mdc.my_unit_log"), u and u.callsign or "")
        if u and u.type == "adam" and #(u.members or {}) < POLICE.UNITS.ADAM_MAX then
            W.button("ov:add", x + lw - POL.px(150), oy + POL.px(4), POL.px(140), POL.px(24), L("police_system.mdc.add_officer"), function()
                addOfficer.open = not addOfficer.open
                if addOfficer.open then
                    MDC.call("signin", {}, function(f) addOfficer.list = f and f.candidates or {} end)
                end
            end)
        end
        if addOfficer.open then
            local ay = ly
            if #addOfficer.list == 0 then W.text(L("police_system.mdc.no_candidates"), x + POL.px(12), ay, lw, POL.px(24), C.dim, 9) end
            for i, cnd in ipairs(addOfficer.list) do
                W.text(cnd.name, x + POL.px(12), ay, lw - POL.px(140), POL.px(26), C.text, 10, true)
                W.button("ov:inv" .. i, x + lw - POL.px(120), ay + POL.px(2), POL.px(108), POL.px(22), L("police_system.mdc.invite"), function()
                    MDC.call("invite", { target = cnd.el }, function(ok) if ok then addOfficer.open = false end end)
                end)
                ay = ay + POL.px(28)
            end
        else
            local tail = d.tail or {}
            local lh = POL.px(20)
            local maxLines = math.floor((oy + oh - ly) / lh)
            local first = math.max(1, #tail - maxLines + 1)
            for i = first, #tail do
                local l = tail[i]
                W.text(POL.clock(l.t) .. "  " .. (l.o ~= "" and (l.o .. " · ") or "") .. L("police_system.log." .. tostring(l.k)),
                    x + POL.px(12), ly + (i - first) * lh, lw - POL.px(24), lh, C.dim, 9)
            end
        end
        -- right column: pursuits, wanted, calls
        local ph = math.floor(rh * 0.36)
        local py = W.card(x + lw + POL.px(12), cy, rw, ph, L("police_system.mdc.active_pursuits"), tostring(#(d.pursuits or {})))
        for i, p in ipairs(d.pursuits or {}) do
            if py + POL.px(46) > cy + ph then break end
            local px = x + lw + POL.px(24)
            W.text(p.name, px, py, rw * 0.5, POL.px(22), C.white, 10, true)
            W.stars(p.level, px + rw * 0.45, py + POL.px(1), 10)
            W.text((p.vehicle or "") .. (p.plate and (" · " .. p.plate) or ""), px, py + POL.px(20), rw * 0.6, POL.px(20), C.dim, 9)
            W.button("ov:join" .. i, x + lw + rw - POL.px(80), py + POL.px(6), POL.px(70), POL.px(28), L("police_system.mdc.join"),
                function() MDC.call("pursuitJoin", { id = p.id }) end, "danger")
            py = py + POL.px(48)
        end
        local wy0 = cy + ph + POL.px(10)
        local wh = math.floor(rh * 0.32)
        local wy = W.card(x + lw + POL.px(12), wy0, rw, wh, L("police_system.mdc.menu_wanted"), tostring(#(d.wanted or {})))
        for _, wnt in ipairs(d.wanted or {}) do
            if wy + POL.px(24) > wy0 + wh then break end
            local px = x + lw + POL.px(24)
            W.text(wnt.name, px, wy, rw * 0.4, POL.px(22), C.white, 10, true)
            W.stars(wnt.level, px + rw * 0.36, wy + POL.px(1), 9)
            W.text(wnt.reason and L(wantedReasonKey(wnt.reason)) or "", px + rw * 0.66, wy, rw * 0.32, POL.px(22), C.dim, 9)
            wy = wy + POL.px(24)
        end
        local cy2 = wy0 + wh + POL.px(10)
        local ch = y + h - cy2
        local calls = d.calls or {}
        local cyy = W.card(x + lw + POL.px(12), cy2, rw, ch, L("police_system.mdc.menu_calls"), tostring(#calls))
        if #calls == 0 then
            W.text(L("police_system.mdc.calls_empty"), x + lw + POL.px(24), cyy, rw - POL.px(24), POL.px(24), C.dim, 9)
        end
        for _, cl in ipairs(calls) do
            if cyy + POL.px(22) > cy2 + ch then break end
            W.text("#" .. cl.id .. "  " .. cl.title .. " · " .. cl.zone, x + lw + POL.px(24), cyy, rw - POL.px(36), POL.px(22),
                cl.status == "open" and C.yellow or C.dim, 9, true)
            cyy = cyy + POL.px(22)
        end
    end,
}
