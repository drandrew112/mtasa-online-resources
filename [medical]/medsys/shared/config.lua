if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- Configuration and shared constants of the medical system.
-- Everything that tunes the physiology, the interaction or the treatments lives here.

MEDIC = {
    TICK = 1000,                -- ms between two simulation steps (one global timer for every patient)

    -- Element data. STATUS is broadcast (it only changes on state transitions),
    -- the vitals are written in "subscribe" mode so only the players examining / treating
    -- the patient receive them (mg_airway reads SPO2 / HEART_RATE from the patient).
    DATA_STATUS = "medic.status",
    DATA_ROLE = "medic.role",     -- true on players with the medic role (set by the server only)
    DATA_SPO2 = "spo2",
    DATA_HEART_RATE = "heartRate",
    DATA_NAME = "medic.name",     -- optional patient name on peds (set by e.g. med_scenemanager)

    -- Baseline (healthy) values
    BLOOD_VOLUME = 5000,        -- ml
    HEART_RATE = 72,            -- BPM
    SYSTOLIC = 120,             -- mmHg
    DIASTOLIC = 80,
    SPO2 = 98,                  -- %

    -- Blood loss per bleeding level in ml/s (0 = none, 1 = mild, 2 = severe, 3 = critical)
    BLEED_RATE = { [0] = 0, 1.5, 5, 12 },
    ARREST_BLEED_FACTOR = 0.2,  -- bleeding keeps going at this fraction without circulation

    -- Vitals move towards their physiological target with these speeds (per second)
    HR_RATE = 3,
    BP_RATE = 2,
    SPO2_RECOVERY = 0.4,

    -- Natural variation: the pressure / pulse targets wander randomly by up to this much
    -- (a new random offset every JITTER_TIME seconds on average; the diastolic follows the systolic)
    BP_JITTER = 4,              -- mmHg systolic
    HR_JITTER = 2,              -- BPM
    JITTER_TIME = 3,

    -- Cardiac arrest (clinical death) triggers
    ARREST_SPO2 = 0,            -- SpO2 at or below this -> pulse 0
    ARREST_BLOOD = 0.5,         -- blood volume fraction at or below this -> pulse 0
    ARREST_SYSTOLIC = 30,       -- systolic pressure (mmHg) at or below this -> pulse 0 (e.g. a drug overdose)
    ARREST_HEART_RATE = 200,    -- a pulse at or above this...
    ARREST_TACHY_TIME = 5,      -- ...for this many seconds -> the heart stops
    BARO_REFLEX = 0.7,          -- BPM added per mmHg the systolic pressure is below SYSTOLIC
    DEATH_TIME = 300,           -- seconds of clinical death before biological death

    -- Consciousness thresholds (checked from the worst down)
    UNCONSCIOUS_SPO2 = 70,
    UNCONSCIOUS_SYSTOLIC = 65,
    DAZED_SPO2 = 88,
    DAZED_SYSTOLIC = 90,
    DAZED_PAIN = 70,
    KNOCKOUT_TIME = 60,         -- seconds a forced "unconscious" / "dazed" state lasts

    -- A patient with nothing left to simulate is dropped from the registry (discharged)
    DISCHARGE_SPO2 = 96,

    -- Interaction (the "Examine patient" world menu comes from ui_interactobject)
    INTERACT_RANGE = 2.5,       -- metres: menu range and the range to start a procedure
    PANEL_RANGE = 4.0,          -- the panel closes beyond this
    REQUIRE_MEDIC_ROLE = true,  -- true: only players flagged with setPlayerMedic can examine / treat,
                                -- see the stretcher menus (med_stretcher) and the EMS tablet hint (med_erm)
                                -- (and use the stretcher; the EMS tablet hint shows to them only)

    -- Equipment (med_bag): interventions need the medical bag / the monitor near the patient
    -- (MEDIC_EQUIPMENT). While med_bag is not running no equipment is asked for at all.
    REQUIRE_EQUIPMENT = true,
    EQUIPMENT_RESOURCE = "med_bag",

    -- Treatments
    IV_FLUID_RATE = 4,          -- ml/s restored with IV access (scaled by the cannulation quality)
    CPR_DURATION = 30,          -- seconds of compressions per CPR round
    CPR_TIME_BONUS = 45,        -- a good CPR round buys this many seconds on the death timer
    ROSC_BASE = 0.35,           -- return of circulation chance for a good CPR round...
    ROSC_PER_PERCENT = 0.005,   -- ...plus this per accuracy percent above the pass limit
    ROSC_IV_BONUS = 0.10,
    ROSC_AIRWAY_BONUS = 0.10,
    ROSC_SPO2 = 55,             -- SpO2 right after return of circulation (at least)
    ROSC_HEART_RATE = 118,
    ROSC_SYSTOLIC = 78,
    -- Intubation: the patient is pre-oxygenated with a bag-valve mask, then the SpO2 falls
    -- during the apnoeic attempt (%/s per mg_airway difficulty)
    PREOX_SPO2 = 95,
    APNEA_RATE = { easy = 0.35, normal = 0.5, hard = 0.65, nightmare = 0.8 },
    -- Medication (needs IV access, no minigame): the medic kneels for this many seconds
    DRUG_TIME = 3,
    -- Oxygen mask (no minigame, put on / taken off in OXYGEN_TIME seconds). Weaker than the tube:
    -- the SpO2 targets of the airway problems and of shock are only lifted by OXYGEN_SPO2_BONUS,
    -- so a critical airway problem still needs intubation.
    OXYGEN_TIME = 3,
    OXYGEN_SPO2 = 100,          -- SpO2 target on the mask without any airway problem
    OXYGEN_SPO2_BONUS = 10,     -- added to the SpO2 target of the airway problems / shock
    OXYGEN_RECOVERY = 2,        -- the SpO2 recovers this many times faster
    OXYGEN_APNEA_FACTOR = 0.5,  -- a paralysed patient desaturates this much slower on the mask
    -- Rapid sequence intubation (RSI): the induction (sedation) first, then the muscle relaxant.
    PARALYSIS_ONSET = 15,       -- seconds until the muscle relaxant stops the breathing
    PARALYSIS_SPO2_RATE = 0.25, -- %/s the SpO2 falls without own breathing (until intubated)
    PANIC_HEART_RATE = 50,      -- an awake patient under the muscle relaxant panics: BPM...
    PANIC_SYSTOLIC = 35,        -- ...and mmHg added to the targets

    -- Transport requested from the panel (peds only): a dead body, or a living patient whose
    -- condition is stable. The vehicle appears at a free spot next to the patient (picked by the
    -- requesting medic's client), loads the patient and leaves.
    TRANSPORT_DELAY = 30,       -- seconds until the vehicle arrives
    TRANSPORT_LOAD_TIME = 5,    -- seconds the vehicle stands there before the patient disappears
    TRANSPORT_LEAVE_TIME = 3,   -- seconds after loading before the vehicle is removed
    TRANSPORT_VEHICLE = { dead = 442, alive = 416 }, -- Romero (hearse) / Ambulance
    TRANSPORT_DRIVER = { dead = 70, alive = 274 },   -- driver skin
    TRANSPORT_SPOT_RANGE = 15,  -- metres: the vehicle spot sent by the client must be this close to the body
    TRANSPORT_MIN_SYSTOLIC = 90,  -- a living patient is only transported with a systolic pressure
    TRANSPORT_MAX_SYSTOLIC = 180, -- in this range (stabilise it first: fluids / Captopril)

    -- Monitor / defibrillator (Lifepak 15). Attached once (timed procedure), it shows the ECG
    -- with the rhythm name, the SpO2 and the blood pressure (without it only the pulse, the
    -- bleeding and the skin are known), and it can shock the patient.
    MONITOR_TIME = 4,           -- seconds to put on the electrodes
    -- Sinus rhythm names by rate (Basic ECG: bradycardia < 60, tachycardia > 100)
    BRADY_RATE = 60,
    TACHY_RATE = 100,
    VT_HEART_RATE = 170,        -- a pulse at or above this is ventricular tachycardia (with pulse)
    -- Lasting VT with pulse (after a ROSC, a shock, setMedicalState "rhythm"): the heart beats at
    -- VT_RATE, the pressure drops, and without cardioversion it turns pulseless after VT_DEGRADE_TIME
    VT_RATE = 180,
    VT_SYSTOLIC_DROP = 30,
    VT_DEGRADE_TIME = 120,
    ROSC_VT_CHANCE = 0.15,      -- a restored heart beats in VT with pulse instead of a sinus rhythm
    -- Untreated arrest rhythms get worse (paused while CPR runs): seconds in the rhythm
    PVT_DEGRADE_TIME = 60,      -- pulseless VT -> VF
    VF_DEGRADE_TIME = 240,      -- VF -> asystole
    PEA_DEGRADE_TIME = 180,     -- PEA -> asystole
    -- CPR: after CPR_CHANGE_MIN seconds of good compressions the rhythm can change at any moment
    -- (on average every CPR_CHANGE_TIME seconds); a change stops the CPR minigame
    CPR_CHANGE_MIN = 10,
    CPR_CHANGE_TIME = 12,
    CPR_SHOCKABLE_ROSC = 0.25,  -- the ROSC chance of CPR is multiplied by this in VF / pulseless VT
    CPR_TO_SHOCKABLE = 0.5,     -- a change in PEA / asystole that is not a ROSC goes to VF this often
    -- Defibrillation
    DEFIB_ENERGY = 200,         -- joules (biphasic), fixed: the ENERGY SELECT buttons are inactive
    DEFIB_CHARGE_TIME = 4.73,   -- seconds to charge = the length of sounds/defib_charge.wav (the charge bar follows it)
    DEFIB_DISARM_TIME = 60,     -- a charge not delivered in this many seconds is dumped
    DEFIB_ANALYZE_TIME = 4,     -- seconds of the ANALYZE rhythm analysis (AED mode, charges when advised)
    SHOCK_SUCCESS = 0.5,        -- a shock ends VF / pulseless VT with this chance
    SHOCK_ROSC = 0.35,          -- after a successful shock the pulse returns with this chance (+ IV,
                                -- airway, adrenaline bonuses), otherwise PEA or asystole follows
    SHOCK_ROSC_PEA = 0.6,       -- share of PEA among the non-ROSC outcomes (the rest is asystole)
    CARDIOVERSION_SYNC = 0.75,  -- SYNC shock on VT with pulse: chance to convert it
    CARDIOVERSION_UNSYNC = 0.45,-- unsynchronised shock on VT with pulse: chance to convert it...
    SHOCK_PULSE_VF = 0.3,       -- ...or it causes VF this often (a shock on a sinus rhythm always stops the heart)
    SHOCK_PAIN = 60,            -- pain points of a shock on a patient who is not down

    -- Blood glucose (mg/dL; the glucometer also shows mmol/L). setMedicalState "glucose" sets the
    -- current and the resting value, the current one drifts back to the resting one.
    DATA_BREATH = "medic.breath", -- breathing key (MEDIC_BREATHING), broadcast for medsys_effects
    GLUCOSE = 95,               -- healthy resting value
    GLUCOSE_DRIFT = 0.08,       -- mg/dL per second towards the resting value
    GLUCOSE_MIN = 10, GLUCOSE_MAX = 900,
    GLUCOSE_WOBBLE = 1.5,       -- mg/dL: max size of the natural random fluctuation around the current value
    GLUCOSE_IV_RATE = 0.12,     -- mg/dL/s an IV line (fluids) lowers a value above GLUCOSE_IV_ABOVE
    GLUCOSE_IV_ABOVE = 180,
    HYPO_GLUCOSE = 70,          -- below: sweating, the pulse rises (HYPO_HEART_RATE per mg/dL, max 25)
    HYPO_HEART_RATE = 0.5,
    HYPO_ARREST_GLUCOSE = 20,   -- below this for HYPO_ARREST_TIME seconds -> cardiac arrest
    HYPO_ARREST_TIME = 240,
    HYPER_LOSS_ABOVE = 300,     -- above: osmotic fluid loss, HYPER_LOSS ml/s at +300 mg/dL
    HYPER_LOSS = 0.6,
    KUSSMAUL_GLUCOSE = 350,     -- above: deep, rapid breathing and acetone breath (ketoacidosis)
    -- consciousness by the glucose (the worst matching line counts)
    GLUCOSE_LOW_CONSCIOUSNESS = { { 30, "unconscious" }, { 45, "dazed" }, { 58, "confused" } },
    GLUCOSE_HIGH_CONSCIOUSNESS = { { 700, "unconscious" }, { 550, "dazed" }, { 420, "confused" } },
    GLUCOMETER_TIME = 5,        -- seconds from the finger prick to the reading
    GLUCOMETER_LOW = 20,        -- the meter shows "LO" below and "HI" above these
    GLUCOMETER_HIGH = 600,

    -- Neuro exam (D of ABCDE): timed, once done its findings stay on the panel (updated live)
    NEURO_TIME = 4,

    -- Stroke: an untreated stroke gets one severity worse after this many seconds; a systolic
    -- pressure outside STROKE_SAFE_SYSTOLIC (too low: less blood to the brain, too high: bleeding)
    -- makes it STROKE_BAD_BP_FACTOR times faster. Only the hospital treats it.
    STROKE_PROGRESS_TIME = 480,
    STROKE_SAFE_SYSTOLIC = { 130, 220 },
    STROKE_BAD_BP_FACTOR = 2.5,

    -- The patient animations and the player's own screen effects live in medsys_effects.
}

-- Heart rhythms (ECG). label = shown under the ECG curve (most players cannot read an ECG),
-- pulse = the heart pumps (palpable pulse), shockable = defibrillation can end it (VF, pVT only),
-- wave = the curve the client draws (client/ecg.lua)
MEDIC_RHYTHMS = {
    SINUS = { label = L.text("medsys.config.normal_sinus_rhythm"), pulse = true, wave = "sinus" },
    SINUS_BRADY = { label = L.text("medsys.config.sinus_bradycardia"), pulse = true, wave = "sinus" },
    SINUS_TACHY = { label = L.text("medsys.config.sinus_tachycardia"), pulse = true, wave = "sinus" },
    VT_WITH_PULSE = { label = L.text("medsys.config.ventricular_tachycardia_with_pulse"), pulse = true, wave = "vt" },
    VF = { label = L.text("medsys.config.ventricular_fibrillation"), shockable = true, wave = "vf" },
    PULSELESS_VT = { label = L.text("medsys.config.pulseless_ventricular_tachycardia"), shockable = true, wave = "vt" },
    PEA = { label = L.text("medsys.config.pulseless_electrical_activity_continue_cpr"), wave = "pea" },
    ASYSTOLE = { label = L.text("medsys.config.asystole"), wave = "flat" },
}

-- Rhythm a cardiac arrest starts with, by its cause (weights). default: a forced arrest
-- (setMedicalState consciousness = clinical_death) or an unknown cause.
MEDIC_ARREST_RHYTHMS = {
    hypoxia = { PEA = 0.5, ASYSTOLE = 0.5 },
    hypovolemia = { PEA = 0.7, ASYSTOLE = 0.3 },
    hypotension = { PEA = 0.6, VF = 0.2, ASYSTOLE = 0.2 },
    tachycardia = { VF = 0.6, PULSELESS_VT = 0.4 },
    vt = { PULSELESS_VT = 0.7, VF = 0.3 },
    shock = { VF = 1 },
    hypoglycemia = { PEA = 0.5, ASYSTOLE = 0.5 },
    default = { ASYSTOLE = 1 }, -- a forced arrest is asystole unless a rhythm is given (setMedicalState "rhythm")
}

-- Test module (server/test.lua, client/test.lua): spawns injured peds in front of an admin.
-- /medtest opens the menu, /medtest <scenario> spawns directly, /medtest clear removes your peds.
MEDIC_TEST = {
    ENABLED = true,            -- turn off in production
    MIN_ADMIN_LEVEL = 4,        -- admin_level above 3
    COMMAND = "medtest",
    MAX_PEDS = 10,              -- per admin, the oldest one is removed beyond this
    SPAWN_DISTANCE = 1.5,       -- metres in front of the admin
    SKINS = { 7, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21, 22, 23, 24, 25, 26, 29, 30, 40, 41 },

    -- Predefined cases. injuries = { { type, severity } }, set = ordered setMedicalState calls
    SCENARIOS = {
        { id = "gsw_torso", label = L.text("medsys.config.gunshot_torso"), desc = L.text("medsys.config.critical_gunshot_wound_arterial_bleeding"),
            injuries = { { "gunshot", 3 } } },
        { id = "gsw_limb", label = L.text("medsys.config.gunshot_limb"), desc = L.text("medsys.config.serious_gunshot_wound_to_leg"),
            injuries = { { "gunshot", 2 } } },
        { id = "shock", label = L.text("medsys.config.hemorrhagic_shock"), desc = L.text("medsys.config.critical_gunshot_already_lost_40_of"),
            injuries = { { "gunshot", 3 } }, set = { { "bloodVolume", 3000 }, { "heartRate", 138 }, { "systolic", 68 }, { "diastolic", 45 } } },
        { id = "car_crash", label = L.text("medsys.config.car_crash"), desc = L.text("medsys.config.open_fracture_and_laceration"),
            injuries = { { "fracture", 3 }, { "gunshot", 1 } } },
        { id = "fall", label = L.text("medsys.config.fall_from_height"), desc = L.text("medsys.config.two_closed_fractures_severe_pain"),
            injuries = { { "fracture", 2 }, { "fracture", 2 } } },
        { id = "house_fire", label = L.text("medsys.config.house_fire"), desc = L.text("medsys.config.critical_burns_with_inhalation_injury"),
            injuries = { { "burn", 3 }, { "suffocation", 1 } } },
        { id = "drowning", label = L.text("medsys.config.drowning"), desc = L.text("medsys.config.pulled_out_of_water_spo2_falling"),
            injuries = { { "suffocation", 3 } }, set = { { "spo2", 74 } } },
        { id = "overdose", label = L.text("medsys.config.overdose"), desc = L.text("medsys.config.unconscious_respiratory_depression"),
            injuries = { { "suffocation", 2 } }, set = { { "consciousness", "unconscious" } } },
        { id = "cardiac_arrest", label = L.text("medsys.config.cardiac_arrest"), desc = L.text("medsys.config.no_pulse_clinical_death_start_cpr"),
            injuries = {}, set = { { "consciousness", "clinical_death" } } },
        { id = "vf_arrest", label = L.text("medsys.config.cardiac_arrest_vf"), desc = L.text("medsys.config.shockable_rhythm_monitor_cpr_and_shock"),
            injuries = {}, set = { { "rhythm", "VF" } } },
        { id = "asystole", label = L.text("medsys.config.cardiac_arrest_asystole"), desc = L.text("medsys.config.non_shockable_cpr_and_adrenaline"),
            injuries = {}, set = { { "rhythm", "ASYSTOLE" } } },
        { id = "vt_pulse", label = L.text("medsys.config.vt_with_pulse"), desc = L.text("medsys.config.wide_fast_rhythm_pulse_present_sync"),
            injuries = {}, set = { { "rhythm", "VT_WITH_PULSE" } } },
        { id = "minor_burn", label = L.text("medsys.config.minor_burn"), desc = L.text("medsys.config.scalded_hand_conscious_and_stable"),
            injuries = { { "burn", 1 } } },
        { id = "hypertension", label = L.text("medsys.config.hypertensive_crisis"), desc = L.text("medsys.config.very_high_blood_pressure_give_captopril"),
            injuries = {}, set = { { "hypertension", 70 }, { "systolic", 190 }, { "diastolic", 125 } } },
        { id = "dead_body", label = L.text("medsys.config.dead_body"), desc = L.text("medsys.config.biological_death_request_transport"),
            injuries = {}, set = { { "consciousness", "dead" } } },
        { id = "stroke", label = L.text("medsys.config.stroke"), desc = L.text("medsys.config.neuro_exam_fast_positive_keep_bp"),
            injuries = { { "stroke", 2 } } },
        { id = "hypo", label = L.text("medsys.config.hypoglycaemia"), desc = L.text("medsys.config.glucose_32_mg_dl_glucose_40"),
            injuries = {}, set = { { "glucose", 32 } } },
        { id = "dka", label = L.text("medsys.config.diabetic_ketoacidosis"), desc = L.text("medsys.config.glucose_520_dehydrated_fluids_insulin"),
            injuries = {}, set = { { "glucose", 520 }, { "bloodVolume", 4100 } } },
        { id = "opioid", label = L.text("medsys.config.opioid_overdose"), desc = L.text("medsys.config.slow_breathing_pinpoint_pupils_naloxone"),
            injuries = { { "opioid", 2 } } },
        { id = "asthma", label = L.text("medsys.config.asthma_attack"), desc = L.text("medsys.config.wheezing_spo2_falling_salbutamol_o2"),
            injuries = { { "asthma", 2 } } },
        { id = "drunk", label = L.text("medsys.config.alcohol_intoxication"), desc = L.text("medsys.config.confused_smells_of_alcohol"),
            injuries = { { "alcohol", 1 } } },
    },
}

-- Injury types. bleed[severity] = bleeding level, loss[severity] = extra fluid loss in ml/s,
-- pain[severity] = pain points, spo2[severity] = SpO2 the patient drifts to while untreated,
-- spo2Rate = how fast (%/s) the SpO2 falls towards that target.
-- treat = the procedure that resolves it, treatedPain = pain multiplier once treated.
-- Optional fields (mostly for the medical conditions below):
--   hidden        not listed on the panel: only its findings show (neuro exam, breathing, skin)
--   treatDrugs    medicines (MEDIC_DRUGS ids) that treat it, see MEDIC_DRUGS.treats
--   treatedSpo2   spo2 targets once treated (nil: a treated one does not lower the SpO2)
--   systolic / heartRate[severity]  added to the circulation targets (treatedVitals scales them once treated)
--   consciousness[severity]  the patient is at least this far down ("confused" / "dazed" / "unconscious")
--   breathing[severity]      what the breathing looks like (MEDIC_BREATHING key)
--   duration[severity]       seconds until it wears off on its own (e.g. after a seizure)
--   neuro[severity]          findings of the neuro exam ({ text, level }, level 1-3 = colour)
--   progress = true          a stroke: gets worse over time (MEDIC.STROKE_*)
-- Conditions without a prehospital treatment show "Needs hospital" (hospital = the cure).
MEDIC_INJURIES = {
    gunshot = {
        label = L.text("medsys.config.gunshot_wound"),
        bleed = { 1, 2, 3 },
        pain = { 30, 50, 70 },
        treat = "bandage", treatedLabel = L.text("medsys.config.bandaged"), treatedPain = 0.6,
    },
    fracture = {
        label = L.text("medsys.config.fracture"),
        bleed = { 0, 0, 1 },            -- a critical one is an open fracture
        pain = { 40, 60, 85 },
        treat = "splint", treatedLabel = L.text("medsys.config.splinted"), treatedPain = 0.4,
    },
    burn = {
        label = L.text("medsys.config.burn"),
        bleed = { 0, 0, 0 },
        loss = { 0.5, 1.5, 3 },         -- plasma loss
        treatedLoss = 0.3,
        pain = { 35, 65, 90 },
        spo2 = { nil, nil, 80 },        -- inhalation injury swells the airway
        treatedSpo2 = { nil, nil, 80 }, -- the dressing does not help the airway
        spo2Rate = 0.3,
        treat = "bandage", treatedLabel = L.text("medsys.config.dressed"), treatedPain = 0.5,
    },
    suffocation = {
        label = L.text("medsys.config.suffocation"),
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        spo2 = { 88, 65, 0 },
        spo2Rate = 0.8,
        treat = "airway", treatedLabel = L.text("medsys.config.airway_secured"), treatedPain = 1,
    },

    -- Visible, hospital only: head injury (fall, crash). Cushing reflex when severe.
    head_injury = {
        label = L.text("medsys.config.head_injury"),
        bleed = { 0, 0, 0 },
        pain = { 25, 40, 50 },
        consciousness = { "confused", "dazed", "unconscious" },
        systolic = { 0, 10, 40 }, heartRate = { 0, -5, -25 },
        spo2 = { nil, nil, 86 }, spo2Rate = 0.3,
        breathing = { nil, nil, "snoring" },
        neuro = {
            { { L.text("medsys.config.scalp_haematoma_asks_same_questions_again"), 1 } },
            { { L.text("medsys.config.scalp_haematoma_vomited_twice"), 2 }, { L.text("medsys.config.drowsy_keeps_closing_eyes"), 2 } },
            { { L.text("medsys.config.pupils_unequal_one_is_wide_and"), 3 }, { L.text("medsys.config.blood_clear_fluid_from_ear"), 3 } },
        },
        treatedPain = 1,
    },

    ---------------------------------------------------------------- medical conditions (hidden)
    stroke = {
        label = L.text("medsys.config.stroke"), hidden = true, progress = true,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        systolic = { 25, 40, 55 }, heartRate = { 0, 0, -5 },
        consciousness = { nil, "confused", "unconscious" },
        spo2 = { nil, nil, 86 }, spo2Rate = 0.25,
        breathing = { nil, nil, "snoring" },
        -- third value = the finding names the affected side ("left" / "right"; side_cap = capitalised), the gaze turns to the other one
        neuro = {
            { { L.text("medsys.config.fast_face_droops_on_s_side"), 3, "side" }, { L.text("medsys.config.fast_speech_slurred"), 3 } },
            { { L.text("medsys.config.fast_face_droops_on_s_side"), 3, "side" }, { L.text("medsys.config.fast_s_arm_drifts_down_weak"), 3, "side" },
                { L.text("medsys.config.fast_speech_slurred_words_mixed_up"), 3 } },
            { { L.text("medsys.config.s_side_paralysed"), 3, "side_cap" }, { L.text("medsys.config.eyes_deviated_to_one_side"), 3 } },
        },
    },
    opioid = {
        label = L.text("medsys.config.opioid_overdose"), hidden = true, treatDrugs = { "naloxone" }, treatedVitals = 0,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        consciousness = { "dazed", "unconscious", "unconscious" },
        systolic = { -10, -20, -30 }, heartRate = { -8, -14, -20 },
        spo2 = { 90, 76, 50 }, spo2Rate = 0.35,
        breathing = { "slow", "slow", "agonal" },
        neuro = {
            { { L.text("medsys.config.pupils_pinpoint"), 2 }, { L.text("medsys.config.needle_marks_on_arms"), 1 } },
            { { L.text("medsys.config.pupils_pinpoint"), 3 }, { L.text("medsys.config.needle_marks_on_arms"), 1 } },
            { { L.text("medsys.config.pupils_pinpoint"), 3 }, { L.text("medsys.config.syringe_lying_next_to_patient"), 1 } },
        },
    },
    sedative = { -- sleeping pills / benzodiazepines (often with alcohol): no antidote, support only
        label = L.text("medsys.config.sedative_overdose"), hidden = true,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        consciousness = { "dazed", "unconscious", "unconscious" },
        systolic = { -10, -20, -35 }, heartRate = { -5, -10, -15 },
        spo2 = { nil, 86, 72 }, spo2Rate = 0.25,
        breathing = { nil, "slow", "snoring" },
        neuro = {
            { { L.text("medsys.config.pupils_normal_size_sluggish"), 1 }, { L.text("medsys.config.slurred_speech_very_sleepy"), 2 } },
            { { L.text("medsys.config.pupils_normal_size_sluggish"), 1 }, { L.text("medsys.config.empty_pill_packets_nearby"), 2 } },
            { { L.text("medsys.config.pupils_sluggish"), 2 }, { L.text("medsys.config.empty_pill_packets_nearby"), 2 }, { L.text("medsys.config.no_gag_reflex"), 3 } },
        },
    },
    stimulant = { -- cocaine / amphetamine: Midazolam calms it
        label = L.text("medsys.config.stimulant_intoxication"), hidden = true, treatDrugs = { "midazolam" }, treatedVitals = 0.3,
        bleed = { 0, 0, 0 },
        pain = { 10, 20, 30 },
        consciousness = { "confused", "confused", "dazed" },
        systolic = { 25, 45, 65 }, heartRate = { 30, 50, 70 },
        breathing = { "rapid", "rapid", "rapid" },
        neuro = {
            { { L.text("medsys.config.pupils_dilated"), 2 }, { L.text("medsys.config.agitated_talks_fast"), 1 } },
            { { L.text("medsys.config.pupils_dilated"), 2 }, { L.text("medsys.config.agitated_jaw_clenching_sweating"), 2 } },
            { { L.text("medsys.config.pupils_dilated"), 3 }, { L.text("medsys.config.paranoid_hot_to_touch"), 3 } },
        },
    },
    alcohol = {
        label = L.text("medsys.config.alcohol_intoxication"), hidden = true,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        consciousness = { "confused", "dazed", "unconscious" },
        systolic = { -5, -10, -18 }, heartRate = { 10, 15, 20 },
        spo2 = { nil, nil, 85 }, spo2Rate = 0.2, -- vomit in the airway
        breathing = { nil, nil, "snoring" },
        neuro = {
            { { L.text("medsys.config.smells_strongly_of_alcohol"), 1 }, { L.text("medsys.config.slurred_speech_unsteady"), 1 } },
            { { L.text("medsys.config.smells_strongly_of_alcohol"), 1 }, { L.text("medsys.config.vomited_cannot_stand"), 2 } },
            { { L.text("medsys.config.smells_strongly_of_alcohol"), 1 }, { L.text("medsys.config.vomit_around_mouth"), 3 } },
        },
    },
    postictal = { -- after an epileptic seizure, wears off by itself
        label = L.text("medsys.config.post_seizure_state"), hidden = true,
        bleed = { 0, 0, 0 },
        pain = { 5, 10, 10 },
        consciousness = { "confused", "dazed", "unconscious" },
        heartRate = { 15, 20, 25 },
        duration = { 240, 480, 720 },
        neuro = {
            { { L.text("medsys.config.bitten_tongue"), 2 }, { L.text("medsys.config.does_not_remember_what_happened"), 1 } },
            { { L.text("medsys.config.bitten_tongue_wet_trousers"), 2 }, { L.text("medsys.config.very_sleepy"), 1 } },
            { { L.text("medsys.config.bitten_tongue_wet_trousers"), 2 }, { L.text("medsys.config.snoring_hard_to_wake"), 3 } },
        },
    },

    -- breathing (lung) conditions
    asthma = {
        label = L.text("medsys.config.asthma_attack"), hidden = true, treatDrugs = { "salbutamol" }, treatedVitals = 0.2,
        bleed = { 0, 0, 0 },
        pain = { 10, 15, 20 },
        heartRate = { 15, 25, 40 },
        spo2 = { 93, 86, 74 }, treatedSpo2 = { nil, 95, 90 }, spo2Rate = 0.3,
        breathing = { "wheeze", "wheeze", "silent" },
        neuro = { { { L.text("medsys.config.speaks_in_full_sentences"), 1 } }, { { L.text("medsys.config.speaks_in_short_phrases_only"), 2 } },
            { { L.text("medsys.config.cannot_speak_exhausted"), 3 } } },
    },
    copd = { -- chronic lung disease flare-up: Salbutamol helps a little, oxygen helps more
        label = L.text("medsys.config.copd_exacerbation"), hidden = true, treatDrugs = { "salbutamol" }, treatedVitals = 0.5,
        bleed = { 0, 0, 0 },
        pain = { 5, 10, 15 },
        heartRate = { 10, 20, 30 },
        spo2 = { 90, 84, 76 }, treatedSpo2 = { 92, 88, 83 }, spo2Rate = 0.2,
        breathing = { "wheeze", "laboured", "laboured" },
        neuro = { { { L.text("medsys.config.pursed_lip_breathing_long_time_smoker"), 1 } },
            { { L.text("medsys.config.pursed_lip_breathing_sits_leaning_forward"), 2 } },
            { { L.text("medsys.config.exhausted_drowsy_from_co2"), 3 } } },
    },
    pulmonary_edema = { -- fluid on the lungs (heart failure): Nitroglycerin + oxygen
        label = L.text("medsys.config.pulmonary_oedema"), hidden = true, treatDrugs = { "nitroglycerin" }, treatedVitals = 0.3,
        bleed = { 0, 0, 0 },
        pain = { 10, 15, 20 },
        systolic = { 25, 40, 55 }, heartRate = { 15, 25, 35 },
        spo2 = { 90, 82, 70 }, treatedSpo2 = { 95, 91, 86 }, spo2Rate = 0.25,
        breathing = { "crackles", "crackles", "crackles" },
        neuro = { { { L.text("medsys.config.swollen_ankles"), 1 } }, { { L.text("medsys.config.swollen_ankles_pink_frothy_sputum"), 2 } },
            { { L.text("medsys.config.pink_frothy_sputum_drowning_feeling"), 3 } } },
    },
}

-- What the breathing looks like. level: 0 normal - 3 critical (panel colour),
-- dyspnea = the patient visibly struggles for air (medsys_effects animation)
MEDIC_BREATHING = {
    normal = { label = L.text("medsys.config.normal"), level = 0 },
    rapid = { label = L.text("medsys.config.rapid"), level = 1 },
    wheeze = { label = L.text("medsys.config.wheezing"), level = 2, dyspnea = true },
    laboured = { label = L.text("medsys.config.laboured"), level = 2, dyspnea = true },
    crackles = { label = L.text("medsys.config.laboured_crackles"), level = 2, dyspnea = true },
    kussmaul = { label = L.text("medsys.config.deep_and_rapid"), level = 2, dyspnea = true },
    silent = { label = L.text("medsys.config.silent_chest_exhausted"), level = 3, dyspnea = true },
    slow = { label = L.text("medsys.config.slow_shallow"), level = 2 },
    snoring = { label = L.text("medsys.config.snoring"), level = 3 },
    agonal = { label = L.text("medsys.config.gasping"), level = 3 },
    none = { label = L.text("medsys.config.not_breathing"), level = 3 },
    ventilated = { label = L.text("medsys.config.ventilated"), level = 0 },
}

MEDIC_SEVERITY = { L.text("medsys.config.minor"), L.text("medsys.config.serious"), L.text("medsys.config.critical") }
MEDIC_BLEEDING = { [0] = L.text("medsys.config.none"), L.text("medsys.config.mild"), L.text("medsys.config.severe"), L.text("medsys.config.critical") }

-- Consciousness states from the best to the worst
MEDIC_CONSCIOUSNESS = {
    stable = L.text("medsys.config.stable"),
    confused = L.text("medsys.config.confused"),  -- awake but disoriented (intoxication, after a seizure, glucose, stroke)
    dazed = L.text("medsys.config.dazed"),
    unconscious = L.text("medsys.config.unconscious"),
    clinical_death = L.text("medsys.config.clinical_death"),
    dead = L.text("medsys.config.dead"),
}

-- Treatment actions offered on the examination panel
MEDIC_ACTIONS = {
    bandage = { label = L.text("medsys.config.bandage") },
    splint = { label = L.text("medsys.config.splint") },
    cpr = { label = L.text("medsys.config.cpr") },
    iv = { label = L.text("medsys.config.iv_access") },
    airway = { label = L.text("medsys.config.intubate") },
    oxygen = { label = L.text("medsys.config.o2_mask"), activeLabel = L.text("medsys.config.remove_o2") }, -- activeLabel: while the mask is on
    medication = { label = L.text("medsys.config.medication") },
    neuro = { label = L.text("medsys.config.neuro_exam"), activeLabel = L.text("medsys.treatment.neuro_exam_done") },
    glucometer = { label = L.text("medsys.config.glucometer"), activeLabel = L.text("medsys.config.put_meter_away") }, -- client-side device window
    transport = { label = L.text("medsys.config.transport"), wideLabel = L.text("medsys.config.request_transport") }, -- wideLabel: alone in its row
}
-- Button rows of the examination panel (ABCDE approach, E is not used for now).
-- The monitor ("monitor" procedure) has no row button: it is attached from the heart rate tile.
-- tag = the big letters on the row label (optional), label = the text under them
MEDIC_ACTION_GROUPS = {
    { tag = "AB", label = L.text("medsys.config.airway_breathing"), actions = { "airway", "oxygen" } },
    { tag = "C", label = L.text("medsys.config.circulation"), actions = { "bandage", "splint", "cpr", "iv", "medication" } },
    { tag = "D", label = L.text("medsys.config.disability"), actions = { "neuro", "glucometer" } },
    { label = L.text("medsys.config.transport"), actions = { "transport" } },
}
-- Equipment each action needs (server/equipment.lua): item = "bag" | "monitor", stock = what must be
-- in the bag ("ivKits" per attempt, "oxygen" while the mask is on; medication: per drug),
-- consume = "done": one piece is used up by a successful action (the IV kit goes at the start).
-- Actions not listed (neuro exam, CPR, transport) need nothing.
MEDIC_EQUIPMENT = {
    bandage = { item = "bag", stock = "bandages", consume = "done" },
    splint = { item = "bag", stock = "splints", consume = "done" },
    iv = { item = "bag", stock = "ivKits" },
    airway = { item = "bag", stock = "airwayKits" },
    oxygen = { item = "bag", stock = "oxygen" },
    medication = { item = "bag" },
    glucometer = { item = "bag", stock = "glucometers" },
    monitor = { item = "monitor" },
}
MEDIC_DEAD_ACTION_GROUPS = { -- the only row when the patient is dead
    { label = L.text("medsys.config.transport"), actions = { "transport" } },
}

-- Medicines (given through the IV access). name = the active ingredient, desc = what it is for,
-- in plain words for players without medical knowledge (keep it to two lines on the panel).
-- Effects while a dose works (duration in seconds):
--   systolic / heartRate  change of the target systolic pressure (mmHg) / pulse (BPM), doses add up
--   analgesia             fraction of the pain taken away (doses add up, max 1)
--   sedation              the patient is unconscious (RSI induction)
--   paralysis             after MEDIC.PARALYSIS_ONSET the patient cannot move or breathe (RSI);
--                         an awake patient panics (MEDIC.PANIC_*)
--   roscBonus             added to the ROSC chance of CPR (does not add up)
--   glucose               mg/dL added to the blood glucose at once (when given)
--   glucoseRate           mg/dL per second while the dose works (insulin: negative)
--   treats                conditions (MEDIC_INJURIES ids) it treats when given
--   awake = true          only for a patient who can swallow (stable / confused)
-- route: nil = through the IV line; "oral" / "inhaled" / "nasal" = no IV access needed
MEDIC_DRUGS = {
    ketamine = {
        name = "Ketamine (Calypsol)",
        class = L.text("medsys.config.anaesthetic_rsi_step_1"),
        desc = L.text("medsys.config.puts_patient_to_sleep_and_takes"),
        sedation = true,
        analgesia = 1,
        systolic = 15,
        heartRate = 8,
        duration = 600,
    },
    rocuronium = {
        name = "Rocuronium bromide (Esmeron)",
        class = L.text("medsys.config.muscle_relaxant_rsi_step_2"),
        desc = L.text("medsys.config.paralyses_muscles_and_stops_breathing_spo2"),
        paralysis = true,
        duration = 2400,
    },
    fentanyl = {
        name = "Fentanyl",
        class = L.text("medsys.config.painkiller"),
        desc = L.text("medsys.config.strong_painkiller_for_patient_who_is"),
        analgesia = 0.7,
        systolic = -10,
        duration = 1800,
    },
    epinephrine = {
        name = "Adrenalin (Tonogen)",
        class = L.text("medsys.config.heart_stimulant"),
        desc = L.text("medsys.config.raises_pulse_and_blood_pressure_in"),
        heartRate = 30,
        systolic = 30,
        roscBonus = 0.15,
        duration = 300,
    },
    captopril = {
        name = "Captopril (Tensiomin)",
        class = L.text("medsys.config.blood_pressure_lowering"),
        desc = L.text("medsys.config.tablet_under_tongue_no_iv_needed"),
        route = "oral", -- no IV access needed
        systolic = -40,
        duration = 600,
    },
    nitroglycerin = {
        name = "Nitroglycerin spray",
        class = L.text("medsys.config.vasodilator"),
        desc = L.text("medsys.config.spray_under_tongue_lowers_blood_pressure"),
        route = "oral",
        systolic = -30,
        treats = { "pulmonary_edema" },
        duration = 600,
    },
    glucose = {
        name = "Glucose 40%",
        class = L.text("medsys.config.blood_sugar_raising"),
        desc = L.text("medsys.config.raises_low_blood_sugar_within_seconds"),
        glucose = 100,
        duration = 60,
    },
    glucose_gel = {
        name = "Oral glucose gel",
        class = L.text("medsys.config.blood_sugar_raising"),
        desc = L.text("medsys.config.sugar_gel_into_cheek_for_awake"),
        route = "oral",
        awake = true,
        glucose = 40,
        duration = 60,
    },
    insulin = {
        name = "Insulin (Actrapid)",
        class = L.text("medsys.config.blood_sugar_lowering"),
        desc = L.text("medsys.config.slowly_lowers_very_high_blood_sugar"),
        glucoseRate = -0.35,
        duration = 900,
    },
    naloxone = {
        name = "Naloxone (Narcan)",
        class = L.text("medsys.config.opioid_antidote_nasal"),
        desc = L.text("medsys.config.nasal_spray_reverses_opioid_heroin_fentanyl"),
        route = "nasal",
        treats = { "opioid" },
        duration = 1800,
    },
    salbutamol = {
        name = "Salbutamol (Ventolin)",
        class = L.text("medsys.config.bronchodilator_nebuliser"),
        desc = L.text("medsys.config.nebulised_opens_airways_in_asthma_or"),
        route = "inhaled",
        heartRate = 12,
        treats = { "asthma", "copd" },
        duration = 900,
    },
    midazolam = {
        name = "Midazolam (Dormicum)",
        class = L.text("medsys.config.sedative"),
        desc = L.text("medsys.config.calms_agitated_patient_cocaine_amphetamine_lower"),
        systolic = -15,
        heartRate = -15,
        treats = { "stimulant" },
        duration = 1200,
    },
}
MEDIC_DRUG_ORDER = { "ketamine", "rocuronium", "fentanyl", "epinephrine", "captopril", "nitroglycerin",
    "glucose", "glucose_gel", "insulin", "naloxone", "salbutamol", "midazolam" }

-- a route ("oral", "inhaled", "nasal") needs no IV access; every other medicine goes through the IV line
function medicDrugNeedsIV(drug)
    return drug.route == nil or drug.route == "iv"
end

-- Accepts 1-3 or "minor"/"serious"/"critical" (also "mild"/"severe")
local SEVERITY_NAMES = { minor = 1, mild = 1, serious = 2, severe = 2, critical = 3 }
function medicNormalizeSeverity(severity)
    if type(severity) == "string" then
        severity = SEVERITY_NAMES[severity:lower()] or tonumber(severity)
    end
    severity = math.floor(tonumber(severity) or 0)
    if severity < 1 or severity > 3 then return nil end
    return severity
end

-- Order of the living consciousness states (the worse one wins)
MEDIC_CONSCIOUSNESS_RANK = { stable = 1, confused = 2, dazed = 3, unconscious = 4 }

-- Glucose in the meter's second unit
function medicGlucoseMmol(mgdl)
    return mgdl / 18.0
end

function medicIsDown(status)
    return status == "unconscious" or status == "clinical_death" or status == "dead"
end
end)
