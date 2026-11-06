-- ER outcomes and the departments behind them (plan: Műtő, Intenzív, Elfekvő, Hullakezelés):
--   * discharge, ward (2 x 6 fixed beds, 20 min), ICU (4 beds, 30 min), transfer (S1 / S2, transfer.lua)
--   * operating theatre: NPC surgeon, 3-10 min, one patient + one waiting place at the handover point
--     (Ú10, PCI / craniotomy / thrombectomy / pericardiotomy first); a Physician sends, a Resident asks
--     and a Physician approves (Ú2; without a Physician on duty the Resident sends). The result is decided
--     at the start: success / complication (-> ICU) / death; the patient comes out on a new stretcher
--     at the post-op point. The marker card shows the time left and the waiting patient.
--   * death: the Physician records time, cause (BNO) and circumstances; the body stays on the stretcher
--     (pushable) until the morgue drop point; nobody takes it in 20 min -> NPC morgue staff (Ú4)
-- Ward / ICU / OR / morgue take the patient when the stretcher is put down at their point (onStretcherSettled).

local OR = {}           -- [hospitalId] = { case, ends, surgery, result, started } while busy
local queue = {}        -- [hospitalId] = { { case, obj, surgery, priority, at }, ... } waiting at the handover point
local beds = {}         -- [hospitalId] = { ward = { { obj, case, ward } }, icu = { ... } }
local SETTLE_RANGE = 1.8
local HANDOVER_TIME = 5000
local QUEUE_MAX = 1     -- the waiting place; a priority operation may wait beside a normal one

local function eq() return ER.running("med_equipments") and exports.med_equipments or nil end
local function ms() return ER.running("medsys") and exports.medsys or nil end
local function now() return getRealTime().timestamp end
local function d2(x1, y1, x2, y2) return ((x1 - x2) ^ 2 + (y1 - y2) ^ 2) ^ 0.5 end

---------------------------------------------------------------- beds

local function buildBeds(e)
    local m = eq()
    if not m then return end
    local h, hid = e.h, e.h.id
    beds[hid] = { ward = {}, icu = {} }
    for _, w in ipairs(e.cfg.wards or {}) do
        for _, b in ipairs(w.beds or {}) do
            local obj = m:createHospitalBed(hid .. ":bed", b.x, b.y, b.z, b.rot or 0, h.dimension, h.interior)
            if obj then table.insert(beds[hid].ward, { obj = obj, ward = w.id }) end
        end
    end
    for _, b in ipairs((e.cfg.icu or {}).beds or {}) do
        local obj = m:createHospitalBed(hid .. ":bed", b.x, b.y, b.z, b.rot or 0, h.dimension, h.interior)
        if obj then table.insert(beds[hid].icu, { obj = obj }) end
    end
end

local function destroyBeds()
    local m = eq()
    for _, b in pairs(beds) do
        for _, list in pairs(b) do
            for _, bed in ipairs(list) do
                if bed.case and isElement(bed.case.ped) then destroyElement(bed.case.ped) end
                if m and isElement(bed.obj) then m:destroyHospitalBed(bed.obj) end
            end
        end
    end
    beds = {}
end

local oldBuild = ER.buildHospital
ER.buildHospital = function(e)
    if oldBuild then oldBuild(e) end
    buildBeds(e)
    local s, h = e.cfg.morgue, e.h
    local push = L.msg("med_hospitals.config.push_patient_in_on_stretcher")
    -- where / wardId: the handover the point does (the 3 s walk-in handover, ER.walkInHandover)
    local function point(p, r, g, b, cardId, card, where, wardId)
        local mk = ER.track(createMarker(p.x, p.y, p.z - 0.05, "cylinder", 1.6, r, g, b, ER.MARKER_ALPHA))
        setElementInterior(mk, h.interior) setElementDimension(mk, h.dimension)
        if ER.running("work_core") then exports.work_core:setElementVisibleToWork(mk, "hospital") end
        card.name = h.name or ""
        ER.markerCard(mk, h.id .. ":" .. cardId, card)
        ER.walkInHandover(e, mk, "er:" .. h.id .. ":" .. cardId, where, wardId)
    end
    if s then
        point(s, 120, 120, 130, "morgue", { title = L.msg("med_hospitals.his.ev_morgue"),
            hint = L.msg("med_hospitals.erc.take_to_morgue"), color = { 150, 150, 160 } }, "morgue")
    end
    if e.cfg.surgery and e.cfg.surgery.handover then
        point(e.cfg.surgery.handover, 70, 150, 220, "surgery", { title = L.msg("med_hospitals.his.out_surgery"), hint = push }, "surgery")
    end
    if e.cfg.icu and e.cfg.icu.handover then
        point(e.cfg.icu.handover, 70, 150, 220, "icu", { title = L.msg("med_hospitals.erc.outcome_icu"), hint = push }, "icu")
    end
    for i, w in ipairs(e.cfg.wards or {}) do
        point(w.handover, 70, 150, 220, w.id or ("ward" .. i), { title = L.msg("med_hospitals.erc.outcome_ward"), hint = push }, "ward", w.id)
    end
