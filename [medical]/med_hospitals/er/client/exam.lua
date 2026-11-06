-- The hospital patient panel (plan: Kórházi betegvizsgálati panel), 1280x720 design size, scaled.
--   bedside (patient menu "Betegvizsgálat", in range): every exam step, procedures, drugs
--   remote (PC / tablet): orders, results, drugs ordered, documentation, diagnoses, outcome
-- Header: triage, name, age, sex, weight, birth date, case number, treating, place, time in the ER,
-- blood group, allergy. Left: body map (front / back). Middle: vitals strip (only measured values),
-- tabs. Right: orders, drug orders, diagnoses (max 5), quick buttons.

EXAM = { open = false, caseId = nil, bedside = false, tab = "exam", side = "front", drugPick = nil, viewer = nil,
         bno = nil, progress = {} }

local s = HGfx.s
local T = HTheme
local function t(key, p) return L("med_hospitals.his." .. key, p) end
local function x_(key, p) return L("med_hospitals.exam." .. key, p) end
local function act(...) if EXAM.caseId then HIS.act(EXAM.caseId, ...) end end

-- the documentation tab only on the PC (the tablet keeps the modern design, without documentation)
local TABS_PC = { "exam", "orders", "treat", "drugs", "transfusion", "docs", "place", "log" }
local TABS_TABLET = { "exam", "orders", "treat", "drugs", "transfusion", "place", "log" }
local function tabs() return EXAM.source == "pc" and TABS_PC or TABS_TABLET end
local DESIGN_W, DESIGN_H = 1280, 720

---------------------------------------------------------------- open / close

-- source: "pc" (hospital PC), "tablet" (J tablet) or "bedside" (patient menu); only the PC documents
function EXAM.show(caseId, bedside, source)
    if not HIS.isStaff() then return end
    EXAM.open, EXAM.caseId, EXAM.bedside = true, caseId, bedside == true
    EXAM.source = source or (bedside and "bedside" or (HIS.open and HIS.mode) or "tablet")
    EXAM.viewer, EXAM.bno, EXAM.drugPick, EXAM.transfer, EXAM.death = nil, nil, nil, nil, nil
    if EXAM.tab == "docs" and EXAM.source ~= "pc" then EXAM.tab = "place" end
    EXAM.case = (HIS.case and HIS.case.id == caseId) and HIS.case or nil
    if not EXAM.bedside and EXAM.tab == "exam" then EXAM.tab = "orders" end
    showCursor(true)
    HIS.send("case", caseId)
    if not HIS.drugs then HIS.send("drugs") end
    -- on the PC: the "Beteglap" window (w7.lua)
    if EXAM.source == "pc" and PCS and PCS.open then PCS.openWindow("case") end
end

function EXAM.close()
    if not EXAM.open then return end
    local inPC = EXAM.inPC()
    EXAM.open = false
    if inPC then return PCS.closeWindow("case", true) end
    if not HIS.open and not (PCS and PCS.open) then showCursor(false) end
end

function EXAM.onCase(c)
    if not EXAM.open then return end
    if c and c.id == EXAM.caseId then EXAM.case = c elseif not c then EXAM.close() end
end

-- the patient menu (ui_interactobject) "Betegvizsgálat" item opens it at the bedside
addEvent("his:openExam", true)
addEventHandler("his:openExam", resourceRoot, function(caseId) HIS.hide() EXAM.show(caseId, true, "bedside") end)

addEvent("his:examProgress", true)
addEventHandler("his:examProgress", resourceRoot, function(caseId, key, secs)
    EXAM.progress[key] = { ends = getTickCount() + secs * 1000, total = secs * 1000 }
end)

-- leaving the bedside turns it into the remote view
setTimer(function()
    if not EXAM.open or not EXAM.bedside then return end
    local c = EXAM.case
    if not c then return end
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        local v = getElementData(ped, "er.case")
        if type(v) == "table" and v.id == c.id then
            local px, py, pz = getElementPosition(localPlayer)
            local x, y, z = getElementPosition(ped)
            if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > 4.0 then EXAM.bedside = false end
            return
        end
    end
end, 1000, 0)

---------------------------------------------------------------- frame

local function frame()
    local sc = math.min((HGfx.screenW - s(30)) / s(DESIGN_W), (HGfx.screenH - s(30)) / s(DESIGN_H), 1)
    local w, h = s(DESIGN_W) * sc, s(DESIGN_H) * sc
    return (HGfx.screenW - w) / 2, (HGfx.screenH - h) / 2, w, h
end

---------------------------------------------------------------- header

