if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- work_hospital - shared configuration. The hospital itself (ER rooms, patients, stretchers)
-- lives in med_hospitals (er/ module); this resource is the work: duty, ranks, exams, pay.

HOSPW = {
    WORK_ID = "hospital",
    NAME = L.text("work_hospital.config.name"),
    DESCRIPTION = L.text("work_hospital.config.description"),
    COLOR = { 70, 150, 220 },

    -- 70 = white coat (until the own doctor / nurse skins arrive through v_modloader)
    SKINS = {
        { model = 70, name = L.text("work_hospital.config.skin_doctor") },
        { model = 274, name = L.text("work_hospital.config.skin_nurse_male") },
        { model = 275, name = L.text("work_hospital.config.skin_nurse_female") },
    },

    MAX_LEVEL = 10,
    LEVEL_XP = 500,
    LEVEL_STEP = 250,
    XP_PER_POINT = 3,                  -- work XP for every intervention point

    -- Duty markers (ground level) and the hospital (med_hospitals id) the staff member works in
    STATIONS = {
        { hospital = "ls_allsaints", duty = { 1153.84, -1307.44, 14.38 }, blip = false },
    },
    -- the exam centre is the same place as the EMS one: each marker is visible only to its own work
    EXAM_MARKERS = {
        { 1152.37, -1316.61, 14.38 },
    },

    -- Pay: every intervention (med_hospitals er/ codes) gives points; at duty end (or on quit) the
    -- points are paid through work_core payWork (the work's /gov payer = the state account chosen by
    -- the government), one receipt line per intervention code.
    POINT_VALUE = 40,                  -- $ per point
    PAY_FACTOR = 0.5,                  -- scales the $ value of a point (also the gov_health salary value)
    MAX_RECEIPT_LINES = 12,           -- the rest is summed into one "Other" line

    -- Competencies (work_core registerCompetencies). Ápoló (nurse) is the base rank; Rezidens and
    -- Orvos need an exam; Főorvos only by appointment (/appoint, admin 3+, from Orvos).
    COMPETENCY = {
        ranks = {
            { id = "nurse", name = L.text("work_hospital.comp.nurse"), short = "N" },   -- given at the end of the hospital tutorial
            { id = "resident", name = L.text("work_hospital.comp.resident"), short = "R", exam = "resident", requires = { "nurse" } },
            { id = "physician", name = L.text("work_hospital.comp.physician"), short = "D", exam = "physician", requires = { "resident" } },
            { id = "chief", name = L.text("work_hospital.comp.chief"), short = "M", appoint = { adminLevel = 3, requires = { "physician" } } },
        },
        certs = {},
        -- activity -> the rank needed (anything not listed is allowed for everyone on duty).
        -- er.* keys are checked by med_hospitals, the others are medsys keys (setMedicPermissions).
        activities = {
            ["er.treat"] = "resident", ["er.order"] = "resident", ["er.diagnose"] = "resident",
            ["er.discharge"] = "resident", ["er.admit"] = "resident", ["er.transfer_s2"] = "resident",
            ["er.suture"] = "resident", ["er.reduction"] = "resident", ["er.fast"] = "resident",
            ["er.icu"] = "physician", ["er.surgery"] = "physician", ["er.surgery_request"] = "resident", ["er.death"] = "physician",
            ["er.transfer_s1"] = "physician", ["er.drain"] = "physician", ["er.lysis"] = "physician",
            ["er.mtp"] = "physician", ["er.chief"] = "chief",
            ["drug.captopril"] = "resident", ["drug.nitroglycerin"] = "resident", ["drug.salbutamol"] = "resident",
            ["drug.glucose"] = "resident", ["drug.glucose_gel"] = "resident", ["drug.naloxone"] = "resident",
            ["drug.insulin"] = "resident", ["drug.midazolam"] = "resident", ["drug.fentanyl"] = "resident",
            ["drug.epinephrine"] = "resident", ["drug.adenosine"] = "resident",
            ["drug.ketamine"] = "physician", ["drug.rocuronium"] = "physician", ["action.airway"] = "physician",
            -- hospital medicines (medsys/shared/conditions.lua); a nurse gives them only when ordered
            ["drug.amiodarone"] = "resident", ["drug.atropine"] = "resident", ["drug.morphine"] = "resident",
            ["drug.metamizole"] = "resident", ["drug.ondansetron"] = "resident", ["drug.lidocaine"] = "resident",
            ["drug.txa"] = "resident", ["drug.aspirin"] = "resident", ["drug.clopidogrel"] = "resident", ["drug.heparin"] = "resident",
            ["drug.ceftriaxone"] = "resident", ["drug.tetanus"] = "resident", ["drug.calcium"] = "resident", ["drug.bicarbonate"] = "resident",
            ["drug.acetylcysteine"] = "resident", ["drug.glucagon"] = "resident", ["drug.charcoal"] = "resident", ["drug.flumazenil"] = "resident",
            ["drug.noradrenaline"] = "physician", ["drug.propofol"] = "physician", ["drug.alteplase"] = "physician",
            ["drug.pralidoxime"] = "physician", ["drug.fomepizole"] = "physician", ["drug.digifab"] = "physician", ["drug.hydroxocobalamin"] = "physician",
            ["defib.charge"] = "physician", ["defib.sync"] = "physician", ["dose.high"] = "physician",
        },
        exams = { passPercent = 75, retryCooldown = 300, help = "hospital_exams", order = { "resident", "physician" }, check = "checkHospitalExam" },
        -- Ú11: besides the knowledge: Rezidens = 2 h on duty as Ápoló; Orvos = 4 h as Rezidens + 20 closed cases as the treating doctor
        examRequirements = {
            resident = { rank = "nurse", hours = 1 },
            physician = { rank = "resident", hours = 2, cases = 20 },
        },
        examFiles = { "resident", "physician" },
        -- Minigames tab (practice): client export start<X>Game(ped = nil, options)
        minigames = {
            { name = "work_hospital.minigames.suture", desc = "work_hospital.minigames.suture_desc", resource = "mg_suture", fn = "startSutureGame", args = { nil, {} }, argc = 2 },
            { name = "work_hospital.minigames.irrigation", desc = "work_hospital.minigames.irrigation_desc", resource = "mg_irrigation", fn = "startIrrigationGame", args = { nil, {} }, argc = 2 },
            { name = "work_hospital.minigames.reduction", desc = "work_hospital.minigames.reduction_desc", resource = "mg_reduction", fn = "startReductionGame", args = { nil, {} }, argc = 2 },
            { name = "work_hospital.minigames.cast", desc = "work_hospital.minigames.cast_desc", resource = "mg_cast", fn = "startCastGame", args = { nil, {} }, argc = 2 },
            { name = "work_hospital.minigames.blooddraw", desc = "work_hospital.minigames.blooddraw_desc", resource = "mg_blooddraw", fn = "startBloodDrawGame", args = { nil, {} }, argc = 2 },
            { name = "work_hospital.minigames.fast", desc = "work_hospital.minigames.fast_desc", resource = "mg_fast", fn = "startFastGame", args = { nil, { efast = true, positives = { ruq = true } } }, argc = 2 },
            { name = "work_hospital.minigames.chestdrain", desc = "work_hospital.minigames.chestdrain_desc", resource = "mg_chestdrain", fn = "startChestDrainGame", args = { nil, {} }, argc = 2 },
            { name = "work_hospital.minigames.ecg", desc = "work_hospital.minigames.ecg_desc", resource = "mg_ecg", fn = "startEcgGame", args = { nil, {} }, argc = 2 },
        },
        examLanguages = { "hu", "en" },
        nametag = true,
    },
}
end)
