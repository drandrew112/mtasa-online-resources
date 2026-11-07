-- med_docs viewer (DX): a document list and a white "paper" page per document type. Opened with
-- exports.med_docs:openDocuments([filter], [opt]) or /dokumentumok. opt.embed = true: drawn inside the
-- hospital PC (med_hospitals er/client/w7.lua: the Dokumentumtár window), the PC gives the rectangle
-- every frame with setDocumentsRect(x, y, w, h) (nil = window not shown) and closes it.
-- The paper is drawn into a render target (clean clipping), scrolls smoothly, has a scrollbar.
-- Coded parts (BNO, interventions, field names) are shown in the viewer's language; the free text
-- stays in the author's language (badge with the language code).

local SX, SY = guiGetScreenSize()
local S = math.max(0.7, math.min(SY / 1080, 1.4))
local function s(v) return v * S end

local V = { open = false, list = {}, doc = nil, filter = {}, scroll = 0, target = 0, listScroll = 0, blocks = nil, embed = false, rect = nil }
local fonts = {}
local function font(size, bold)
    local key = size .. (bold and "b" or "r")
    if not fonts[key] then
        fonts[key] = dxCreateFont(bold and DOCS.PAPER_FONT_BOLD or DOCS.PAPER_FONT, math.max(6, math.floor(size * S + 0.5)), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return fonts[key]
end
-- opt: an optional text ("" when the key does not exist)
local function t(key, p, opt)
    local k = "med_docs.view." .. key
    if opt and not L.has(k) then return "" end
    return L(k, p)
end
local function lang() return L.lang() == "hu" and "hu" or "en" end
local function bno(code) return getBNOName(code, lang()) end
local function codeName(code)
    local k = "med_docs.code." .. tostring(code):lower():gsub("%-", "_")
    return L.has(k) and L(k) or tostring(code)
end
local function dt(ts, withDate)
    if not ts then return "—" end
    local tm = getRealTime(ts)
    if withDate then return ("%04d.%02d.%02d. %02d:%02d"):format(tm.year + 1900, tm.month + 1, tm.monthday, tm.hour, tm.minute) end
    return ("%02d:%02d"):format(tm.hour, tm.minute)
end
local function hk(key, p) return L("med_hospitals." .. key, p) end
function medsysECGText(spec)
    local res = getResourceFromName("medsys")
    if not res or getResourceState(res) ~= "running" then return "", "" end
    return exports.medsys:getECG12Text(spec)
end

---------------------------------------------------------------- open / close

-- filter: { type, caseRef, mine, search, only } (only = the one type the filter row offers)
-- opt: { embed = true } inside the hospital PC
function openDocuments(filter, opt)
    V.open, V.filter, V.doc, V.blocks = true, type(filter) == "table" and filter or {}, nil, nil
    V.scroll, V.target, V.listScroll, V.sbDrag = 0, 0, 0, nil
    V.embed = type(opt) == "table" and opt.embed == true
    V.rect = nil
    if not V.embed then showCursor(true) end
    triggerServerEvent("docs:list", resourceRoot, V.filter)
    return true
end

-- embedded: the PC window rectangle of this frame (nil: the window is not shown, nothing is drawn)
function setDocumentsRect(x, y, w, h)
    if not V.open or not V.embed then return false end
    V.rect = (x and y and w and h) and { x, y, w, h } or nil
    return true
end

-- embedded: the filter of the open viewer (the Documents button of a patient in the PC)
function setDocumentsFilter(filter)
    if not V.open then return false end
    V.filter, V.doc, V.blocks, V.scroll, V.target, V.listScroll = type(filter) == "table" and filter or {}, nil, nil, 0, 0, 0
    triggerServerEvent("docs:list", resourceRoot, V.filter)
    return true
end

function closeDocuments()
    if not V.open then return end
    V.open, V.rect, V.sbDrag = false, nil, nil
    if not V.embed then showCursor(false) end
    V.embed = false
end

function isDocumentViewerOpen() return V.open end

addCommandHandler("dokumentumok", function() if V.open and not V.embed then closeDocuments() elseif not V.open then openDocuments() end end)
addCommandHandler("docs", function() if V.open and not V.embed then closeDocuments() elseif not V.open then openDocuments() end end)

addEvent("docs:list", true)
addEventHandler("docs:list", resourceRoot, function(list) V.list = list or {} end)
-- BNO names arrive asynchronously (client/bno.lua): the page is laid out again
addEventHandler("bno:names", resourceRoot, function() V.blocks = nil end)
-- Ú12: the leader edits the text parts (ui_core text input: epicrisis, then "what happened")
local editToken
function editStep()
    local e = V.editing
    if not e then return end
    local res = getResourceFromName("ui_core")
    if not res or getResourceState(res) ~= "running" then V.editing = nil return end
    local b = V.doc and V.doc.body or {}
    local current = e.step == "epicrisis" and (b.epicrisis or "") or ((b.handover or {}).text or "")
    editToken = exports.ui_core:openTextInput(t(e.step == "epicrisis" and "edit_epicrisis" or "edit_what"), e.step == "epicrisis" and 1200 or 600, current, "")
end
addEvent("ui_core:textInputResult")
addEventHandler("ui_core:textInputResult", root, function(token, text)
    if not editToken or token ~= editToken then return end
    editToken = nil
    local e = V.editing
    if not e then return end
    if type(text) ~= "string" then V.editing = nil return end
    if e.step == "epicrisis" then e.epicrisis, e.step = text, "what" setTimer(editStep, 100, 1) return end
    V.editing = nil
    triggerServerEvent("docs:editEms", resourceRoot, e.id, { epicrisis = e.epicrisis, what = text })
    if V.open and not V.embed then setTimer(function() showCursor(true) end, 50, 1) end
end)
addEvent("docs:notice", true)
addEventHandler("docs:notice", resourceRoot, function(key)
    local res = getResourceFromName("ui_core")
    if res and getResourceState(res) == "running" then exports.ui_core:addNotification(t("title"), t("notice_" .. tostring(key)), key == "edit_denied") end
    if key == "edit_saved" then triggerServerEvent("docs:list", resourceRoot, V.filter) end
end)

-- a document was made / replaced: the list refreshes; the open document follows its replacement
addEvent("docs:changed", true)
addEventHandler("docs:changed", resourceRoot, function(oldId, newId)
    if not V.open then return end
    triggerServerEvent("docs:list", resourceRoot, V.filter)
    if V.doc and oldId and V.doc.id == oldId then triggerServerEvent("docs:get", resourceRoot, newId) end
end)

addEvent("docs:doc", true)
addEventHandler("docs:doc", resourceRoot, function(doc) V.doc, V.blocks, V.scroll, V.target, V.contentHeight = doc or nil, nil, 0, 0, 0 end)

---------------------------------------------------------------- images of med_hospitals (downloaded there on demand)

local IMG = { ct = "er/img/ct/%s.jpg", xray = "er/img/xr/xr_%s.jpg", fast = "er/img/us/us_%s.jpg", ecg = "er/img/ecg/ecg_%s.jpg" }
local textures = {}
local function imageOf(kind, file)
    local rel = (IMG[kind] or "%s"):format(file)
    local path = ":med_hospitals/" .. rel
    local tex = textures[path]
    if tex then return tex end
    if fileExists(path) then
        tex = dxCreateTexture(path)
        textures[path] = tex or nil
        return tex
    end
    local res = getResourceFromName("med_hospitals")
    if res and getResourceState(res) == "running" and not textures[path .. "#asked"] then
        textures[path .. "#asked"] = true
        pcall(function() exports.med_hospitals:requestImage(rel) end)
    end
    return nil
end

---------------------------------------------------------------- document -> blocks

-- block kinds: { "hosp", lines, right } { "title", text } { "sec", text } (grey bar, EMS sheet only)
--              { "h5", text } (underlined section title) { "rule" } { "kv", key, value } { "kv2", k1, v1, k2, v2 }
--              { "row", cols, header } { "text", text } { "img", kind, file, caption } { "gap" } { "box", title, text }
--              { "sign", name, role } { "foot", text } { "ecg12", spec, caption }
local LAB_GROUPS = {
    { "cbc", { hb = true, hct = true, wbc = true, plt = true } },
    { "chem", { na = true, k = true, crea = true, glu = true, ck = true, trop = true, crp = true, che = true } },
    { "other", { lact = true, ph = true, be = true, inr = true, aptt = true, ddimer = true, cohb = true, etoh = true, screen = true, group = true, crossmatch = true } },
}
local function bloodGroup(v)
    local abo, rh = tostring(v):match("^(%w+)([%+%-])$")
    return abo and (abo .. " Rh" .. rh) or tostring(v)
end
local function num(v)
    if type(v) ~= "number" then return tostring(v) end
    local s = (math.abs(v) < 10 and v % 1 ~= 0) and ("%.2f"):format(v) or ((v % 1 ~= 0) and ("%.1f"):format(v) or tostring(v))
    s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return lang() == "hu" and s:gsub("%.", ",") or s
end

local function build(doc)
    local b = doc.body or {}
    local out = {}
    local function add(...) out[#out + 1] = { ... } end
    -- section title: the grey bar is the EMS case sheet's own format, every other document has the
    -- underlined title of the paper samples
    local function sec(text) add(doc.type == "ems" and "sec" or "h5", text) end
    local p = b.patient or {}
    local hospital = b.hospitalName or doc.hospital or ""
    local docNo = doc.no ~= "" and doc.no or ("#" .. tostring(doc.id))
    local function header(dept)
        add("hosp", { hospital, t("er_department"), dept or t("city_ls") }, t("doc_no", { no = docNo }))
    end
    local function patient(arrivalLine)
        add("kv2", t("patient_name"), p.name or (doc.patient ~= "" and doc.patient) or t("unknown"), t("birth"), p.birth or (p.age and t("age_years", { n = p.age })) or "—")
        if arrivalLine then add("kv2", t("admitted"), dt(b.arrivedAt or (b.arrival and b.arrival.at), true), t("arrival_kind"), arrivalLine) end
    end
    local function patientEnd() add("rule") end
    local function footer()
        add("gap")
        add("foot", t("page_foot", { no = docNo, v = doc.version or 1 }))
    end
    local function diagnoses(list)
        sec(t("diagnoses"))
        if #(list or {}) == 0 then add("text", "—") end
        for _, d in ipairs(list or {}) do
            if type(d) == "table" then add("row", { bno(d.code), d.code, dt(d.at, true):sub(1, 11) })
            else add("row", { bno(d), d, "" }) end
        end
    end
    local function findings(list)
        if #(list or {}) == 0 then return add("text", hk("his.result_negative")) end
        for _, fid in ipairs(list) do add("text", "• " .. hk("erc.finding_" .. fid) .. " — " .. t("finding_desc_" .. fid, nil, true)) end
    end

    if doc.type == "amb" then
        header()
        add("title", t("type_amb"))
        local a = b.arrival or {}
        local kind = a.kind == "ems" and hk("er.arrived_ems", { unit = a.unit or "?" }) .. ((a.medics and #a.medics > 0) and (": " .. table.concat(a.medics, ", ")) or "")
            or hk("er.arrived_" .. tostring(a.kind or "brought"))
        patient(kind)
        add("kv2", t("triage"), tostring(b.triage or "—"), t("treating"), b.treating or "—")
        patientEnd()
        sec(t("anamnesis"))
        add("text", (b.anamnesis ~= "" and b.anamnesis) or "—")
        sec(t("status"))
        local st = b.status or {}
        if b.statusText and b.statusText ~= "" then add("text", b.statusText) end
        add("text", ("RR %s Hgmm · P %s/min · SpO₂ %s%% · %s%s%s"):format(st.bp or "—", st.hr or "—", st.spo2 or "—",
            st.consciousness and hk("his.consc_" .. st.consciousness) or "—", st.gcs and (" · GCS " .. st.gcs) or "", st.nrs and (" · NRS " .. st.nrs) or ""))
        sec(t("interventions"))
        add("row", { t("code"), t("name"), t("count"), t("points") }, true)
        local total = 0
        for _, it in ipairs(b.interventions or {}) do
            add("row", { it.code, codeName(it.code), tostring(it.n), tostring(it.points or "") })
            total = total + (tonumber(it.points) or 0)
        end
        if #(b.interventions or {}) == 0 then add("text", "—") else add("row", { "", t("total"), "", tostring(total) }, true) end
        if #(b.surgeries or {}) > 0 then
            for _, s in ipairs(b.surgeries) do add("text", ("%s  %s — %s"):format(dt(s.started), hk("erc.surgery_" .. s.id), t("op_" .. tostring(s.result)))) end
        end
        diagnoses(b.diagnoses)
        sec(t("epicrisis"))
        add("text", (b.epicrisis and b.epicrisis ~= "" and b.epicrisis) or "—")
        sec(t("related"))
        local rel = {}
        for _, r in ipairs(b.related or {}) do rel[#rel + 1] = t("type_" .. r.type) .. " " .. tostring(r.no) end
        add("text", #rel > 0 and table.concat(rel, " · ") or "—")
        sec(t("outcome"))
        local o = hk("his.out_" .. tostring(b.outcome))
        if b.department then o = o .. ": " .. hk("his.dept_" .. b.department) end
        if b.place and b.place ~= "" and (b.outcome == "ward" or b.outcome == "icu") then o = o .. ", " .. tostring(b.place) end
        add("text", o .. ", " .. dt(b.closedAt) .. (b.risky and ("  (" .. t("risky") .. ")") or ""))
        add("gap")
        add("sign", b.treating or doc.author, t("treating_doctor"))
        footer()
    elseif doc.type == "lab" then
        header(t("lab_department"))
        add("title", t("type_lab"))
        patient()
        add("kv2", t("sample"), dt(b.at, true) .. (b.performer and (" (" .. b.performer .. ")") or ""), t("issued"), dt(b.issued or b.at, true) .. " · " .. t("auto_validated"))
        patientEnd()
        sec(hk("erc.order_" .. tostring(b.order):gsub("%.", "_")))
        add("row", { t("test"), t("value"), t("flag"), t("reference") }, true)
        local explain = {}
        for _, g in ipairs(LAB_GROUPS) do
            local rows = {}
            for _, v in ipairs(b.values or {}) do if g[2][v.key] then rows[#rows + 1] = v end end
            if #rows > 0 then
                add("row", { t("lab_group_" .. g[1]), "", "", "" }, true)
                for _, v in ipairs(rows) do
                    local value = v.key == "group" and bloodGroup(v.value) or (num(v.value) .. " " .. (v.unit or ""))
                    local ref = ""
                    if v.low and v.high and type(v.value) == "number" then ref = (v.low == 0 and v.key ~= "etoh") and ("< " .. num(v.high)) or (num(v.low) .. "–" .. num(v.high)) end
                    add("row", { hk("his.lab_" .. v.key), value, v.flag and t("flag_" .. v.flag) or "", ref })
                    if v.flag then explain[#explain + 1] = t("explain_" .. v.key .. "_" .. v.flag, nil, true) end
                    if v.key == "group" then explain[#explain + 1] = t("explain_group") end
                end
            end
        end
        local lines = {}
        for _, e in ipairs(explain) do if e ~= "" then lines[#lines + 1] = "• " .. e end end
        add("box", t("explain_title"), #lines > 0 and table.concat(lines, "\n") or hk("his.lab_explain_normal"))
        footer()
    elseif doc.type == "ct" or doc.type == "xray" or doc.type == "fast" then
        header(t("imaging_department"))
        add("title", t("type_" .. doc.type))
        patient()
        local study = hk("erc.order_" .. tostring(b.order):gsub("%.", "_"))
        if b.side then study = study .. " (" .. t("side_" .. tostring(b.side)) .. ")" end
        add("kv2", t("study"), study, t("time"), dt(b.at, true))
        if b.performer then add("kv", t("performer"), b.performer) end
        patientEnd()
        sec(t("findings"))
        if doc.type == "fast" and type(b.windows) == "table" then
            for _, win in ipairs({ "ruq", "luq", "pelvis", "cardiac", "lung_r", "lung_l" }) do
                local w = b.windows[win]
                add("row", { hk("fast.w_" .. win), w and t("fast_" .. w) or t("fast_none") })
            end
        end
        findings(b.findings)
        if b.control then add("text", t("control_cast")) end
        sec(t("impression"))
        add("text", (#(b.findings or {}) > 0) and t("impression_positive") or t("impression_negative"))
        for _, img in ipairs(b.images or {}) do add("img", doc.type, img.file, img.finding and hk("erc.finding_" .. img.finding) or (img.desc and L(img.desc) or "")) end
        footer()
    elseif doc.type == "ecg" then
        header()
        add("title", t("type_ecg"))
        patient()
        add("kv2", t("time"), dt(b.at, true), t("rhythm"), hk("his.ecg_" .. tostring(b.image)))
        patientEnd()
        if type(b.spec) == "table" then
            local m, interp = medsysECGText(b.spec)
            add("kv", t("ecg_measure"), m)
            add("kv", t("ecg_machine"), interp)
            add("ecg12", b.spec, "25 mm/s · 10 mm/mV")
        else
            add("img", "ecg", b.image or "sinus", "25 mm/s · 10 mm/mV")
        end
        footer()
    elseif doc.type == "ems" then
        local task, unit, h = b.task or {}, b.unit or {}, b.handover or {}
        add("hosp", { "SAEMS", "San Andreas EMS", t("ems_site") }, t("ems_patient_short", { name = p.name or t("unknown") }) .. "\n" .. t("made_at", { at = dt(doc.created, true) }))
        add("title", t("type_ems"))
        sec(t("ems_call"))
        add("kv2", t("ems_case_id"), task.id and ("ERM #" .. task.id) or "—", t("ems_priority"), task.priority and ("P" .. task.priority) or "—")
        add("kv2", t("ems_call_date"), dt(task.created, true), t("ems_reason"), t("reason_" .. tostring(b.reason or "rescue")))
        add("kv2", t("ems_place"), task.zone or "—", t("ems_leader"), (b.leader or "") .. (unit.callsign and ("  (" .. unit.callsign .. ")") or ""))
        sec(t("ems_patient"))
        local first, last = tostring(p.name or ""):match("^(%S+)%s+(.+)$")
        add("kv2", t("last_name"), last or p.name or "—", t("birth"), p.birth or "—")
        add("kv2", t("first_name"), first or "—", t("gender"), p.gender and t((p.gender == "f" or p.gender == "female") and "female" or "male") or "—")
        add("kv2", t("citizen_id"), p.cid and tostring(p.cid) or "—", t("id_checked"), t(p.idChecked and "yes" or "no"))
        sec(t("diagnosis"))
        local inj = {}
        for _, i in ipairs(b.injuries or {}) do inj[#inj + 1] = (i.label or i.type or "?") .. (i.partLabel and (" (" .. i.partLabel .. ")") or "") end
        add("kv", t("findings"), #inj > 0 and table.concat(inj, "; ") or "—")
        add("kv", t("illness"), t("illness_" .. tostring(b.illness or "medical")))
        add("kv", "NACA", b.naca and (tostring(b.naca) .. " – " .. t("naca_" .. b.naca)) or "—")
        sec(t("ems_handover"))
        if h and h.at then
            add("kv", t("handover_ok"), t("handover_institution"))
            add("kv2", t("ems_handover_time"), dt(h.at, true), t("ems_hospital"), h.hospital or "—")
        else
            add("kv", t("handover_ok"), t("handover_none") .. (b.noHandover and b.noHandover ~= "" and (" (" .. b.noHandover .. ")") or ""))
        end
        sec(t("epicrisis_ems"))
        add("text", (b.epicrisis and b.epicrisis ~= "" and b.epicrisis) or "—")
        sec(t("ems_what"))
        add("kv", t("ems_by_call"), task.description or "—")
        add("kv", t("ems_by_handover"), (h.text and h.text ~= "" and h.text) or "—")
        add("foot", t("confidential"))
        -- page 2: exam, timeline, ECG, vitals, state
        sec(t("ems_exam"))
        local e = b.abcde
        if type(e) == "table" then
            add("kv", t("abcde_a"), t("airway_" .. tostring(e.a)))
            local bb = e.b or {}
            add("kv", t("abcde_b"), ("%s, SpO₂ %s%%%s"):format(t("breath_" .. tostring(bb.breathing), nil, true), bb.spo2 or "—", bb.oxygen and (", " .. t("on_oxygen")) or ""))
            local cc = e.c or {}
            add("kv", t("abcde_c"), ("P %s/min, RR %s Hgmm, %s"):format(cc.hr or "—", cc.bp or "—", t("skin_" .. tostring(cc.skin), nil, true)))
            local d = e.d or {}
            add("kv", t("abcde_d"), ("GCS %s, %s"):format(d.gcs or "—", hk("his.consc_" .. tostring(d.consciousness))))
            local ee = {}
            for _, i in ipairs(e.e or {}) do ee[#ee + 1] = tostring(i.type) .. (i.part and (" / " .. tostring(i.part)) or "") end
            add("kv", t("abcde_e"), #ee > 0 and table.concat(ee, ", ") or "—")
        end
        sec(t("ems_timeline"))
        add("row", { t("time"), t("description"), t("by") }, true)
        if #(b.timeline or {}) == 0 then add("text", "—") end
        for _, ev in ipairs(b.timeline or {}) do
            add("row", { dt(ev.at), hk("erc.medsys_" .. tostring(ev.action)) .. (ev.option and (" (" .. ev.option .. ")") or ""), ev.medic or "" })
        end
        for _, d in ipairs(b.drugs or {}) do add("row", { "", t("drug") .. ": " .. tostring(d.name or d.id) .. " " .. tostring(d.dose or ""), "" }) end
        if b.ecg then
            sec(t("type_ecg"))
            if type(b.ecg) == "table" then
                local m, interp = medsysECGText(b.ecg)
                add("kv", t("ecg_measure"), m)
                add("kv", t("ecg_machine"), interp)
                add("ecg12", b.ecg, "eMedia – EKG")
            else add("img", "ecg", b.ecg, "eMedia – EKG") end
        end
        sec(t("vitals_table"))
        add("row", { t("time"), "P", "RR", "SpO₂", "GCS" }, true)
        for _, v in ipairs(b.vitalsTable or {}) do add("row", { dt(v.at), tostring(v.hr or "—"), tostring(v.bp or "—"), tostring(v.spo2 or "—") .. "%", tostring(v.gcs or "—") }) end
        if #(b.vitalsTable or {}) == 0 then add("text", "—") end
        sec(t("patient_state"))
        add("kv", t("patient_state"), t("state_" .. tostring(b.state or "unchanged")))
        if b.editedBy then add("kv", t("edited_by"), b.editedBy) end
        add("gap")
        add("foot", t("confidential") .. " · " .. t("lang_code", { lang = (doc.lang or ""):upper() }) .. " · " .. docNo .. " v" .. tostring(doc.version or 1))
    elseif doc.type == "op" then
        header(t("surgery_department"))
        add("title", t("type_op"))
        patient()
        add("kv2", t("operation"), hk("erc.surgery_" .. tostring(b.surgery)), t("code"), tostring(b.code or ""))
        add("kv2", t("started"), dt(b.started, true), t("finished"), dt(b.finished, true))
        add("kv2", t("surgeon"), t("npc_surgeon"), t("blood_loss"), tostring(b.bloodLoss or 0) .. " ml")
        add("kv", t("result"), t("op_" .. tostring(b.result or (b.success and "success" or "death"))))
        patientEnd()
        sec(t("op_description"))
        add("text", t("op_desc_" .. tostring(b.surgery), nil, true))
        if (b.transfusions or 0) > 0 then add("text", t("op_transfusions", { n = b.transfusions })) end
        diagnoses(b.diagnoses)
        add("gap")
        add("sign", t("npc_surgeon"), t("surgeon"))
        footer()
    elseif doc.type == "death" then
        header()
        add("title", t("type_death"))
        patient()
        add("kv2", t("death_time"), dt(b.at, true), t("death_place"), tostring(b.place or ""))
        if b.arrivedDead then add("kv", t("arrived_dead"), t("yes")) end
        patientEnd()
        sec(t("death_cause"))
        if b.cause then add("row", { bno(b.cause), b.cause, "" }) else add("text", "—") end
        sec(t("death_circumstances"))
        local circ = b.circumstances == "or" and t("died_in_or") or b.circumstances
        add("text", (circ and circ ~= "") and circ or "—")
        diagnoses(b.diagnoses)
        if b.collectedBy == "npc" then add("text", t("collected_npc")) end
        add("gap")
        add("sign", b.by ~= "" and b.by or doc.author, t("examining_doctor"))
        footer()
    end
    return out
end

---------------------------------------------------------------- drawing

local PAPER_INK = tocolor(17, 17, 17)
local DIM = tocolor(90, 90, 90)

-- UI font (list, filters, title bar): Roboto; the paper itself is Tinos (font above)
local uiFonts = {}
local function ui(size, bold)
    local key = size .. (bold and "b" or "r")
    if not uiFonts[key] then
        uiFonts[key] = dxCreateFont(bold and "client/fonts/RobotoB.ttf" or "client/fonts/Roboto.ttf", math.max(6, math.floor(size * S + 0.5)), false, "antialiased")
            or (bold and "default-bold" or "default")
    end
    return uiFonts[key]
end

-- letter-spaced capitals for the document title (the paper samples: A M B U L Á N S   L A P)
local function spaced(text)
    local out = {}
    for ch in tostring(text):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch == " " and "  " or ch end
    return table.concat(out, " ")
end

-- The paper into x, y, w, h (a render target at 0, 0 normally). sheets[block] = ECG sheet texture.
-- Every document follows the paper samples of the plan: header with a rule, letter-spaced underlined
-- title, patient block with a rule, bold underlined section titles (h5), indented text, signature,
-- footer with a rule. Only the EMS case sheet (Mentési lap) keeps its grey section bars (sec).
local function drawPaper(x, y, w, h, sheets)
    dxDrawRectangle(x, y, w, h, tocolor(255, 255, 255))
    if not V.doc then
        return dxDrawText(t("pick_document"), x, y, x + w, y + h, DIM, 1, font(11), "center", "center")
    end
    V.blocks = V.blocks or build(V.doc)
    local ems = V.doc.type == "ems"
    local pad = s(30)
    local left, full = x + pad, w - 2 * pad
    local cx, cw = left, full
    local cy = y + pad - V.scroll
    local bottom = y + h
    local indent = ems and 0 or s(16)
    local function visible(hgt) return cy + hgt > y and cy < bottom end
    local function line(text, f, color, align, hgt, ix)
        ix = ix or 0
        local lines = L.wrap(tostring(text or ""), cw - ix, 1, f)
        for _, ln in ipairs(lines) do
            if visible(hgt) then dxDrawText(ln, cx + ix, cy, cx + cw, cy + hgt, color or PAPER_INK, 1, f, align or "left", "center", true) end
            cy = cy + hgt
        end
    end
    local function rule(thick)
        if visible(s(2)) then dxDrawRectangle(left, cy, full, thick or 1, PAPER_INK) end
    end
    local function langBadge()
        if V.doc.lang and visible(s(16)) then
            dxDrawRectangle(left + full - s(34), cy, s(34), s(16), tocolor(230, 230, 226))
            dxDrawText((V.doc.lang or ""):upper(), left + full - s(34), cy, left + full, cy + s(16), DIM, 1, font(8, true), "center", "center")
        end
    end
    for _, b in ipairs(V.blocks) do
        local k = b[1]
        if k == "hosp" then
            -- hospital / service block on the left, number and date on the right, a rule under it
            local lines = b[2]
            if visible(#lines * s(18)) then
                for i, ln in ipairs(lines) do
                    dxDrawText(tostring(ln), cx, cy + (i - 1) * s(18), cx + cw * 0.62, cy + i * s(18), i == 1 and PAPER_INK or DIM, 1, font(i == 1 and 11 or 9, i == 1), "left", "center", true)
                end
                local ri = 0
                for ln in tostring(b[3] or ""):gmatch("[^\n]+") do
                    dxDrawText(ln, cx + cw * 0.5, cy + ri * s(18), cx + cw, cy + (ri + 1) * s(18), PAPER_INK, 1, font(9, ri == 0), "right", "center", true)
                    ri = ri + 1
                end
            end
            cy = cy + #lines * s(18) + s(4)
            rule(s(1.5))
            cy = cy + s(8)
            langBadge()
        elseif k == "kv2" then
            -- two label - value pairs in one line
            local half = cw / 2
            if visible(s(18)) then
                dxDrawText(b[2] .. ":", cx, cy, cx + half * 0.42, cy + s(18), DIM, 1, font(9, true), "left", "center", true)
                dxDrawText(tostring(b[3] or ""), cx + half * 0.42, cy, cx + half - s(6), cy + s(18), PAPER_INK, 1, font(9), "left", "center", true)
                dxDrawText(b[4] .. ":", cx + half, cy, cx + half + half * 0.42, cy + s(18), DIM, 1, font(9, true), "left", "center", true)
                dxDrawText(tostring(b[5] or ""), cx + half + half * 0.42, cy, cx + cw, cy + s(18), PAPER_INK, 1, font(9), "left", "center", true)
            end
            cy = cy + s(18)
        elseif k == "rule" then
            -- end of the patient block
            cy = cy + s(4)
            rule(1)
            cy = cy + s(6)
        elseif k == "head" then
            local l1 = tostring(b[2]):gsub("\n", "  ·  ")
            local r1 = tostring(b[3]):gsub("\n", "  ·  ")
            if visible(s(20)) then
                dxDrawText(l1, cx, cy, cx + cw * 0.62, cy + s(20), PAPER_INK, 1, font(10, true), "left", "center", true)
                dxDrawText(r1, cx + cw * 0.62, cy, cx + cw, cy + s(20), PAPER_INK, 1, font(9), "right", "center", true)
            end
            cy = cy + s(22)
            rule(s(1.5))
            cy = cy + s(10)
            langBadge()
        elseif k == "title" then
            cy = cy + s(10)
            if ems then
                line(L.upper(b[2]), font(14, true), PAPER_INK, "center", s(26))
            else
                local txt = spaced(L.upper(b[2]))
                local f = font(13, true)
                local tw = math.min(cw, L.width(txt, 1, f))
                if visible(s(26)) then
                    dxDrawText(txt, cx, cy, cx + cw, cy + s(24), PAPER_INK, 1, f, "center", "center", true)
                    dxDrawRectangle(cx + (cw - tw) / 2, cy + s(22), tw, s(1.2), PAPER_INK)
                end
                cy = cy + s(26)
            end
            cy = cy + s(10)
        elseif k == "sec" then
            -- grey bar: the EMS case sheet only (build() gives h5 to every other document)
            cy = cy + s(6)
            if visible(s(20)) then
                dxDrawRectangle(cx, cy, cw, s(20), tocolor(110, 110, 110))
                dxDrawText(b[2], cx + s(6), cy, cx + cw, cy + s(20), tocolor(255, 255, 255), 1, font(9, true), "left", "center", true)
            end
            cy = cy + s(24)
        elseif k == "h5" then
            -- bold underlined section title
            cy = cy + s(8)
            local f = font(10, true)
            local tw = math.min(cw, L.width(tostring(b[2]), 1, f))
            if visible(s(20)) then
                dxDrawText(b[2], cx, cy, cx + cw, cy + s(20), PAPER_INK, 1, f, "left", "center", true)
                dxDrawRectangle(cx, cy + s(17), tw, 1, PAPER_INK)
            end
            cy = cy + s(22)
        elseif k == "kv" then
            if visible(s(18)) then
                dxDrawText(b[2] .. ":", cx + indent, cy, cx + cw * 0.3, cy + s(18), DIM, 1, font(9, true), "left", "center", true)
            end
            local save = cx
            cx, cw = cx + cw * 0.3, cw * 0.7
            line(b[3], font(9), PAPER_INK, "left", s(18))
            cx, cw = save, full
        elseif k == "row" then
            local cols = b[2]
            local n = #cols
            local widths = n == 5 and { 0.2, 0.2, 0.24, 0.18, 0.18 } or (n == 4 and { 0.38, 0.22, 0.18, 0.22 } or (n == 3 and { 0.5, 0.18, 0.32 } or { 0.35, 0.65 }))
            local rx, rw = cx + indent, cw - indent
            if visible(s(18)) then
                local xx = rx
                for i, col in ipairs(cols) do
                    dxDrawText(tostring(col), xx, cy, xx + rw * widths[i] - s(6), cy + s(18), b[3] and DIM or PAPER_INK, 1, font(9, b[3] == true), "left", "center", true)
                    xx = xx + rw * widths[i]
                end
                -- a header row of a table: a thin rule under it (non-EMS documents)
                if b[3] and not ems then dxDrawRectangle(rx, cy + s(17), rw, 1, tocolor(60, 60, 60)) end
            end
            cy = cy + s(18)
        elseif k == "text" then
            line(b[2], font(9), PAPER_INK, "left", s(18), indent)
        elseif k == "box" then
            cy = cy + s(8)
            local lines = {}
            for para in (tostring(b[3]) .. "\n"):gmatch("(.-)\n") do
                for _, ln in ipairs(L.wrap(para, cw - s(16), 1, font(9))) do lines[#lines + 1] = ln end
            end
            local bh = s(24) + #lines * s(16)
            if visible(bh) then
                dxDrawRectangle(cx, cy, cw, bh, tocolor(40, 40, 40))
                dxDrawRectangle(cx + 1, cy + 1, cw - 2, bh - 2, tocolor(255, 255, 255))
                dxDrawText(b[2], cx + s(8), cy + s(4), cx + cw, cy + s(20), PAPER_INK, 1, font(9, true), "left", "center")
                for i, ln in ipairs(lines) do dxDrawText(ln, cx + s(8), cy + s(20) + (i - 1) * s(16), cx + cw, cy + s(36) + (i - 1) * s(16), PAPER_INK, 1, font(9), "left", "center") end
            end
            cy = cy + bh
        elseif k == "img" then
            cy = cy + s(6)
            local tex = imageOf(b[2], b[3])
            local iw, ih = 384, 384
            if tex then iw, ih = dxGetMaterialSize(tex) end
            local sc = math.min((cw - indent) / iw, s(300) / ih)
            local dw, dh = iw * sc, ih * sc
            if visible(dh) then
                if tex then dxDrawImage(cx + indent, cy, dw, dh, tex) else
                    dxDrawRectangle(cx + indent, cy, dw, dh, tocolor(20, 20, 20))
                    dxDrawText(t("loading_image"), cx + indent, cy, cx + indent + dw, cy + dh, tocolor(200, 200, 200), 1, font(9), "center", "center")
                end
            end
            cy = cy + dh + s(2)
            if b[4] and b[4] ~= "" then line(b[4], font(8), DIM, "left", s(16), indent) end
        elseif k == "ecg12" then
            -- a 12-lead ECG from its spec (medsys renders the sheet; fetched before the render target)
            cy = cy + s(6)
            local dh = cw * 0.56
            if visible(dh) then
                local sh = sheets and sheets[b]
                if sh then
                    local sc = math.min(cw / sh[2], dh / sh[3])
                    dxDrawImage(cx + (cw - sh[2] * sc) / 2, cy + (dh - sh[3] * sc) / 2, sh[2] * sc, sh[3] * sc, sh[1])
                else
                    dxDrawRectangle(cx, cy, cw, dh, tocolor(255, 240, 240))
                end
            end
            cy = cy + dh + s(2)
            if b[3] and b[3] ~= "" then line(b[3], font(8), DIM, "left", s(16)) end
        elseif k == "gap" then
            cy = cy + s(18)
        elseif k == "sign" then
            if visible(s(56)) then
                for dx = 0, s(200), s(4) do dxDrawRectangle(cx + cw - s(200) + dx, cy + s(14), s(2), 1, DIM) end
                dxDrawText(tostring(b[2] or ""), cx + cw - s(200), cy + s(16), cx + cw, cy + s(34), PAPER_INK, 1, font(9, true), "center", "center")
                if b[3] then dxDrawText(tostring(b[3]), cx + cw - s(200), cy + s(34), cx + cw, cy + s(50), DIM, 1, font(8), "center", "center") end
            end
            cy = cy + s(56)
        elseif k == "foot" then
            if ems then
                line(b[2], font(8), DIM, "center", s(16))
            else
                rule(1)
                cy = cy + s(3)
                line(b[2], font(8), DIM, "left", s(16))
            end
        end
    end
    V.contentHeight = (cy + V.scroll) - y + pad
end

-- ECG sheets of the open document (medsys draws them into its own render targets on the first call)
local function ecgSheets()
    local out = {}
    if not V.blocks then return out end
    local res = getResourceFromName("medsys")
    if not res or getResourceState(res) ~= "running" then return out end
    for _, b in ipairs(V.blocks) do
        if b[1] == "ecg12" then
            local ok, rt, w, h = pcall(function() return exports.medsys:getECG12Sheet(b[2]) end)
            if ok and rt and isElement(rt) then out[b] = { rt, w, h } end
        end
    end
    return out
end

---------------------------------------------------------------- the paper area: render target, smooth scroll, scrollbar

local paperRT, rtW, rtH
local function paperTarget(w, h)
    w, h = math.floor(w), math.floor(h)
    if w < 8 or h < 8 then return nil end
    if not (paperRT and isElement(paperRT) and rtW == w and rtH == h) then
        if paperRT and isElement(paperRT) then destroyElement(paperRT) end
        paperRT = dxCreateRenderTarget(w, h, false)
        rtW, rtH = w, h
    end
    return paperRT
end
addEventHandler("onClientRestore", root, function() if paperRT and isElement(paperRT) then destroyElement(paperRT) end paperRT = nil end)

local SCROLL_STEP = 54   -- design px per wheel notch
local hits = {}
local lastFrame = getTickCount()

local function maxScroll(ph) return math.max(0, (V.contentHeight or 0) - ph) end

-- reader background + the paper (centred, at most 860 px wide) + its scrollbar
local function drawPaperArea(ax, ay, aw, ah, readerColor, w7)
    dxDrawRectangle(ax, ay, aw, ah, readerColor)
    local sbW = s(14)
    local pw = math.min(aw - sbW - s(28), s(860))
    local px = ax + (aw - sbW - pw) / 2
    local py, ph = ay + s(12), ah - s(12)
    V.paperArea = { ax, ay, aw, ah }
    V.pageH = ph
    -- smooth scroll towards the target
    local now = getTickCount()
    local dt = math.min(0.1, (now - lastFrame) / 1000)
    lastFrame = now
    local mx = maxScroll(ph)
    V.target = math.max(0, math.min(V.target or 0, mx))
    if V.sbDrag then V.scroll = V.target
    else V.scroll = V.scroll + (V.target - V.scroll) * math.min(1, dt * 14) end
    if math.abs(V.target - V.scroll) < 0.5 then V.scroll = V.target end
    -- the paper, clipped by a render target
    local sheets = ecgSheets()
    local rt = paperTarget(pw, ph)
    if rt then
        -- an opaque target (the paper is white everywhere): normal blending, no alpha tricks needed
        dxSetRenderTarget(rt, true)
        drawPaper(0, 0, pw, ph, sheets)
        dxSetRenderTarget()
        dxDrawImage(px, py, pw, ph, rt)
    else
        drawPaper(px, py, pw, ph, sheets)   -- no video memory for the target: unclipped
    end
    -- scrollbar (Win7 look inside the hospital PC)
    local sx, sy, sh = ax + aw - sbW, ay, ah
    dxDrawRectangle(sx, sy, sbW, sh, w7 and tocolor(42, 47, 53) or tocolor(30, 36, 43))
    dxDrawRectangle(sx, sy, 1, sh, tocolor(17, 17, 17))
    local total = math.max(ph, V.contentHeight or ph)
    local thumbH = math.max(s(30), sh * ph / total)
    local thumbY = sy + (sh - thumbH) * ((mx > 0) and (V.scroll / mx) or 0)
    if mx > 0 then
        local cxp, cyp = getCursorPosition()
        local hov = V.sbDrag or (cxp and (function() local a, b = cxp * SX, cyp * SY return a >= sx and a <= sx + sbW and b >= thumbY and b <= thumbY + thumbH end)())
        local c1 = hov and tocolor(110, 122, 136) or tocolor(84, 94, 106)
        dxDrawRectangle(sx + s(2), thumbY + 1, sbW - s(4), thumbH - 2, c1)
        dxDrawRectangle(sx + s(2), thumbY + 1, s(1), thumbH - 2, tocolor(255, 255, 255, 40))
        -- the track pages, the thumb drags
        hits[#hits + 1] = { sx, sy, sbW, sh, function(_, cy2)
            if cy2 >= thumbY and cy2 <= thumbY + thumbH then
                V.sbDrag = { grab = cy2 - thumbY, top = sy, range = sh - thumbH, max = mx }
            elseif cy2 < thumbY then V.target = V.target - ph * 0.9
            else V.target = V.target + ph * 0.9 end
        end }
    end
end

addEventHandler("onClientCursorMove", root, function(_, _, ax, ay)
    local d = V.sbDrag
    if not d or not V.open then return end
    if d.range <= 0 then return end
    V.target = math.max(0, math.min(d.max, (ay - d.top - d.grab) / d.range * d.max))
end)

---------------------------------------------------------------- frame: standalone panel or embedded in the hospital PC

local function inside(px, py, x, y, w, h) return px >= x and px <= x + w and py >= y and py <= y + h end
local function hovered(x, y, w, h)
    if not isCursorShowing() then return false end
    local cx, cy = getCursorPosition()
    return inside(cx * SX, cy * SY, x, y, w, h)
end

local FILTERS = { { "all", nil }, { "type_ems", "ems" }, { "type_amb", "amb" }, { "type_lab", "lab" }, { "type_ct", "ct" }, { "type_xray", "xray" },
                  { "type_fast", "fast" }, { "type_ecg", "ecg" }, { "type_op", "op" }, { "type_death", "death" } }

local function canEdit() return V.doc and V.doc.type == "ems" and V.doc.editable end
local function startEdit() V.editing = { id = V.doc.id, step = "epicrisis" } editStep() end

-- the filter buttons (w7: flat toolbar buttons with a frame on hover / when on)
local function drawFilters(fx, fy, maxX, fh, w7)
    for _, f in ipairs(FILTERS) do
        if not (V.filter.only and f[2] ~= V.filter.only and f[2] ~= nil) then
            local label = t(f[1])
            local fw = L.width(label, 1, ui(9, true)) + s(18)
            if fx + fw > maxX then break end
            local on = V.filter.type == f[2]
            local hov = hovered(fx, fy, fw, fh)
            if w7 then
                if on or hov then
                    dxDrawRectangle(fx, fy, fw, fh, tocolor(90, 103, 117))
                    dxDrawRectangle(fx + 1, fy + 1, fw - 2, fh - 2, on and tocolor(58, 70, 84) or tocolor(52, 60, 70))
                    dxDrawRectangle(fx + 1, fy + 1, fw - 2, 1, tocolor(255, 255, 255, 30))
                end
            else
                dxDrawRectangle(fx, fy, fw, fh, on and tocolor(47, 134, 232) or (hov and tocolor(52, 60, 70) or tocolor(39, 46, 55)))
            end
            dxDrawText(label, fx, fy, fx + fw, fy + fh, tocolor(233, 237, 242), 1, ui(9, on), "center", "center")
            hits[#hits + 1] = { fx, fy, fw, fh, function()
                V.filter.type = f[2]
                triggerServerEvent("docs:list", resourceRoot, V.filter)
            end }
            fx = fx + fw + s(4)
        end
    end
end

-- the document list (w7: Explorer-like selection)
local function drawList(lx, ly, lw, lh, w7)
    local rowH = s(46)
    local visible = math.max(1, math.floor(lh / rowH))
    V.listScroll = math.max(0, math.min(V.listScroll, #V.list - visible))
    for i = 1, math.min(visible, #V.list - V.listScroll) do
        local d = V.list[i + V.listScroll]
        local ry = ly + (i - 1) * rowH
        local on = V.doc and V.doc.id == d.id
        local hov = hovered(lx, ry, lw, rowH - s(4))
        if w7 then
            if on then
                dxDrawRectangle(lx, ry, lw, rowH - s(4), tocolor(79, 140, 196))
                dxDrawRectangle(lx + 1, ry + 1, lw - 2, rowH - s(4) - 2, tocolor(38, 72, 104))
                dxDrawRectangle(lx + 1, ry + 1, lw - 2, (rowH - s(4)) / 2, tocolor(255, 255, 255, 18))
            elseif hov then
                dxDrawRectangle(lx, ry, lw, rowH - s(4), tocolor(64, 84, 104))
                dxDrawRectangle(lx + 1, ry + 1, lw - 2, rowH - s(4) - 2, tocolor(40, 50, 61))
            end
        else
            dxDrawRectangle(lx, ry, lw, rowH - s(4), on and tocolor(30, 60, 100) or (hov and tocolor(39, 46, 55) or tocolor(30, 36, 43)))
        end
        dxDrawText(("%s  ·  %s"):format(d.no ~= "" and d.no or ("#" .. d.id), t("type_" .. d.type)), lx + s(10), ry + s(2), lx + lw - s(6), ry + s(22), tocolor(233, 237, 242), 1, ui(9, true), "left", "center", true)
        dxDrawText(("%s  ·  %s  ·  %s"):format(d.patient ~= "" and d.patient or t("unknown"), d.author or "", dt(d.created, true)), lx + s(10), ry + s(20), lx + lw - s(6), ry + s(40), tocolor(152, 162, 174), 1, ui(8), "left", "center", true)
        hits[#hits + 1] = { lx, ry, lw, rowH - s(4), function() triggerServerEvent("docs:get", resourceRoot, d.id) end }
    end
    if #V.list == 0 then dxDrawText(t("no_documents"), lx, ly, lx + lw, ly + s(40), tocolor(152, 162, 174), 1, ui(9), "center", "center") end
    V.listArea = { lx, ly, lw, lh }
end

-- standalone panel (the EMS / admin /dokumentumok view)
local function drawStandalone()
    local w, h = math.min(s(1240), SX - s(40)), math.min(s(760), SY - s(40))
    local x, y = (SX - w) / 2, (SY - h) / 2
    dxDrawRectangle(x - s(6), y - s(6), w + s(12), h + s(12), tocolor(16, 18, 21))
    dxDrawRectangle(x, y, w, h, tocolor(21, 25, 30))
    local lx, ly, lw, lh = x + s(10), y + s(54), s(360), h - s(64)
    drawPaperArea(x + s(380), y + s(54), w - s(390), h - s(64), tocolor(74, 80, 88), false)
    drawList(lx, ly, lw, lh, false)
    -- header over everything
    dxDrawRectangle(x, y, w, s(44), tocolor(14, 17, 21))
    dxDrawText(t("title"), x + s(16), y, x + w, y + s(44), tocolor(233, 237, 242), 1, ui(12, true), "left", "center")
    local bx = x + w - s(44)
    dxDrawRectangle(bx, y + s(8), s(32), s(28), hovered(bx, y + s(8), s(32), s(28)) and tocolor(150, 50, 50) or tocolor(60, 40, 44))
    dxDrawText("X", bx, y + s(8), bx + s(32), y + s(36), tocolor(255, 255, 255), 1, ui(10, true), "center", "center")
    hits[#hits + 1] = { bx, y + s(8), s(32), s(28), closeDocuments }
    local maxX = bx - s(10)
    if canEdit() then
        local ex = bx - s(150)
        dxDrawRectangle(ex, y + s(8), s(140), s(28), tocolor(47, 134, 232))
        dxDrawText(t("edit_sheet"), ex, y + s(8), ex + s(140), y + s(36), tocolor(255, 255, 255), 1, ui(9, true), "center", "center")
        hits[#hits + 1] = { ex, y + s(8), s(140), s(28), startEdit }
        maxX = ex - s(10)
    end
    drawFilters(x + s(200), y + s(10), maxX, s(24), false)
end

-- embedded in the hospital PC window (med_hospitals er/client/w7.lua gives the rectangle): toolbar
-- with the filters, list on the left, the paper on a grey reader background on the right
local function drawEmbedded(x, y, w, h)
    local tbH = s(34)
    -- toolbar
    dxDrawRectangle(x, y, w, tbH, tocolor(40, 46, 53))
    dxDrawRectangle(x, y, w, tbH / 2, tocolor(255, 255, 255, 8))
    dxDrawRectangle(x, y + tbH - 1, w, 1, tocolor(17, 17, 17))
    local maxX = x + w - s(8)
    if canEdit() then
        local ew = L.width(t("edit_sheet"), 1, ui(9, true)) + s(26)
        local ex = x + w - ew - s(8)
        local hov = hovered(ex, y + s(5), ew, tbH - s(10))
        dxDrawRectangle(ex, y + s(5), ew, tbH - s(10), tocolor(43, 106, 168))
        dxDrawRectangle(ex + 1, y + s(6), ew - 2, tbH - s(12), hov and tocolor(70, 130, 190) or tocolor(52, 108, 162))
        dxDrawText(t("edit_sheet"), ex, y + s(5), ex + ew, y + tbH - s(5), tocolor(255, 255, 255), 1, ui(9, true), "center", "center")
        hits[#hits + 1] = { ex, y + s(5), ew, tbH - s(10), startEdit }
        maxX = ex - s(10)
    end
    drawFilters(x + s(8), y + s(5), maxX, tbH - s(10), true)
    -- list
    local lw = math.min(s(330), w * 0.32)
    local by, bh = y + tbH, h - tbH
    dxDrawRectangle(x, by, lw, bh, tocolor(30, 34, 39))
    dxDrawRectangle(x + lw, by, 1, bh, tocolor(58, 66, 75))
    drawList(x + s(4), by + s(4), lw - s(8), bh - s(8), true)
    -- paper
    drawPaperArea(x + lw + 1, by, w - lw - 1, bh, tocolor(90, 96, 104), true)
end

addEventHandler("onClientRender", root, function()
    if not V.open then return end
    hits = {}
    if V.embed then
        local r = V.rect
        if not r then V.listArea, V.paperArea = nil, nil return end
        drawEmbedded(r[1], r[2], r[3], r[4])
    else
        drawStandalone()
    end
end, true, "low-5")

addEventHandler("onClientClick", root, function(button, state, ax, ay)
    if not V.open or button ~= "left" then return end
    if state == "up" then V.sbDrag = nil return end
    if V.embed and not V.rect then return end
    for i = #hits, 1, -1 do
        local hh = hits[i]
        if inside(ax, ay, hh[1], hh[2], hh[3], hh[4]) then return hh[5](ax, ay) end
    end
end)

-- wheel over the list or the paper; PgUp / PgDn, Home / End, arrows on the paper; ESC closes the
-- standalone panel (embedded: the PC closes the window)
function documentsKey(key)
    if not V.open or (V.embed and not V.rect) then return false end
    local cx, cy = getCursorPosition()
    cx, cy = (cx or 0) * SX, (cy or 0) * SY
    local d = (key == "mouse_wheel_down" and 1) or (key == "mouse_wheel_up" and -1) or 0
    if d ~= 0 then
        if V.listArea and inside(cx, cy, unpack(V.listArea)) then V.listScroll = V.listScroll + d return true end
        if V.paperArea and inside(cx, cy, unpack(V.paperArea)) then V.target = (V.target or 0) + d * s(SCROLL_STEP) return true end
        return false
    end
    local page = (V.pageH or s(600)) * 0.9
    if key == "pgdn" then V.target = (V.target or 0) + page
    elseif key == "pgup" then V.target = (V.target or 0) - page
    elseif key == "home" then V.target = 0
    elseif key == "end" then V.target = math.huge
    elseif key == "arrow_d" then V.target = (V.target or 0) + s(SCROLL_STEP)
    elseif key == "arrow_u" then V.target = (V.target or 0) - s(SCROLL_STEP)
    else return false end
    return true
end

addEventHandler("onClientKey", root, function(key, press)
    if not V.open or not press then return end
    if getElementData(localPlayer, "textInputOpen") then return end
    if documentsKey(key) then
        if key:find("^mouse_wheel") == nil then cancelEvent() end
        return
    end
    if key == "escape" and not V.embed then
        cancelEvent()
        closeDocuments()
    end
end)
