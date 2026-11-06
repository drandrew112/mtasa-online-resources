L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- Hospital conditions and medicines (plan: Új kórképek, Mérgezések, kórházi gyógyszerlista). Declarative
-- like the ones in shared/config.lua; the time course (STEMI necrosis and stage, appendicitis turning
-- septic, lysis, poisons) is in server/conditions.lua, the labs in server/labs.lua (MEDIC_LAB_EFFECTS),
-- the 12-lead ECG in ecg12 (MEDIC_ECG_EFFECTS).

local function T(k) return L.text("medsys.cond." .. k) end
local function N(k, lvl) return { L.text("medsys.cond.n_" .. k), lvl or 2 } end

local NEW = {
    -- acute coronary syndrome: 1 NSTEMI, 2 STEMI, 3 STEMI in cardiogenic shock (territory: server/conditions.lua)
    acs = { label = T("acs"), hidden = true, bleed = { 0, 0, 0 }, pain = { 60, 75, 85 },
        systolic = { 5, -5, -35 }, heartRate = { 10, 15, 25 }, spo2 = { nil, 94, 88 }, spo2Rate = 0.1,
        consciousness = { nil, nil, "confused" },
        neuro = { { N("chest_pain") }, { N("chest_pain", 3), N("sweaty") }, { N("chest_pain", 3), N("cold_clammy", 3) } } },
    appendicitis = { label = T("appendicitis"), hidden = true, bleed = { 0, 0, 0 }, pain = { 45, 60, 80 },
        heartRate = { 8, 15, 25 }, systolic = { 0, 0, -10 },
        neuro = { { N("rlq_pain") }, { N("rlq_pain"), N("fever") }, { N("rigid_abdomen", 3), N("fever", 3) } } },
    renal_colic = { label = T("renal_colic"), hidden = true, bleed = { 0, 0, 0 }, pain = { 70, 85, 90 }, heartRate = { 15, 20, 25 },
        systolic = { 15, 20, 25 }, treatDrugs = { "metamizole", "morphine" }, treatedVitals = 0.2,
        neuro = { { N("flank_pain") }, { N("flank_pain", 3), N("restless") }, { N("flank_pain", 3), N("vomits") } } },
    gi_bleed = { label = T("gi_bleed"), hidden = true, bleed = { 0, 0, 0 }, loss = { 0.6, 1.4, 2.8 }, pain = { 10, 20, 30 },
        heartRate = { 10, 20, 35 },
        neuro = { { N("melaena") }, { N("haematemesis", 3) }, { N("haematemesis", 3), N("cold_clammy", 3) } } },
    sepsis = { label = T("sepsis"), hidden = true, bleed = { 0, 0, 0 }, pain = { 10, 15, 20 },
        systolic = { -15, -30, -50 }, heartRate = { 20, 30, 45 }, spo2 = { nil, 93, 88 }, spo2Rate = 0.1,
        consciousness = { nil, "confused", "dazed" }, breathing = { "rapid", "rapid", "rapid" },
        treatDrugs = { "ceftriaxone" }, treatedVitals = 0.5,
        neuro = { { N("fever") }, { N("fever", 3), N("mottled") }, { N("fever", 3), N("mottled", 3) } } },
    dka = { label = T("dka"), hidden = true, bleed = { 0, 0, 0 }, pain = { 15, 20, 30 }, loss = { 0.1, 0.25, 0.4 },
        heartRate = { 15, 25, 35 }, consciousness = { nil, "confused", "dazed" }, breathing = { "kussmaul", "kussmaul", "kussmaul" },
        treatDrugs = { "insulin" }, treatedVitals = 0.3,
        neuro = { { N("acetone") }, { N("acetone"), N("dry_mouth") }, { N("acetone", 3), N("dry_mouth", 3) } } },
    pe = { label = T("pe"), hidden = true, bleed = { 0, 0, 0 }, pain = { 30, 45, 60 },
        systolic = { 0, -15, -40 }, heartRate = { 25, 35, 50 }, spo2 = { 92, 85, 74 }, spo2Rate = 0.25,
        breathing = { "rapid", "rapid", "laboured" }, treatDrugs = { "alteplase" }, treatedVitals = 0.2, treatedSpo2 = { nil, 94, 90 },
        neuro = { { N("pleuritic") }, { N("pleuritic"), N("swollen_calf") }, { N("pleuritic", 3), N("syncope", 3) } } },
    anaphylaxis = { label = T("anaphylaxis"), hidden = true, bleed = { 0, 0, 0 }, pain = { 10, 15, 20 },
        systolic = { -25, -45, -70 }, heartRate = { 25, 35, 45 }, spo2 = { 93, 86, 74 }, spo2Rate = 0.35,
        breathing = { "wheeze", "wheeze", "silent" }, consciousness = { nil, "confused", "unconscious" },
        treatDrugs = { "epinephrine" }, treatedVitals = 0.1, treatedSpo2 = { nil, 95, 92 },
        neuro = { { N("urticaria") }, { N("urticaria"), N("lip_swelling", 3) }, { N("stridor", 3), N("lip_swelling", 3) } } },
    hyperkalemia = { label = T("hyperkalemia"), hidden = true, bleed = { 0, 0, 0 }, pain = { 0, 5, 10 },
        heartRate = { -10, -20, -35 }, systolic = { 0, -10, -25 }, treatDrugs = { "calcium" }, treatedVitals = 0.3,
        neuro = { { N("weak") }, { N("weak", 3) }, { N("weak", 3), N("paraesthesia", 3) } } },
    tamponade = { label = T("tamponade"), hidden = true, bleed = { 0, 0, 0 }, pain = { 20, 30, 40 },
        systolic = { -25, -45, -65 }, heartRate = { 20, 30, 40 }, consciousness = { nil, "confused", "dazed" },
        neuro = { { N("jvd") }, { N("jvd", 3), N("muffled", 3) }, { N("jvd", 3), N("muffled", 3) } } },
    afib = { label = T("afib"), hidden = true, rhythm = "AFIB", bleed = { 0, 0, 0 }, pain = { 5, 10, 15 },
        heartRate = { 30, 45, 60 }, systolic = { 0, -10, -25 }, treatDrugs = { "amiodarone" }, treatedVitals = 0.2,
        neuro = { { N("palpitations") }, { N("palpitations"), N("dizzy") }, { N("palpitations", 3), N("dizzy", 3) } } },
    avb3 = { label = T("avb3"), hidden = true, rhythm = "AVB3", bleed = { 0, 0, 0 }, pain = { 0, 5, 10 },
        heartRate = { -30, -38, -45 }, systolic = { -10, -25, -40 }, consciousness = { nil, "confused", "dazed" },
        neuro = { { N("dizzy") }, { N("dizzy", 3), N("syncope") }, { N("syncope", 3) } } },
    -- minor injuries (walk-ins): visible
    sprain = { label = T("sprain"), bleed = { 0, 0, 0 }, pain = { 25, 40, 55 },
        treat = "splint", treatedLabel = L.text("medsys.config.splinted"), treatedPain = 0.4 },
    laceration = { label = T("laceration"), bleed = { 1, 1, 2 }, pain = { 15, 25, 35 },
        treat = "bandage", treatedLabel = L.text("medsys.config.bandaged"), treatedPain = 0.6 },
    -- poisonings (plan: Mérgezések); opioid, sedative, stimulant, alcohol are in shared/config.lua
    poison_paracetamol = { label = T("poison_paracetamol"), hidden = true, bleed = { 0, 0, 0 }, pain = { 5, 15, 30 },
        treatDrugs = { "acetylcysteine" }, neuro = { { N("nausea", 1) }, { N("nausea") }, { N("jaundice", 3) } } },
    poison_tca = { label = T("poison_tca"), hidden = true, bleed = { 0, 0, 0 }, pain = { 0, 0, 0 },
        heartRate = { 25, 40, 55 }, systolic = { -10, -25, -45 }, consciousness = { "confused", "dazed", "unconscious" },
        treatDrugs = { "bicarbonate" }, treatedVitals = 0.3,
        neuro = { { N("dilated_dry") }, { N("dilated_dry"), N("twitching") }, { N("dilated_dry", 3), N("seizure", 3) } } },
    poison_organophosphate = { label = T("poison_organophosphate"), hidden = true, bleed = { 0, 0, 0 }, pain = { 10, 15, 20 },
        heartRate = { -20, -30, -40 }, spo2 = { 92, 84, 72 }, spo2Rate = 0.3, breathing = { "crackles", "crackles", "laboured" },
        consciousness = { nil, "confused", "unconscious" }, treatDrugs = { "atropine", "pralidoxime" }, treatedVitals = 0.2,
        neuro = { { N("salivation") }, { N("salivation"), N("pinpoint") }, { N("salivation", 3), N("pinpoint", 3) } } },
    poison_co = { label = T("poison_co"), hidden = true, bleed = { 0, 0, 0 }, pain = { 10, 15, 20 },
        heartRate = { 10, 20, 30 }, consciousness = { "confused", "dazed", "unconscious" },
        neuro = { { N("headache") }, { N("headache"), N("cherry", 1) }, { N("headache", 3), N("smoke_room", 3) } } },
    poison_betablocker = { label = T("poison_betablocker"), hidden = true, bleed = { 0, 0, 0 }, pain = { 0, 0, 0 },
        heartRate = { -20, -30, -40 }, systolic = { -20, -35, -50 }, consciousness = { nil, "confused", "dazed" },
        treatDrugs = { "glucagon", "calcium" }, treatedVitals = 0.3, neuro = { { N("dizzy") }, { N("dizzy", 3) }, { N("syncope", 3) } } },
    poison_digoxin = { label = T("poison_digoxin"), hidden = true, bleed = { 0, 0, 0 }, pain = { 5, 10, 15 },
        heartRate = { -15, -25, -35 }, systolic = { -5, -15, -30 }, treatDrugs = { "digifab" }, treatedVitals = 0.2,
        neuro = { { N("nausea") }, { N("yellow_vision") }, { N("yellow_vision", 3), N("confused_old", 3) } } },
    poison_methanol = { label = T("poison_methanol"), hidden = true, bleed = { 0, 0, 0 }, pain = { 10, 20, 30 },
        heartRate = { 10, 20, 30 }, consciousness = { nil, "confused", "unconscious" }, breathing = { nil, "kussmaul", "kussmaul" },
        treatDrugs = { "fomepizole" }, neuro = { { N("blurred") }, { N("blurred", 3) }, { N("blind", 3) } } },
    poison_cyanide = { label = T("poison_cyanide"), hidden = true, bleed = { 0, 0, 0 }, pain = { 5, 10, 10 },
        heartRate = { 15, -10, -35 }, systolic = { -10, -35, -60 }, consciousness = { "confused", "unconscious", "unconscious" },
        treatDrugs = { "hydroxocobalamin" }, treatedVitals = 0.2, neuro = { { N("almond", 1) }, { N("smoke_room", 3) }, { N("smoke_room", 3) } } },
}
for id, def in pairs(NEW) do MEDIC_INJURIES[id] = def end