end
UnloadHandlers[#UnloadHandlers + 1] = destroyBeds

local function freeBed(hid, kind)
    for _, bed in ipairs(beds[hid] and beds[hid][kind] or {}) do
        if not bed.case and isElement(bed.obj) then return bed end
    end
end

local function bedCount(hid, kind)
    local used, total = 0, 0
    for _, bed in ipairs(beds[hid] and beds[hid][kind] or {}) do
        total = total + 1
        if bed.case then used = used + 1 end
    end
    return used, total
end

---------------------------------------------------------------- closing a case

local function closeWithDoc(c, outcome, by)
    c.outcome = outcome
    if ER.writeAmbulatory then ER.writeAmbulatory(c, outcome, by) end
    if isElement(by) and #(c.diagnoses or {}) > 0 then
        ER.points(by, "HK-A05", 6, L.forPlayer(by, "med_hospitals.erc.code_a05"), c)
        local good = ER.correctDiagnoses and ER.correctDiagnoses(c) or 0
        if good > 0 then ER.points(by, "HK-DX", 2 * good, L.forPlayer(by, "med_hospitals.erc.code_dx"), c) end
    end
    if isElement(c.treating) and #(c.diagnoses or {}) > 0 and not c.bonusPaid then
        -- case bonus of the treating doctor: 15 % of the case's points (salary only, not care value)
        local bonus = math.floor((c.pointsTotal or 0) * ERC.CASE_BONUS + 0.5)
        if bonus > 0 then
            c.bonusPaid = true
            ER.points(c.treating, "HK-CASE", bonus, L.forPlayer(c.treating, "med_hospitals.erc.code_case"))
        end
    end
end

local function removePatient(c)
    local m = eq()
    local ped = c.ped
    local st = m and isElement(ped) and m:getPatientStretcher(ped)
    ER.closeCase(c, c.outcome)
    if isElement(ped) then destroyElement(ped) end
    if st and m and m:isHospitalStretcher(st) then setTimer(function() if isElement(st) then m:destroyHospitalStretcher(st) end end, 200, 1) end
end

---------------------------------------------------------------- surgery: which operation, who sends (Ú2)

-- the findings an operation ends (besides the finding's own "surgery")
local SURGERY_TREATS = {
    thoracotomy = { htx = true }, thrombectomy = { stroke_isch = true },
    vascular = { wound_arm = true, wound_leg = true },
    debridement = { wound_arm = true, wound_leg = true, wound_torso = true, wound_head = true, wound_neck = true },
}
local function treatsFinding(sid, fid)
    local d = ERC.FINDINGS[fid]
    if d and d.surgery == sid then return true end
    return SURGERY_TREATS[sid] and SURGERY_TREATS[sid][fid] or false
end

-- the operations the confirmed (or visible) untreated findings need: { { id, finding } }, priority first
function ER.surgeryOptions(c)
    local rev = ER.revealed and ER.revealed(c) or {}
    local out, seen = {}, {}
    local function add(sid, fid)
        if ERC.SURGERIES[sid] and not seen[sid] then seen[sid] = true out[#out + 1] = { id = sid, finding = fid } end
    end
    for _, f in ipairs(ER.findings(c)) do
        local d = ERC.FINDINGS[f.id]
        if d and not f.treated and (rev[f.id] or d.visible or d.suture) then
            if d.surgery then add(d.surgery, f.id) end
            if f.id == "htx" and f.thoracotomy then add("thoracotomy", f.id) end
            if f.id == "stroke_isch" then add("thrombectomy", f.id) end
            if f.id == "wound_arm" or f.id == "wound_leg" then add("vascular", f.id) end
            if d.suture then add("debridement", f.id) end
        end
    end
    table.sort(out, function(a, b)
        local pa, pb = ERC.SURGERIES[a.id].priority and 1 or 0, ERC.SURGERIES[b.id].priority and 1 or 0
        if pa ~= pb then return pa > pb end
        return a.id < b.id
    end)
    return out
end

local function physiciansOnDuty(hid)
    local out = {}
    for _, p in ipairs(ER.staff(hid)) do if ER.can(p, "er.surgery") then out[#out + 1] = p end end
    return out
end

local function sendToSurgery(c, player, sid, approvedBy)
    local o = ERC.OUTCOMES.surgery
    c.pending = { kind = "surgery", surgery = sid, by = approvedBy or player, requestedBy = approvedBy and player or nil, code = o.code, points = o.points }
    ER.log(c, "surgery_order", sid, approvedBy or player)
    ER.syncCase(c)
    if isElement(player) then ER.notify(player, L.forPlayer(player, "med_hospitals.erc.push_to_surgery")) end
    if approvedBy and isElement(approvedBy) and approvedBy ~= player then
        ER.notify(approvedBy, L.forPlayer(approvedBy, "med_hospitals.erc.surgery_approved_you", { name = c.name or "?" }))
    end
end

local function requestSurgery(c, player, sid)
    local opts = ER.surgeryOptions(c)
    if not ERC.SURGERIES[sid] then sid = opts[1] and opts[1].id end
    local ok = false
    for _, o in ipairs(opts) do if o.id == sid then ok = true end end
    if not sid or not ok then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.no_surgery_needed"), true) end
    if #(c.diagnoses or {}) == 0 then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.diagnosis_first"), true) end
    if ER.can(player, "er.surgery") then return sendToSurgery(c, player, sid) end
    -- Ú2: a Resident asks, a Physician approves; no Physician on duty -> the Resident sends
    if not ER.can(player, "er.surgery_request") then
        local _, needName = ER.can(player, "er.surgery")
        return ER.notify(player, L.forPlayer(player, "med_hospitals.er.rank_needed", { rank = needName or "?" }), true)
    end
    local docs = physiciansOnDuty(c.hospital)
    if #docs == 0 then return sendToSurgery(c, player, sid) end
    c.pending = { kind = "surgery_request", surgery = sid, by = player, at = now() }
    ER.log(c, "surgery_request", sid, player)
    ER.syncCase(c)
    ER.notify(player, L.forPlayer(player, "med_hospitals.erc.surgery_requested"))
    for _, p in ipairs(docs) do
        ER.notify(p, L.forPlayer(p, "med_hospitals.erc.surgery_request_alert", { name = c.name or "?", by = getPlayerName(player),
            what = L.forPlayer(p, "med_hospitals.erc.surgery_" .. sid) }), true)
    end
end

local function answerRequest(c, player, approve)
    local p = c.pending
    if not p or p.kind ~= "surgery_request" then return end
    if not ER.canDo(player, "er.surgery") then return end
    if approve then
        sendToSurgery(c, isElement(p.by) and p.by or player, p.surgery, player)
    else
        c.pending = nil
        ER.log(c, "surgery_rejected", p.surgery, player)
        ER.syncCase(c)
        if isElement(p.by) then ER.notify(p.by, L.forPlayer(p.by, "med_hospitals.erc.surgery_rejected", { name = c.name or "?" }), true) end
    end
end

---------------------------------------------------------------- death record (Orvos: time, cause, circumstances)

local DEFAULT_CAUSE = "R9600"

local function recordDeath(c, player, arg, snap)
    if not (snap.dead or snap.clinicalDeath or c.dead) then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.not_dead"), true)
    end
    if c.deathAt then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.death_recorded_already"), true) end
    arg = type(arg) == "table" and arg or {}
    local cause = type(arg.cause) == "string" and arg.cause:upper():gsub("[^%w]", ""):sub(1, 6) or ""
    if cause == "" then cause = c.diagnoses and c.diagnoses[1] or DEFAULT_CAUSE end
    if ER.running("med_docs") and not exports.med_docs:getBNO(cause) then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.death_cause_invalid", { code = cause }), true)
    end
    if snap.clinicalDeath and not snap.dead and ms() then ms():setMedicalState(c.ped, "consciousness", "dead") end
    local o = ERC.OUTCOMES.death
    c.dead, c.status = true, "dead"
    c.deathAt, c.deathBy = now(), getPlayerName(player)
    c.deathCause = cause
    c.deathCircumstances = type(arg.text) == "string" and arg.text:gsub("[%c]", " "):sub(1, 300) or ""
    c.pending = { kind = "morgue" }
    ER.points(player, o.code, o.points, L.forPlayer(player, "med_hospitals.erc.outcome_death"), c)
    closeWithDoc(c, "death", player)
    ER.log(c, "outcome", "death " .. cause, player)
    ER.syncCase(c)
    ER.notify(player, L.forPlayer(player, "med_hospitals.erc.take_to_morgue"))
end

---------------------------------------------------------------- outcome actions (his:action "outcome")

local function need(c, player, kind)
    local o = ERC.OUTCOMES[kind]
    if not o then return false end
    local ok, needName = ER.can(player, o.need)
    if not ok then ER.notify(player, L.forPlayer(player, "med_hospitals.er.rank_needed", { rank = needName or "?" }), true) return false end
    if kind ~= "death" and #(c.diagnoses or {}) == 0 then
        ER.notify(player, L.forPlayer(player, "med_hospitals.erc.diagnosis_first"), true) return false
    end
    return o
end

function ER.setOutcome(c, player, kind, arg)
    if kind == "retake" then
        if not c.bed then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.retake_not_in_bed"), true) end
        return ER.retake(c, player)
    end
    if kind == "surgery_approve" or kind == "surgery_reject" then return answerRequest(c, player, kind == "surgery_approve") end
    if c.outcome and kind ~= "death" then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.outcome_set"), true) end
    local snap = ms() and ms():getMedicalState(c.ped) or {}
    if kind == "surgery" then
        if snap.dead then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.patient_dead"), true) end
        if c.pending and (c.pending.kind == "surgery" or c.pending.kind == "surgery_request") then
            return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.outcome_set"), true)
        end
        return requestSurgery(c, player, arg)
    end
    local o = need(c, player, kind)
    if not o then return end
    if kind == "death" then return recordDeath(c, player, arg, snap) end
    if snap.dead then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.patient_dead"), true) end

    if kind == "discharge" then
        ER.points(player, o.code, o.points, L.forPlayer(player, "med_hospitals.erc.outcome_discharge"), c)
        closeWithDoc(c, "discharge", player)
        ER.log(c, "outcome", "discharge", player)
        if (snap.systolic or 120) < 90 or (snap.spo2 or 99) < 90 then c.riskyDischarge = true end
        ER.notify(player, L.forPlayer(player, "med_hospitals.erc.discharged", { name = c.name or "?" }))
        removePatient(c)
    elseif kind == "ward" or kind == "icu" then
        local used, total = bedCount(c.hospital, kind)
        if used >= total then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.no_bed_" .. kind), true) end
        c.pending = { kind = kind, department = arg, by = player, code = o.code, points = o.points }
        ER.syncCase(c)
        ER.notify(player, L.forPlayer(player, "med_hospitals.erc.push_to_" .. kind))
    elseif kind == "transfer_s1" or kind == "transfer_s2" then
        if ER.requestTransfer then ER.requestTransfer(c, player, kind == "transfer_s1" and "S1" or "S2", arg) end
    end
end

---------------------------------------------------------------- handover points (stretcher put down)

local function settleAt(e, x, y)
    local cfg = e.cfg
    if cfg.morgue and d2(x, y, cfg.morgue.x, cfg.morgue.y) <= SETTLE_RANGE then return "morgue" end
    if cfg.icu and cfg.icu.handover and d2(x, y, cfg.icu.handover.x, cfg.icu.handover.y) <= SETTLE_RANGE then return "icu" end
    if cfg.surgery and cfg.surgery.handover and d2(x, y, cfg.surgery.handover.x, cfg.surgery.handover.y) <= SETTLE_RANGE + 0.8 then return "surgery" end
    for _, w in ipairs(cfg.wards or {}) do
        if d2(x, y, w.handover.x, w.handover.y) <= SETTLE_RANGE then return "ward", w.id end
    end
end

local function toBed(c, kind, wardId, obj, by)
    local m = eq()
    local bed
    for _, b in ipairs(beds[c.hospital] and beds[c.hospital][kind] or {}) do
        if not b.case and (not wardId or b.ward == wardId) then bed = b break end
    end
    bed = bed or freeBed(c.hospital, kind)
    if not bed then return ER.notify(by, L.forPlayer(by, "med_hospitals.erc.no_bed_" .. kind), true) end
    if not m:putPatientOnStretcher(bed.obj, c.ped) then return end
    bed.case = c
    c.bed, c.location = bed, kind == "icu" and "icu" or (bed.ward or "ward")
    c.status = kind
    c.stayEnds = now() + (kind == "icu" and ERC.TIMES.icu or ERC.TIMES.ward)
    c.paused = false
    if kind == "icu" then c.icuSince, c.lastVisit = now(), now() end
    local p = c.pending
    c.pending = nil
    if p and isElement(p.by) then ER.points(p.by, p.code, p.points, L.forPlayer(p.by, "med_hospitals.erc.outcome_" .. kind), c) end
    if isElement(by) and by ~= (p and p.by) then ER.points(by, "HK-T06", 2, L.forPlayer(by, "med_hospitals.erc.code_t06"), c) end
    closeWithDoc(c, kind, p and p.by or by)
    c.outcome = kind
    ER.log(c, "move", kind, by)
    ER.syncCase(c)
    setTimer(function() if isElement(obj) then m:destroyHospitalStretcher(obj) end end, 200, 1)
end

-- the risk of the operation from the patient's state: shock index, time to the OR, blood given, other
-- untreated critical findings, age -> death, complication probabilities
local function surgeryRisk(c, sid, snap)
    local risk = 0
    local hr, sys = snap.heartRate or 80, snap.systolic or 120
    local si = sys > 0 and hr / sys or 2
    if si > 1.4 then risk = risk + 0.22 elseif si > 1.0 then risk = risk + 0.1 end
    local mins = (now() - (c.created or now())) / 60
    if mins > 30 then risk = risk + 0.12 elseif mins > 15 then risk = risk + 0.06 end
    local bp = snap.bloodPercent or 100
    if bp < 70 then risk = risk + ((c.transfusions and #c.transfusions > 0) and 0.06 or 0.16) end
    for _, f in ipairs(ER.findings(c)) do
        local d = ERC.FINDINGS[f.id]
        if d and d.critical and not f.treated and not treatsFinding(sid, f.id) then risk = risk + 0.06 end
    end
    local age = tonumber(c.age) or 40
    if age > 80 then risk = risk + 0.12 elseif age > 65 then risk = risk + 0.06 end
    if snap.clinicalDeath then risk = risk + 0.4 end
    local death = math.min(0.85, 0.02 + risk * 0.45)
    local complication = math.min(0.6, 0.06 + risk * 0.7)
    return death, complication
end
ER.surgeryRisk = surgeryRisk

local MAJOR = { laparotomy = true, liver = true, splenectomy = true, craniotomy = true, thoracotomy = true, vascular = true, pelvis_exfix = true }

local function orCard(hid)
    if not ER.running("ui_core") then return end
    local o, q = OR[hid], queue[hid] or {}
    local hint
    if o then
        local left = math.max(0, o.ends - now())
        hint = L.msg("med_hospitals.erc.or_card_busy", { min = math.floor(left / 60), sec = ("%02d"):format(left % 60), n = #q })
    elseif #q > 0 then
        hint = L.msg("med_hospitals.erc.or_card_queue", { n = #q })
    else
        hint = L.msg("med_hospitals.config.push_patient_in_on_stretcher")
    end
    exports.ui_core:updateMarkerUI("er:" .. hid .. ":surgery", { hint = hint })
end

local function startSurgery(c, obj, by)
    local hid = c.hospital
    local m = eq()
    local sid = c.pending.surgery
    local s = ERC.SURGERIES[sid]
    m:takePatientOff(obj)
    setTimer(function() if isElement(obj) then m:destroyHospitalStretcher(obj) end end, 200, 1)
    local ped = c.ped
    setElementFrozen(ped, true)
    setElementCollisionsEnabled(ped, false)
    setElementDimension(ped, 64999)   -- invisible, the medsys state lives on
    local snap = ms() and ms():getMedicalState(ped) or {}
    local pDeath, pComp = surgeryRisk(c, sid, snap)
    local r = math.random()
    local result = r < pDeath and "death" or (r < pDeath + pComp and "complication" or "success")
    -- the surgeon controls the bleeding while operating (the patient does not bleed out on the table)
    if result ~= "death" and ms() then ms():setMedicalState(ped, "bleeding", 0) end
    OR[hid] = { case = c, ends = now() + s.time, surgery = sid, result = result, started = now(),
                bloodLoss = math.floor(math.max(100, (100 - (snap.bloodPercent or 100)) * 40 + math.random(100, 400))) }
    c.status, c.location = "surgery", "or"
    local p = c.pending
    c.pending = nil
    if isElement(p.by) then
        ER.points(p.by, p.code, p.points, L.forPlayer(p.by, "med_hospitals.erc.outcome_surgery"), c)
        ER.points(p.by, s.code, s.points, L.forPlayer(p.by, "med_hospitals.erc.surgery_" .. sid), c)
    end
    if isElement(by) and by ~= p.by then ER.points(by, "HK-T06", 2, L.forPlayer(by, "med_hospitals.erc.code_t06"), c) end
    ER.log(c, "surgery", sid, by)
    ER.syncCase(c)
    orCard(hid)
    ER.notifyStaff(hid, function(pl) return L.forPlayer(pl, "med_hospitals.erc.surgery_started", { name = c.name or "?", min = math.ceil(s.time / 60) }) end)
end

-- the stretcher is at the handover point: 5 s, then into the OR or onto the waiting place
local function handToSurgery(c, obj, by)
    local hid = c.hospital
    local sid = c.pending.surgery
    local q = queue[hid] or {}
    queue[hid] = q
    for _, w in ipairs(q) do if w.case == c then return end end
    if c.orHanding then return end
    if OR[hid] then
        local prio = ERC.SURGERIES[sid].priority
        local limit = QUEUE_MAX
        if prio then
            local normal = 0
            for _, w in ipairs(q) do if not w.priority then normal = normal + 1 end end
            limit = QUEUE_MAX + (normal > 0 and 1 or 0)
        end
        if #q >= limit then
            return by and ER.notify(by, L.forPlayer(by, "med_hospitals.erc.or_busy", { s = math.max(0, OR[hid].ends - now()) }), true)
        end
        q[#q + 1] = { case = c, obj = obj, surgery = sid, priority = prio and true or false, at = now() }
        table.sort(q, function(a, b)
            if a.priority ~= b.priority then return a.priority end
            return a.at < b.at
        end)
        c.status = "or_waiting"
        ER.log(c, "or_waiting", sid, by)
        ER.syncCase(c)
        orCard(hid)
        local pos = 1
        for i, w in ipairs(q) do if w.case == c then pos = i end end
        return by and ER.notify(by, L.forPlayer(by, "med_hospitals.erc.or_queued", { n = pos }))
    end
    if by then ER.notify(by, L.forPlayer(by, "med_hospitals.erc.or_handing_over")) end
    c.orHanding = true
    setTimer(function()
        c.orHanding = nil
        local m = eq()
        if not ER.cases[c.ped] or not m or not isElement(obj) or m:getStretcherPatient(obj) ~= c.ped then return end
        if not c.pending or c.pending.kind ~= "surgery" then return end
        if OR[hid] then return handToSurgery(c, obj, by) end
        startSurgery(c, obj, isElement(by) and by or nil)
    end, HANDOVER_TIME, 1)
end

-- the next waiting patient (still on the stretcher at the handover point) goes in
local function nextFromQueue(hid)
    local q = queue[hid]
    local m = eq()
    while q and #q > 0 and not OR[hid] do
        local w = table.remove(q, 1)
        local c = w.case
        if ER.cases[c.ped] and m and isElement(w.obj) and m:getStretcherPatient(w.obj) == c.ped and c.pending and c.pending.kind == "surgery" then
            local x, y = getElementPosition(w.obj)
            local h = ER.byHospital[hid].cfg.surgery.handover
            if d2(x, y, h.x, h.y) <= SETTLE_RANGE + 0.8 then startSurgery(c, w.obj, nil) end
        end
    end
    orCard(hid)
end

local function finishSurgery(hid)
    local o = OR[hid]
    OR[hid] = nil
    local c = o.case
    local e = ER.byHospital[hid]
    if not ER.cases[c.ped] or not isElement(c.ped) or not e then return nextFromQueue(hid) end
    local ped, m = c.ped, eq()
    local post = e.cfg.surgery and e.cfg.surgery.postop
    setElementDimension(ped, e.h.dimension)
    setElementCollisionsEnabled(ped, true)
    setElementFrozen(ped, false)
    local snap = ms() and ms():getMedicalState(ped) or {}
    if o.result ~= "death" and snap.dead then o.result = "death" end
    if o.result == "death" then
        if ms() then ms():setMedicalState(ped, "consciousness", "dead") end
        c.dead, c.status = true, "dead"
        c.deathAt, c.deathBy, c.deathCause = now(), "NPC", c.diagnoses and c.diagnoses[1] or DEFAULT_CAUSE
        c.deathCircumstances = "or"
        c.pending = { kind = "morgue" }
        c.outcome = "death"
        ER.log(c, "death", "or")
    else
        -- the operated findings end (partial care: the others stay)
        local ids = {}
        for _, f in ipairs(ER.findings(c)) do
            if not f.treated and treatsFinding(o.surgery, f.id) then
                f.treated = true
                if f.injuryId then ids[#ids + 1] = f.injuryId end
            end
        end
        if ms() then
            if #ids > 0 then ms():treatInjuries(ped, ids, 15) end
            if o.surgery == "pci" then ms():reperfuseACS(ped, "pci") end
            ms():setMedicalState(ped, "bloodVolume", math.max(snap.bloodVolume or 0, 4200))
            if MAJOR[o.surgery] then ms():setMedicalState(ped, "intubated", true) end
            if o.result == "complication" then
                ms():setMedicalState(ped, "systolic", 82)
                ms():setMedicalState(ped, "heartRate", 122)
                ms():setMedicalState(ped, "intubated", true)
            else
                ms():setMedicalState(ped, "systolic", math.max(snap.systolic or 0, 108))
            end
        end
        c.status = o.result == "complication" and "postop_icu" or "postop"
        c.needsICU = o.result == "complication" or nil
        ER.log(c, o.result == "complication" and "complication" or "surgery_done", o.surgery)
    end
    c.surgeries = c.surgeries or {}
    c.surgeries[#c.surgeries + 1] = { id = o.surgery, result = o.result, started = o.started, finished = now(), bloodLoss = o.bloodLoss }
    if ER.writeOpNote then ER.writeOpNote(c, o.surgery, o.result, o.started, o.bloodLoss) end
    local obj = post and m:createHospitalStretcher(hid, post.x, post.y, post.z, post.rot or 180, e.h.dimension, e.h.interior)
    if obj then m:putPatientOnStretcher(obj, ped) elseif post then setElementPosition(ped, post.x, post.y, post.z + 1) end
    c.location = "postop"
    ER.syncCase(c)
    local key = o.result == "death" and "med_hospitals.erc.surgery_died" or (o.result == "complication" and "med_hospitals.erc.surgery_complication" or "med_hospitals.erc.surgery_done")
    ER.notifyStaff(hid, function(pl) return L.forPlayer(pl, key, { name = c.name or "?" }) end, o.result ~= "success")
    nextFromQueue(hid)
end

---------------------------------------------------------------- morgue

local function morgue(c, obj, by)
    local m = eq()
    if isElement(by) then ER.points(by, "HK-A12", 3, L.forPlayer(by, "med_hospitals.erc.code_a12"), c) end
    if ER.writeDeathCertificate then ER.writeDeathCertificate(c, by) end
    ER.log(c, "morgue", "", by)
    local ped = c.ped
    ER.closeCase(c, "dead")
    if isElement(ped) then destroyElement(ped) end
    setTimer(function() if isElement(obj) then m:destroyHospitalStretcher(obj) end end, 200, 1)
end

-- Ú4: a recorded body nobody took to the morgue in 20 min -> the NPC morgue staff takes it (no points,
-- the death certificate is still written)
local function npcCollect(c)
    local m = eq()
    local st = m and isElement(c.ped) and m:getPatientStretcher(c.ped)
    c.collectedBy = "npc"
    if ER.writeDeathCertificate then ER.writeDeathCertificate(c, nil) end
    ER.log(c, "morgue", "npc")
    local ped = c.ped
    ER.closeCase(c, "dead")
    if isElement(ped) then destroyElement(ped) end
    if st and m:isHospitalStretcher(st) then setTimer(function() if isElement(st) then m:destroyHospitalStretcher(st) end end, 200, 1) end
    ER.notifyStaff(c.hospital, function(p) return L.forPlayer(p, "med_hospitals.erc.morgue_npc", { name = c.name or "?" }) end)
end

-- The checks of a handover at a point without doing it: ok | false, the message key (nil = silent)
local function handoverCheck(c, where, ped)
    local dead = c.dead or (ms() and (ms():getMedicalState(ped) or {}).dead)
    if where == "morgue" then
        if not dead then return false end
        if not c.deathAt then return false, "med_hospitals.erc.record_death_first" end
        return true
    end
    local p = c.pending
    if where == "surgery" and p and p.kind == "surgery_request" then return false, "med_hospitals.erc.surgery_waits_approval" end
    if not p or p.kind ~= where then return false, "med_hospitals.erc.no_order_for_" .. where end
    return true
end

local function doHandover(c, obj, by, where, wardId)
    local ok, why = handoverCheck(c, where, c.ped)
    if not ok then
        if why and by then ER.notify(by, L.forPlayer(by, why), true) end
        return
    end
    if where == "morgue" then return morgue(c, obj, by) end
    if where == "surgery" then handToSurgery(c, obj, by) else toBed(c, where, wardId, obj, by) end
end

local forced = {}   -- [stretcher] = { where, wardId }: let go by the walk-in handover below

addEventHandler("onStretcherSettled", root, function(snapper)
    local obj = source
    local m = eq()
    if not m or not m:isHospitalStretcher(obj) then return end
    local e = ER.byHospital[m:getStretcherHospital(obj)]
    if not e then return end
    local f = forced[obj]
    forced[obj] = nil
    local ped = ER.patientOfStretcher(obj)
    local c = ped and ER.cases[ped]
    if not c then return end
    local where, wardId
    if f then
        where, wardId = f[1], f[2]
    else
        local x, y = getElementPosition(obj)
        where, wardId = settleAt(e, x, y)
    end
    if not where then return end
    doHandover(c, obj, isElement(snapper) and snapper or nil, where, wardId)
end)

---------------------------------------------------------------- walk-in handover (2026-11-06)
-- Pushing the patient on a stretcher into a handover marker is enough: after 3 s in the marker (the
-- card counts down) the stretcher is let go and the handover runs. Leaving the marker earlier cancels
-- it. Putting the stretcher down in the marker still works as before.

local WALKIN_MS = 3000
local walkins = {}   -- [player] = { timer, marker, card }

local function clearCard(player, card)
    if ER.running("ui_core") and isElement(player) then exports.ui_core:setMarkerUIMeta(card, nil, player) end
end

local function cancelWalkIn(player)
    local w = walkins[player]
    if not w then return end
    walkins[player] = nil
    if isTimer(w.timer) then killTimer(w.timer) end
    clearCard(player, w.card)
end

function ER.walkInHandover(e, marker, card, where, wardId)
    addEventHandler("onMarkerHit", marker, function(hit, dim)
        if not dim or not isElement(hit) or getElementType(hit) ~= "player" or getPedOccupiedVehicle(hit) then return end
        local m = eq()
        if not m or not ER.isStaff(hit, e.h.id) then return end
        local obj = m:getPusherStretcher(hit)
        if not obj or not m:isHospitalStretcher(obj) then return end
        local ped = ER.patientOfStretcher(obj)
        local c = ped and ER.cases[ped]
        if not c then return end
        local ok, why = handoverCheck(c, where, ped)
        if not ok then
            if why then ER.notify(hit, L.forPlayer(hit, why), true) end
            return
        end
        cancelWalkIn(hit)
        local player = hit
        walkins[player] = { marker = marker, card = card, timer = setTimer(function()
            local w = walkins[player]
            walkins[player] = nil
            clearCard(player, card)
            if not w or not isElement(player) or not isElement(marker) or not isElementWithinMarker(player, marker) then return end
            local mm = eq()
            if not mm or mm:getPusherStretcher(player) ~= obj or not ER.cases[ped] then return end
            forced[obj] = { where, wardId }
            if not mm:releaseHospitalStretcher(obj) then
                -- not let go (an older med_equipments): the handover anyway, from the stretcher in hand
                forced[obj] = nil
                doHandover(ER.cases[ped], obj, player, where, wardId)
            end
        end, WALKIN_MS, 1) }
        if ER.running("ui_core") then
            exports.ui_core:setMarkerUIMeta(card, { progress = { duration = WALKIN_MS, remaining = WALKIN_MS,
                text = L.forPlayer(player, "med_hospitals.erc.walkin_handover") } }, player)
        end
    end)
    addEventHandler("onMarkerLeave", marker, function(hit)
        local w = walkins[hit]
        if w and w.marker == marker then cancelWalkIn(hit) end
    end)
end
addEventHandler("onPlayerQuit", root, function() cancelWalkIn(source) end)
addEventHandler("onElementDestroy", root, function() if forced[source] then forced[source] = nil end end)

---------------------------------------------------------------- timers: ward / ICU stays, OR, deterioration, morgue

local function bad(snap)
    if snap.dead or snap.clinicalDeath then return true end
    if (snap.spo2 or 99) < 88 then return true end
    if (snap.systolic or 120) < 85 then return true end
    local hr = snap.heartRate or 80
    if hr < 40 or hr > 140 then return true end
    return snap.consciousness == "unconscious" and not snap.intubated
end

-- who gets the alarm: the treating doctor; without them every Physician on duty (ICU) / every staff member (ward)
local function alarmTo(c, kind)
    if isElement(c.treating) then return { c.treating } end
    if kind == "icu" then
        local docs = physiciansOnDuty(c.hospital)
        if #docs > 0 then return docs end
    end
    return ER.staff(c.hospital)
end

setTimer(function()
    local t = now()
    for hid, o in pairs(OR) do
        if t >= o.ends then finishSurgery(hid) else orCard(hid) end
    end
    for hid, q in pairs(queue) do
        for i = #q, 1, -1 do if not ER.cases[q[i].case.ped] then table.remove(q, i) end end
        if not OR[hid] and #q > 0 then nextFromQueue(hid) end
    end
    for hid, b in pairs(beds) do
        for kind, list in pairs(b) do
            for _, bed in ipairs(list) do
                local c = bed.case
                if c and (not ER.cases[c.ped] or not isElement(c.ped)) then
                    bed.case = nil
                elseif c then
                    local snap = ms() and ms():getMedicalState(c.ped) or {}
                    if bad(snap) then
                        if not c.paused then
                            c.paused = true
                            c.pausedLeft = math.max(0, (c.stayEnds or t) - t)
                            for _, p in ipairs(alarmTo(c, kind)) do
                                ER.notify(p, L.forPlayer(p, "med_hospitals.erc.ward_alert", { name = c.name or "?", where = c.location or kind }), true)
                            end
                            ER.log(c, "deterioration", kind)
                            ER.syncCase(c)
                        end
                    elseif c.paused then
                        c.paused = false
                        c.stayEnds = t + (c.pausedLeft or 60)
                        ER.syncCase(c)
                    elseif c.stayEnds and t >= c.stayEnds then
                        bed.case = nil
                        ER.log(c, "stay_end", kind)
                        local ped = c.ped
                        ER.closeCase(c, kind == "icu" and "icu_ward" or kind)
                        if isElement(ped) then destroyElement(ped) end
                    end
                end
            end
        end
    end
    -- Ú4: recorded bodies left on a stretcher
    local collect = {}
    for _, c in pairs(ER.cases) do
        if c.dead and c.deathAt and t - c.deathAt >= (ERC.TIMES.morgueNpc or 1200) and not c.bed then collect[#collect + 1] = c end
    end
    for _, c in ipairs(collect) do npcCollect(c) end
end, 5000, 0)

---------------------------------------------------------------- take back (Visszavétel) from a ward / ICU bed

-- The patient goes from the fixed bed onto a hospital stretcher at the room's handover point; the case
-- is open again (status treating), the next closure writes a new version of the Ambuláns lap.
function ER.retake(c, player)
    local m = eq()
    local bed = c.bed
    if not m or not bed then return false end
    local e = ER.byHospital[c.hospital]
    if not e then return false end
    local spot
    if bed.ward then
        for _, w in ipairs(e.cfg.wards or {}) do if w.id == bed.ward then spot = w.handover end end
    elseif e.cfg.icu then
        spot = e.cfg.icu.handover
    end
    if not spot then return false end
    if ER.spotTaken(c.hospital, spot) then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.retake_spot_taken"), true)
    end
    local obj, err = m:createHospitalStretcher(c.hospital, spot.x, spot.y, spot.z, spot.rot or 0, e.h.dimension, e.h.interior)
    if not obj then
        return ER.notify(player, L.forPlayer(player, err == "limit" and "med_hospitals.er.stretcher_limit" or "med_hospitals.er.stretcher_failed"), true)
    end
    if not m:putPatientOnStretcher(obj, c.ped) then
        m:destroyHospitalStretcher(obj)
        return false
    end
    bed.case = nil
    c.bed, c.outcome, c.pending, c.paused, c.stayEnds = nil, nil, nil, false, nil
    c.status = "treating"
    c.location = bed.ward or "icu"
    c.reopened = (c.reopened or 0) + 1
    if not c.treating and ER.can(player, "er.treat") then ER.setTreating(c, player) end
    if ER.award then ER.award(player, c, "HK-A14", 3, "med_docs.code.hk_a14") end
    ER.log(c, "retake", bed.ward or "icu", player)
    ER.syncCase(c)
    ER.notify(player, L.forPlayer(player, "med_hospitals.erc.retaken", { name = c.name or "?" }))
    return true
end

---------------------------------------------------------------- board (PC / tablet "Osztály")

function ER.board(hid)
    local t = now()
    local out = { ward = {}, icu = {}, corridorFree = ER.freeCorridorCount(hid), stretchers = #ER.stretchers(hid) }
    for kind, list in pairs(beds[hid] or {}) do
        for i, bed in ipairs(list) do
            local c = bed.case
            out[kind][i] = c and { name = c.name or false, id = c.id, left = c.paused and -1 or math.max(0, (c.stayEnds or t) - t),
                                   paused = c.paused or false, ward = bed.ward } or { free = true, ward = bed.ward }
        end
    end
    local o = OR[hid]
    out["or"] = o and { busy = true, name = o.case.name or false, left = math.max(0, o.ends - t), surgery = o.surgery } or { busy = false }
    out.orQueue = {}
    for _, w in ipairs(queue[hid] or {}) do out.orQueue[#out.orQueue + 1] = { name = w.case.name or false, id = w.case.id, surgery = w.surgery, priority = w.priority } end
    -- surgery requests waiting for a Physician (Ú2)
    out.requests = {}
    for _, c in pairs(ER.cases) do
        if c.hospital == hid and c.pending and c.pending.kind == "surgery_request" then
            out.requests[#out.requests + 1] = { id = c.id, name = c.name or false, surgery = c.pending.surgery,
                by = isElement(c.pending.by) and getPlayerName(c.pending.by) or "?" }
        end
    end
    return out
end

function ER.isOrBusy(hid) return OR[hid] ~= nil end
