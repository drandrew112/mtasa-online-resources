if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- work_ems - shared configuration.
-- Positions are placeholders around All Saints: fine-tune them with work_core's /workpos
-- (on foot: marker point, in a vehicle: spawn point { x, y, z, rot }).

EMS = {
    WORK_ID = "ems",
    NAME = "EMS",
    DESCRIPTION = L.text("work_ems.config.emergency_medical_services"),
    COLOR = { 220, 50, 50 },

    -- Outfits (276/272/273 = OMSZ uniforms, replaced by v_modloader)
    SKINS = {
        { model = 276, name = L.text("work_ems.config.paramedic_omsz_1") },
        { model = 272, name = L.text("work_ems.config.paramedic_omsz_2") },
        { model = 273, name = L.text("work_ems.config.paramedic_omsz_coat") },
        { model = 274, name = L.text("work_ems.config.male_paramedic") },
        { model = 275, name = L.text("work_ems.config.female_paramedic") },
    },

    -- Work levels (work_core). XP is earned per treated patient (completed hospital handover).
    -- The level has no names: what a medic may do is the competency (COMPETENCY below), not the level.
    MAX_LEVEL = 10,
    LEVEL_XP = 500,                    -- XP for level 2
    LEVEL_STEP = 250,                  -- added for every further level
    XP_PER_PATIENT = 100,              -- every crew member, completed ERM task handover
    XP_HANDOVER = 60,                  -- the medic who hands a patient over at a hospital
    XP_TRANSPORT = { alive = 40, dead = 15 }, -- requested transport that actually left (by patient state)
    -- medsys interventions: XP for a successful one, once per patient (and per drug for medication)
    -- so repeating a button on the same patient cannot be farmed
    XP_TREATMENT = {
        bandage = 8, splint = 12, cpr = 20, iv = 12, airway = 25,
        oxygen = 6, medication = 10, neuro = 6, glucometer = 4, monitor = 4,
    },

    -- Vehicles offered at the duty vehicle markers. Plates: PLATE_PREFIX + PLATE_DIGITS random digits.
    -- level = work level needed to request the vehicle.
    -- equipment = med_equipments level of the vehicle when it is handed out (default EQUIPMENT_DEFAULT):
    -- "basic" = only the stretcher. The bag + Lifepak come at the ERM sign-in by the unit type
    -- (med_erm Config.UNIT_EQUIPMENT: BLS / SOLO -> "bls", ALS / DOC / HELI -> "als").
    -- Only these vehicles carry EMS equipment, other ambulances none.
    EQUIPMENT_DATA = "med.equipment",  -- vehicle element data read by med_equipments (shared/equipment.lua)
    EQUIPMENT_DEFAULT = "basic",
    PLATE_PREFIX = "A-",
    PLATE_DIGITS = 4,
    VEHICLES = {
        { model = 416, name = L.text("work_ems.config.mercedes_sprinter_omsz"), paintjob = "hu_omsz", sirenType = "fsvas320",
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60 } },
        { model = 416, name = L.text("work_ems.config.mercedes_sprinter_omsz_white"), paintjob = "hu_omsz_white", sirenType = "fsvas320",
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60 } },
        { model = 416, name = L.text("work_ems.config.mercedes_sprinter_omsz_old"), paintjob = "hu_omsz_old", sirenType = "premier_hazard_7109",
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60 } },
        { model = 483, name = L.text("work_ems.config.mercedes_sprinter_2018_omsz"),
          tuning = { engine = 3, turbo = 3, brakes = 3, wheels = "verywide", steeringLock = 60, driveType = "awd" } },
        { model = 582, name = L.text("work_ems.config.toyota_hiace_omsz"),
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60 } },
        { model = 456, name = L.text("work_ems.config.mission_row_ambulance"),
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60 } },
        { model = 598, name = L.text("work_ems.config.skoda_octavia_omsz"), paintjob = "hu_omsz", elsExtra = 1, sirenType = "soundoff",
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60, driveType = "awd" } },
        { model = 598, name = L.text("work_ems.config.skoda_octavia_omsz_white"), paintjob = "hu_omsz_white", elsExtra = 1, sirenType = "soundoff",
          tuning = { engine = 2, turbo = 2, brakes = 2, wheels = "verywide", steeringLock = 60, driveType = "awd" } },
        { model = 487, name = L.text("work_ems.config.air_ambulance"), level = 3 },
    },

    -- Competencies (work_core registerCompetencies; README.md "Competencies"). Independent of the work
    -- level: only exams (B+ automatically from B + the drug exam) and the chief physician appointment
    -- (/appoint, admin 3+, only for a physician) give them. badge = image on the tablet and the exam panel;
    -- the nametag uses v_nametags img/ranks/ems/<order>.png.
    COMPETENCY = {
        ranks = {
            { id = "t", name = L.text("work_ems.comp.t"), short = "T", base = true, badge = ":work_ems/img/badges/t.png" },
            { id = "a", name = L.text("work_ems.comp.a"), short = "A", exam = "a", requires = { "t" }, badge = ":work_ems/img/badges/a.png" },
            { id = "b", name = L.text("work_ems.comp.b"), short = "B", exam = "b", requires = { "a" }, badge = ":work_ems/img/badges/b.png" },
            { id = "bplus", name = L.text("work_ems.comp.bplus"), short = "B+", auto = { "b", "drug" }, badge = ":work_ems/img/badges/bplus.png", nametagCerts = { "rsi" } },
            { id = "c", name = L.text("work_ems.comp.c"), short = "C", exam = "c", requires = { "bplus", "rsi" }, badge = ":work_ems/img/badges/c.png" },
            { id = "d", name = L.text("work_ems.comp.d"), short = "D", exam = "d", requires = { "c" }, badge = ":work_ems/img/badges/d.png" },
            { id = "e", name = L.text("work_ems.comp.e"), short = "E", appoint = { adminLevel = 3, requires = { "d" } }, badge = ":work_ems/img/badges/e.png" },
        },
        certs = {
            { id = "drug", name = L.text("work_ems.comp.drug"), short = "Rx", exam = "drug", requires = { "b" }, exactRank = "b" },
            { id = "rsi", name = L.text("work_ems.comp.rsi"), short = "RSI", exam = "rsi", requires = { "bplus" } },
        },
        -- medsys keys (setMedicPermissions) -> the competency needed; anything not listed is allowed
        -- (examination, CPR, bandage, transport, the Lifepak sound button)
        activities = {
            ["action.oxygen"] = "a", ["action.splint"] = "a", ["action.neuro"] = "a", ["action.glucometer"] = "a",
            ["action.monitor"] = "a",
            ["defib.analyze"] = "b", ["defib.shock"] = "b",            -- AED mode: ANALYZE charges by itself
            ["defib.charge"] = "c", ["defib.sync"] = "c",              -- manual charge, cardioversion
            ["action.iv"] = "b", ["action.infusion"] = "b",
            ["infusion.pressure"] = "bplus",                           -- the pressure bag drip rate
            ["drug.captopril"] = "b", ["drug.nitroglycerin"] = "b", ["drug.salbutamol"] = "b",
            ["drug.glucose"] = "b", ["drug.glucose_gel"] = "b", ["drug.naloxone"] = "b",
            ["drug.insulin"] = "bplus", ["drug.midazolam"] = "bplus", ["drug.fentanyl"] = "bplus", ["drug.epinephrine"] = "bplus",
            ["drug.adenosine"] = "bplus",
            ["drug.ketamine"] = "rsi", ["drug.rocuronium"] = "rsi", ["action.airway"] = "rsi",
            ["dose.high"] = "d",                                       -- the orange (above usual) doses
        },
        exams = { passPercent = 75, retryCooldown = 300, help = "medical_exams", order = { "a", "b", "c", "d", "drug", "rsi" } },
        -- exam files: exams/<lang>/<id>.json (README.md "Exams"); images under exams/img/, listed in meta.xml
        examFiles = { "a", "b", "drug", "rsi", "c", "d" },
        examLanguages = { "hu", "en" },
        -- Minigames tab (practice, not needed for any exam): client export called with args
        minigames = {
            { name = "work_ems.minigames.cpr", desc = "work_ems.minigames.cpr_desc", resource = "mg_cpr", fn = "startCPRGame", args = { 30 }, argc = 1 },
            { name = "work_ems.minigames.iv", desc = "work_ems.minigames.iv_desc", resource = "mg_intravenous", fn = "startIVGame", args = {}, argc = 0 },
            { name = "work_ems.minigames.airway", desc = "work_ems.minigames.airway_desc", resource = "mg_airway", fn = "startAirwayGame", args = {}, argc = 0 },
            { name = "work_ems.minigames.splint", desc = "work_ems.minigames.splint_desc", resource = "mg_splinting", fn = "startSplintGame", args = { nil, 2 }, argc = 2 },
            { name = "work_ems.minigames.arrows", desc = "work_ems.minigames.arrows_desc", resource = "mg_arrows", fn = "startArrowsGame", args = { 8 }, argc = 1 },
        },
        nametag = true,
    },
    EXAM_MARKERS = {                              -- exam centres, ground level
        { 1182.61, -1334.37, 12.58 },             -- LS All Saints
        { 2014.44, -1433.86, 12.55 },             -- LS County General
        { 1603.63, 1817.20, 9.82 },               -- LV General
        { -2649.42, 638.66, 13.45 },              -- SF Medical Center
    },

    -- Stations: a duty marker and (optionally) a duty vehicle marker with spawn points.
    -- z = ground level for the markers.
    STATIONS = {
        {
            name = L.text("work_ems.config.ls_all_saints_general_hospital"),
            duty = { 1182.82, -1330.80, 12.58 },
            blip = false,
            vehicle = {
                marker = { 1184.0, -1323.6, 12.6 },
                spawns = {
                    { 1185.5, -1316.0, 13.6, 0 },
                    { 1185.5, -1331.0, 13.6, 180 },
                },
            },
        },
        {
            name = L.text("work_ems.config.ls_country_general_hospital"),
            duty = { 2011.27, -1436.85, 12.55 },
            blip = false,
            vehicle = {
                marker = { 2003.23, -1444.75, 12.56 },
                spawns = {
                    { 1993.78, -1445.92, 13.62, 180 },
                    { 2012.09, -1453.29, 13.60, 90 },
                    { 2002.36, -1453.56, 13.61, 90 },
                },
            },
        },
        {
            name = L.text("work_ems.config.lv_general_hospital"),
            duty = { 1600.46, 1817.23, 9.82 },
            blip = false,
            vehicle = {
                marker = { 1591.24, 1818.71, 9.82 },
                spawns = {
                    { 1589.76, 1849.82, 9.98, 180 },
                    { 1594.06, 1850.25, 9.98, 180 },
                    { 1597.83, 1850.19, 9.98, 180 },
                    { 1604.44, 1850.72, 9.98, 180 },
                    { 1610.51, 1851.14, 9.98, 180 }
                },
            },
        },
        {
            name = L.text("work_ems.config.sf_medical_center"),
            duty = { -2652.48511, 637.51929, 13.45312 },
            blip = false,
            vehicle = {
                marker = { -2646.46, 635.51, 13.45 },
                spawns = {
                    { -2633.04, 628.72, 13.61, 270 },
                    { -2619.99, 629.10, 13.61, 270 },
                    { -2704.61, 630.83, 13.61, 270 },
                    { -2704.89, 623.54, 13.61, 270 }
                }
            },
        }
    },
}
end)