-- the hospital medicines (hospital = true: only with the hospital's stock, server/equipment.lua)
local function D(k) return L.text("medsys.drug." .. k) end
local function opts(unit, list, std, def, perKg) local o = {} for i, v in ipairs(list) do o[i] = { dose = v[1], high = v[2], note = v[3] and D("note_" .. v[3]) or nil } end
    return { unit = unit, perKg = perKg or nil, standard = std, default = def or 1, options = o } end
local DRUGS = {
    amiodarone = { name = "Amiodaron (Cordarone)", class = D("c_antiarrhythmic"), desc = D("d_amiodarone"), heartRate = -15,
        treats = { "afib" }, dosing = opts("mg", { { 150 }, { 300, false, "arrest" } }, 300, 1), duration = 1800 },
    atropine = { name = "Atropin", class = D("c_anticholinergic"), desc = D("d_atropine"), heartRate = 25,
        treats = { "poison_organophosphate" }, dosing = opts("mg", { { 0.5 }, { 1 }, { 2, true, "op" } }, 1, 2), duration = 900 },
    noradrenaline = { name = "Noradrenalin (perfúzor)", class = D("c_vasopressor"), desc = D("d_noradrenaline"), systolic = 35, heartRate = 5,
        dosing = opts("mcg/kg/min", { { 0.05 }, { 0.1 }, { 0.2, true } }, 0.1, 2), duration = 900 },
    propofol = { name = "Propofol", class = D("c_anaesthetic"), desc = D("d_propofol"), systolic = -20, sedation = true,
        dosing = opts("mg", { { 1 }, { 2, true } }, 1.5, 1, true), duration = 600 },
    morphine = { name = "Morfin", class = D("c_painkiller"), desc = D("d_morphine"), analgesia = 0.6, systolic = -5,
        treats = { "renal_colic" }, dosing = opts("mg", { { 2 }, { 5 }, { 10, true } }, 5, 2), duration = 1800 },
    metamizole = { name = "Metamizol (Algopyrin)", class = D("c_painkiller"), desc = D("d_metamizole"), analgesia = 0.35,
        treats = { "renal_colic" }, dosing = opts("mg", { { 1000 }, { 2000, true } }, 1000, 1), duration = 2400 },
    ondansetron = { name = "Ondansetron", class = D("c_antiemetic"), desc = D("d_ondansetron"), dosing = opts("mg", { { 4 }, { 8 } }, 4, 1), duration = 1800 },
    flumazenil = { name = "Flumazenil (Anexate)", class = D("c_antidote"), desc = D("d_flumazenil"), treats = { "sedative" },
        dosing = opts("mg", { { 0.2 }, { 0.5, true } }, 0.2, 1), duration = 600 },
    lidocaine = { name = "Lidokain 1%", class = D("c_local"), desc = D("d_lidocaine"), analgesia = 0.2, dosing = opts("mg", { { 50 }, { 100 } }, 50, 1), duration = 1200 },
    txa = { name = "Tranexámsav (TXA)", class = D("c_haemostatic"), desc = D("d_txa"), dosing = opts("g", { { 1 } }, 1, 1), duration = 3600 },
    alteplase = { name = "Alteplase (Actilyse)", class = D("c_thrombolytic"), desc = D("d_alteplase"), treats = { "pe" },
        dosing = opts("mg", { { 0.9, false, "stroke" }, { 1.0, true, "stemi" } }, 0.9, 1, true), duration = 3600 },
    aspirin = { name = "Acetilszalicilsav (ASA)", class = D("c_antiplatelet"), desc = D("d_aspirin"), route = "oral",
        dosing = opts("mg", { { 250 }, { 500 } }, 250, 1), duration = 7200 },
    clopidogrel = { name = "Klopidogrél", class = D("c_antiplatelet"), desc = D("d_clopidogrel"), route = "oral",
        dosing = opts("mg", { { 300, false, "lysis" }, { 600, false, "pci" } }, 600, 2), duration = 7200 },
    heparin = { name = "Heparin", class = D("c_anticoagulant"), desc = D("d_heparin"), dosing = opts("NE", { { 5000 } }, 5000, 1), duration = 3600 },
    ceftriaxone = { name = "Ceftriaxon", class = D("c_antibiotic"), desc = D("d_ceftriaxone"), treats = { "sepsis" },
        dosing = opts("g", { { 2 } }, 2, 1), duration = 7200 },
    tetanus = { name = "Tetanusz vakcina (Tetadif)", class = D("c_vaccine"), desc = D("d_tetanus"), route = "im", duration = 60 },
    calcium = { name = "Kalcium-glükonát 10%", class = D("c_electrolyte"), desc = D("d_calcium"), treats = { "hyperkalemia", "poison_betablocker" },
        dosing = opts("ml", { { 10 }, { 30, true } }, 10, 1), duration = 900 },
    bicarbonate = { name = "Nátrium-bikarbonát 8,4%", class = D("c_electrolyte"), desc = D("d_bicarbonate"), treats = { "poison_tca" },
        dosing = opts("ml", { { 50 }, { 100, true } }, 50, 1), duration = 900 },
    acetylcysteine = { name = "N-acetilcisztein", class = D("c_antidote"), desc = D("d_acetylcysteine"), treats = { "poison_paracetamol" }, duration = 3600 },
    pralidoxime = { name = "Pralidoxim", class = D("c_antidote"), desc = D("d_pralidoxime"), treats = { "poison_organophosphate" }, duration = 3600 },
    glucagon = { name = "Glukagon", class = D("c_antidote"), desc = D("d_glucagon"), heartRate = 15, treats = { "poison_betablocker" }, duration = 1200 },
    fomepizole = { name = "Fomepizol", class = D("c_antidote"), desc = D("d_fomepizole"), treats = { "poison_methanol" }, duration = 3600 },
    digifab = { name = "Digoxin-ellenanyag (Fab)", class = D("c_antidote"), desc = D("d_digifab"), treats = { "poison_digoxin" }, duration = 3600 },
    hydroxocobalamin = { name = "Hidroxokobalamin (Cyanokit)", class = D("c_antidote"), desc = D("d_hydroxocobalamin"), treats = { "poison_cyanide" }, duration = 3600 },
    charcoal = { name = "Aktív szén 50 g", class = D("c_decontamination"), desc = D("d_charcoal"), route = "oral", duration = 3600 },
}
for id, d in pairs(DRUGS) do
    d.hospital = true
    MEDIC_DRUGS[id] = d
end
-- the prehospital drugs that treat the new conditions too
local function addTreat(drug, cond)
    local d = MEDIC_DRUGS[drug]
    if not d then return end
    d.treats = d.treats or {}
    for _, c in ipairs(d.treats) do if c == cond then return end end
    d.treats[#d.treats + 1] = cond
end
addTreat("epinephrine", "anaphylaxis")
addTreat("insulin", "dka")
addTreat("insulin", "hyperkalemia")
end)
