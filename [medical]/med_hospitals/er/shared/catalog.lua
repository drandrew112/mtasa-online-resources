-- ER catalogue (shared): orders, hidden findings, imaging library, surgeries, outcomes, BNO subset.
-- Texts are v_locals keys (med_hospitals.erc.*). Images live in er/img/<kind>/<file>.jpg and are
-- downloaded by the staff clients on demand (download="false" in meta.xml).

ERC = {}

-- clinical time: 1 game hour = 10 real minutes (S2 transfer: 3 h = 30 min)
ERC.CLINICAL_SCALE = 6

ERC.CASE_BONUS = 0.15   -- the treating doctor's bonus: 15 % of the closed, documented case's points

-- every intervention pays POINT_MULT times its code table points to the staff (2026-11-06: x5). The
-- state's care value (er/server/pay.lua) stays on the base points; the documents show the paid points.
ERC.POINT_MULT = 5

ERC.TIMES = {
    lab = 120,          -- s until the lab result arrives
    ct = 10,            -- s of scanning (one patient at a time)
    xray = 6,
    fast = 15,
    ecg = 8,
    ward = 1200,        -- s on the ward before the case closes
    icu = 1800,
    transferS1 = 180,   -- s before an automatic transfer when no suitable unit is logged in
    transferS2 = 600,
    morgueNpc = 1200,   -- s before the NPC morgue staff takes an abandoned body
}

-- Orders: kind -> list of { id, code, points, label, region? }
ERC.ORDERS = {
    lab = {
        { id = "full",       code = "HK-L16", points = 8 },   -- every panel at once (teljes labor)
        { id = "basic",      code = "HK-L02", points = 3 },
        { id = "trauma",     code = "HK-L03", points = 4 },
        { id = "cardiac",    code = "HK-L04", points = 4 },
        { id = "coag",       code = "HK-L05", points = 3 },
        { id = "abg",        code = "HK-L06", points = 5 },
        { id = "tox",        code = "HK-L07", points = 4 },
        { id = "group",      code = "HK-L08", points = 3 },
        { id = "crossmatch", code = "HK-L09", points = 3 },
        { id = "inflam",     code = "HK-L12", points = 3 },
    },
    -- X-ray by body part; sided parts need the side when ordered (a wrong side = negative + not indicated)
    xray = {
        { id = "chest",   code = "HK-K01", points = 5 },
        { id = "humerus", code = "HK-K02", points = 4, sided = true },
        { id = "elbow",   code = "HK-K02", points = 4, sided = true },
        { id = "forearm", code = "HK-K02", points = 4, sided = true },
        { id = "hand",    code = "HK-K02", points = 4, sided = true },
        { id = "pelvis",  code = "HK-K04", points = 5 },
        { id = "femur",   code = "HK-K03", points = 4, sided = true },
        { id = "knee",    code = "HK-K03", points = 4, sided = true },
        { id = "tibia",   code = "HK-K03", points = 4, sided = true },
        { id = "ankle",   code = "HK-K03", points = 4, sided = true },
        { id = "foot",    code = "HK-K03", points = 4, sided = true },
        { id = "spine_c", code = "HK-K05", points = 5 },
        { id = "spine_t", code = "HK-K05", points = 5 },
        { id = "spine_l", code = "HK-K05", points = 5 },
    },
    ct = {
        { id = "head",    code = "HK-K10", points = 8 },
        { id = "chest",   code = "HK-K12", points = 8 },
        { id = "abdomen", code = "HK-K13", points = 9 },
        { id = "spine",   code = "HK-K11", points = 7 },
        { id = "trauma",  code = "HK-K15", points = 14 },
    },
    fast = { { id = "fast", code = "HK-K20", points = 8 } },
    ecg = { { id = "ecg12", code = "HK-E01", points = 5 } },
}

