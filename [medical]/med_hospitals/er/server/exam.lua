-- Hospital examination (plan: Vizsgálati panel, "Vizsgálat" tab). Every exam step takes 2-6 s at the
-- bedside and writes result lines into the case (c.exam["region:method"] = { lines }). The lines come from
-- the hidden findings and the medsys state: an exam never confirms a hidden finding (imaging does), but it
-- shows its signs (right upper quadrant guarding over a liver injury) and makes the Teendők hint specific.
--
-- line = { key, params } (v_locals med_hospitals.exam.<key>, the client translates it)

local EXAM_RANGE = 3.2

ER.EXAM = {
    vitals  = { measure = { t = 4, code = "HK-V09" } },
    head    = { inspect = { t = 2 }, palpate = { t = 3 } },
    chest   = { inspect = { t = 2 }, palpate = { t = 3 }, auscultate = { t = 4, code = "HK-V11" }, percuss = { t = 3, code = "HK-V11" } },
    abdomen = { inspect = { t = 2 }, palpate = { t = 4, code = "HK-V10" }, auscultate = { t = 3, code = "HK-V10" } },
    limbs   = { inspect = { t = 2 }, palpate = { t = 3 }, cms = { t = 4, code = "HK-V12" } },
    spine   = { inspect = { t = 2 }, palpate = { t = 3, code = "HK-V13" } },
    neuro   = { gcs = { t = 3, code = "HK-V04" }, pupils = { t = 2, code = "HK-V04" }, nihss = { t = 6, code = "HK-V05" }, strength = { t = 3 },
                befast = { t = 3, code = "HK-V16" } },
    skin    = { inspect = { t = 2 }, temp = { t = 3, code = "HK-V08" } },
    pain    = { nrs = { t = 2, code = "HK-V06" } },
    history = { anamnesis = { t = 4, code = "HK-V03" }, meds = { t = 3 }, allergy = { t = 2 }, lastmeal = { t = 2 }, event = { t = 3 } },
}
ER.EXAM_ORDER = { "vitals", "head", "chest", "abdomen", "limbs", "spine", "neuro", "skin", "pain", "history" }

local function ms() return ER.running("medsys") and exports.medsys or nil end

