-- police_system / modules/mdc/client/pages/records.lua
-- Citizens / Vehicles: one list each of the police database, Player / NPC filter, search (name, plate, citizen id,
-- model, owner), 25 a page. A row opens the profile: earlier reports (date, author), fines and warnings (date,
-- officer; Százados+ can refund a fine), warrants, vehicles; the temporary wanted level of a player (live).

local MDC = POL.mdc
local C = POL.colors
local S = { citizens = { filter = "all", page = 1 }, vehicles = { filter = "all", page = 1 }, tab = "records" }

local function filterBar(kind, x, y)
    local st = S[kind]
    local bx = x
    for _, f in ipairs({ "all", "player", "npc" }) do
        W.button(kind .. ":f:" .. f, bx, y, POL.px(90), POL.px(28), L("police_system.mdc.filter_" .. f),
            function() st.filter = f; st.page = 1; MDC.load() end, st.filter == f and "active" or nil)
        bx = bx + POL.px(94)
    end
    W.field(kind .. ":q", bx + POL.px(10), y, POL.px(300), POL.px(28), L("police_system.mdc.search_" .. kind), { max = 40 })
    W.button(kind .. ":go", bx + POL.px(318), y, POL.px(100), POL.px(28), L("police_system.mdc.search"),
        function() st.page = 1; MDC.load() end, "primary")
end

local function pager(kind, x, y, w, more)
    local st = S[kind]
    if st.page > 1 then W.button(kind .. ":prev", x, y, POL.px(100), POL.px(28), "‹ " .. L("police_system.mdc.prev"), function() st.page = st.page - 1; MDC.load() end) end
    W.text(L("police_system.mdc.page", { page = st.page }), x, y, w, POL.px(28), C.dim, 9, false, "center")
    if more then W.button(kind .. ":next", x + w - POL.px(100), y, POL.px(100), POL.px(28), L("police_system.mdc.next") .. " ›", function() st.page = st.page + 1; MDC.load() end) end
end

local function query(kind)
    local f = W.fields[kind .. ":q"]
    return f and f:getText() or ""
end

------------------------------------------------------------------------ citizens

function MDC.openCitizen(id)
    MDC.data.citizen = nil
    S.tab = "records"
    MDC.go("citizens", { citizen = id })
end

function MDC.openVehicle(id)
    MDC.data.vehicle = nil
    MDC.go("vehicles", { vehicle = id })
end

local function field(x, y, label, value, color, w)
    W.text(L.upper(label), x, y, w or POL.px(180), POL.px(16), C.dim, 8, true)
    W.text(value, x, y + POL.px(16), w or POL.px(180), POL.px(24), color or C.white, 11, true)
end