-- where an order is performed (room of the patient's stretcher); nil = anywhere.
-- The 12-lead ECG machine stands in the shock room (the EMS Lifepak has its own, med_erm / medsys).
ERC.ORDER_ROOM = { ct = "ct", xray = "xray", fast = "shock", ecg = "shock" }

-- the region an order looks at -> the finding regions it shows
ERC.LOOKS_AT = {
    ["ct.head"] = { head = true }, ["ct.chest"] = { chest = true }, ["ct.abdomen"] = { abdomen = true, pelvis = true },
    ["ct.spine"] = { spine = true }, ["ct.trauma"] = { head = true, chest = true, abdomen = true, spine = true, pelvis = true },
    ["fast.fast"] = { abdomen = true, chest = true },
}

-- Hidden findings: what imaging / lab shows and what the patient needs.
--   region, bno, ct / xray / fast = image file (without extension) shown when the region is examined
--   surgery = ERC.SURGERIES id that ends it, cast / suture = treated in the cast / wound room
-- xr = { part, img, sided, cast }: the X-ray part that shows it, the image (er/img/xr/xr_<img>[_<side>].jpg),
--   whether the image has a left / right version, the control image once it is in a cast
-- ct = image (er/img/ct/<img>[_r].jpg; ERC.CT_SIDED images have a mirrored right variant)
ERC.FINDINGS = {
    concussion   = { region = "head", bno = "S0600", ct = "head_normal" },
    edh          = { region = "head", bno = "S0640", ct = "head_edh", surgery = "craniotomy", critical = true },
    sdh          = { region = "head", bno = "S0650", ct = "head_sdh", surgery = "craniotomy" },
    sah          = { region = "head", bno = "S0660", ct = "head_sah" },
    brain_contusion = { region = "head", bno = "S0630", ct = "head_contusion" },
    skull_fx     = { region = "head", bno = "S0200", ct = "head_fracture" },
    face_fx      = { region = "head", bno = "S0220", ct = "head_fracture" },
    ich          = { region = "head", bno = "I6100", ct = "head_ich" },
    stroke_isch  = { region = "head", bno = "I6340", ct = "head_normal", lysis = true },
    htx          = { region = "chest", bno = "S2710", ct = "chest_htx_med", xr = { part = "chest", img = "chest_htx", sided = true }, drain = true },
    ptx          = { region = "chest", bno = "S2700", ct = "chest_ptx_lung", xr = { part = "chest", img = "chest_ptx", sided = true }, drain = true },
    lung_contusion = { region = "chest", bno = "S2730", ct = "chest_contusion_lung", xr = { part = "chest", img = "chest_contusion", sided = true } },
    rib_fx       = { region = "chest", bno = "S2240", ct = "chest_ribfx_bone", xr = { part = "chest", img = "chest_ribfx", sided = true } },
    rib_fx_single = { region = "chest", bno = "S2230", ct = "chest_ribfx_bone", xr = { part = "chest", img = "chest_ribfx", sided = true } },
    spleen       = { region = "abdomen", bno = "S3600", ct = "abd_spleen", surgery = "splenectomy", critical = true },
    liver        = { region = "abdomen", bno = "S3610", ct = "abd_liver", surgery = "liver", critical = true },
    gsw_abdomen  = { region = "abdomen", bno = "S3110", ct = "abd_normal", surgery = "laparotomy", critical = true },
    cspine_fx    = { region = "spine", bno = "S1290", ct = "spine_compression", xr = { part = "spine_c", img = "spine_c_fx" } },
    tspine_fx    = { region = "spine", bno = "S2200", ct = "spine_compression", xr = { part = "spine_t", img = "spine_t_fx" } },
    lumbar_fx    = { region = "spine", bno = "S3200", ct = "spine_compression", xr = { part = "spine_l", img = "spine_l_fx" } },
    pelvis_fx    = { region = "pelvis", bno = "S3270", xr = { part = "pelvis", img = "pelvis_fx" }, surgery = "pelvis_exfix", binder = true },
    femneck_fx   = { region = "pelvis", bno = "S7200", xr = { part = "pelvis", img = "pelvis_neckfx", sided = true }, surgery = "orif" },
    femur_fx     = { region = "leg", bno = "S7230", xr = { part = "femur", img = "femur_fx", sided = true }, surgery = "orif" },
    tibia_fx     = { region = "leg", bno = "S8220", xr = { part = "tibia", img = "tibia_fx", sided = true, cast = "tibia_cast" }, cast = true, reduction = true },
    ankle_fx     = { region = "leg", bno = "S8260", xr = { part = "ankle", img = "ankle_fx", sided = true }, cast = true },
    radius_fx    = { region = "arm", bno = "S5250", xr = { part = "forearm", img = "forearm_colles", sided = true, cast = "forearm_cast" }, cast = true, reduction = true },
    humerus_fx   = { region = "arm", bno = "S4230", xr = { part = "humerus", img = "humerus_fx", sided = true }, cast = true },
    wound_arm    = { region = "arm", bno = "S5180", suture = true },
    wound_leg    = { region = "leg", bno = "S8180", suture = true },
    wound_torso  = { region = "chest", bno = "S2110", suture = true },
    wound_head   = { region = "head", bno = "S0100", suture = true },
    wound_neck   = { region = "head", bno = "S1180", suture = true },
    burn         = { region = "skin", bno = "T3100" },
    burn_major   = { region = "skin", bno = "T3120", icu = true },
    opioid       = { region = "tox", bno = "T4010", tox = "opioid" },
    sedative     = { region = "tox", bno = "T4240", tox = "benzodiazepine" },
    stimulant    = { region = "tox", bno = "T4360", tox = "amphetamine" },
    alcohol      = { region = "tox", bno = "F1000", tox = "ethanol" },
    asthma       = { region = "chest", bno = "J4590" },
    copd         = { region = "chest", bno = "J4410" },
    pulm_edema   = { region = "chest", bno = "J81H0", xr = { part = "chest", img = "chest_edema" } },
    asphyxia     = { region = "chest", bno = "T71H0" },
}
ERC.CT_SIDED = { head_edh = true, head_sdh = true, head_contusion = true, head_ich = true, head_fracture = true,
    chest_ptx_lung = true, chest_htx_med = true, chest_contusion_lung = true, chest_ribfx_bone = true }

-- the X-ray image of a part without a finding
function ERC.xrayNormal(part, side)
    if part == "chest" or part == "pelvis" or part:find("^spine_") then return part .. "_normal" end
    return part .. "_normal_" .. (side == "right" and "right" or "left")
end

-- default image of an examined region without a finding (normal study)
ERC.NORMAL = {
    ["ct.head"] = "head_normal", ["ct.chest"] = "chest_normal_lung", ["ct.abdomen"] = "abd_normal", ["ct.spine"] = "spine_normal",
    ["ct.trauma"] = "head_normal", ["fast.fast"] = "ruq_neg",
}
-- image folder + file prefix per kind
ERC.IMAGE_PATH = { ct = "er/img/ct/%s.jpg", xray = "er/img/xr/xr_%s.jpg", fast = "er/img/us/us_%s.jpg", ecg = "er/img/ecg/ecg_%s.jpg" }
ERC.XRAY_CONTROL_CODE = "HK-K06"   -- control film of a cast

-- Surgeries (NPC surgeon, er/server/outcome.lua). time = s in the OR
ERC.SURGERIES = {   -- the 13 operations of the plan (time = s in the OR, 1 plan minute = 60 s)
    splenectomy    = { code = "HK-O10", points = 30, time = 360 },
    laparotomy     = { code = "HK-O11", points = 32, time = 420 },
    liver          = { code = "HK-O12", points = 36, time = 480 },
    appendectomy   = { code = "HK-O13", points = 24, time = 300 },
    craniotomy     = { code = "HK-O14", points = 40, time = 540, priority = true },
    thoracotomy    = { code = "HK-O15", points = 40, time = 600 },
    orif           = { code = "HK-O16", points = 30, time = 480 },
    pelvis_exfix   = { code = "HK-O17", points = 26, time = 360 },
    vascular       = { code = "HK-O18", points = 32, time = 420 },
    pci            = { code = "HK-O19", points = 30, time = 360, priority = true },
    thrombectomy   = { code = "HK-O20", points = 32, time = 420, priority = true },
    debridement    = { code = "HK-O21", points = 18, time = 240 },
    pericardiotomy = { code = "HK-O22", points = 20, time = 180, priority = true },
}

-- Outcomes: code, points, needed er.* activity
ERC.OUTCOMES = {
    discharge = { code = "HK-A10", points = 3, need = "er.discharge" },
    ward      = { code = "HK-A06", points = 5, need = "er.admit" },
    icu       = { code = "HK-A07", points = 8, need = "er.icu" },
    surgery   = { code = "HK-O01", points = 6, need = "er.surgery" },
    transfer_s1 = { code = "HK-A08", points = 6, need = "er.transfer_s1" },
    transfer_s2 = { code = "HK-A09", points = 4, need = "er.transfer_s2" },
    death     = { code = "HK-A11", points = 4, need = "er.death" },
}
ERC.WARD_DEPARTMENTS = { "surgery", "trauma", "internal", "neurology", "cardiology" }

-- BNO subset offered until the full BNO database (med_docs/bno) is built: the Hungarian names are
-- the exact BNOTORZS.DBF texts, the English ones are the WHO ICD-10 titles.
ERC.BNO = {
    S0600 = { "Agyrázkódás", "Concussion" },
    S0640 = { "Epiduralis vérzés", "Epidural haemorrhage" },
    S0650 = { "Traumás subduralis vérzés", "Traumatic subdural haemorrhage" },
    S0660 = { "Traumás subarachnoidealis vérzés", "Traumatic subarachnoid haemorrhage" },
    S0630 = { "Lokalizált agysérülés", "Focal brain injury" },
    S0200 = { "A koponyaboltozat törése", "Fracture of vault of skull" },
    S0100 = { "A fejbőr nyílt sebe", "Open wound of scalp" },
    I6100 = { "Agyállományi vérzés féltekében, subcorticalis", "Intracerebral haemorrhage in hemisphere, subcortical" },
    I6340 = { "Agyi infarctus a cerebralis ütőerek emboliája miatt", "Cerebral infarction due to embolism of cerebral arteries" },
    S2710 = { "Traumás haemothorax", "Traumatic haemothorax" },
    S2700 = { "Traumás pneumothorax", "Traumatic pneumothorax" },
    S2730 = { "A tüdő egyéb sérülése", "Other injuries of lung" },
    S2230 = { "Bordatörés", "Fracture of rib" },
    S2240 = { "Többszörös bordatörés", "Multiple fractures of ribs" },
    S2120 = { "A mellkas hátulsó falának nyílt sebe", "Open wound of back wall of thorax" },
    S3600 = { "A lép sérülése", "Injury of spleen" },
    S3610 = { "A máj vagy epehólyag sérülése", "Injury of liver or gallbladder" },
    S3100 = { "A hát alsó részének és medencének nyílt sebe", "Open wound of lower back and pelvis" },
    S3200 = { "Az ágyéki csigolya törése", "Fracture of lumbar vertebra" },
    S8220 = { "A sípcsont (tibia) testének törése", "Fracture of shaft of tibia" },
    S8260 = { "A külboka törése", "Fracture of lateral malleolus" },
    S8180 = { "A lábszár egyéb részeinek nyílt sebe", "Open wound of other parts of lower leg" },
    S7200 = { "A combnyak törése", "Fracture of neck of femur" },
    S5250 = { "Az orsócsont (radius) distalis végének törése", "Fracture of lower end of radius" },
    S5180 = { "Az alkar egyéb részeinek nyílt sebe", "Open wound of other parts of forearm" },
    S4230 = { "A humerus középső részének törése", "Fracture of shaft of humerus" },
    S9340 = { "A boka rándulása és húzódása", "Sprain and strain of ankle" },
    T1400 = { "Nem meghatározott testtájék felületes sérülése", "Superficial injury of unspecified body region" },
    T3100 = { "A testfelület kevesebb, mint 10%-át érintő égés", "Burns involving less than 10% of body surface" },
    T3120 = { "A testfelület 20-29%-át érintő égés", "Burns involving 20-29% of body surface" },
    T4010 = { "Heroin által okozott mérgezés", "Poisoning by heroin" },
    T4040 = { "Egyéb syntheticus narcoticumok által okozott mérgezés", "Poisoning by other synthetic narcotics" },
    T4240 = { "Benzodiazepinek által okozott mérgezés", "Poisoning by benzodiazepines" },
    T4050 = { "Cocain által okozott mérgezés", "Poisoning by cocaine" },
    T4360 = { "Psychostimulánsok, abusus lehetőségével által okozott mérgezés", "Poisoning by psychostimulants with abuse potential" },
    F1000 = { "Alkohol okozta akut intoxikáció", "Mental and behavioural disorders due to use of alcohol: acute intoxication" },
    J4590 = { "Asthma, k.m.n.", "Asthma, unspecified" },
    J46H0 = { "Status asthmaticus", "Status asthmaticus" },
    J4410 = { "Idült obstructiv tüdőbetegség heveny fellángolással, k.m.n.", "Chronic obstructive pulmonary disease with acute exacerbation, unspecified" },
    J81H0 = { "Tüdővizenyő", "Pulmonary oedema" },
    T71H0 = { "Megfulladás", "Asphyxiation" },
    I2100 = { "Heveny elülső fali transmuralis szívizomelhalás", "Acute transmural myocardial infarction of anterior wall" },
    I2110 = { "Heveny alsó fali transmuralis szívizomelhalás", "Acute transmural myocardial infarction of inferior wall" },
    I2140 = { "Heveny subendocardialis szívizomelhalás", "Acute subendocardial myocardial infarction" },
    I48H0 = { "Pitvari fibrillatio és flutter", "Atrial fibrillation and flutter" },
    I4900 = { "Kamra fibrillatio és flutter", "Ventricular fibrillation and flutter" },
    I4690 = { "Szívmegállás, k.m.n.", "Cardiac arrest, unspecified" },
    R5710 = { "Hypovolaemiás shock", "Hypovolaemic shock" },
    R4020 = { "Coma, k.m.n.", "Coma, unspecified" },
    R0740 = { "Mellkasi fájdalom, k.m.n.", "Chest pain, unspecified" },
    E1620 = { "Hypoglycaemia, k.m.n.", "Hypoglycaemia, unspecified" },
    R9600 = { "Hirtelen halál", "Instantaneous death" },
}

-- the name of a BNO code in a language ("hu" | "en")
function ERC.bnoName(code, lang)
    local b = ERC.BNO[code]
    if not b then return code end
    return lang == "hu" and b[1] or b[2]
end

-- every order definition by "kind.id"
ERC.ORDER_BY_KEY = {}
for kind, list in pairs(ERC.ORDERS) do
    for _, o in ipairs(list) do
        o.kind = kind
        o.key = kind .. "." .. o.id
        ERC.ORDER_BY_KEY[o.key] = o
    end
end