local function has(c, ids)
    local out = {}
    for _, f in ipairs(ER.findings(c)) do
        if ids[f.id] then out[#out + 1] = f end
    end
    return out
end
local function set(...) local t = {} for _, v in ipairs({ ... }) do t[v] = true end return t end

-- seeded per case (stable answers to the history questions)
local function seeded(c, salt, n) return ((c.id or 1) * 7919 + salt * 104729) % n + 1 end

---------------------------------------------------------------- the patient's background (history answers)

local ALLERGIES = { "none", "none", "none", "none", "none", "none", "penicillin", "nsaid", "latex", "contrast" }
local MEDS = { "none", "none", "none", "none", "antihypertensive", "statin", "inhaler", "anticoagulant", "antidepressant", "insulin" }

function ER.background(c)
    if c.background then return c.background end
    local b = { allergy = ALLERGIES[seeded(c, 11, #ALLERGIES)], meds = MEDS[seeded(c, 13, #MEDS)],
                lastmeal = seeded(c, 17, 9) + 1 }   -- hours ago
    -- the conditions decide some answers
    for _, f in ipairs(ER.findings(c)) do
        if f.id == "asthma" or f.id == "copd" then b.meds = "inhaler" end
        if f.id == "stroke_isch" or f.id == "ich" then b.meds = seeded(c, 19, 2) == 1 and "anticoagulant" or "antihypertensive" end
    end
    if b.meds == "anticoagulant" and ms() then
        -- an anticoagulated patient bleeds more and has a high INR (medsys labs)
        pcall(function() ms():setMedicalState(c.ped, "anticoagulant", true) end)
    end
    c.background = b
    return b
end

---------------------------------------------------------------- result lines

local SIDE = { left = "left", right = "right" }
local function sideKey(f) return f and SIDE[f.side] or "left" end
local function L1(key, p) return { key, p or {} } end

local GCS = { stable = { 4, 5, 6 }, confused = { 4, 4, 6 }, dazed = { 3, 3, 5 }, unconscious = { 1, 2, 4 }, clinical_death = { 1, 1, 1 }, dead = { 1, 1, 1 } }

local function lines(c, region, method, snap)
    local out = {}
    local function add(key, p) out[#out + 1] = L1(key, p) end
    local down = snap.consciousness == "unconscious" or snap.clinicalDeath or snap.dead
    if region == "vitals" then
        local rr = ({ normal = 16, rapid = 26, wheeze = 24, laboured = 28, crackles = 28, kussmaul = 30, silent = 32, slow = 7, snoring = 12, agonal = 4, none = 0, ventilated = 14 })[snap.breathing or "normal"] or 16
        c.measured = { hr = snap.heartRate, bp = snap.bloodPressure, spo2 = snap.spo2, rr = rr, at = getRealTime().timestamp }
        add("vitals_line", { hr = snap.heartRate or "-", bp = snap.bloodPressure or "-", spo2 = snap.spo2 or "-", rr = rr })
    elseif region == "head" then
        if method == "inspect" then
            if #has(c, set("wound_head")) > 0 then add("head_wound") end
            if #has(c, set("skull_fx")) > 0 then add("head_haematoma") end
            if #has(c, set("face_fx")) > 0 then add("face_deformity") end
            if #has(c, set("edh", "sdh", "sah", "brain_contusion")) > 0 and #has(c, set("skull_fx", "wound_head")) == 0 then add("head_bruise") end
            if #out == 0 then add("head_normal") end
        else
            if #has(c, set("skull_fx")) > 0 then add("skull_step") elseif #has(c, set("face_fx")) > 0 then add("face_crepitus") else add("skull_normal") end
        end
    elseif region == "chest" then
        local ptx, htx = has(c, set("ptx"))[1], has(c, set("htx"))[1]
        local rib = has(c, set("rib_fx", "rib_fx_single"))[1]
        if method == "inspect" then
            if #has(c, set("wound_torso", "htx")) > 0 then add("chest_wound") end
            if ptx or htx then add("chest_reduced", { side = sideKey(ptx or htx) }) end
            if rib then add("chest_painful_breathing") end
            if #has(c, set("asthma", "copd", "pulm_edema")) > 0 then add("chest_accessory_muscles") end
            if #out == 0 then add("chest_normal") end
        elseif method == "palpate" then
            if rib then add("chest_rib_tender", { side = sideKey(rib) }) end
            if ptx then add("chest_emphysema") end
            if #out == 0 then add("chest_palp_normal") end
        elseif method == "auscultate" then
            if ptx or htx then add("chest_absent", { side = sideKey(ptx or htx) }) end
            if #has(c, set("asthma", "copd")) > 0 then add("chest_wheeze") end
            if #has(c, set("pulm_edema")) > 0 then add("chest_crackles") end
            if #has(c, set("tamponade")) > 0 then add("heart_muffled") end
            if #out == 0 then add("chest_ausc_normal") end
        else
            if ptx then add("chest_hyperresonant", { side = sideKey(ptx) }) end
            if htx then add("chest_dull", { side = sideKey(htx) }) end
            if #out == 0 then add("chest_perc_normal") end
        end
    elseif region == "abdomen" then
        local spleen, liver, gsw = has(c, set("spleen"))[1], has(c, set("liver"))[1], has(c, set("gsw_abdomen"))[1]
        if method == "inspect" then
            if gsw then add("abd_wound") end
            if spleen then add("abd_bruise", { side = "left" }) end
            if liver then add("abd_bruise", { side = "right" }) end
            if #out == 0 then add("abd_normal") end
        elseif method == "palpate" then
            if down then add("abd_palp_unconscious") end
            if spleen then add("abd_guarding", { side = "left" }) end
            if liver then add("abd_guarding", { side = "right" }) end
            if gsw then add("abd_diffuse") end
            if #has(c, set("appendicitis")) > 0 then add("abd_mcburney") end
            if #has(c, set("renal_colic")) > 0 then add("abd_flank") end
            if #out == 0 then add("abd_soft") end
        else
            if spleen or liver or gsw or #has(c, set("opioid", "appendicitis")) > 0 then add("abd_sounds_quiet") else add("abd_sounds_normal") end
        end
    elseif region == "limbs" then
        local fx = has(c, set("radius_fx", "humerus_fx", "tibia_fx", "femur_fx", "ankle_fx"))
        local neck = has(c, set("femneck_fx"))[1]
        local pelvis = has(c, set("pelvis_fx"))[1]
        local wounds = has(c, set("wound_arm", "wound_leg"))
        if method == "inspect" then
            for _, w in ipairs(wounds) do add("limb_wound", { side = sideKey(w), part = w.id == "wound_arm" and "arm" or "leg" }) end
            for _, f in ipairs(fx) do
                if f.treated then add("limb_cast", { side = sideKey(f), part = (f.id:find("radius") or f.id:find("humerus")) and "arm" or "leg" })
                else add("limb_deformity", { side = sideKey(f), part = (f.id:find("radius") or f.id:find("humerus")) and "arm" or "leg" }) end
            end
            if neck then add("leg_short_rotated", { side = sideKey(neck) }) end
            if #out == 0 then add("limbs_normal") end
        elseif method == "palpate" then
            if #fx > 0 then add("limb_crepitus") end
            if pelvis then add("pelvis_unstable") end
            if neck then add("hip_pain", { side = sideKey(neck) }) end
            if #out == 0 then add("limbs_palp_normal") end
        else
            if #fx > 0 or neck then
                local tight = false
                for _, f in ipairs(fx) do if f.castTight then tight = true end end
                add(tight and "cms_cast_tight" or "cms_ok_pain")
            else add("cms_normal") end
        end
    elseif region == "spine" then
        local sp = has(c, set("cspine_fx", "tspine_fx", "lumbar_fx"))[1]
        if method == "inspect" then add(sp and "spine_bruise" or "spine_normal")
        else
            if sp then add("spine_tender", { level = sp.id == "cspine_fx" and "c" or (sp.id == "tspine_fx" and "t" or "l") }) else add("spine_palp_normal") end
        end
    elseif region == "neuro" then
        local g = GCS[snap.consciousness or "stable"] or GCS.stable
        local stroke = has(c, set("stroke_isch", "ich"))[1]
        local mass = has(c, set("edh", "sdh"))[1]
        if method == "gcs" then
            c.gcs = g[1] + g[2] + g[3]
            add("gcs", { total = c.gcs, e = g[1], v = g[2], m = g[3] })
        elseif method == "pupils" then
            if #has(c, set("opioid")) > 0 then add("pupils_pinpoint")
            elseif #has(c, set("stimulant")) > 0 then add("pupils_dilated")
            elseif mass and (snap.consciousness ~= "stable") then add("pupil_blown", { side = sideKey(mass) })
            elseif snap.clinicalDeath or snap.dead then add("pupils_fixed")
            else add("pupils_normal") end
        elseif method == "nihss" then
            local score = 0
            if stroke then for _, inj in ipairs(snap.conditions or {}) do if inj.type == "stroke" then score = ({ 4, 9, 16 })[inj.severity] or 6 end end end
            c.nihss = c.nihss or score
            c.nihssLast = score
            add("nihss", { score = score })
        elseif method == "befast" then
            add(stroke and "befast_positive" or "befast_negative")
        else
            if stroke then add("hemiparesis", { side = stroke.side == "left" and "right" or "left" })
            elseif #has(c, set("cspine_fx")) > 0 and snap.consciousness ~= "stable" then add("tetraparesis")
            elseif down then add("strength_untestable")
            else add("strength_normal") end
        end
    elseif region == "skin" then
        if method == "inspect" then
            local sign = (snap.spo2 or 99) < 85 and "cyanotic"
                or (((snap.bloodPercent or 100) < 80 or (snap.systolic or 120) < 90) and "pale")
                or snap.skinSign or "normal"
            add("skin_" .. sign)
            local burn = has(c, set("burn", "burn_major"))[1]
            if burn then add(burn.id == "burn_major" and "burn_major" or "burn_minor") end
        else
            local t = 36.6
            if #has(c, set("sepsis", "appendicitis")) > 0 then t = 38.6 end
            if #has(c, set("stimulant")) > 0 then t = 38.1 end
            c.temperature = t
            add("temperature", { t = string.format("%.1f", t) })
        end
    elseif region == "pain" then
        c.nrs = math.floor((snap.pain or 0) / 10 + 0.5)
        add(down and "nrs_untestable" or "nrs", { n = c.nrs })
    elseif region == "history" then
        local b = ER.background(c)
        local speaks = not down and snap.consciousness ~= "dazed"
        if method == "anamnesis" then
            if c.anamnesis and c.anamnesis ~= "" then add("hx_handover", { text = c.anamnesis }) end
            if not speaks then add("hx_not_possible") end
        elseif not speaks then add("hx_not_possible")
        elseif method == "meds" then add("meds_" .. b.meds)
        elseif method == "allergy" then add("allergy_" .. b.allergy) c.allergy = b.allergy
        elseif method == "lastmeal" then add("lastmeal", { h = b.lastmeal })
        else
            local cause
            for _, inj in ipairs(snap.injuries or {}) do if inj.cause then cause = inj.cause end end
            add(cause and ("event_" .. cause) or (#has(c, set("stroke_isch", "ich")) > 0 and "event_stroke") or "event_unknown")
        end
    end
    return out
end

---------------------------------------------------------------- doing an exam step

function ER.examine(c, player, region, method)
    local def = ER.EXAM[region] and ER.EXAM[region][method]
    if not def or not isElement(c.ped) then return false end
    local px, py, pz = getElementPosition(player)
    local x, y, z = getElementPosition(c.ped)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > EXAM_RANGE then
        return ER.notify(player, L.forPlayer(player, "med_hospitals.exam.too_far"), true)
    end
    c.examBusy = c.examBusy or {}
    local key = region .. ":" .. method
    if c.examBusy[key] then return false end
    c.examBusy[key] = true
    triggerClientEvent(player, "his:examProgress", resourceRoot, c.id, key, def.t)
    setPedAnimation(player, "MEDIC", "CPR", def.t * 1000, false, false, false, false)
    setTimer(function()
        c.examBusy[key] = nil
        if not ER.cases[c.ped] then return end
        if isElement(player) then setPedAnimation(player) end
        local snap = ms() and ms():getMedicalState(c.ped) or {}
        c.exam = c.exam or {}
        c.exam[key] = { lines = lines(c, region, method, snap), at = getRealTime().timestamp, by = isElement(player) and getPlayerName(player) or "" }
        if isElement(player) then
            -- points: the primary survey once, the region's own code, the full exam after six regions
            if not c.primaryDone then c.primaryDone = true ER.award(player, c, "HK-V01", 4, "med_docs.code.hk_v01") end
            if def.code then ER.award(player, c, def.code, 0, "med_docs.code." .. def.code:lower():gsub("%-", "_")) end
            local regions = {}
            for k in pairs(c.exam) do regions[k:match("^(%w+):")] = true end
            local n = 0 for _ in pairs(regions) do n = n + 1 end
            if n >= 6 and not c.fullExamDone then c.fullExamDone = true ER.award(player, c, "HK-V02", 8, "med_docs.code.hk_v02") end
        end
        ER.log(c, "exam", key, player)
        ER.syncCase(c)
    end, def.t * 1000, 1)
    return true
end

-- the status text template of the Ambuláns lap (from the exam results), in a language
function ER.statusTemplate(c, lang)
    local parts = {}
    for _, region in ipairs(ER.EXAM_ORDER) do
        for method in pairs(ER.EXAM[region]) do
            local e = c.exam and c.exam[region .. ":" .. method]
            if e and region ~= "history" then
                for _, ln in ipairs(e.lines) do
                    local p = {}
                    for k, v in pairs(ln[2] or {}) do p[k] = v end
                    if p.side then p.side = L.forLang(lang, "med_hospitals.exam.side_" .. p.side) end
                    if p.part then p.part = L.forLang(lang, "med_hospitals.exam.part_" .. p.part) end
                    parts[#parts + 1] = L.forLang(lang, "med_hospitals.exam." .. ln[1], p)
                end
            end
        end
    end
    return table.concat(parts, " ")
end