local function drawCitizen(x, y, w, h)
    local p = MDC.data.citizen
    W.button("cz:back", x, y, POL.px(100), POL.px(28), "‹ " .. L("police_system.mdc.back"), function() MDC.go("citizens") end)
    if not p then W.text(L("police_system.mdc.loading"), x, y + POL.px(40), w, POL.px(30), C.dim, 11) return end
    local cy = y + POL.px(40)
    dxDrawRectangle(x, cy, w, POL.px(150), C.panel)
    W.text(p.name, x + POL.px(16), cy + POL.px(8), w * 0.5, POL.px(34), C.white, 17, true)
    local bx = x + POL.px(16) + math.min(w * 0.5, dxGetTextWidth(p.name, 1, POL.font(17, true))) + POL.px(12)
    if p.kind == "npc" then bx = bx + W.badge("NPC", bx, cy + POL.px(16), C.accentDim) + POL.px(6) end
    local active = 0
    for _, wr in ipairs(p.warrants or {}) do if wr.status == "active" then active = active + 1 end end
    if active > 0 then bx = bx + W.badge("WARRANT", bx, cy + POL.px(16), C.red) + POL.px(6) end
    if (p.wanted or 0) > 0 then bx = bx + W.badge("WANTED " .. ("★"):rep(p.wanted), bx, cy + POL.px(16), tocolor(170, 130, 20, 255)) + POL.px(6) end
    local fy = cy + POL.px(52)
    local fw = (w - POL.px(32)) / 5
    field(x + POL.px(16), fy, L("police_system.mdc.citizen_id"), "#" .. tostring(p.id), nil, fw)
    field(x + POL.px(16) + fw, fy, L("police_system.mdc.birth"), tostring(p.birth or "-") .. (p.age and (" (" .. p.age .. ")") or ""), nil, fw)
    field(x + POL.px(16) + fw * 2, fy, L("police_system.mdc.gender"), L("police_system.mdc.gender_" .. tostring(p.gender or "m")), nil, fw)
    field(x + POL.px(16) + fw * 3, fy, L("police_system.mdc.licence"), L("police_system.query.licence_" .. tostring(p.licence)),
        p.licence == "suspended" and C.red or nil, fw)
    local vtxt = {}
    for i, v in ipairs(p.vehicles or {}) do if i <= 2 then vtxt[#vtxt + 1] = (exports.veh_manager:getModelName(v.model or 0) or "?") .. " · " .. tostring(v.plate) end end
    field(x + POL.px(16) + fw * 4, fy, L("police_system.mdc.vehicles"), #vtxt > 0 and table.concat(vtxt, ", ") or "-", nil, fw)
    if (p.wanted or 0) > 0 then
        local r = {}
        for _, id in ipairs(p.wantedReasons or {}) do r[#r + 1] = L(wantedReasonKey(id)) end
        W.text(L("police_system.mdc.wanted_reasons") .. ": " .. table.concat(r, ", "), x + POL.px(16), fy + POL.px(46), w - POL.px(220), POL.px(24), C.yellow, 9, true)
    end
    W.button("cz:warrant", x + w - POL.px(190), cy + POL.px(112), POL.px(174), POL.px(28), L("police_system.mdc.issue_warrant"),
        function() MDC.warrantForm(p.id, p.name) end, "danger")
    cy = cy + POL.px(160)
    local tabs = { "records", "reports", "warrants", "vehicles" }
    local tx = x
    for _, t in ipairs(tabs) do
        W.button("cz:tab:" .. t, tx, cy, POL.px(170), POL.px(30), L("police_system.mdc.tab_" .. t), function() S.tab = t end, S.tab == t and "active" or nil)
        tx = tx + POL.px(174)
    end
    cy = cy + POL.px(36)
    local rows, cols = {}, nil
    if S.tab == "records" then
        cols = { { L("police_system.mdc.col_date"), 1.4 }, { L("police_system.mdc.col_type"), 0.8 }, { L("police_system.mdc.col_offence"), 3 },
                 { L("police_system.mdc.col_amount"), 1, "right" }, { L("police_system.mdc.col_officer"), 1.6 }, { "", 1 } }
        for _, r in ipairs(p.records or {}) do
            rows[#rows + 1] = { cells = { POL.date(r.at), L.upper(L("police_system.mdc.type_" .. r.type)), L(btkKey(r.btk)),
                r.type == "fine" and POL.money(r.amount) or "-", (r.unit ~= "" and (r.unit .. " ") or "") .. tostring(r.officer or ""),
                function(bx, by, bw, bh)
                    if r.refunded then W.text(L("police_system.mdc.refunded"), bx, by, bw, bh, C.dim, 9)
                    elseif p.canRefund and r.type == "fine" and r.amount > 0 then
                        W.button("rf" .. r.id, bx, by + POL.px(3), bw, bh - POL.px(6), L("police_system.mdc.refund"),
                            function() MDC.call("refund", { id = r.id }, function(ok) if ok then MDC.openCitizen(p.id) end end) end)
                    end
                end }, colors = { C.dim, r.type == "fine" and C.orange or C.accent } }
        end
    elseif S.tab == "reports" then
        cols = { { L("police_system.mdc.col_date"), 1.4 }, { L("police_system.mdc.col_title"), 4 }, { L("police_system.mdc.col_author"), 1.6 }, { L("police_system.mdc.col_lang"), 0.6 } }
        for _, r in ipairs(p.reports or {}) do
            rows[#rows + 1] = { cells = { POL.date(r.at), r.title, (r.unit or "") .. " " .. tostring(r.author or ""), L.upper(r.lang or "") }, id = r.id }
        end
    elseif S.tab == "warrants" then
        cols = { { L("police_system.mdc.col_date"), 1.4 }, { L("police_system.mdc.col_reasons"), 3 }, { L("police_system.mdc.col_description"), 3 },
                 { L("police_system.mdc.col_status"), 1 } }
        for _, wr in ipairs(p.warrants or {}) do
            local rs = {}
            for _, id in ipairs(wr.reasons or {}) do rs[#rs + 1] = id:find("%.") and L(btkKey(id)) or L(wantedReasonKey(id)) end
            rows[#rows + 1] = { cells = { POL.date(wr.at), table.concat(rs, ", "), wr.description, L("police_system.mdc.status_" .. tostring(wr.status)) },
                colors = { C.dim, wr.status == "active" and C.red or C.dim } }
        end
    else
        cols = { { L("police_system.mdc.col_plate"), 1.4 }, { L("police_system.mdc.col_model"), 2 } }
        for _, v in ipairs(p.vehicles or {}) do
            rows[#rows + 1] = { cells = { tostring(v.plate), exports.veh_manager:getModelName(v.model or 0) or "?" }, id = v.id }
        end
    end
    W.table("cz:" .. S.tab, x, cy, w, y + h - cy, cols, rows, function(r)
        if S.tab == "reports" and r.id then MDC.openReport(r.id, true)
        elseif S.tab == "vehicles" and r.id then MDC.openVehicle(r.id) end
    end, POL.px(30))
end

MDC.pages.citizens = {
    load = function()
        local v = MDC.view
        if v and v.citizen then
            MDC.call("citizen", { id = v.citizen }, function(d) MDC.data.citizen = d end)
            return
        end
        local st = S.citizens
        MDC.call("citizens", { filter = st.filter, q = query("citizens"), page = st.page }, function(d) MDC.data.citizens = d end)
    end,
    draw = function(x, y, w, h)
        if MDC.view and MDC.view.citizen then return drawCitizen(x, y, w, h) end
        W.text(L("police_system.mdc.menu_citizens"), x, y, w, POL.px(30), C.white, 15, true)
        filterBar("citizens", x, y + POL.px(36))
        local d = MDC.data.citizens or { rows = {} }
        local rows = {}
        for _, r in ipairs(d.rows or {}) do
            local flags = {}
            if (r.warrants or 0) > 0 then flags[#flags + 1] = "WARRANT" end
            if (r.wanted or 0) > 0 then flags[#flags + 1] = "WANTED " .. ("★"):rep(r.wanted) end
            rows[#rows + 1] = { cells = { r.name, r.kind == "npc" and "NPC" or L("police_system.mdc.player"), "#" .. r.id, tostring(r.birth or "-"),
                table.concat(flags, "  ") }, colors = { nil, C.dim, C.dim, C.dim, C.red }, id = r.id }
        end
        local ty = y + POL.px(76)
        W.table("citizens", x, ty, w, y + h - ty - POL.px(40), { { L("police_system.mdc.col_name"), 3 }, { L("police_system.mdc.col_type"), 1 },
            { L("police_system.mdc.citizen_id"), 1 }, { L("police_system.mdc.birth"), 1.4 }, { "", 2 } }, rows, function(r) MDC.openCitizen(r.id) end)
        pager("citizens", x, y + h - POL.px(32), w, d.more)
    end,
}

------------------------------------------------------------------------ vehicles

local function drawVehicle(x, y, w, h)
    local v = MDC.data.vehicle
    W.button("vh:back", x, y, POL.px(100), POL.px(28), "‹ " .. L("police_system.mdc.back"), function() MDC.go("vehicles") end)
    if not v then W.text(L("police_system.mdc.loading"), x, y + POL.px(40), w, POL.px(30), C.dim, 11) return end
    local cy = y + POL.px(40)
    dxDrawRectangle(x, cy, w, POL.px(130), C.panel)
    W.text(tostring(v.plate or "-"), x + POL.px(16), cy + POL.px(8), w * 0.4, POL.px(34), C.white, 17, true)
    local bx = x + POL.px(16) + dxGetTextWidth(tostring(v.plate or "-"), 1, POL.font(17, true)) + POL.px(12)
    if v.kind == "npc" then bx = bx + W.badge("NPC", bx, cy + POL.px(16), C.accentDim) + POL.px(6) end
    if v.stolen then bx = bx + W.badge("STOLEN", bx, cy + POL.px(16), C.red) + POL.px(6) end
    if v.owner and (v.owner.warrants or 0) > 0 then W.badge("OWNER WARRANT", bx, cy + POL.px(16), C.red) end
    local fw = (w - POL.px(32)) / 5
    local fy = cy + POL.px(52)
    field(x + POL.px(16), fy, L("police_system.mdc.col_model"), exports.veh_manager:getModelName(v.model or 0) or "?", nil, fw)
    field(x + POL.px(16) + fw, fy, L("police_system.query.owner"), v.owner and v.owner.name or "-", nil, fw)
    field(x + POL.px(16) + fw * 2, fy, L("police_system.query.registration"), tostring(v.registration), nil, fw)
    field(x + POL.px(16) + fw * 3, fy, L("police_system.query.inspection"), tostring(v.inspection),
        tostring(v.inspection):find("expired") and C.red or nil, fw)
    if v.owner then
        W.button("vh:owner", x + w - POL.px(190), cy + POL.px(92), POL.px(174), POL.px(28), L("police_system.mdc.open_owner"),
            function() MDC.openCitizen(v.owner.id) end)
    end
    cy = cy + POL.px(140)
    local rows = {}
    for _, r in ipairs(v.records or {}) do
        rows[#rows + 1] = { cells = { POL.date(r.at), L.upper(L("police_system.mdc.type_" .. r.type)), L(btkKey(r.btk)),
            r.type == "fine" and POL.money(r.amount) or "-", (r.unit or "") .. " " .. tostring(r.officer or "") }, colors = { C.dim } }
    end
    W.table("vh:records", x, cy, w, y + h - cy, { { L("police_system.mdc.col_date"), 1.4 }, { L("police_system.mdc.col_type"), 0.8 },
        { L("police_system.mdc.col_offence"), 3 }, { L("police_system.mdc.col_amount"), 1, "right" }, { L("police_system.mdc.col_officer"), 1.6 } }, rows)
end

MDC.pages.vehicles = {
    load = function()
        local v = MDC.view
        if v and v.vehicle then
            MDC.call("vehicle", { id = v.vehicle }, function(d) MDC.data.vehicle = d end)
            return
        end
        local st = S.vehicles
        MDC.call("vehicles", { filter = st.filter, q = query("vehicles"), page = st.page }, function(d) MDC.data.vehicles = d end)
    end,
    draw = function(x, y, w, h)
        if MDC.view and MDC.view.vehicle then return drawVehicle(x, y, w, h) end
        W.text(L("police_system.mdc.menu_vehicles"), x, y, w, POL.px(30), C.white, 15, true)
        filterBar("vehicles", x, y + POL.px(36))
        local d = MDC.data.vehicles or { rows = {} }
        local rows = {}
        for _, r in ipairs(d.rows or {}) do
            rows[#rows + 1] = { cells = { tostring(r.plate or "-"), exports.veh_manager:getModelName(r.model or 0) or "?", r.owner,
                r.kind == "npc" and "NPC" or L("police_system.mdc.player"), r.stolen and "STOLEN" or "" },
                colors = { nil, nil, nil, C.dim, C.red }, id = r.id }
        end
        local ty = y + POL.px(76)
        W.table("vehicles", x, ty, w, y + h - ty - POL.px(40), { { L("police_system.mdc.col_plate"), 1.4 }, { L("police_system.mdc.col_model"), 1.6 },
            { L("police_system.query.owner"), 2.4 }, { L("police_system.mdc.col_type"), 1 }, { "", 1 } }, rows, function(r) MDC.openVehicle(r.id) end)
        pager("vehicles", x, y + h - POL.px(32), w, d.more)
    end,
}