local function drawHeader(c, x, y, w)
    local h = s(64)
    HGfx.round(x, y, w, h, s(8), T.header)
    dxDrawRectangle(x, y + h - s(8), w, s(8), T.header)
    dxDrawRectangle(x, y + h - 1, w, 1, T.line)
    HGfx.button(x + s(10), y + s(14), s(36), s(36), "‹", { color = { 40, 48, 58 }, font = HGfx.font(15, true) }, function()
        EXAM.close()
        if not HIS.open and not EXAM.bedside then HIS.show(HIS.mode) end
    end)
    HIS.tooltip(x + s(10), y + s(14), s(36), s(36), t("back"))
    HIS.triBadge(x + s(56), y + s(16), s(40), s(32), c.triage)
    HGfx.text(c.name or t("unknown"), x + s(106), y + s(6), w * 0.4, s(28), T.text, HGfx.font(15, true))
    local sub = {}
    if c.age then sub[#sub + 1] = t("age_years", { n = c.age }) end
    sub[#sub + 1] = t("gender_" .. tostring(c.gender))
    if c.weight then sub[#sub + 1] = c.weight .. " kg" end
    if c.birth then sub[#sub + 1] = t("born", { d = tostring(c.birth):gsub("-", ".") }) end
    sub[#sub + 1] = t("case_no", { n = c.id })
    HGfx.text(table.concat(sub, " · "), x + s(106), y + s(34), w * 0.45, s(22), T.dim, HGfx.font(9))
    -- top right: close (the whole panel, as the last ESC)
    local right = x + w - s(10)
    if not EXAM.inPC() then
        HGfx.button(x + w - s(46), y + s(14), s(36), s(36), "X", { color = { 90, 40, 46 }, font = HGfx.font(12, true) }, function() EXAM.close() end)
        HIS.tooltip(x + w - s(46), y + s(14), s(36), s(36), t("close"))
        right = x + w - s(52)
    end
    -- right side: key facts as small boxes
    local facts = {
        { t("fact_treating"), c.treating or "—" }, { t("fact_place"), tostring(c.location or "-") },
        { t("fact_time"), t("min_short", { n = HIS.mins(c.timeIn) }) },
        { t("fact_blood"), c.bloodGroup or "?" },
    }
    local fx = right
    for i = #facts, 1, -1 do
        local f = facts[i]
        local fw = math.max(L.width(f[2], 1, HGfx.font(10, true)), L.width(f[1], 1, HGfx.font(8))) + s(20)
        fx = fx - fw - s(6)
        HGfx.round(fx, y + s(12), fw, s(40), s(6), T.panel)
        HGfx.text(f[1], fx + s(10), y + s(14), fw, s(16), T.faint, HGfx.font(8))
        HGfx.text(f[2], fx + s(10), y + s(30), fw - s(14), s(20), T.text, HGfx.font(10, true))
    end
    if c.allergy and c.allergy ~= "none" then
        local label = t("allergy", { what = x_("allergy_name_" .. c.allergy) })
        local aw = L.width(label, 1, HGfx.font(9, true)) + s(20)
        HGfx.round(fx - aw - s(8), y + s(20), aw, s(24), s(12), tocolor(120, 40, 36))
        HGfx.text(label, fx - aw - s(8), y + s(20), aw, s(24), T.text, HGfx.font(9, true), "center")
    end
    return h
end

---------------------------------------------------------------- body map

-- regions drawn as boxes on a 100 x 220 figure: { id, x, y, w, h, part, side }
local FRONT = {
    { "head", 38, 0, 24, 24, "head" }, { "neck", 44, 24, 12, 8, "neck" },
    { "chest_r", 30, 32, 20, 28, "chest", "right" }, { "chest_l", 50, 32, 20, 28, "chest", "left" },
    { "abd_r", 32, 60, 18, 26, "abdomen", "right" }, { "abd_l", 50, 60, 18, 26, "abdomen", "left" },
    { "pelvis", 32, 86, 36, 16, "pelvis" },
    { "arm_r", 14, 34, 14, 66, "arm", "right" }, { "arm_l", 72, 34, 14, 66, "arm", "left" },
    { "leg_r", 33, 104, 16, 104, "leg", "right" }, { "leg_l", 51, 104, 16, 104, "leg", "left" },
}
local BACK = {
    { "head", 38, 0, 24, 24, "head" }, { "spine_c", 44, 24, 12, 10, "spine_c" },
    { "spine_t", 42, 34, 16, 34, "spine_t" }, { "spine_l", 42, 68, 16, 20, "spine_l" },
    { "back_l", 28, 34, 14, 52, "chest", "left" }, { "back_r", 58, 34, 14, 52, "chest", "right" },
    { "pelvis", 32, 88, 36, 16, "pelvis" },
    { "arm_l", 14, 34, 14, 66, "arm", "left" }, { "arm_r", 72, 34, 14, 66, "arm", "right" },
    { "leg_l", 33, 106, 16, 102, "leg", "left" }, { "leg_r", 51, 106, 16, 102, "leg", "right" },
}

local function partState(c, part, side)
    local st = nil
    for _, f in ipairs(c.findings or {}) do
        if f.part == part and (not side or not f.side or f.side == side) then
            st = f.treated and (st or "treated") or "hot"
        end
    end
    return st
end

local function drawBodyMap(c, x, y, w, h)
    HGfx.button(x, y, w / 2 - s(2), s(24), t("map_front"), { color = EXAM.side == "front" and { 47, 134, 232 } or { 34, 40, 48 }, font = HGfx.font(8, true) }, function() EXAM.side = "front" end)
    HGfx.button(x + w / 2 + s(2), y, w / 2 - s(2), s(24), t("map_back"), { color = EXAM.side == "back" and { 47, 134, 232 } or { 34, 40, 48 }, font = HGfx.font(8, true) }, function() EXAM.side = "back" end)
    local list = EXAM.side == "front" and FRONT or BACK
    local fh = h - s(90)
    local sc = math.min(w / 100, fh / 215)
    local ox = x + (w - 100 * sc) / 2
    local oy = y + s(32)
    for _, r in ipairs(list) do
        local st = partState(c, r[6], r[7])
        local col = st == "hot" and tocolor(150, 50, 44) or (st == "treated" and tocolor(40, 100, 70) or tocolor(42, 50, 59))
        local rx, ry, rw, rh = ox + r[2] * sc, oy + r[3] * sc, r[4] * sc, r[5] * sc
        HGfx.round(rx, ry, rw, rh, s(4), col)
        local label = L("medsys.body." .. r[6]) .. (r[7] and (" (" .. L("medsys.body." .. r[7]) .. ")") or "")
        HIS.tooltip(rx, ry, rw, rh, label)
    end
    local ly = y + h - s(52)
    HGfx.round(x, ly, s(12), s(12), s(2), tocolor(150, 50, 44)) HGfx.text(t("map_finding"), x + s(18), ly - s(2), w, s(16), T.dim, HGfx.font(8))
    HGfx.round(x, ly + s(18), s(12), s(12), s(2), tocolor(40, 100, 70)) HGfx.text(t("map_treated"), x + s(18), ly + s(16), w, s(16), T.dim, HGfx.font(8))
    HGfx.round(x, ly + s(36), s(12), s(12), s(2), tocolor(42, 50, 59)) HGfx.text(t("map_none"), x + s(18), ly + s(34), w, s(16), T.dim, HGfx.font(8))
end

---------------------------------------------------------------- vitals strip

local function drawVitals(c, x, y, w)
    local v, m = c.vitals or {}, c.measured or {}
    local mon = c.monitor
    local hr = mon and v.hr or m.hr
    local bp = mon and v.bp or m.bp
    local spo2 = mon and v.spo2 or m.spo2
    local items = {
        { "HR", hr or "–", { 70, 211, 122 } }, { t("v_bp"), bp or "–", { 233, 237, 242 } }, { "SpO₂", spo2 and (spo2 .. "%") or "–", { 79, 208, 255 } },
        { t("v_rr"), m.rr or "–", { 233, 237, 242 } }, { "EtCO₂", (mon and v.etco2) or "–", { 230, 210, 90 } },
        { "T", c.temperature and string.format("%.1f", c.temperature) or "–", { 233, 237, 242 } },
        { "GCS", c.gcs or "–", { 233, 237, 242 } }, { "NRS", c.nrs and (c.nrs .. "/10") or "–", { 255, 138, 122 } },
    }
    local h = s(48)
    HGfx.round(x, y, w, h, s(6), tocolor(0, 0, 0, 220))
    local iw = w / #items
    for i, it in ipairs(items) do
        local ix = x + (i - 1) * iw
        HGfx.text(it[1], ix + s(10), y + s(3), iw, s(14), T.faint, HGfx.font(8))
        HGfx.text(tostring(it[2]), ix + s(10), y + s(16), iw - s(12), s(30), HGfx.rgb(it[3]), HGfx.font(14, true))
    end
    local src = mon and t("vitals_monitor") or (m.at and t("vitals_measured", { t = HIS.hhmm(m.at) }) or t("vitals_none"))
    HIS.tooltip(x, y, w, h, src)
    return h
end

---------------------------------------------------------------- tab: exam

local function method(c, region, mth, x, y)
    local key = region .. ":" .. mth
    local done = c.exam and c.exam[key]
    local label = x_("m_" .. mth)
    local w = L.width(label, 1, HGfx.font(8, true)) + s(16)
    local prog = EXAM.progress[key]
    local busy = prog and getTickCount() < prog.ends
    local col = done and { 31, 77, 54 } or { 45, 53, 63 }
    HGfx.button(x, y, w, s(20), label, { color = col, disabled = not EXAM.bedside or busy, font = HGfx.font(8, true) }, function() act("exam", region, mth) end)
    if busy then
        local f = 1 - (prog.ends - getTickCount()) / prog.total
        dxDrawRectangle(x, y + s(18), w * f, s(2), T.accent)
    end
    if not EXAM.bedside then HIS.tooltip(x, y, w, s(20), t("bedside_only")) end
    return w
end

local REGION_METHODS = {
    vitals = { "measure" }, head = { "inspect", "palpate" }, chest = { "inspect", "palpate", "auscultate", "percuss" },
    abdomen = { "inspect", "palpate", "auscultate" }, limbs = { "inspect", "palpate", "cms" }, spine = { "inspect", "palpate" },
    neuro = { "gcs", "pupils", "nihss", "strength", "befast" }, skin = { "inspect", "temp" }, pain = { "nrs" },
    history = { "anamnesis", "meds", "allergy", "lastmeal", "event" },
}
local REGIONS = { "vitals", "head", "chest", "abdomen", "limbs", "spine", "neuro", "skin", "pain", "history" }

local function lineText(ln)
    local p = {}
    for k, v in pairs(ln[2] or {}) do p[k] = v end
    if p.side then p.side = x_("side_" .. p.side) end
    if p.part then p.part = x_("part_" .. p.part) end
    if p.level then p.level = x_("level_" .. p.level) end
    return x_(ln[1], p)
end

local function drawExam(c, x, y, w, h)
    local colW = (w - s(10)) / 2
    local cols = { y, y }
    local off = HGfx.getScroll("exam", 30)
    HGfx.scrollArea("exam", x, y, w, h)
    local skip = off * s(20)
    for i, region in ipairs(REGIONS) do
        local col = (i % 2 == 1) and 1 or 2
        local cx = x + (col - 1) * (colW + s(10))
        -- card height from the result lines
        local resLines = {}
        for _, mth in ipairs(REGION_METHODS[region]) do
            local e = c.exam and c.exam[region .. ":" .. mth]
            for _, ln in ipairs(e and e.lines or {}) do
                for _, wl in ipairs(HGfx.wrap("• " .. lineText(ln), colW - s(20), HGfx.font(9))) do resLines[#resLines + 1] = wl end
            end
        end
        local ch = s(52) + math.max(1, #resLines) * s(15)
        local cy = cols[col] - skip
        if cy + ch > y and cy < y + h then
            HGfx.round(cx, cy, colW, ch, s(6), T.panel)
            HGfx.text(x_("r_" .. region), cx + s(10), cy + s(4), colW, s(18), T.text, HGfx.font(10, true))
            local mx = cx + s(10)
            for _, mth in ipairs(REGION_METHODS[region]) do
                local mw = method(c, region, mth, mx, cy + s(24))
                mx = mx + mw + s(4)
            end
            if #resLines == 0 then HGfx.text(t("not_examined"), cx + s(10), cy + s(48), colW, s(15), T.faint, HGfx.font(9)) end
            for li, ln in ipairs(resLines) do
                local ly = cy + s(48) + (li - 1) * s(15)
                if ly > y and ly < y + h - s(10) then HGfx.text(ln, cx + s(10), ly, colW - s(16), s(15), T.text, HGfx.font(9)) end
            end
        end
        cols[col] = cols[col] + ch + s(8)
    end
end

---------------------------------------------------------------- tab: orders (+ results)

local function orderName(key) return L("med_hospitals.erc.order_" .. tostring(key):gsub("%.", "_")) end

local function drawOrders(c, x, y, w, h)
    local by = y
    for _, kind in ipairs({ "lab", "xray", "ct", "fast", "ecg" }) do
        HGfx.text(t("order_group_" .. kind), x, by, s(90), s(26), T.faint, HGfx.font(8, true))
        local bx = x + s(94)
        for _, o in ipairs(ERC.ORDERS[kind]) do
            local label = L("med_hospitals.erc.order_" .. o.key:gsub("%.", "_") .. "_short")
            local ind = c.indications and c.indications[o.key]
            local bw = L.width(label, 1, HGfx.font(9, true)) + s(30)
            if bx + bw > x + w then bx = x + s(94) by = by + s(28) end
            local picking = EXAM.sidePick == o.key
            HGfx.button(bx, by + s(2), bw, s(22), label, { color = picking and { 47, 134, 232 } or { 38, 46, 56 }, font = HGfx.font(9, true), align = "left" }, function()
                if o.sided then EXAM.sidePick = picking and nil or o.key else act("order", o.key) end
            end)
            if not o.sided then
                HGfx.text(ind and "✓" or "!", bx + bw - s(18), by + s(2), s(14), s(22), ind and tocolor(63, 179, 122) or tocolor(229, 160, 58), HGfx.font(10, true), "center")
                HIS.tooltip(bx, by + s(2), bw, s(22), ind and t("indicated") or t("not_indicated_tip"))
            else
                HGfx.text("◂▸", bx + bw - s(20), by + s(2), s(16), s(22), T.dim, HGfx.font(8, true), "center")
                HIS.tooltip(bx, by + s(2), bw, s(22), t("pick_side_tip"))
            end
            bx = bx + bw + s(4)
            if picking then
                for _, sd in ipairs({ "left", "right" }) do
                    local sl = L("medsys.body." .. sd)
                    local sw = L.width(sl, 1, HGfx.font(9, true)) + s(16)
                    if bx + sw > x + w then bx = x + s(94) by = by + s(28) end
                    HGfx.button(bx, by + s(2), sw, s(22), sl, { color = { 47, 134, 232 }, font = HGfx.font(9, true) }, function()
                        EXAM.sidePick = nil
                        act("order", o.key, sd)
                    end)
                    bx = bx + sw + s(4)
                end
            end
        end
        by = by + s(30)
    end
    by = by + s(4)
    HGfx.text(t("orders_list"), x, by, w, s(18), T.faint, HGfx.font(8, true))
    by = by + s(20)
    local list = c.orders or {}
    local rowH = s(30)
    local visible = math.floor((y + h - by) / rowH)
    local off = HGfx.getScroll("orders", #list - visible)
    HGfx.scrollArea("orders", x, by, w, y + h - by)
    for i = 1, math.min(visible, #list - off) do
        local o = list[#list - off - i + 1]
        local ry = by + (i - 1) * rowH
        HGfx.round(x, ry, w, rowH - s(4), s(5), T.panel)
        local status = t("ord_" .. tostring(o.status))
        local name = orderName(o.key) .. (o.side and (" (" .. L("medsys.body." .. o.side) .. ")") or "")
        HGfx.text(("%s  ·  %s  ·  %s%s"):format(name, status, o.by or "", o.indicated and "" or ("  · " .. t("not_indicated"))),
            x + s(10), ry, w - s(130), rowH - s(4), o.indicated and T.text or tocolor(229, 160, 58), HGfx.font(9))
        if o.status == "ordered" then
            HGfx.button(x + w - s(112), ry + s(3), s(106), rowH - s(10), t("perform"), { color = { 47, 134, 232 }, font = HGfx.font(9, true) }, function() act("perform", o.id) end)
        elseif o.status == "done" and o.resultId then
            HGfx.button(x + w - s(112), ry + s(3), s(106), rowH - s(10), t("view_result"), { color = { 31, 77, 54 }, font = HGfx.font(9, true) }, function()
                for _, r in ipairs(c.results or {}) do if r.id == o.resultId then EXAM.viewer = { result = r, index = 1 } end end
            end)
        end
    end
end

---------------------------------------------------------------- tab: procedures / room treatments

-- ICU / shock room: ventilator, noradrenaline, sedation, rounds, blood gas (er/server/icu.lua)
local function drawIcu(c, x, y, w)
    local v = c.icu
    if not v then return y end
    local by = y
    HGfx.round(x, by, w, s(118), s(6), T.panel)
    HGfx.text(t("icu_title"), x + s(10), by + s(4), w * 0.5, s(18), T.faint, HGfx.font(8, true))
    local dis = not EXAM.bedside
    local function btn(bx, byy, bw, label, color, fn) HGfx.button(bx, byy, bw, s(22), label, { color = color or { 45, 53, 63 }, font = HGfx.font(8, true), disabled = dis }, fn) end
    local right = x + w - s(10)
    btn(right - s(120), by + s(4), s(120), (v.icu and v.nextVisit > 0) and t("icu_visit_in", { s = v.nextVisit }) or t("icu_visit"), { 47, 134, 232 }, function() act("icu", "visit") end)
    btn(right - s(246), by + s(4), s(120), t("icu_abg"), nil, function() act("icu", "abg") end)
    local vy = by + s(30)
    local vent = v.vent or { mode = "VC", fio2 = 60, peep = 5, rr = 14, vt = 450 }
    if not v.intubated then
        HGfx.text(t("icu_not_intubated"), x + s(10), vy, w * 0.5, s(22), T.dim, HGfx.font(9))
    else
        HGfx.text(t("icu_vent", { mode = vent.mode, spo2 = v.spo2Target or "-", etco2 = v.etco2 or "-", mv = v.mv or "-" }), x + s(10), vy, w, s(22), v.vent and T.text or T.dim, HGfx.font(9, true))
        local cx = x + s(10)
        vy = vy + s(24)
        btn(cx, vy, s(44), vent.mode == "VC" and "PC" or "VC", nil, function() act("icu", "vent", { mode = vent.mode == "VC" and "PC" or "VC" }) end)
        cx = cx + s(50)
        for _, k in ipairs({ "fio2", "peep", "rr", "vt" }) do
            local lim = v.limits and v.limits[k] or { 0, 100, 1 }
            HGfx.text(t("icu_" .. k, { v = vent[k] }), cx, vy, s(78), s(22), T.text, HGfx.font(8), "center")
            btn(cx + s(80), vy, s(22), "-", nil, function() act("icu", "vent", { [k] = vent[k] - lim[3] }) end)
            btn(cx + s(104), vy, s(22), "+", nil, function() act("icu", "vent", { [k] = vent[k] + lim[3] }) end)
            cx = cx + s(134)
        end
    end
    local ny = by + s(84)
    HGfx.text(t("icu_norad", { rate = v.norad, map = v.map, target = v.targetMap }), x + s(10), ny, s(250), s(22), T.text, HGfx.font(9))
    local steps = v.noradSteps or { 0 }
    local idx = 1
    for i, r in ipairs(steps) do if math.abs(r - v.norad) < 0.001 then idx = i end end
    btn(x + s(262), ny, s(22), "-", nil, function() act("icu", "norad", steps[math.max(1, idx - 1)]) end)
    btn(x + s(286), ny, s(22), "+", nil, function() act("icu", "norad", steps[math.min(#steps, idx + 1)]) end)
    local sx = x + s(330)
    HGfx.text(t("icu_sedation"), sx, ny, s(70), s(22), T.faint, HGfx.font(8, true))
    for lvl = 0, 2 do
        btn(sx + s(72) + lvl * s(84), ny, s(80), t("icu_sed_" .. lvl), v.sedation == lvl and { 47, 134, 232 } or nil, function() act("icu", "sedation", lvl) end)
    end
    return by + s(126)
end

local function drawTreat(c, x, y, w, h)
    local by = drawIcu(c, x, y, w)
    HGfx.text(t("treat_findings"), x, by, w, s(18), T.faint, HGfx.font(8, true))
    by = by + s(20)
    local any = false
    for _, f in ipairs(c.findings or {}) do
        local d = ERC.FINDINGS[f.id]
        if d and not f.treated then
            local opts = {}
            if d.suture then opts[#opts + 1] = f.irrigated and "suture" or "irrigate" end
            if d.reduction and not f.reduced then opts[#opts + 1] = "reduction" end
            if d.cast and (not d.reduction or f.reduced) then opts[#opts + 1] = "cast" end
            if d.drain then opts[#opts + 1] = "drain" end
            if d.region == "skin" then opts[#opts + 1] = "burn_dressing" end
            if #opts > 0 then
                any = true
                HGfx.round(x, by, w, s(32), s(5), T.panel)
                HGfx.text(("%s  %s"):format(exports.med_docs:getBNOCode(d.bno), L("med_hospitals.erc.finding_" .. f.id)), x + s(10), by, w * 0.5, s(32), T.text, HGfx.font(9))
                local bx = x + w
                for j = #opts, 1, -1 do
                    local label = L("med_hospitals.erc.treat_" .. opts[j])
                    local bw = L.width(label, 1, HGfx.font(9, true)) + s(18)
                    bx = bx - bw - s(6)
                    HGfx.button(bx, by + s(5), bw, s(22), label, { color = { 47, 134, 232 }, font = HGfx.font(9, true), disabled = not EXAM.bedside },
                        function() act("treat", opts[j], f.index) end)
                    if not EXAM.bedside then HIS.tooltip(bx, by + s(5), bw, s(22), t("bedside_only")) end
                end
                by = by + s(36)
            end
        end
    end
    if not any then HGfx.text(t("no_treatments"), x, by, w, s(20), T.faint, HGfx.font(9)) by = by + s(24) end
    -- room procedures (er/server/procedures.lua): rank, room, consumable; grey = the reason as tooltip
    HGfx.text(t("treat_procedures"), x, by + s(6), w, s(18), T.faint, HGfx.font(8, true))
    by = by + s(28)
    local procs = c.procedures or {}
    local colW = (w - s(8)) / 2
    for i, p in ipairs(procs) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local px, py = x + col * (colW + s(8)), by + row * s(34)
        if py > y + h - s(34) then break end
        local ok = p.available == true
        HGfx.button(px, py, colW, s(30), L("med_hospitals.proc." .. p.id), { color = ok and { 38, 46, 56 } or { 30, 34, 40 }, disabled = not ok or not EXAM.bedside,
            align = "left", font = HGfx.font(9, true) }, function() act("procedure", p.id) end)
        HGfx.text(p.rank and L("work_hospital.comp." .. p.rank) or "", px, py, colW - s(10), s(30), T.faint, HGfx.font(8), "right")
        if not ok then HIS.tooltip(px, py, colW, s(30), tostring(p.available)) elseif not EXAM.bedside then HIS.tooltip(px, py, colW, s(30), t("bedside_only")) end
    end
    if #procs == 0 then HGfx.text(t("no_procedures"), x, by, w, s(20), T.faint, HGfx.font(9)) end
    HGfx.button(x, y + h - s(32), s(260), s(30), t("open_medsys"), { color = { 47, 134, 232 }, disabled = not EXAM.bedside, font = HGfx.font(9, true) }, function()
        EXAM.close()
        act("medsys")
    end)
end

---------------------------------------------------------------- tab: drugs

local function drugDose(d, opt)
    if not opt then return "" end
    return ("%s %s%s"):format(tostring(opt.dose), d.dosing.unit, d.dosing.perKg and "/kg" or "")
end

local function drawDrugs(c, x, y, w, h)
    local drugs = HIS.drugs or {}
    local listW = w * 0.62
    local colW = (listW - s(8)) / 2
    local rowH = s(44)
    local visible = math.floor(h / rowH) * 2
    local off = HGfx.getScroll("drugs", math.ceil((#drugs - visible) / 2)) * 2
    HGfx.scrollArea("drugs", x, y, listW, h)
    for i = 1, math.min(visible, #drugs - off) do
        local d = drugs[i + off]
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local dx, dy = x + col * (colW + s(8)), y + row * rowH
        local on = EXAM.drugPick == d.id
        local hov = HGfx.hover(dx, dy, colW, rowH - s(4))
        HGfx.round(dx, dy, colW, rowH - s(4), s(6), on and tocolor(30, 70, 120) or (hov and T.panel2 or T.panel))
        HGfx.text(HGfx.fit(d.name, colW - s(16), HGfx.font(9, true)), dx + s(8), dy + s(2), colW - s(12), s(20), T.text, HGfx.font(9, true))
        HGfx.text(HGfx.fit((d.class and L(d.class) or "") .. "  ·  " .. x_("route_" .. tostring(d.route)), colW - s(16), HGfx.font(8)), dx + s(8), dy + s(20), colW - s(12), s(18), T.dim, HGfx.font(8))
        HGfx.hit(dx, dy, colW, rowH - s(4), function() EXAM.drugPick = on and nil or d.id end)
    end
    -- right: the picked drug (dose options, order / give) and the drug orders
    local rx, rw = x + listW + s(12), w - listW - s(12)
    local pick
    for _, d in ipairs(drugs) do if d.id == EXAM.drugPick then pick = d end end
    local ry = y
    if pick then
        HGfx.round(rx, ry, rw, s(150), s(6), T.panel)
        HGfx.text(pick.name, rx + s(10), ry + s(4), rw, s(22), T.text, HGfx.font(11, true))
        local lines = HGfx.wrap(pick.desc and L(pick.desc) or "", rw - s(20), HGfx.font(8))
        for i = 1, math.min(2, #lines) do HGfx.text(lines[i], rx + s(10), ry + s(24) + (i - 1) * s(14), rw, s(14), T.dim, HGfx.font(8)) end
        if c.allergy and c.allergy ~= "none" and x_("allergy_drugs_" .. c.allergy):find(pick.id, 1, true) then
            HGfx.text(t("allergy_warning"), rx + s(10), ry + s(54), rw, s(16), tocolor(255, 120, 110), HGfx.font(9, true))
        end
        local by = ry + s(72)
        local bx = rx + s(10)
        local opts = pick.dosing and pick.dosing.options or { false }
        for idx, opt in ipairs(opts) do
            local label = opt and (drugDose(pick, opt) .. (opt.high and " !" or "")) or t("standard_dose")
            local bw = L.width(label, 1, HGfx.font(8, true)) + s(14)
            if bx + bw > rx + rw - s(10) then bx = rx + s(10) by = by + s(24) end
            local sel = (EXAM.doseIndex or (pick.dosing and pick.dosing.default) or 1) == idx
            HGfx.button(bx, by, bw, s(20), label, { color = sel and { 47, 134, 232 } or { 45, 53, 63 }, font = HGfx.font(8, true) }, function() EXAM.doseIndex = idx end)
            if opt and opt.note then HIS.tooltip(bx, by, bw, s(20), L(opt.note)) end
            bx = bx + bw + s(4)
        end
        local idx = EXAM.doseIndex or (pick.dosing and pick.dosing.default) or 1
        local bw2 = (rw - s(28)) / 2
        HGfx.button(rx + s(10), ry + s(118), bw2, s(26), t("drug_order"), { color = { 38, 46, 56 }, font = HGfx.font(9, true) }, function()
            act("drugOrder", pick.id, idx)
        end)
        HGfx.button(rx + s(18) + bw2, ry + s(118), bw2, s(26), t("drug_give"), { color = { 47, 134, 232 }, disabled = not EXAM.bedside, font = HGfx.font(9, true) }, function()
            act("give", pick.id, idx)
        end)
        if not EXAM.bedside then HIS.tooltip(rx + s(18) + bw2, ry + s(118), bw2, s(26), t("bedside_only")) end
        ry = ry + s(158)
    else
        HGfx.text(t("drug_pick"), rx, ry, rw, s(20), T.faint, HGfx.font(9))
        ry = ry + s(26)
    end
    HGfx.text(t("drug_orders"), rx, ry, rw, s(18), T.faint, HGfx.font(8, true))
    ry = ry + s(20)
    for i = #(c.drugOrders or {}), 1, -1 do
        local o = c.drugOrders[i]
        if ry > y + h - s(28) then break end
        local name = o.drug
        for _, d in ipairs(drugs) do if d.id == o.drug then name = d.name end end
        HGfx.round(rx, ry, rw, s(26), s(4), o.status == "ordered" and tocolor(60, 44, 26) or T.panel)
        HGfx.text(HGfx.fit(("%s · %s · %s"):format(name, t("dorder_" .. o.status), o.by or ""), rw - s(70), HGfx.font(8)), rx + s(8), ry, rw - s(70), s(26), T.text, HGfx.font(8))
        if o.status == "ordered" then
            HGfx.button(rx + rw - s(62), ry + s(3), s(58), s(20), t("cancel"), { color = { 80, 40, 44 }, font = HGfx.font(8, true) }, function() act("drugCancel", o.id) end)
        end
        ry = ry + s(30)
    end
end

---------------------------------------------------------------- tab: transfusion

local function drawTransfusion(c, x, y, w, h)
    local v = c.transfusion
    if not v then
        return HGfx.text(t("transfusion_unavailable"), x, y + s(20), w, s(30), T.faint, HGfx.font(10), "center")
    end
    HGfx.text(t("transfusion_group", { group = v.group or t("group_unknown") }), x, y, w, s(24), T.text, HGfx.font(11, true))
    HGfx.text(v.crossmatched and t("crossmatch_done") or t("crossmatch_needed"), x, y + s(24), w, s(20), v.crossmatched and tocolor(63, 179, 122) or tocolor(229, 160, 58), HGfx.font(9))
    local by = y + s(54)
    for _, u in ipairs(v.units or {}) do
        if by > y + h - s(40) then break end
        HGfx.round(x, by, w, s(30), s(5), u.compatible and T.panel or tocolor(30, 34, 40))
        HGfx.text(("%s  %s  ·  %s"):format(L("med_hospitals.transfusion.product_" .. u.product), u.group, t("units_left", { n = u.stock })), x + s(10), by, w - s(150), s(30), u.compatible and T.text or T.faint, HGfx.font(9))
        HGfx.button(x + w - s(140), by + s(4), s(134), s(22), t("transfuse"), { color = { 160, 40, 44 }, disabled = not u.compatible or not EXAM.bedside or u.stock <= 0, font = HGfx.font(9, true) },
            function() act("transfuse", u.product, u.group) end)
        if not u.compatible then HIS.tooltip(x, by, w, s(30), t("incompatible")) end
        by = by + s(34)
    end
    for _, r in ipairs(v.running or {}) do
        if by > y + h - s(24) then break end
        HGfx.text(t("transfusion_running", { what = L("med_hospitals.transfusion.product_" .. r.product) .. " " .. r.group, s = r.left }), x, by, w, s(22), tocolor(79, 208, 255), HGfx.font(9))
        by = by + s(24)
    end
end

---------------------------------------------------------------- tab: documentation

-- PC only (2026-11-06): the free texts of the Ambuláns lap and the BNO diagnoses. The tablet / bedside
-- view has no documentation tab; the server refuses these actions away from a PC too (ER.atPC).
local function drawDocs(c, x, y, w, h)
    local colW = (w - s(12)) * 0.58
    local by = y
    for _, field in ipairs({ "anamnesis", "status", "epicrisis" }) do
        local text = c.texts and c.texts[field] or ""
        HGfx.text(t("doc_" .. field), x, by, colW - s(200), s(20), T.faint, HGfx.font(8, true))
        HGfx.button(x + colW - s(90), by, s(90), s(20), t("edit"), { color = { 45, 53, 63 }, font = HGfx.font(8, true) }, function()
            HIS.input(t("doc_" .. field), 1200, text, function(v) act("text", field, v) end)
        end)
        if field == "status" then
            HGfx.button(x + colW - s(200), by, s(104), s(20), t("from_exam"), { color = { 45, 53, 63 }, font = HGfx.font(8, true), disabled = (c.statusTemplate or "") == "" }, function()
                act("text", "status", c.statusTemplate)
            end)
        end
        local lines = HGfx.wrap(text ~= "" and text or "—", colW - s(16), HGfx.font(9))
        local boxH = s(10) + math.min(6, #lines) * s(15)
        HGfx.round(x, by + s(22), colW, boxH, s(5), T.panel)
        for i = 1, math.min(6, #lines) do HGfx.text(lines[i], x + s(8), by + s(26) + (i - 1) * s(15), colW - s(16), s(15), T.text, HGfx.font(9)) end
        by = by + s(30) + boxH
    end
    HGfx.button(x, by, s(170), s(26), t("case_documents"), { color = { 45, 53, 63 }, font = HGfx.font(9, true) }, function()
        if HIS.openDocuments then HIS.openDocuments({ caseRef = c.docRef }) end
    end)
    -- right: diagnoses (BNO search)
    local rx, rw = x + colW + s(12), w - colW - s(12)
    HGfx.text(t("diag_title", { n = #(c.diagnoses or {}) }), rx, y, rw - s(110), s(20), T.text, HGfx.font(10, true))
    HGfx.button(rx + rw - s(104), y, s(104), s(22), t("diag_add"), { color = { 47, 134, 232 }, disabled = #(c.diagnoses or {}) >= 5, font = HGfx.font(9, true) },
        function() EXAM.bno = { query = "", results = {} } end)
    local dy = y + s(28)
    for _, code in ipairs(c.diagnoses or {}) do
        HGfx.round(rx, dy, rw, s(40), s(5), T.panel)
        HGfx.text(exports.med_docs:getBNOCode(code), rx + s(8), dy + s(2), s(70), s(18), T.accent, HGfx.font(9, true))
        HGfx.text(HGfx.fit(exports.med_docs:getBNOName(code), rw - s(90), HGfx.font(9)), rx + s(8), dy + s(19), rw - s(90), s(18), T.text, HGfx.font(9))
        HGfx.button(rx + rw - s(70), dy + s(9), s(64), s(22), t("remove"), { color = { 80, 40, 44 }, font = HGfx.font(8, true) }, function() act("diagRemove", code) end)
        dy = dy + s(44)
    end
    -- suggested codes from the findings shown
    local sugg = {}
    local have = {}
    for _, code in ipairs(c.diagnoses or {}) do have[code] = true end
    for _, f in ipairs(c.findings or {}) do if f.bno and not have[f.bno] then sugg[#sugg + 1] = f.bno have[f.bno] = true end end
    if #sugg > 0 then
        HGfx.text(t("diag_suggested"), rx, dy + s(4), rw, s(18), T.faint, HGfx.font(8, true))
        dy = dy + s(24)
        for _, code in ipairs(sugg) do
            if dy > y + h - s(30) then break end
            HGfx.button(rx, dy, rw, s(26), exports.med_docs:getBNOCode(code) .. "  " .. exports.med_docs:getBNOName(code),
                { color = { 30, 60, 100 }, align = "left", font = HGfx.font(8, true) }, function() act("diagAdd", code) end)
            dy = dy + s(30)
        end
    end
end

-- Elhelyezés (disposition): the outcome buttons, on the tablet and the PC alike.
local function drawPlace(c, x, y, w, h)
    local colW = math.min(w, s(640))
    local by = y
    if #(c.diagnoses or {}) == 0 then
        HGfx.round(x, by, colW, s(30), s(5), tocolor(70, 55, 25))
        HGfx.text(t(EXAM.source == "pc" and "place_need_diag" or "place_need_diag_pc"), x + s(10), by, colW - s(20), s(30), T.text, HGfx.font(9, true))
        by = by + s(38)
    end
    -- outcome
    HGfx.text(t("outcome"), x, by, colW, s(20), T.faint, HGfx.font(8, true))
    by = by + s(22)
    if c.outcome then HGfx.text(t("outcome_done", { what = t("out_" .. tostring(c.outcome)) }), x, by, colW, s(20), T.text, HGfx.font(10, true)) by = by + s(24) end
    -- a surgery order / request waiting (U2): the Physician approves or rejects here too
    if c.pendingKind == "surgery_request" or c.pendingKind == "surgery" then
        local what = L("med_hospitals.erc.surgery_" .. tostring(c.pendingSurgery))
        HGfx.round(x, by, colW, s(30), s(5), c.pendingKind == "surgery" and tocolor(30, 70, 120) or tocolor(70, 55, 25))
        HGfx.text(t(c.pendingKind == "surgery" and "surgery_ordered" or "surgery_waiting", { what = what }), x + s(8), by, colW - s(200), s(30), T.text, HGfx.font(9, true))
        if c.pendingKind == "surgery_request" then
            HGfx.button(x + colW - s(190), by + s(3), s(90), s(24), t("or_approve"), { color = { 40, 150, 90 }, font = HGfx.font(8, true) }, function() act("outcome", "surgery_approve") end)
            HGfx.button(x + colW - s(96), by + s(3), s(90), s(24), t("or_reject"), { color = { 150, 50, 50 }, font = HGfx.font(8, true) }, function() act("outcome", "surgery_reject") end)
        end
        by = by + s(36)
    end
    if c.needsICU then HGfx.text(t("needs_icu"), x, by, colW, s(18), tocolor(235, 120, 90), HGfx.font(9, true)) by = by + s(22) end
    local btns = { { "discharge" }, { "ward" }, { "icu" }, { "surgery" }, { "transfer" }, { "death", { 120, 40, 44 } } }
    if c.inBed then table.insert(btns, 1, { "retake", { 47, 134, 232 } }) end
    local bw = (colW - s(8)) / 3
    for i, b in ipairs(btns) do
        local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
        local bx, byy = x + col * (bw + s(4)), by + row * s(32)
        HGfx.button(bx, byy, bw, s(28), t("out_" .. b[1]), { color = b[2] or { 38, 46, 56 }, font = HGfx.font(9, true) }, function()
            EXAM.dept, EXAM.surg = nil, nil
            if b[1] == "ward" then EXAM.dept = true
            elseif b[1] == "transfer" then EXAM.transfer = { class = "S2", needs = {}, target = nil, note = "" }
            elseif b[1] == "surgery" then
                local opts = c.surgeryOptions or {}
                if #opts == 1 then act("outcome", "surgery", opts[1].id) else EXAM.surg = true end
            elseif b[1] == "death" then EXAM.death = { cause = (c.diagnoses or {})[1] or "R9600", text = "" }
            else act("outcome", b[1]) end
        end)
    end
    by = by + math.ceil(#btns / 3) * s(32)
    if EXAM.dept then
        local bx = x
        for _, d in ipairs(ERC.WARD_DEPARTMENTS) do
            local label = t("dept_" .. d)
            local bw2 = L.width(label, 1, HGfx.font(8, true)) + s(14)
            HGfx.button(bx, by, bw2, s(24), label, { color = { 47, 134, 232 }, font = HGfx.font(8, true) }, function() EXAM.dept = nil act("outcome", "ward", d) end)
            bx = bx + bw2 + s(4)
        end
    end
    if EXAM.surg then
        -- the operations the confirmed findings need (priority ones first)
        local opts = c.surgeryOptions or {}
        if #opts == 0 then HGfx.text(t("no_surgery_options"), x, by, colW, s(20), T.faint, HGfx.font(9)) end
        local bx, row = x, by
        for _, o in ipairs(opts) do
            local label = L("med_hospitals.erc.surgery_" .. o.id)
            local bw2 = L.width(label, 1, HGfx.font(8, true)) + s(14)
            if bx + bw2 > x + colW then bx, row = x, row + s(28) end
            HGfx.button(bx, row, bw2, s(24), label, { color = { 47, 134, 232 }, font = HGfx.font(8, true) }, function() EXAM.surg = nil act("outcome", "surgery", o.id) end)
            bx = bx + bw2 + s(4)
        end
    end
end

---------------------------------------------------------------- tab: pathway (log)

local function drawLog(c, x, y, w, h)
    local list = c.events or {}
    local rowH = s(20)
    local visible = math.floor(h / rowH)
    local off = HGfx.getScroll("log", #list - visible)
    HGfx.scrollArea("log", x, y, w, h)
    for i = 1, math.min(visible, #list - off) do
        local e = list[#list - off - i + 1]
        HGfx.text(("%s  %s  %s  %s"):format(HIS.hhmm(e.at), t("ev_" .. tostring(e.kind)), tostring(e.text or ""), e.by and ("· " .. e.by) or ""),
            x, y + (i - 1) * rowH, w, rowH, T.dim, HGfx.font(9))
    end
end

local DRAW = { exam = drawExam, orders = drawOrders, treat = drawTreat, drugs = drawDrugs, transfusion = drawTransfusion, docs = drawDocs, place = drawPlace, log = drawLog }

---------------------------------------------------------------- right column

local function drawRight(c, x, y, w, h)
    HGfx.text(t("right_orders"), x, y, w, s(18), T.faint, HGfx.font(8, true))
    local by = y + s(20)
    local shown = 0
    for i = #(c.orders or {}), 1, -1 do
        local o = c.orders[i]
        if shown >= 6 then break end
        shown = shown + 1
        local col = o.status == "done" and { 63, 179, 122 } or (o.status == "running" and { 47, 134, 232 } or { 229, 130, 42 })
        HGfx.round(x, by, w, s(36), s(5), T.panel)
        dxDrawRectangle(x, by, s(3), s(36), HGfx.rgb(col))
        HGfx.text(HGfx.fit(orderName(o.key), w - s(14), HGfx.font(9, true)), x + s(10), by + s(2), w - s(14), s(18), T.text, HGfx.font(9, true))
        local st = o.status == "running" and o.ends and t("ord_left", { s = math.max(0, o.ends - getRealTime().timestamp) }) or t("ord_" .. o.status)
        HGfx.text(st .. (o.indicated and "" or (" · " .. t("not_indicated"))), x + s(10), by + s(18), w - s(14), s(16), T.dim, HGfx.font(8))
        if o.status == "done" and o.resultId then
            HGfx.hit(x, by, w, s(36), function() for _, r in ipairs(c.results or {}) do if r.id == o.resultId then EXAM.viewer = { result = r, index = 1 } end end end)
        end
        by = by + s(40)
    end
    if shown == 0 then HGfx.text(t("no_orders"), x, by, w, s(18), T.faint, HGfx.font(9)) by = by + s(22) end
    HGfx.button(x, by + s(4), w, s(26), t("new_order"), { color = { 47, 134, 232 }, font = HGfx.font(9, true) }, function() EXAM.tab = "orders" end)
    by = by + s(40)
    HGfx.text(t("diag_title", { n = #(c.diagnoses or {}) }), x, by, w, s(18), T.faint, HGfx.font(8, true))
    by = by + s(20)
    for _, code in ipairs(c.diagnoses or {}) do
        HGfx.text(HGfx.fit(exports.med_docs:getBNOCode(code) .. "  " .. exports.med_docs:getBNOName(code), w, HGfx.font(8)), x, by, w, s(16), T.text, HGfx.font(8))
        by = by + s(18)
    end
    -- triage + treating
    local ty = y + h - s(96)
    HGfx.text(t("triage_set"), x, ty, w, s(18), T.faint, HGfx.font(8, true))
    if c.triageSuggest then
        HGfx.text(t("triage_suggest", { level = c.triageSuggest }), x, ty, w, s(18), HGfx.rgb(HIS.TRI[c.triageSuggest]), HGfx.font(8, true), "right")
        HIS.tooltip(x, ty, w, s(18), t("triage_suggest_tip"))
    end
    local tw = (w - s(12)) / 4
    for level = 1, 4 do
        HGfx.button(x + (level - 1) * (tw + s(4)), ty + s(20), tw, s(26), tostring(level), { color = HIS.TRI[level], textColor = tocolor(255, 255, 255) }, function() act("triage", level) end)
    end
    local tl = c.treating and t("treating_is", { name = c.treating }) or t("take_over")
    HGfx.button(x, ty + s(54), w, s(30), HGfx.fit(tl, w - s(10), HGfx.font(9, true)), { color = c.treating and { 34, 40, 48 } or { 47, 134, 232 }, font = HGfx.font(9, true) }, function() act("treating") end)
end

---------------------------------------------------------------- overlays: result viewer, BNO search, transfer request

local function drawViewer(x, y, w, h)
    local v = EXAM.viewer
    local r = v.result
    HGfx.hits = {}
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 238))
    HGfx.text(("%s · %s"):format(orderName(r.key), HIS.hhmm(r.at)), x + s(14), y + s(8), w - s(70), s(28), T.text, HGfx.font(12, true))
    HGfx.button(x + w - s(48), y + s(8), s(36), s(28), "X", { color = { 60, 40, 44 } }, function() EXAM.viewer = nil end)
    local cy, ch = y + s(46), h - s(90)
    if r.kind == "lab" then
        local by = cy
        local colW = (w - s(80)) / 2
        for i, val in ipairs(r.values or {}) do
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)
            local vx, vy = x + s(30) + col * (colW + s(20)), by + row * s(24)
            local c2 = val.flag and tocolor(255, 170, 150) or T.text
            HGfx.text(t("lab_" .. val.key), vx, vy, colW * 0.45, s(22), T.text, HGfx.font(10))
            HGfx.text(tostring(val.value) .. " " .. (val.unit or ""), vx + colW * 0.45, vy, colW * 0.25, s(22), c2, HGfx.font(10, true))
            if val.low and val.high and type(val.value) == "number" then HGfx.text(("%s – %s"):format(val.low, val.high), vx + colW * 0.7, vy, colW * 0.2, s(22), T.faint, HGfx.font(9)) end
            if val.flag then HGfx.text(t("flag_" .. val.flag), vx + colW * 0.88, vy, colW * 0.12, s(22), c2, HGfx.font(9, true)) end
            if val.note then HIS.tooltip(vx, vy, colW, s(22), t("labnote_" .. val.note)) end
        end
        local lines = HGfx.wrap(t(r.positive and "lab_explain_abnormal" or "lab_explain_normal"), w - s(60), HGfx.font(9))
        local ey = by + math.ceil(#(r.values or {}) / 2) * s(24) + s(12)
        for i, line in ipairs(lines) do HGfx.text(line, x + s(30), ey + (i - 1) * s(16), w, s(16), T.dim, HGfx.font(9)) end
        return
    end
    if r.kind == "ecg" and type(r.spec) == "table" then
        local m, interp = exports.medsys:getECG12Text(r.spec)
        HGfx.text(m, x + s(14), cy - s(4), w - s(28), s(20), T.text, HGfx.font(10, true))
        HGfx.text(interp, x + s(14), cy + s(16), w - s(28), s(20), tocolor(255, 200, 120), HGfx.font(9))
        exports.medsys:drawECG12(r.spec, x + s(14), cy + s(40), w - s(28), ch - s(40))
        return
    end
    local list = r.kind == "ecg" and { { file = r.image } } or (r.images or {})
    v.index = math.max(1, math.min(v.index, #list))
    local item = list[v.index]
    if item then
        local tex = HIS.image(HIS.imagePath(r.kind, item.file))
        if tex then
            local iw, ih = dxGetMaterialSize(tex)
            local sc = math.min((w - s(40)) / iw, ch / ih)
            dxDrawImage(x + (w - iw * sc) / 2, cy, iw * sc, ih * sc, tex)
        else
            HGfx.text(t("loading_image"), x, cy, w, ch, T.faint, HGfx.font(10), "center")
        end
        local cap = item.finding and L("med_hospitals.erc.finding_" .. item.finding) or (r.kind == "ecg" and t("ecg_" .. tostring(r.image)) or t("result_negative"))
        if item.desc then cap = cap .. " — " .. L(item.desc) end
        HGfx.text(HGfx.fit(cap, w - s(160), HGfx.font(10, true)), x + s(14), y + h - s(38), w - s(160), s(30), T.text, HGfx.font(10, true))
    end
    if #list > 1 then
        HGfx.button(x + w - s(124), y + h - s(38), s(52), s(28), "‹", nil, function() v.index = v.index - 1 end)
        HGfx.button(x + w - s(66), y + h - s(38), s(52), s(28), "›", nil, function() v.index = v.index + 1 end)
    end
end

local bnoToken = 0
addEvent("onClientBNOResults")
addEventHandler("onClientBNOResults", root, function(token, results)
    if EXAM.bno and EXAM.bno.token == token then EXAM.bno.results = results end
end)

local function drawBNO(x, y, w, h)
    local b = EXAM.bno
    HGfx.hits = {}
    dxDrawRectangle(x, y, w, h, tocolor(10, 12, 15, 242))
    HGfx.text(t("bno_pick"), x + s(14), y + s(8), w - s(70), s(28), T.text, HGfx.font(12, true))
    HGfx.button(x + w - s(48), y + s(8), s(36), s(28), "X", { color = { 60, 40, 44 } }, function() EXAM.bno = nil end)
    HGfx.button(x + s(14), y + s(44), w - s(28), s(32), b.query ~= "" and (t("bno_query") .. ": " .. b.query) or t("bno_search_hint"),
        { color = { 34, 40, 48 }, align = "left", font = HGfx.font(10) }, function()
            HIS.input(t("bno_pick"), 60, b.query, function(q)
                bnoToken = bnoToken + 1
                b.query, b.token, b.results = q, bnoToken, {}
                local c = EXAM.case
                exports.med_docs:searchBNO(q, bnoToken, c and { sex = c.gender == "female" and "f" or "m", age = c.age } or nil)
            end)
        end)
    local rowH = s(28)
    local top = y + s(86)
    local visible = math.floor((h - s(96)) / rowH)
    local off = HGfx.getScroll("bno", #b.results - visible)
    HGfx.scrollArea("bno", x, top, w, h - s(96))
    for i = 1, math.min(visible, #b.results - off) do
        local e = b.results[i + off]
        local ry = top + (i - 1) * rowH
        local hov = HGfx.hover(x + s(14), ry, w - s(28), rowH - s(2))
        HGfx.round(x + s(14), ry, w - s(28), rowH - s(2), s(4), hov and T.panel2 or T.panel)
        HGfx.text(e.fmt .. (e.flag ~= "" and (" " .. e.flag) or ""), x + s(24), ry, s(80), rowH - s(2), T.accent, HGfx.font(9, true))
        HGfx.text(HGfx.fit(e.name, w - s(150), HGfx.font(9)), x + s(110), ry, w - s(140), rowH - s(2), T.text, HGfx.font(9))
        HGfx.hit(x + s(14), ry, w - s(28), rowH - s(2), function() act("diagAdd", e.code) EXAM.bno = nil end)
    end
    if b.query ~= "" and #b.results == 0 then HGfx.text(t("bno_none"), x, top + s(20), w, s(30), T.faint, HGfx.font(10), "center") end
end

local function drawTransfer(x, y, w, h)
    local tr = EXAM.transfer
    HGfx.hits = {}
    local pw, ph = s(560), s(380)
    local px, py = x + (w - pw) / 2, y + (h - ph) / 2
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 170))
    HGfx.round(px, py, pw, ph, s(10), T.bg)
    HGfx.text(t("transfer_title"), px + s(16), py + s(10), pw, s(26), T.text, HGfx.font(12, true))
    local by = py + s(46)
    for i, cls in ipairs({ "S1", "S2" }) do
        HGfx.button(px + s(16) + (i - 1) * s(150), by, s(140), s(28), t("transfer_" .. cls:lower()), { color = tr.class == cls and { 120, 60, 170 } or { 45, 53, 63 }, font = HGfx.font(9, true) },
            function() tr.class = cls end)
    end
    by = by + s(40)
    HGfx.text(t("transfer_needs"), px + s(16), by, pw, s(18), T.faint, HGfx.font(8, true))
    by = by + s(20)
    for i, need in ipairs({ "oxygen", "drugs", "ventilated", "monitor" }) do
        local on = tr.needs[need]
        HGfx.button(px + s(16) + ((i - 1) % 2) * s(262), by + math.floor((i - 1) / 2) * s(32), s(256), s(28), (on and "☑ " or "☐ ") .. t("need_" .. need),
            { color = { 38, 46, 56 }, align = "left", font = HGfx.font(9) }, function() tr.needs[need] = not on end)
    end
    by = by + s(72)
    HGfx.text(t("transfer_target"), px + s(16), by, pw, s(18), T.faint, HGfx.font(8, true))
    by = by + s(20)
    local bx = px + s(16)
    for _, h2 in ipairs(EXAM.hospitals or {}) do
        local bw = L.width(h2.name, 1, HGfx.font(8, true)) + s(16)
        if bx + bw > px + pw - s(16) then bx = px + s(16) by = by + s(28) end
        HGfx.button(bx, by, bw, s(24), h2.name, { color = tr.target == h2.id and { 47, 134, 232 } or { 45, 53, 63 }, font = HGfx.font(8, true) }, function() tr.target = h2.id end)
        bx = bx + bw + s(4)
    end
    by = by + s(34)
    HGfx.button(px + s(16), by, pw - s(32), s(30), tr.note ~= "" and tr.note or t("transfer_note_hint"), { color = { 34, 40, 48 }, align = "left", font = HGfx.font(9) }, function()
        HIS.input(t("transfer_note"), 200, tr.note, function(v) tr.note = v end)
    end)
    HGfx.button(px + s(16), py + ph - s(44), (pw - s(40)) / 2, s(32), t("cancel"), { color = { 60, 40, 44 }, font = HGfx.font(10, true) }, function() EXAM.transfer = nil end)
    HGfx.button(px + s(24) + (pw - s(40)) / 2, py + ph - s(44), (pw - s(40)) / 2, s(32), t("transfer_send"), { color = { 47, 134, 232 }, font = HGfx.font(10, true), disabled = not tr.target },
        function()
            act("outcome", tr.class == "S1" and "transfer_s1" or "transfer_s2", { needs = tr.needs, target = tr.target, note = tr.note })
            EXAM.transfer = nil
        end)
end

-- death record (Orvos): time = now, cause (BNO: a diagnosis or a common code), circumstances
local DEATH_CODES = { "R9600", "I4610", "R5710", "T7940", "R0920" }
local function drawDeath(x, y, w, h)
    local d = EXAM.death
    local c = EXAM.case or {}
    HGfx.hits = {}
    local pw, ph = s(520), s(330)
    local px, py = x + (w - pw) / 2, y + (h - ph) / 2
    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 170))
    HGfx.round(px, py, pw, ph, s(10), T.bg)
    HGfx.text(t("death_title"), px + s(16), py + s(10), pw, s(26), T.text, HGfx.font(12, true))
    local by = py + s(46)
    HGfx.text(t("death_cause"), px + s(16), by, pw, s(18), T.faint, HGfx.font(8, true))
    by = by + s(20)
    local codes, seen = {}, {}
    for _, code in ipairs(c.diagnoses or {}) do if not seen[code] then seen[code] = true codes[#codes + 1] = code end end
    for _, code in ipairs(DEATH_CODES) do if not seen[code] then seen[code] = true codes[#codes + 1] = code end end
    local cw = (pw - s(40)) / 2
    for i, code in ipairs(codes) do
        if i > 8 then break end
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local label = exports.med_docs:getBNOCode(code) .. "  " .. (exports.med_docs:getBNOName(code) or "")
        HGfx.button(px + s(16) + col * (cw + s(8)), by + row * s(30), cw, s(26), HGfx.fit(label, cw - s(12), HGfx.font(8)),
            { color = d.cause == code and { 47, 134, 232 } or { 38, 46, 56 }, align = "left", font = HGfx.font(8) }, function() d.cause = code end)
    end
    by = by + math.ceil(math.min(8, #codes) / 2) * s(30) + s(6)
    HGfx.text(t("death_circumstances"), px + s(16), by, pw, s(18), T.faint, HGfx.font(8, true))
    by = by + s(20)
    HGfx.button(px + s(16), by, pw - s(32), s(30), d.text ~= "" and HGfx.fit(d.text, pw - s(50), HGfx.font(9)) or t("death_circumstances_hint"), { color = { 34, 40, 48 }, align = "left", font = HGfx.font(9) }, function()
        HIS.input(t("death_circumstances"), 300, d.text, function(v) d.text = v end)
    end)
    HGfx.button(px + s(16), py + ph - s(44), cw, s(32), t("cancel"), { color = { 60, 40, 44 }, font = HGfx.font(10, true) }, function() EXAM.death = nil end)
    HGfx.button(px + s(24) + cw, py + ph - s(44), cw, s(32), t("death_record"), { color = { 120, 40, 44 }, font = HGfx.font(10, true) },
        function()
            act("outcome", "death", { cause = d.cause, text = d.text })
            EXAM.death = nil
        end)
end

addEvent("his:hospitals", true)
addEventHandler("his:hospitals", resourceRoot, function(list) EXAM.hospitals = list end)

---------------------------------------------------------------- render + input

-- The panel content into x, y, w, h (the own frame below, or a window of the hospital PC: w7.lua).
-- A result open (EXAM.viewer): only the result is drawn, the panel below neither shows nor reacts; X
-- (or ESC) brings the panel back as it was. The other dialogs (BNO, transfer, death) keep the panel
-- visible behind them, without hover and tooltips.
function EXAM.draw(x, y, w, h)
    local c = EXAM.case
    if not c then
        HGfx.text(t("loading"), x, y, w, h, T.faint, HGfx.font(11), "center")
        return
    end
    if EXAM.viewer then
        drawViewer(x, y, w, h)
        return
    end
    local modal = EXAM.bno or EXAM.transfer or EXAM.death
    HGfx.blockHover = modal and true or false
    local hh = drawHeader(c, x, y, w)
    local top = y + hh + s(10)
    local leftW, rightW = s(160), s(240)
    drawBodyMap(c, x + s(12), top, leftW, h - hh - s(22))
    local mx, mw = x + s(12) + leftW + s(12), w - leftW - rightW - s(48)
    local vh = drawVitals(c, mx, top, mw)
    -- tabs (the documentation tab only on the PC)
    local ty = top + vh + s(8)
    local tx = mx
    local list = tabs()
    local known = false
    for _, key in ipairs(list) do if key == EXAM.tab then known = true end end
    if not known then EXAM.tab = EXAM.bedside and "exam" or "orders" end
    for _, key in ipairs(list) do
        local label = t("tab_" .. key)
        local tw = L.width(label, 1, HGfx.font(9, true)) + s(20)
        HGfx.button(tx, ty, tw, s(26), label, { color = EXAM.tab == key and { 47, 134, 232 } or { 30, 36, 43 }, font = HGfx.font(9, true), tab = true, active = EXAM.tab == key }, function() EXAM.tab = key EXAM.dept = nil end)
        tx = tx + tw + s(4)
    end
    if not EXAM.bedside then
        HGfx.text(t("remote_view"), tx + s(8), ty, mx + mw - tx - s(8), s(26), T.faint, HGfx.font(8), "right")
    end
    local body = ty + s(34)
    DRAW[EXAM.tab](c, mx, body, mw, y + h - s(12) - body)
    drawRight(c, x + w - rightW - s(12), top, rightW, h - hh - s(22))
    HGfx.blockHover = false
    if modal then
        HIS.tip = nil
        HGfx.hits = {}
        if EXAM.bno then drawBNO(x + w * 0.2, y + h * 0.1, w * 0.6, h * 0.8)
        elseif EXAM.transfer then drawTransfer(x, y, w, h)
        elseif EXAM.death then drawDeath(x, y, w, h) end
    end
end

-- ESC: the open dialog first, then the panel
function EXAM.escape()
    if EXAM.viewer then EXAM.viewer = nil elseif EXAM.bno then EXAM.bno = nil elseif EXAM.transfer then EXAM.transfer = nil elseif EXAM.death then EXAM.death = nil else EXAM.close() end
end

-- inside the hospital PC (w7.lua draws and routes it)
function EXAM.inPC() return EXAM.open and EXAM.source == "pc" and PCS ~= nil and PCS.open == true end

addEventHandler("onClientRender", root, function()
    if not EXAM.open or EXAM.inPC() then return end
    HGfx.hits, HGfx.scrollAreas = {}, {}
    HGfx.setSkin("modern")
    local x, y, w, h = frame()
    HGfx.round(x - s(6), y - s(6), w + s(12), h + s(12), s(14), T.bezel)
    HGfx.round(x, y, w, h, s(8), T.bg)
    EXAM.draw(x, y, w, h)
    HIS.drawTip()
end)

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not EXAM.open or EXAM.inPC() or button ~= "left" or state ~= "down" then return end
    HGfx.click(ax, ay)
end)

addEventHandler("onClientKey", root, function(key, press)
    if not EXAM.open or EXAM.inPC() or not press then return end
    if key == "mouse_wheel_up" then HGfx.wheel(-1)
    elseif key == "mouse_wheel_down" then HGfx.wheel(1)
    elseif key == "escape" then
        cancelEvent()
        EXAM.escape()
    end
end)

-- the hospital list for the transfer request (target)
addEventHandler("onClientResourceStart", resourceRoot, function() triggerServerEvent("his:hospitalsReq", resourceRoot) end)
