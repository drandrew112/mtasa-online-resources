-- ER hospital information system (server): hidden findings, orders and their results, diagnoses,
-- the todo list and the data the DX tablet / PC shows (er/client/his.lua).
--
-- case fields added here: findings = { { id, injuryId, part, treated } }, orders = { order },
-- results = { result }, diagnoses = { bno, ... }, done = { [code] = count }, nextId
-- order  = { id, key, kind, by, byName, at, status = "ordered" | "running" | "done", indicated }
-- result = { id, orderId, key, kind, at, image?, images?, finding ids, values?, positive }

local LAB_REF = {   -- { unit, low, high, decimals }
    hb = { "g/l", 120, 170 }, hct = { "l/l", 0.36, 0.50 }, wbc = { "G/l", 4.0, 10.0 }, plt = { "G/l", 140, 400 },
    na = { "mmol/l", 135, 145 }, k = { "mmol/l", 3.5, 5.1 }, crea = { "µmol/l", 59, 104 }, glu = { "mmol/l", 3.7, 6.0 },
    lact = { "mmol/l", 0.5, 2.2 }, ph = { "", 7.35, 7.45 }, be = { "mmol/l", -2, 2 }, inr = { "", 0.8, 1.2 },
    aptt = { "s", 26, 36 }, ck = { "U/l", 0, 190 }, trop = { "ng/l", 0, 14 }, crp = { "mg/l", 0, 5 }, etoh = { "‰", 0, 0 },
    ddimer = { "mg/l", 0, 0.5 }, cohb = { "%", 0, 3 }, che = { "kU/l", 5.3, 12.9 },
}
local PANELS = {
    basic = { "hb", "hct", "wbc", "plt", "na", "k", "crea", "glu" },
    trauma = { "hb", "hct", "wbc", "plt", "lact", "ck", "inr", "aptt" },
    cardiac = { "trop", "ck", "k" },
    coag = { "inr", "aptt", "plt", "ddimer" },
    abg = { "ph", "be", "lact", "glu", "k", "na", "cohb" },
    tox = { "etoh", "che" },
    group = {},
    crossmatch = {},
    inflam = { "crp", "wbc", "lact" },
}
-- teljes labor: every value of every panel once, the blood group and the tox screen too
PANELS.full = {}
do
    local seen = {}
    for _, id in ipairs({ "basic", "trauma", "cardiac", "coag", "abg", "inflam", "tox" }) do
        for _, key in ipairs(PANELS[id]) do
            if not seen[key] then seen[key] = true PANELS.full[#PANELS.full + 1] = key end
        end
    end
end
local MEDSYS_POINTS = {   -- onMedicalTreatment action -> code, points (once per patient per action)
    bandage = { "HK-C08", 4 }, splint = { "HK-S13", 3 }, cpr = { "HK-R01", 8 }, iv = { "HK-C01", 3 },
    airway = { "HK-R05", 15 }, oxygen = { "HK-R03", 2 }, medication = { "HK-G01", 2 }, neuro = { "HK-V04", 3 },
    glucometer = { "HK-V07", 2 }, monitor = { "HK-E02", 2 }, infusion = { "HK-C03", 2 },
}


local function medsys() return ER.running("medsys") and exports.medsys or nil end

local function seeded(c, salt, n)
    -- deterministic pick 1..n per case
    local v = (c.id * 7919 + (salt or 0) * 104729) % 2147483647
    return (v % n) + 1
end

---------------------------------------------------------------- findings

-- medsys injury (core part / side, medsys shared/body.lua) -> hidden finding ids. salt keeps the
-- seeded picks of one injury stable.
local function mapInjury(c, inj, salt)
    local t, sev, part, out = inj.type, inj.severity or 1, inj.part, {}
    local side = inj.side
    local function add(id) out[#out + 1] = id end
    local function organ() -- left: spleen, right: liver
        if side == "left" then return "spleen" elseif side == "right" then return "liver" end
        return seeded(c, salt, 2) == 1 and "spleen" or "liver"
    end
    if t == "gunshot" then
        if part == "head" then if sev >= 2 then add("skull_fx") add("edh") else add("wound_head") end
        elseif part == "face" then add("wound_head") if sev >= 2 then add("face_fx") end
        elseif part == "neck" then add("wound_neck") if sev >= 3 then add("cspine_fx") end
        elseif part == "chest" then
            if sev == 1 then add("wound_torso") else add("htx") add("rib_fx") end
            if sev >= 3 then add("ptx") end
        elseif part == "abdomen" then
            add("gsw_abdomen")
            if sev >= 3 then add(organ()) end
        elseif part == "pelvis" then
            add("gsw_abdomen") if sev >= 2 then add("pelvis_fx") end
        elseif part == "arm" then add("wound_arm") if sev >= 2 then add(seeded(c, salt, 2) == 1 and "humerus_fx" or "radius_fx") end
        elseif part == "leg" then add("wound_leg") if sev == 2 then add("tibia_fx") elseif sev >= 3 then add("femur_fx") end
        else add("wound_torso") end
    elseif t == "fracture" then
        if part == "head" then add("skull_fx") if sev >= 3 then add("edh") end
        elseif part == "face" then add("face_fx")
        elseif part == "neck" or part == "spine_c" then add("cspine_fx")
        elseif part == "spine_t" then add("tspine_fx")
        elseif part == "spine_l" then add("lumbar_fx")
        elseif part == "chest" or part == "abdomen" then
            add(sev == 1 and "rib_fx_single" or "rib_fx")
            if sev >= 3 then add("ptx") end
        elseif part == "pelvis" then
            if sev == 2 then add("femneck_fx") else add("pelvis_fx") end
            if sev >= 3 then add("femneck_fx") end
        elseif part == "arm" then
            if sev == 1 then add("radius_fx") elseif sev == 2 then add(seeded(c, salt, 2) == 1 and "radius_fx" or "humerus_fx") else add("humerus_fx") end
        else
            if sev == 1 then add("ankle_fx") elseif sev == 2 then add("tibia_fx") else add("femur_fx") end
        end
    elseif t == "burn" then add(sev >= 3 and "burn_major" or "burn")
    elseif t == "head_injury" then
        if sev == 1 then add("concussion") elseif sev == 2 then add(seeded(c, salt, 2) == 1 and "brain_contusion" or "sdh")
        else add(seeded(c, salt, 3) == 1 and "sah" or "edh") add("skull_fx") end
    elseif t == "stroke" then add(sev >= 3 and "ich" or "stroke_isch")
    elseif t == "opioid" or t == "sedative" or t == "stimulant" or t == "alcohol" then add(t)
    elseif t == "asthma" or t == "copd" then add(t)
    elseif t == "pulmonary_edema" then add("pulm_edema")
    elseif t == "suffocation" then add("asphyxia")
    elseif ERC.CONDITION_FINDINGS and ERC.CONDITION_FINDINGS[t] then
        -- new medsys conditions (acs, appendicitis ...): their own finding list, by severity
        for _, fid in ipairs(ERC.CONDITION_FINDINGS[t](inj, c) or {}) do add(fid) end
    end
    return out
end

function ER.findings(c)
    c.findings = c.findings or {}
    local m = medsys()
    if not m or not isElement(c.ped) then return c.findings end
    local snap = m:getMedicalState(c.ped)
    if not snap then return c.findings end
    local have = {}
    for _, f in ipairs(c.findings) do have[tostring(f.injuryId)] = true end
    local all = {}
    for _, i in ipairs(snap.injuries or {}) do all[#all + 1] = i end
    for _, i in ipairs(snap.conditions or {}) do all[#all + 1] = i end
    for _, inj in ipairs(all) do
        if not have[tostring(inj.id)] then
            for _, fid in ipairs(mapInjury(c, inj, tonumber(inj.id) or 1)) do
                c.findings[#c.findings + 1] = { id = fid, injuryId = inj.id, part = inj.part, side = inj.side, treated = false }
            end
        end
    end
    return c.findings
end

local function findingsInRegions(c, regions)
    local out = {}
    for _, f in ipairs(ER.findings(c)) do
        local def = ERC.FINDINGS[f.id]
        if def and regions[def.region] then out[#out + 1] = f end
    end
    return out
end

local function revealed(c)
    local out = {}
    for _, r in ipairs(c.results or {}) do
        for _, fid in ipairs(r.findings or {}) do out[fid] = true end
    end
    return out
end
ER.revealed = revealed

---------------------------------------------------------------- indication

-- o = catalogue order, side = the side of a sided X-ray
local function isIndicated(c, o, side)
    local snap = medsys() and medsys():getMedicalState(c.ped) or {}
    local f = ER.findings(c)
    if o.kind == "lab" then
        if o.id == "full" then
            return #f > 0 or (snap.consciousness and snap.consciousness ~= "stable") or (snap.spo2 or 100) < 94
                or (snap.systolic or 120) < 100 or (snap.rhythm and snap.rhythm ~= "SINUS")
        end
        if o.id == "basic" or o.id == "trauma" or o.id == "group" or o.id == "coag" then return #f > 0 end
        if o.id == "abg" then return (snap.spo2 or 100) < 94 or snap.intubated or (snap.breathing and snap.breathing ~= "normal") end
        if o.id == "tox" then
            for _, x in ipairs(f) do if ERC.FINDINGS[x.id] and ERC.FINDINGS[x.id].region == "tox" then return true end end
            return snap.consciousness and snap.consciousness ~= "stable"
        end
        if o.id == "cardiac" then
            for _, x in ipairs(f) do if ERC.FINDINGS[x.id] and ERC.FINDINGS[x.id].cardiac then return true end end
            return snap.rhythm and snap.rhythm ~= "SINUS"
        end
        return #f > 0
    elseif o.kind == "ecg" then
        if snap.rhythm and snap.rhythm ~= "SINUS" then return true end
        for _, x in ipairs(f) do
            local d = ERC.FINDINGS[x.id]
            if d and (d.cardiac or d.region == "tox" or d.region == "chest") then return true end
        end
        return (c.age or 0) >= 40 or (snap.consciousness and snap.consciousness ~= "stable")
    elseif o.kind == "fast" then
        if (snap.systolic or 120) < 90 then return true end
        return #findingsInRegions(c, { abdomen = true, chest = true, pelvis = true }) > 0
    elseif o.kind == "xray" then
        for _, x in ipairs(f) do
            local xr = ERC.FINDINGS[x.id] and ERC.FINDINGS[x.id].xr
            if xr and xr.part == o.id and (not o.sided or x.side == side) then return true end
        end
        return false
    end
    local regions = ERC.LOOKS_AT[o.key]
    return regions ~= nil and #findingsInRegions(c, regions) > 0
end
ER.isIndicated = isIndicated

---------------------------------------------------------------- results

local function newId(c) c.nextId = (c.nextId or 0) + 1 return c.nextId end

-- Lab values of a panel from the medsys simulation (medsys getLabValues). The blood draw errors
-- (er/server/minigames.lua, mg_blooddraw) spoil some of them like in a real lab.
local function labValues(c, panel, errors)
    local all = medsys() and medsys():getLabValues(c.ped) or {}
    local values = {}
    errors = errors or {}
    for _, key in ipairs(PANELS[panel] or {}) do
        local ref = LAB_REF[key]
        local n = tonumber(all[key]) or 0
        local note
        if errors.diluted and (key == "hb" or key == "hct" or key == "na" or key == "plt") then n = n * 0.88 note = "diluted" end
        if errors.concentrated and (key == "hb" or key == "hct") then n = n * 1.08 note = "concentrated" end
        if errors.edta and key == "k" then n = n + 2.8 note = "edta" end
        n = (key == "ph" or key == "hct") and math.floor(n * 100 + 0.5) / 100 or (math.abs(n) >= 50 and math.floor(n + 0.5) or math.floor(n * 10 + 0.5) / 10)
        local flag = (n < ref[2] and "low") or (n > ref[3] and "high") or nil
        if key == "etoh" then flag = n > 0 and "high" or nil end
        local v = { key = key, value = n, unit = ref[1], low = ref[2], high = ref[3], flag = flag, note = note }
        if errors.hemolysed and key == "k" then v.value, v.flag, v.note = "—", nil, "hemolysed" end
        if errors.underfilled and (key == "inr" or key == "aptt") then v.value, v.flag, v.note = "—", nil, "underfilled" end
        values[#values + 1] = v
    end
    if panel == "group" or panel == "full" then
        c.bloodGroup = all.group or c.bloodGroup or "0+"
        values[#values + 1] = { key = "group", value = c.bloodGroup, unit = "" }
    end
    if panel == "crossmatch" then
        values[#values + 1] = { key = "crossmatch", value = c.groupKnown and "✓" or "—", unit = "" }
    end
    if panel == "tox" or panel == "full" then
        local pos = all.screen or {}
        values[#values + 1] = { key = "screen", value = #pos > 0 and table.concat(pos, ", ") or "neg", unit = "", flag = #pos > 0 and "high" or nil }
    end
    return values
end

local ECG_IMAGE = { SINUS = "sinus", SINUS_BRADY = "brady", SINUS_TACHY = "tachy", SVT = "svt", VT_WITH_PULSE = "vt",
    PULSELESS_VT = "vt", VF = "vf", PEA = "pea", ASYSTOLE = "asystole", AFIB = "afib", AVB3 = "avb3" }
local FAST_IMAGE = { ruq = "ruq", luq = "luq", pelvis = "pelvis", cardiac = "cardiac", lung_r = "lung", lung_l = "lung" }

-- extra: the minigame details (FAST windows, ECG electrode errors)
local function makeResult(c, o, extra)
    c.results = c.results or {}
    local def = ERC.ORDER_BY_KEY[o.key] or {}
    local r = { id = newId(c), orderId = o.id, key = o.key, kind = o.kind, at = getRealTime().timestamp, findings = {}, side = o.side }
    if o.kind == "lab" then
        r.panel = def.id
        r.values = labValues(c, def.id, o.drawErrors)
        for _, v in ipairs(r.values) do if v.flag then r.positive = true end end
        local reveals = ERC.labReveals and ERC.labReveals(def.id) or {}
        for _, x in ipairs(ER.findings(c)) do
            local d = ERC.FINDINGS[x.id]
            if d and ((d.tox and (def.id == "tox" or def.id == "full")) or reveals[x.id]) then r.findings[#r.findings + 1] = x.id end
        end
    elseif o.kind == "ecg" then
        local snap = medsys() and medsys():getMedicalState(c.ped) or {}
        r.image = ECG_IMAGE[snap.rhythm or "SINUS"] or "sinus"
        r.rhythm = snap.rhythm
        r.spec = medsys() and medsys():getECGSpec(c.ped, extra) or false
        r.positive = r.image ~= "sinus" or (r.spec and r.spec.stemi) and true or false
        for _, x in ipairs(ER.findings(c)) do
            local d = ERC.FINDINGS[x.id]
            if d and d.ecg then r.findings[#r.findings + 1] = x.id end
        end
    elseif o.kind == "fast" then
        r.images, r.windows = {}, (extra and extra.windows) or {}
        local pos = ER.fastPositives(c)
        for _, win in ipairs({ "ruq", "luq", "pelvis", "cardiac", "lung_r", "lung_l" }) do
            local w = r.windows[win]
            if w == "pos" or w == "neg" then
                local img = FAST_IMAGE[win] .. "_" .. ((win:find("^lung")) and (w == "pos" and "ptx" or "norm") or w)
                r.images[#r.images + 1] = { file = img, window = win, desc = "med_hospitals.fast.w_" .. win }
                if w == "pos" then r.positive = true end
            end
        end
        -- the findings behind a positive window are shown
        for _, x in ipairs(ER.findings(c)) do
            local win = ({ liver = "ruq", spleen = "luq", gsw_abdomen = "ruq", pelvis_fx = "pelvis", tamponade = "cardiac" })[x.id]
            if (x.id == "ptx") then win = x.side == "left" and "lung_l" or "lung_r" end
            if (x.id == "htx") then win = x.side == "left" and "luq" or "ruq" end
            if win and r.windows[win] == "pos" then r.findings[#r.findings + 1] = x.id end
        end
        if #r.images == 0 then r.images[1] = { file = "ruq_neg", desc = "med_hospitals.fast.not_evaluable" } end
    elseif o.kind == "xray" then
        r.images = {}
        for _, x in ipairs(ER.findings(c)) do
            local xr = ERC.FINDINGS[x.id] and ERC.FINDINGS[x.id].xr
            if xr and xr.part == def.id and (not def.sided or x.side == o.side) then
                local img = (x.treated and xr.cast) or xr.img
                if xr.sided then img = img .. "_" .. (x.side == "right" and "right" or "left") end
                r.images[#r.images + 1] = { file = img, finding = x.id }
                r.findings[#r.findings + 1] = x.id
                if x.treated and xr.cast then r.control = true end
            end
        end
        if #r.images == 0 then r.images[1] = { file = ERC.xrayNormal(def.id, o.side) } end
        r.positive = #r.findings > 0 and not r.control
    else
        local regions = ERC.LOOKS_AT[o.key] or {}
        r.images = {}
        for _, x in ipairs(findingsInRegions(c, regions)) do
            local img = ERC.FINDINGS[x.id].ct
            r.findings[#r.findings + 1] = x.id
            if img then
                if ERC.CT_SIDED[img] and x.side == "right" then img = img .. "_r" end
                r.images[#r.images + 1] = { file = img, finding = x.id }
            end
        end
        if #r.images == 0 then r.images[1] = { file = ERC.NORMAL[o.key] or "head_normal" } end
        r.positive = #r.findings > 0
    end
    c.results[#c.results + 1] = r
    return r
end

---------------------------------------------------------------- orders

local function canDo(player, activity)
    local ok, need = ER.can(player, activity)
    if not ok then ER.notify(player, L.forPlayer(player, "med_hospitals.er.rank_needed", { rank = need or "?" }), true) end
    return ok
end
ER.canDo = canDo

-- points of an intervention: the code table (er/shared/codes.lua) gives the points and the per-case
-- limit; without indication (halve) half of it. Every done intervention is counted on the case
-- (Ambuláns lap) even past the limit.
local function award(player, c, code, points, labelKey, halve)
    c.done = c.done or {}
    c.done[code] = (c.done[code] or 0) + 1
    local def = ERC.CODES and ERC.CODES[code]
    if def then points = def.points end
    if c.done[code] > (def and def.limit or 3) then return end -- per case limit
    local p = halve and math.max(1, math.floor(points / 2)) or points
    ER.points(player, code, p, L.forPlayer(player, labelKey), c)
end

ER.award = award

function ER.order(c, player, key, side)
    local o = ERC.ORDER_BY_KEY[key]
    if not o then return false end
    if not canDo(player, "er.order") then return false end
    if o.sided and side ~= "left" and side ~= "right" then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.pick_side"), true) end
    if not o.sided then side = nil end
    c.orders = c.orders or {}
    for _, x in ipairs(c.orders) do
        if x.key == key and x.side == side and x.status ~= "done" then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.already_ordered"), true) end
    end
    local ord = { id = newId(c), key = key, kind = o.kind, side = side, by = getPlayerName(player), at = getRealTime().timestamp,
                  status = "ordered", indicated = isIndicated(c, o, side) }
    c.orders[#c.orders + 1] = ord
    ER.log(c, "order", key .. (side and (" " .. side) or ""), player)
    ER.syncCase(c)
    return ord
end

local function orderLabel(player, key) return L.forPlayer(player, "med_hospitals.erc.order_" .. key:gsub("%.", "_")) end

local function near(player, ped, range)
    if not isElement(player) or not isElement(ped) then return false end
    local px, py, pz = getElementPosition(player)
    local x, y, z = getElementPosition(ped)
    return getDistanceBetweenPoints3D(px, py, pz, x, y, z) <= (range or 3.2)
end

-- the result is ready: document, points, the treating doctor told, the wall monitor of the room
local function finishOrder(c, ord, player, extra)
    if not ER.cases[c.ped] then return end
    local o = ERC.ORDER_BY_KEY[ord.key]
    ord.status = "done"
    local r = makeResult(c, ord, extra)
    ord.resultId = r.id
    if r.kind == "lab" and ER.onLabResult then ER.onLabResult(c, r.panel) end
    if ER.writeResultDoc then ER.writeResultDoc(c, r, isElement(player) and player or nil) end
    if isElement(player) then
        local code = (r.control and ERC.XRAY_CONTROL_CODE) or o.code
        award(player, c, code, o.points, "med_docs.code." .. code:lower():gsub("%-", "_"), not ord.indicated and not r.control)
    end
    ER.log(c, "result", ord.key, player)
    ER.syncCase(c)
    if (r.kind == "ct" or r.kind == "xray") and ER.wallShow then ER.wallShow(c, r) end
    local who = c.treating or player
    if isElement(who) then ER.notify(who, L.forPlayer(who, "med_hospitals.erc.result_ready", { what = orderLabel(who, ord.key), name = c.name or "?" })) end
end

ER.finishOrder = finishOrder

---------------------------------------------------------------- CT: one patient at a time, a queue, the table slides into the gantry

local ctBusy = {}    -- [hospitalId] = case
local ctQueue = {}   -- [hospitalId] = { { case, order, player } }

local function ctSlide(c, inward)
    local e = ER.byHospital[c.hospital]
    local m = ER.running("med_equipments") and exports.med_equipments
    local st = m and m:getPatientStretcher(c.ped)
    local cfg = e and e.cfg.ct
    if not st or not cfg or not cfg.table then return end
    local t = cfg.table
    local gx, gy = t.x, t.y + (cfg.slide or 2.4)
    if inward then
        c.ctReturn = { getElementPosition(st) }
        moveObject(st, 3000, gx, gy, t.z + 0.0, 0, 0, 0, "InOutQuad")
    elseif c.ctReturn then
        local p = c.ctReturn
        moveObject(st, 3000, p[1], p[2], p[3], 0, 0, 0, "InOutQuad")
        c.ctReturn = nil
    end
end

local function ctStart(c, ord, player)
    local hid = c.hospital
    ctBusy[hid] = c
    ord.status = "running"
    ord.performer = getPlayerName(player)
    local time = ERC.TIMES.ct
    ord.ends = getRealTime().timestamp + time + 6
    ER.syncCase(c)
    ER.notify(player, L.forPlayer(player, "med_hospitals.erc.started", { what = orderLabel(player, ord.key), s = time + 6 }))
    ctSlide(c, true)
    setTimer(function()
        ctSlide(c, false)
        setTimer(function()
            ctBusy[hid] = nil
            finishOrder(c, ord, player)
            -- the next in the queue whose patient is (still) at the CT
            local q = ctQueue[hid] or {}
            while #q > 0 do
                local nxt = table.remove(q, 1)
                if ER.cases[nxt.case.ped] and nxt.order.status == "queued" and tostring(nxt.case.location):find("^ct") then
                    return ctStart(nxt.case, nxt.order, isElement(nxt.player) and nxt.player or player)
                elseif nxt.order.status == "queued" then
                    nxt.order.status = "ordered"
                    ER.syncCase(nxt.case)
                end
            end
        end, 3000, 1)
    end, (time + 3) * 1000, 1)
end

---------------------------------------------------------------- performing an order

function ER.perform(c, player, orderId)
    local ord
    for _, x in ipairs(c.orders or {}) do if x.id == orderId then ord = x end end
    if not ord or ord.status ~= "ordered" then return false end
    local o = ERC.ORDER_BY_KEY[ord.key]
    local room = ERC.ORDER_ROOM[o.kind]
    if room and not (c.location and c.location:find("^" .. room)) then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.needs_room_" .. room), true)
    end
    local e = ER.byHospital[c.hospital]
    if o.kind == "ct" then
        if ctBusy[c.hospital] then
            ord.status = "queued"
            ctQueue[c.hospital] = ctQueue[c.hospital] or {}
            table.insert(ctQueue[c.hospital], (c.triage == 1) and 1 or (#ctQueue[c.hospital] + 1), { case = c, order = ord, player = player })
            ER.syncCase(c)
            return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.ct_queued", { n = #ctQueue[c.hospital] }))
        end
        return ctStart(c, ord, player)
    end
    if o.kind == "xray" then
        -- the radiographer steps behind the lead wall to the control desk (exposure 3 s)
        local ctl = e and e.cfg.xray and e.cfg.xray.control
        if ctl then
            local px, py = getElementPosition(player)
            if getDistanceBetweenPoints2D(px, py, ctl.x, ctl.y) > 1.8 then
                return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.xray_control"), true)
            end
        end
        ord.status, ord.performer = "running", getPlayerName(player)
        ord.ends = getRealTime().timestamp + ERC.TIMES.xray
        ER.syncCase(c)
        setPedAnimation(player, "INT_OFFICE", "OFF_Sit_Type_Loop", ERC.TIMES.xray * 1000, true, false, false, false)
        ER.notify(player, L.forPlayer(player, "med_hospitals.erc.started", { what = orderLabel(player, ord.key), s = ERC.TIMES.xray }))
        setTimer(function() if isElement(player) then setPedAnimation(player) end finishOrder(c, ord, player) end, ERC.TIMES.xray * 1000, 1)
        return true
    end
    -- bedside orders: the blood draw, FAST and the 12-lead ECG are minigames at the patient
    if not near(player, c.ped) then return ER.notify(player, L.forPlayer(player, "med_hospitals.exam.too_far"), true) end
    if o.kind == "fast" and not canDo(player, "er.fast") then return false end
    if o.kind == "lab" then
        ord.status = "drawing"
        ER.syncCase(c)
        local snap = medsys() and medsys():getMedicalState(c.ped) or {}
        return ER.minigame("blooddraw", player, c, { tubes = ER.panelTubes(o.id), stand = true }, function(success, pct, d, reason)
            if reason == "cancelled" or reason == "quit" or reason == "died" or reason == "invalid" then ord.status = "ordered" ER.syncCase(c) return end
            if not success then ord.status = "ordered" ER.syncCase(c) return ER.minigameFailed(player, c, "blooddraw") end
            award(player, c, "HK-L01", 4, "med_docs.code.hk_l01")
            ord.drawErrors = { hemolysed = d.hemolysis == true, edta = d.edta == true, underfilled = d.citrate == true,
                               concentrated = (tonumber(d.tourniquet) or 0) > 60, diluted = snap.infusion ~= nil and math.random() < 0.3 }
            ord.status = "running"
            local secs = o.id == "crossmatch" and 60 or ERC.TIMES.lab
            ord.ends = getRealTime().timestamp + secs
            ER.syncCase(c)
            ER.notify(player, L.forPlayer(player, "med_hospitals.erc.lab_sent", { s = secs }))
            setTimer(function() finishOrder(c, ord, player) end, secs * 1000, 1)
        end)
    end
    if o.kind == "fast" then
        ord.status = "running"
        ER.syncCase(c)
        return ER.minigame("fast", player, c, { efast = true, positives = ER.fastPositives(c), stand = true }, function(success, pct, d, reason)
            if reason == "cancelled" or reason == "quit" or reason == "died" or reason == "invalid" then ord.status = "ordered" ER.syncCase(c) return end
            if not success then ord.status = "ordered" ER.syncCase(c) return ER.minigameFailed(player, c, "fast") end
            finishOrder(c, ord, player, { windows = d.windows or {} })
        end)
    end
    if o.kind == "ecg" then
        ord.status = "running"
        ER.syncCase(c)
        return ER.minigame("ecg", player, c, { stand = true, guide = ER.ecgGuide and ER.ecgGuide(player) or false }, function(success, pct, d, reason)
            if reason == "cancelled" or reason == "quit" or reason == "died" or reason == "invalid" then ord.status = "ordered" ER.syncCase(c) return end
            if not success then ord.status = "ordered" ER.syncCase(c) return ER.minigameFailed(player, c, "ecg") end
            finishOrder(c, ord, player, { swapRALA = d.swapRALA == true, wrongV = tonumber(d.wrongV) or 0, wrongLimb = tonumber(d.wrongLimb) or 0 })
        end)
    end
    return false
end

---------------------------------------------------------------- treatments in the rooms (minigames)

ER.TREATMENTS = {
    suture = { code = "HK-S04", room = "wound", need = "er.suture", game = "suture", stock = "suture_kit", fits = function(d) return d.suture end },
    irrigate = { code = "HK-S01", room = "wound", game = "irrigation", stock = "irrigation_saline", fits = function(d) return d.suture end },
    cast = { code = "HK-S10", room = "cast", game = "cast", stock = "plaster", needsXray = true, fits = function(d) return d.cast end },
    reduction = { code = "HK-S08", room = "cast", need = "er.reduction", game = "reduction", needsXray = true, fits = function(d) return d.reduction end },
    drain = { code = "HK-R08", room = "shock", need = "er.drain", game = "chestdrain", stock = "chest_drain_kit", fits = function(d) return d.drain end },
    burn_dressing = { code = "HK-S07", stock = "burn_dressing", time = 6, fits = function(d) return d.region == "skin" end },
}

local PART_LABEL = { arm = "arm", leg = "leg", head = "head", chest = "chest", abdomen = "abdomen" }

function ER.treat(c, player, kind, findingIndex)
    local t = ER.TREATMENTS[kind]
    local f = c.findings and c.findings[findingIndex]
    if not t or not f or f.treated then return false end
    local def = ERC.FINDINGS[f.id]
    if not def or not t.fits(def) then return false end
    if not revealed(c)[f.id] and not def.suture and def.region ~= "skin" then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.examine_first"), true)
    end
    if t.need and not canDo(player, t.need) then return false end
    if t.room and not (c.location and c.location:find("^" .. t.room)) then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.needs_room_" .. t.room), true)
    end
    if t.needsXray and not revealed(c)[f.id] then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.xray_first"), true) end
    if kind == "cast" and def.reduction and not f.reduced then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.reduce_first"), true) end
    if kind == "suture" and not f.irrigated then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.irrigate_first"), true) end
    if not near(player, c.ped) then return ER.notify(player, L.forPlayer(player, "med_hospitals.exam.too_far"), true) end
    -- the stock: checked now, used only after a successful minigame (a failed one can be retried)
    local stockOk = not t.stock or not ER.useStock
    if t.stock and ER.useStock then
        if t.game then stockOk = ER.hasStock(c, t.stock, 1) else stockOk = ER.useStock(c, t.stock, 1) end
    end
    if not stockOk then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.stock.out_of", { what = L.forPlayer(player, "med_hospitals.stock.item_" .. t.stock) }), true)
    end
    local function done(success, pct, d)
        if not ER.cases[c.ped] then return end
        if kind == "irrigate" then
            f.irrigated = true
            if (tonumber(d.clean) or pct) < 100 then f.infectionRisk = true end
        elseif kind == "suture" then
            f.treated = success
            f.quality = pct
            if pct < 60 then f.infectionRisk = true end
        elseif kind == "reduction" then
            if d.reduced == true or (success and d.reduced == nil) then f.reduced = true
            else return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.reduction_failed"), true) end
        elseif kind == "cast" then
            if d.tight then
                f.castTight = true
                ER.notify(player, L.forPlayer(player, "med_hospitals.erc.cast_tight"), true)
            else
                f.castTight = nil
                f.treated = success or pct >= 50
            end
        elseif kind == "drain" then
            f.treated = success or pct >= 50
            if d.vessel or d.wrongSpot then
                -- a vessel hit under the rib: bleeding
                if medsys() then medsys():setMedicalState(c.ped, "bleeding", 2) end
                ER.log(c, "complication", "drain_bleeding", player)
            end
            if f.treated and medsys() then
                local snap = medsys():getMedicalState(c.ped) or {}
                medsys():setMedicalState(c.ped, "spo2", math.min(99, (snap.spo2 or 90) + 8))
            end
            if f.id == "htx" then
                -- the drain output decides about the thoracotomy (> 1500 ml)
                local snap = medsys() and medsys():getMedicalState(c.ped) or {}
                f.drainOutput = (snap.bloodPercent or 100) < 70 and math.random(1500, 2200) or math.random(300, 1200)
                ER.log(c, "drain_output", tostring(f.drainOutput) .. " ml", player)
                if f.drainOutput > 1500 then
                    f.thoracotomy = true
                    ER.notify(player, L.forPlayer(player, "med_hospitals.erc.drain_massive", { ml = f.drainOutput }), true)
                end
            end
        else
            f.treated = true
        end
        if isElement(player) and (kind == "reduction" or kind == "irrigate" or f.treated) then
            award(player, c, t.code, 0, "med_docs.code." .. t.code:lower():gsub("%-", "_"))
        end
        ER.log(c, "treat", kind .. ":" .. f.id, player)
        ER.syncCase(c)
    end
    if t.game then
        local opts = { stand = true, part = L.forPlayer(player, "medsys.body." .. tostring(f.part or "arm")) }
        if kind == "reduction" then opts.analgesia = ER.hasAnalgesia(c) end
        if kind == "suture" then opts.tremor = ER.hasAnalgesia(c) and 0 or 0.6 opts.length = 4 end
        if kind == "drain" then opts.side = f.side == "left" and "left" or "right" end
        return ER.minigame(t.game, player, c, opts, function(success, pct, d, reason)
            if reason == "cancelled" or reason == "quit" or reason == "died" or reason == "invalid" then return end
            d = d or {}
            if not success then
                -- a failed chest drain: no drain, but a vessel hit still bleeds (the mistake's consequence)
                if kind == "drain" and (d.vessel or d.wrongSpot) and ER.cases[c.ped] then
                    if medsys() then medsys():setMedicalState(c.ped, "bleeding", 2) end
                    ER.log(c, "complication", "drain_bleeding", player)
                end
                return ER.minigameFailed(player, c, t.game)
            end
            if t.stock and ER.useStock and not ER.useStock(c, t.stock, 1) then
                return ER.notify(player, L.forPlayer(player, "med_hospitals.stock.out_of", { what = L.forPlayer(player, "med_hospitals.stock.item_" .. t.stock) }), true)
            end
            done(true, pct, d)
        end)
    end
    ER.notify(player, L.forPlayer(player, "med_hospitals.erc.started", { what = L.forPlayer(player, "med_hospitals.erc.treat_" .. kind), s = t.time or 6 }))
    setPedAnimation(player, "MEDIC", "CPR", (t.time or 6) * 1000, false, false, false, false)
    setTimer(function() done(true, 100, {}) end, (t.time or 6) * 1000, 1)
    return true
end

---------------------------------------------------------------- drug orders (the treating doctor orders, anyone on duty gives it)

function ER.orderDrug(c, player, drug, dose)
    if not canDo(player, "er.order") then return false end
    if type(drug) ~= "string" or #drug > 32 then return false end
    c.drugOrders = c.drugOrders or {}
    for _, o in ipairs(c.drugOrders) do
        if o.drug == drug and o.status == "ordered" then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.already_ordered"), true) end
    end
    c.drugOrders[#c.drugOrders + 1] = { id = newId(c), drug = drug, dose = tonumber(dose), by = getPlayerName(player),
                                        at = getRealTime().timestamp, status = "ordered" }
    ER.log(c, "drug_order", drug .. (dose and (" " .. tostring(dose)) or ""), player)
    ER.syncCase(c)
    return true
end

function ER.cancelDrugOrder(c, player, id)
    for _, o in ipairs(c.drugOrders or {}) do
        if o.id == id and o.status == "ordered" then o.status = "cancelled" ER.log(c, "drug_cancel", o.drug, player) ER.syncCase(c) return true end
    end
end

---------------------------------------------------------------- diagnoses

function ER.addDiagnosis(c, player, code)
    if not canDo(player, "er.diagnose") then return false end
    code = tostring(code or ""):upper():gsub("[%s%.]", "")
    c.diagnoses = c.diagnoses or {}
    -- the BNO database (med_docs/bno): known, not expired, fits the patient, max 5, "*" only with a "+"
    if ER.running("med_docs") then
        local sex = c.gender == "female" and "f" or (c.gender == "male" and "m" or nil)
        local ok, why = exports.med_docs:checkDiagnosis(code, c.diagnoses, sex, c.age)
        if not ok then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc." .. tostring(why)), true) end
    else
        if not ERC.BNO[code] then return false end
        if #c.diagnoses >= 5 then return ER.notify(player, L.forPlayer(player, "med_hospitals.erc.max_diagnoses"), true) end
        for _, d in ipairs(c.diagnoses) do if d == code then return false end end
    end
    c.diagnoses[#c.diagnoses + 1] = code
    c.diagnosisAt = c.diagnosisAt or {}
    c.diagnosisAt[code] = getRealTime().timestamp
    ER.log(c, "diagnosis", code, player)
    ER.syncCase(c)
    return true
end

function ER.removeDiagnosis(c, player, code)
    for i, d in ipairs(c.diagnoses or {}) do
        if d == code then table.remove(c.diagnoses, i) ER.syncCase(c) return true end
    end
end

-- how many diagnoses match a finding (bonus at closure)
function ER.correctDiagnoses(c)
    local want, n = {}, 0
    for _, f in ipairs(ER.findings(c)) do local d = ERC.FINDINGS[f.id]; if d then want[d.bno] = true end end
    for _, code in ipairs(c.diagnoses or {}) do if want[code] then n = n + 1 end end
    return n
end

---------------------------------------------------------------- todo list (tablet Teendők)

function ER.todos(c, viewer)
    local out = {}
    local function add(state, key, params) out[#out + 1] = { state = state, key = key, params = params or {} } end
    if c.triage == 0 then add("need", "todo_triage") else add("ok", "todo_triage_done", { level = c.triage }) end
    if not c.treating then add("need", "todo_treating") end
    local rev = revealed(c)
    local covered = {}
    for _, r in ipairs(c.results or {}) do for reg in pairs(ERC.LOOKS_AT[r.key] or {}) do covered[reg] = true end end
    local hinted = {}
    for i, f in ipairs(ER.findings(c)) do
        local d = ERC.FINDINGS[f.id]
        if d then
            if rev[f.id] or d.suture or d.region == "skin" or d.visible then
                if not f.treated then
                    if d.reduction and not f.reduced then add("need", "todo_reduction")
                    elseif d.cast then add("need", "todo_cast")
                    elseif d.suture then add("need", f.irrigated and "todo_suture" or "todo_irrigate")
                    elseif d.drain then add("need", "todo_drain")
                    elseif d.surgery then add("need", "todo_surgery")
                    elseif d.lysis then add("need", "todo_lysis")
                    elseif d.region == "skin" then add("need", "todo_burn")
                    end
                end
            elseif not covered[d.region] and not hinted[d.region] and d.region ~= "tox" then
                hinted[d.region] = true
                add("hint", "todo_imaging", { region = d.region })
            elseif d.region == "tox" and not hinted.tox then
                hinted.tox = true
                add("hint", "todo_tox")
            end
        end
    end
    for _, o in ipairs(c.orders or {}) do
        if o.status == "ordered" then add("need", "todo_order_pending", { order = o.key })
        elseif o.status == "running" then add("run", "todo_order_running", { order = o.key }) end
    end
    if #(c.diagnoses or {}) == 0 then add("need", "todo_diagnosis") else add("ok", "todo_diagnosis_done", { n = #c.diagnoses }) end
    if not c.outcome then add("todo", "todo_outcome") end
    return out
end

---------------------------------------------------------------- data for the clients

local function summary(c)
    local snap = medsys() and medsys():getMedicalState(c.ped) or {}
    return {
        id = c.id, name = c.name or false, age = c.age, gender = c.gender, triage = c.triage, treating = c.treatingName or false,
        location = c.location, status = c.status, arrival = c.arrival and c.arrival.kind or "brought",
        unit = c.arrival and c.arrival.unit or false, created = c.created, dead = (snap.dead or c.dead) and true or false,
        pending = (function() local n = 0 for _, o in ipairs(c.orders or {}) do if o.status ~= "done" then n = n + 1 end end return n end)(),
        results = #(c.results or {}), outcome = c.outcome or false, inBed = c.bed ~= nil,
        pendingKind = c.pending and c.pending.kind or false, pendingSurgery = c.pending and c.pending.surgery or false,
        deathRecorded = c.deathAt and true or false, needsICU = c.needsICU or false,
    }
end

local function detail(c, viewer)
    local s = summary(c)
    local snap = medsys() and medsys():getMedicalState(c.ped) or {}
    s.vitals = { hr = snap.heartRate, bp = snap.bloodPressure, spo2 = snap.spo2, consciousness = snap.consciousness,
                 rhythm = snap.rhythm, pain = snap.pain, breathing = snap.breathing, monitor = snap.monitor ~= nil,
                 bloodPercent = snap.bloodPercent, glucose = snap.glucose }
    s.anamnesis = c.anamnesis or (c.arrival and c.arrival.text) or ""
    s.orders = c.orders or {}
    s.results = c.results or {}
    s.diagnoses = c.diagnoses or {}
    s.todos = ER.todos(c, viewer)
    s.bloodGroup = c.bloodGroup
    -- findings the staff may see: revealed by a result, or visible (wounds, burns)
    local rev, fl = revealed(c), {}
    for i, f in ipairs(ER.findings(c)) do
        local d = ERC.FINDINGS[f.id]
        if d and (rev[f.id] or d.suture or d.region == "skin" or d.visible) then
            fl[#fl + 1] = { index = i, id = f.id, bno = d.bno, treated = f.treated, reduced = f.reduced, irrigated = f.irrigated, part = f.part }
        end
    end
    s.findings = fl
    s.events = c.events
    -- exam panel (er/client/exam.lua)
    s.exam = c.exam or {}
    s.measured = c.measured or false
    s.monitor = snap.monitor ~= nil
    s.weight = snap.weight
    s.gcs, s.nrs, s.temperature, s.nihss = c.gcs, c.nrs, c.temperature, c.nihssLast
    s.allergy = c.allergy or false
    s.drugOrders = c.drugOrders or {}
    s.surgeryOptions = ER.surgeryOptions and ER.surgeryOptions(c) or {}
    s.icu = ER.icuView and ER.icuView(c) or false
    s.texts = { anamnesis = s.anamnesis, status = c.statusText or "", epicrisis = c.epicrisis or "" }
    s.statusTemplate = ER.statusTemplate and ER.statusTemplate(c, L.lang(viewer)) or ""
    s.timeIn = getRealTime().timestamp - (c.created or getRealTime().timestamp)
    s.docRef = "er:" .. tostring(c.hospital) .. ":" .. tostring(c.id) .. ":" .. tostring(c.created or 0)   -- med_docs case_ref (docs.lua)
    s.birth = c.birth or false
    s.indications = {}
    for key, o in pairs(ERC.ORDER_BY_KEY) do s.indications[key] = isIndicated(c, o) end
    s.procedures = ER.procedureList and ER.procedureList(c, viewer) or {}
    s.transfusion = ER.transfusionView and ER.transfusionView(c) or false
    s.dead = snap.dead or c.dead or false
    s.triageSuggest = ER.triageSuggest and ER.triageSuggest(c) or false
    return s
end

addEvent("his:request", true)
addEventHandler("his:request", resourceRoot, function(what, arg)
    local player = client
    local hid = getElementData(player, "hosp.staff")
    if not hid or not ER.isStaff(player, hid) then return end
    if what == "list" then
        local list = {}
        for _, c in pairs(ER.cases) do if c.hospital == hid then list[#list + 1] = summary(c) end end
        table.sort(list, function(a, b)
            local ta, tb = a.triage == 0 and 0 or a.triage, b.triage == 0 and 0 or b.triage
            if ta ~= tb then return ta < tb end
            return a.id < b.id
        end)
        local board = ER.board and ER.board(hid) or {}
        board.cards = ER.cards and ER.cards(hid) or {}
        board.unregistered = ER.unregisteredRows and ER.unregisteredRows(hid) or {}
        board.threads = ER.threadList and ER.threadList(hid, player) or {}
        board.notes = ER.notesOf and ER.notesOf(player) or {}
        triggerClientEvent(player, "his:list", resourceRoot, list, board)
    elseif what == "drugs" then
        if ER.running("medsys") then triggerClientEvent(player, "his:drugs", resourceRoot, exports.medsys:getDrugCatalog()) end
    elseif what == "register" then
        if ER.registerToken then ER.registerToken(hid, player, tostring(arg)) end
    elseif what == "stock" then
        if ER.stockView then triggerClientEvent(player, "his:stock", resourceRoot, ER.stockView(hid)) end
    elseif what == "stockOrder" then
        if ER.orderStock then
            local ok, why = ER.orderStock(hid, player)
            ER.notify(player, L.forPlayer(player, ok and "med_hospitals.stock.ordered" or ("med_hospitals.stock.order_" .. tostring(why)), { cost = why }), not ok)
            triggerClientEvent(player, "his:stock", resourceRoot, ER.stockView(hid))
        end
    elseif what == "case" then
        for _, c in pairs(ER.cases) do
            if c.id == arg and c.hospital == hid then
                return triggerClientEvent(player, "his:case", resourceRoot, detail(c, player))
            end
        end
        triggerClientEvent(player, "his:case", resourceRoot, false)
    end
end)

-- documentation (free texts, BNO diagnoses) only at a hospital PC, never from the tablet (2026-11-06)
local PC_DOC_RANGE = 3.0
function ER.atPC(player)
    if not isElement(player) then return false end
    local px, py, pz = getElementPosition(player)
    local dim, int = getElementDimension(player), getElementInterior(player)
    for _, e in pairs(ER.byHospital) do
        if (e.h.dimension or 0) == dim and (e.h.interior or 0) == int then
            for _, pc in ipairs(e.cfg.pcs or {}) do
                if getDistanceBetweenPoints3D(px, py, pz, pc.x, pc.y, pc.z) <= PC_DOC_RANGE then return true end
            end
        end
    end
    return false
end

local function docsAtPC(player)
    if ER.atPC(player) then return true end
    ER.notify(player, L.forPlayer(player, "med_hospitals.his.docs_pc_only"), true)
    return false
end

local function caseById(hid, id)
    for _, c in pairs(ER.cases) do if c.id == id and c.hospital == hid then return c end end
end

addEvent("his:action", true)
addEventHandler("his:action", resourceRoot, function(caseId, action, a1, a2)
    local player = client
    local hid = getElementData(player, "hosp.staff")
    if not hid or not ER.isStaff(player, hid) then return end
    local c = caseById(hid, caseId)
    if not c then return end
    if action == "order" then ER.order(c, player, a1, a2)
    elseif action == "perform" then ER.perform(c, player, tonumber(a1))
    elseif action == "orderPerform" then
        local ord = ER.order(c, player, a1, a2)
        if ord then ER.perform(c, player, ord.id) end
    elseif action == "treat" then ER.treat(c, player, a1, tonumber(a2))
    elseif action == "drugOrder" then ER.orderDrug(c, player, a1, a2)
    elseif action == "drugCancel" then ER.cancelDrugOrder(c, player, tonumber(a1))
    elseif action == "diagAdd" then if docsAtPC(player) then ER.addDiagnosis(c, player, a1) end
    elseif action == "diagRemove" then if docsAtPC(player) then ER.removeDiagnosis(c, player, a1) end
    elseif action == "triage" then ER.setTriage(c, tonumber(a1), player)
    elseif action == "treating" then
        local ok = canDo(player, "er.treat")
        if ok and c.triage > 0 then
            local first = not c.treating
            ER.setTreating(c, player)
            if c.status == "triaged" or c.status == "waiting" then c.status = "treating" ER.syncCase(c) end
            if first then ER.points(player, "HK-A02", 2, L.forPlayer(player, "med_hospitals.er.code_a02"), c) end
        end
    elseif action == "outcome" and ER.setOutcome then ER.setOutcome(c, player, a1, a2)
    elseif action == "exam" then ER.examine(c, player, a1, a2)
    elseif action == "text" then
        -- free text parts of the Ambuláns lap (the author's language stays; K23)
        if (a1 == "anamnesis" or a1 == "status" or a1 == "epicrisis") and type(a2) == "string" and docsAtPC(player) then
            local text = a2:gsub("[%c]", " "):sub(1, 1200)
            if a1 == "anamnesis" then c.anamnesis = text elseif a1 == "status" then c.statusText = text else c.epicrisis = text end
            ER.log(c, "text", a1, player)
            ER.syncCase(c)
        end
    elseif action == "give" then
        -- a medicine from the panel: medsys does it with every check (rank, IV access, stock, ordered for a nurse)
        if ER.running("medsys") then
            local ok, why = exports.medsys:startTreatmentFor(player, c.ped, "medication", tostring(a1), tonumber(a2))
            if not ok and why then ER.notify(player, tostring(why), true) end
        end
    elseif action == "medsys" then
        -- the medsys panel (monitor, IV, infusion, airway, CPR ...) on this patient
        if ER.running("medsys") then exports.medsys:openExamination(player, c.ped) end
    elseif action == "procedure" and ER.doProcedure then ER.doProcedure(c, player, a1, a2)
    elseif action == "transfuse" and ER.transfuse then ER.transfuse(c, player, a1, a2)
    elseif action == "icu" and ER.icuAction then ER.icuAction(c, player, a1, a2)
    end
end)

-- every staff client with the HIS open re-reads after a change
local dirtyTimer = {}
local function markDirty(hid)
    if dirtyTimer[hid] then return end
    dirtyTimer[hid] = setTimer(function()
        dirtyTimer[hid] = nil
        for _, p in ipairs(ER.staff(hid)) do triggerClientEvent(p, "his:dirty", resourceRoot) end
    end, 300, 1)
end
local oldChanged = ER.onCaseChanged
ER.onCaseChanged = function(c) if oldChanged then oldChanged(c) end markDirty(c.hospital) end
local oldClosed = ER.onCaseClosed
ER.onCaseClosed = function(c) if oldClosed then oldClosed(c) end markDirty(c.hospital) end
ER.markDirty = markDirty

-- the hospitals (transfer target picker of the patient panel)
addEvent("his:hospitalsReq", true)
addEventHandler("his:hospitalsReq", resourceRoot, function()
    local list = {}
    for _, h in ipairs(Hospitals.list) do list[#list + 1] = { id = h.id, name = h.name } end
    triggerClientEvent(client, "his:hospitals", resourceRoot, list)
end)

-- The PC desks of every ER (the client draws the [E] hint near them). The hospitals are loaded 500 ms
-- after the start, so a client that said hello before that got an empty list: every ready client
-- gets the list again once the hospitals are (re)loaded.
local readyClients = {}

local function pcList()
    local list = {}
    for _, e in pairs(ER.byHospital) do
        for _, pc in ipairs(e.cfg.pcs or {}) do list[#list + 1] = { x = pc.x, y = pc.y, z = pc.z, hospital = e.h.id } end
    end
    return list
end

addEvent("his:hello", true)
addEventHandler("his:hello", resourceRoot, function()
    readyClients[client] = true
    triggerClientEvent(client, "his:pcs", resourceRoot, pcList())
end)
addEventHandler("onPlayerQuit", root, function() readyClients[source] = nil end)

LoadHandlers[#LoadHandlers + 1] = function()
    local list = pcList()
    for p in pairs(readyClients) do
        if isElement(p) then triggerClientEvent(p, "his:pcs", resourceRoot, list) else readyClients[p] = nil end
    end
end

---------------------------------------------------------------- points for medsys interventions by the staff

addEvent("onMedicalTreatment")
addEventHandler("onMedicalTreatment", root, function(medic, action, success)
    if success ~= true or not isElement(medic) then return end
    local c = ER.cases[source]
    if not c or not ER.isStaff(medic, c.hospital) then return end
    local p = MEDSYS_POINTS[action]
    if not p then return end
    c.medsysDone = c.medsysDone or {}
    local key = tostring(medic) .. action
    if c.medsysDone[key] then return end
    c.medsysDone[key] = true
    ER.points(medic, p[1], p[2], L.forPlayer(medic, "med_hospitals.erc.medsys_" .. action), c)
    ER.log(c, "medsys", action, medic)
    markDirty(c.hospital)
end)
