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
    SINUS = { label = "Normal Sinus Rhythm", pulse = true, wave = "sinus" },
    SINUS_BRADY = { label = "Sinus Bradycardia", pulse = true, wave = "sinus" },
    SINUS_TACHY = { label = "Sinus Tachycardia", pulse = true, wave = "sinus" },
    VT_WITH_PULSE = { label = "Ventricular Tachycardia with Pulse", pulse = true, wave = "vt" },
    VF = { label = "Ventricular Fibrillation", shockable = true, wave = "vf" },
    PULSELESS_VT = { label = "Pulseless Ventricular Tachycardia", shockable = true, wave = "vt" },
    PEA = { label = "Pulseless Electrical Activity - continue CPR", wave = "pea" },
    ASYSTOLE = { label = "Asystole", wave = "flat" },
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
        { id = "gsw_torso", label = "Gunshot - torso", desc = "Critical gunshot wound, arterial bleeding",
            injuries = { { "gunshot", 3 } } },
        { id = "gsw_limb", label = "Gunshot - limb", desc = "Serious gunshot wound to the leg",
            injuries = { { "gunshot", 2 } } },
        { id = "shock", label = "Hemorrhagic shock", desc = "Critical gunshot, already lost 40% of the blood",
            injuries = { { "gunshot", 3 } }, set = { { "bloodVolume", 3000 }, { "heartRate", 138 }, { "systolic", 68 }, { "diastolic", 45 } } },
        { id = "car_crash", label = "Car crash", desc = "Open fracture and a laceration",
            injuries = { { "fracture", 3 }, { "gunshot", 1 } } },
        { id = "fall", label = "Fall from height", desc = "Two closed fractures, severe pain",
            injuries = { { "fracture", 2 }, { "fracture", 2 } } },
        { id = "house_fire", label = "House fire", desc = "Critical burns with inhalation injury",
            injuries = { { "burn", 3 }, { "suffocation", 1 } } },
        { id = "drowning", label = "Drowning", desc = "Pulled out of the water, SpO2 falling fast",
            injuries = { { "suffocation", 3 } }, set = { { "spo2", 74 } } },
        { id = "overdose", label = "Overdose", desc = "Unconscious, respiratory depression",
            injuries = { { "suffocation", 2 } }, set = { { "consciousness", "unconscious" } } },
        { id = "cardiac_arrest", label = "Cardiac arrest", desc = "No pulse, clinical death - start CPR",
            injuries = {}, set = { { "consciousness", "clinical_death" } } },
        { id = "vf_arrest", label = "Cardiac arrest - VF", desc = "Shockable rhythm - monitor, CPR and shock",
            injuries = {}, set = { { "rhythm", "VF" } } },
        { id = "asystole", label = "Cardiac arrest - asystole", desc = "Non-shockable - CPR and adrenaline",
            injuries = {}, set = { { "rhythm", "ASYSTOLE" } } },
        { id = "vt_pulse", label = "VT with pulse", desc = "Wide fast rhythm, pulse present - SYNC cardioversion",
            injuries = {}, set = { { "rhythm", "VT_WITH_PULSE" } } },
        { id = "minor_burn", label = "Minor burn", desc = "Scalded hand, conscious and stable",
            injuries = { { "burn", 1 } } },
        { id = "hypertension", label = "Hypertensive crisis", desc = "Very high blood pressure - give Captopril",
            injuries = {}, set = { { "hypertension", 70 }, { "systolic", 190 }, { "diastolic", 125 } } },
        { id = "dead_body", label = "Dead body", desc = "Biological death - request transport",
            injuries = {}, set = { { "consciousness", "dead" } } },
        { id = "stroke", label = "Stroke", desc = "Neuro exam: FAST positive - keep the BP safe, transport",
            injuries = { { "stroke", 2 } } },
        { id = "hypo", label = "Hypoglycaemia", desc = "Glucose 32 mg/dL - Glucose 40% IV",
            injuries = {}, set = { { "glucose", 32 } } },
        { id = "dka", label = "Diabetic ketoacidosis", desc = "Glucose 520, dehydrated - fluids, insulin",
            injuries = {}, set = { { "glucose", 520 }, { "bloodVolume", 4100 } } },
        { id = "opioid", label = "Opioid overdose", desc = "Slow breathing, pinpoint pupils - Naloxone",
            injuries = { { "opioid", 2 } } },
        { id = "asthma", label = "Asthma attack", desc = "Wheezing, SpO2 falling - Salbutamol, O2",
            injuries = { { "asthma", 2 } } },
        { id = "drunk", label = "Alcohol intoxication", desc = "Confused, smells of alcohol",
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
        label = "Gunshot wound",
        bleed = { 1, 2, 3 },
        pain = { 30, 50, 70 },
        treat = "bandage", treatedLabel = "Bandaged", treatedPain = 0.6,
    },
    fracture = {
        label = "Fracture",
        bleed = { 0, 0, 1 },            -- a critical one is an open fracture
        pain = { 40, 60, 85 },
        treat = "splint", treatedLabel = "Splinted", treatedPain = 0.4,
    },
    burn = {
        label = "Burn",
        bleed = { 0, 0, 0 },
        loss = { 0.5, 1.5, 3 },         -- plasma loss
        treatedLoss = 0.3,
        pain = { 35, 65, 90 },
        spo2 = { nil, nil, 80 },        -- inhalation injury swells the airway
        treatedSpo2 = { nil, nil, 80 }, -- the dressing does not help the airway
        spo2Rate = 0.3,
        treat = "bandage", treatedLabel = "Dressed", treatedPain = 0.5,
    },
    suffocation = {
        label = "Suffocation",
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        spo2 = { 88, 65, 0 },
        spo2Rate = 0.8,
        treat = "airway", treatedLabel = "Airway secured", treatedPain = 1,
    },

    -- Visible, hospital only: head injury (fall, crash). Cushing reflex when severe.
    head_injury = {
        label = "Head injury",
        bleed = { 0, 0, 0 },
        pain = { 25, 40, 50 },
        consciousness = { "confused", "dazed", "unconscious" },
        systolic = { 0, 10, 40 }, heartRate = { 0, -5, -25 },
        spo2 = { nil, nil, 86 }, spo2Rate = 0.3,
        breathing = { nil, nil, "snoring" },
        neuro = {
            { { "Scalp haematoma, asks the same questions again", 1 } },
            { { "Scalp haematoma, vomited twice", 2 }, { "Drowsy, keeps closing the eyes", 2 } },
            { { "Pupils: UNEQUAL - one is wide and slow", 3 }, { "Blood / clear fluid from the ear", 3 } },
        },
        treatedPain = 1,
    },

    ---------------------------------------------------------------- medical conditions (hidden)
    stroke = {
        label = "Stroke", hidden = true, progress = true,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        systolic = { 25, 40, 55 }, heartRate = { 0, 0, -5 },
        consciousness = { nil, "confused", "unconscious" },
        spo2 = { nil, nil, 86 }, spo2Rate = 0.25,
        breathing = { nil, nil, "snoring" },
        -- %s = the affected side ("left" / "right"), the gaze turns to the other one
        neuro = {
            { { "FAST: face droops on the %s side", 3 }, { "FAST: speech slurred", 3 } },
            { { "FAST: face droops on the %s side", 3 }, { "FAST: %s arm drifts down, weak grip", 3 },
                { "FAST: speech slurred, words mixed up", 3 } },
            { { "%s side paralysed", 3 }, { "Eyes deviated to one side", 3 } },
        },
    },
    opioid = {
        label = "Opioid overdose", hidden = true, treatDrugs = { "naloxone" }, treatedVitals = 0,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        consciousness = { "dazed", "unconscious", "unconscious" },
        systolic = { -10, -20, -30 }, heartRate = { -8, -14, -20 },
        spo2 = { 90, 76, 50 }, spo2Rate = 0.35,
        breathing = { "slow", "slow", "agonal" },
        neuro = {
            { { "Pupils: pinpoint", 2 }, { "Needle marks on the arms", 1 } },
            { { "Pupils: pinpoint", 3 }, { "Needle marks on the arms", 1 } },
            { { "Pupils: pinpoint", 3 }, { "Syringe lying next to the patient", 1 } },
        },
    },
    sedative = { -- sleeping pills / benzodiazepines (often with alcohol): no antidote, support only
        label = "Sedative overdose", hidden = true,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        consciousness = { "dazed", "unconscious", "unconscious" },
        systolic = { -10, -20, -35 }, heartRate = { -5, -10, -15 },
        spo2 = { nil, 86, 72 }, spo2Rate = 0.25,
        breathing = { nil, "slow", "snoring" },
        neuro = {
            { { "Pupils: normal size, sluggish", 1 }, { "Slurred speech, very sleepy", 2 } },
            { { "Pupils: normal size, sluggish", 1 }, { "Empty pill packets nearby", 2 } },
            { { "Pupils: sluggish", 2 }, { "Empty pill packets nearby", 2 }, { "No gag reflex", 3 } },
        },
    },
    stimulant = { -- cocaine / amphetamine: Midazolam calms it
        label = "Stimulant intoxication", hidden = true, treatDrugs = { "midazolam" }, treatedVitals = 0.3,
        bleed = { 0, 0, 0 },
        pain = { 10, 20, 30 },
        consciousness = { "confused", "confused", "dazed" },
        systolic = { 25, 45, 65 }, heartRate = { 30, 50, 70 },
        breathing = { "rapid", "rapid", "rapid" },
        neuro = {
            { { "Pupils: dilated", 2 }, { "Agitated, talks fast", 1 } },
            { { "Pupils: dilated", 2 }, { "Agitated, jaw clenching, sweating", 2 } },
            { { "Pupils: dilated", 3 }, { "Paranoid, hot to the touch", 3 } },
        },
    },
    alcohol = {
        label = "Alcohol intoxication", hidden = true,
        bleed = { 0, 0, 0 },
        pain = { 0, 0, 0 },
        consciousness = { "confused", "dazed", "unconscious" },
        systolic = { -5, -10, -18 }, heartRate = { 10, 15, 20 },
        spo2 = { nil, nil, 85 }, spo2Rate = 0.2, -- vomit in the airway
        breathing = { nil, nil, "snoring" },
        neuro = {
            { { "Smells strongly of alcohol", 1 }, { "Slurred speech, unsteady", 1 } },
            { { "Smells strongly of alcohol", 1 }, { "Vomited, cannot stand", 2 } },
            { { "Smells strongly of alcohol", 1 }, { "Vomit around the mouth", 3 } },
        },
    },
    postictal = { -- after an epileptic seizure, wears off by itself
        label = "Post-seizure state", hidden = true,
        bleed = { 0, 0, 0 },
        pain = { 5, 10, 10 },
        consciousness = { "confused", "dazed", "unconscious" },
        heartRate = { 15, 20, 25 },
        duration = { 240, 480, 720 },
        neuro = {
            { { "Bitten tongue", 2 }, { "Does not remember what happened", 1 } },
            { { "Bitten tongue, wet trousers", 2 }, { "Very sleepy", 1 } },
            { { "Bitten tongue, wet trousers", 2 }, { "Snoring, hard to wake", 3 } },
        },
    },

    -- breathing (lung) conditions
    asthma = {
        label = "Asthma attack", hidden = true, treatDrugs = { "salbutamol" }, treatedVitals = 0.2,
        bleed = { 0, 0, 0 },
        pain = { 10, 15, 20 },
        heartRate = { 15, 25, 40 },
        spo2 = { 93, 86, 74 }, treatedSpo2 = { nil, 95, 90 }, spo2Rate = 0.3,
        breathing = { "wheeze", "wheeze", "silent" },
        neuro = { { { "Speaks in full sentences", 1 } }, { { "Speaks in short phrases only", 2 } },
            { { "Cannot speak, exhausted", 3 } } },
    },
    copd = { -- chronic lung disease flare-up: Salbutamol helps a little, oxygen helps more
        label = "COPD exacerbation", hidden = true, treatDrugs = { "salbutamol" }, treatedVitals = 0.5,
        bleed = { 0, 0, 0 },
        pain = { 5, 10, 15 },
        heartRate = { 10, 20, 30 },
        spo2 = { 90, 84, 76 }, treatedSpo2 = { 92, 88, 83 }, spo2Rate = 0.2,
        breathing = { "wheeze", "laboured", "laboured" },
        neuro = { { { "Pursed-lip breathing, long-time smoker", 1 } },
            { { "Pursed-lip breathing, sits leaning forward", 2 } },
            { { "Exhausted, drowsy from the CO2", 3 } } },
    },
    pulmonary_edema = { -- fluid on the lungs (heart failure): Nitroglycerin + oxygen
        label = "Pulmonary oedema", hidden = true, treatDrugs = { "nitroglycerin" }, treatedVitals = 0.3,
        bleed = { 0, 0, 0 },
        pain = { 10, 15, 20 },
        systolic = { 25, 40, 55 }, heartRate = { 15, 25, 35 },
        spo2 = { 90, 82, 70 }, treatedSpo2 = { 95, 91, 86 }, spo2Rate = 0.25,
        breathing = { "crackles", "crackles", "crackles" },
        neuro = { { { "Swollen ankles", 1 } }, { { "Swollen ankles, pink frothy sputum", 2 } },
            { { "Pink frothy sputum, drowning feeling", 3 } } },
    },
}

-- What the breathing looks like. level: 0 normal - 3 critical (panel colour),
-- dyspnea = the patient visibly struggles for air (medsys_effects animation)
MEDIC_BREATHING = {
    normal = { label = "Normal", level = 0 },
    rapid = { label = "Rapid", level = 1 },
    wheeze = { label = "Wheezing", level = 2, dyspnea = true },
    laboured = { label = "Laboured", level = 2, dyspnea = true },
    crackles = { label = "Laboured, crackles", level = 2, dyspnea = true },
    kussmaul = { label = "Deep and rapid", level = 2, dyspnea = true },
    silent = { label = "Silent chest, exhausted", level = 3, dyspnea = true },
    slow = { label = "Slow, shallow", level = 2 },
    snoring = { label = "Snoring", level = 3 },
    agonal = { label = "Gasping", level = 3 },
    none = { label = "Not breathing", level = 3 },
    ventilated = { label = "Ventilated", level = 0 },
}

MEDIC_SEVERITY = { "Minor", "Serious", "Critical" }
MEDIC_BLEEDING = { [0] = "None", "Mild", "Severe", "Critical" }

-- Consciousness states from the best to the worst
MEDIC_CONSCIOUSNESS = {
    stable = "Stable",
    confused = "Confused",  -- awake but disoriented (intoxication, after a seizure, glucose, stroke)
    dazed = "Dazed",
    unconscious = "Unconscious",
    clinical_death = "Clinical death",
    dead = "Dead",
}

-- Treatment actions offered on the examination panel
MEDIC_ACTIONS = {
    bandage = { label = "Bandage" },
    splint = { label = "Splint" },
    cpr = { label = "CPR" },
    iv = { label = "IV access" },
    airway = { label = "Intubate" },
    oxygen = { label = "O2 mask", activeLabel = "Remove O2" }, -- activeLabel: while the mask is on
    medication = { label = "Medication" },
    neuro = { label = "Neuro exam", activeLabel = "Neuro exam done" },
    glucometer = { label = "Glucometer", activeLabel = "Put meter away" }, -- client-side device window
    transport = { label = "Transport", wideLabel = "Request transport" }, -- wideLabel: alone in its row
}
-- Button rows of the examination panel (ABCDE approach, E is not used for now).
-- The monitor ("monitor" procedure) has no row button: it is attached from the heart rate tile.
-- tag = the big letters on the row label (optional), label = the text under them
MEDIC_ACTION_GROUPS = {
    { tag = "AB", label = "Airway, Breathing", actions = { "airway", "oxygen" } },
    { tag = "C", label = "Circulation", actions = { "bandage", "splint", "cpr", "iv", "medication" } },
    { tag = "D", label = "Disability", actions = { "neuro", "glucometer" } },
    { label = "Transport", actions = { "transport" } },
}
MEDIC_DEAD_ACTION_GROUPS = { -- the only row when the patient is dead
    { label = "Transport", actions = { "transport" } },
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
        class = "Anaesthetic - RSI step 1",
        desc = "Puts the patient to sleep and takes away all pain, raises the blood pressure a little. "
            .. "Intubation: give it BEFORE the muscle relaxant.",
        sedation = true,
        analgesia = 1,
        systolic = 15,
        heartRate = 8,
        duration = 600,
    },
    rocuronium = {
        name = "Rocuronium bromide (Esmeron)",
        class = "Muscle relaxant - RSI step 2",
        desc = "Paralyses the muscles and stops the breathing: the SpO2 falls until the patient is "
            .. "intubated. An awake patient panics - put them to sleep first.",
        paralysis = true,
        duration = 2400,
    },
    fentanyl = {
        name = "Fentanyl",
        class = "Painkiller",
        desc = "Strong painkiller for a patient who is awake. Lowers the blood pressure slightly.",
        analgesia = 0.7,
        systolic = -10,
        duration = 1800,
    },
    epinephrine = {
        name = "Adrenalin (Tonogen)",
        class = "Heart stimulant",
        desc = "Raises the pulse and the blood pressure. In cardiac arrest it makes CPR more likely "
            .. "to restart the heart. Too many doses drive the pulse dangerously high.",
        heartRate = 30,
        systolic = 30,
        roscBonus = 0.15,
        duration = 300,
    },
    captopril = {
        name = "Captopril (Tensiomin)",
        class = "Blood pressure lowering",
        desc = "Tablet under the tongue, no IV needed. Lowers high blood pressure. It lowers a normal "
            .. "or low pressure too: given to a patient in shock it can stop the heart.",
        route = "oral", -- no IV access needed
        systolic = -40,
        duration = 600,
    },
    nitroglycerin = {
        name = "Nitroglycerin spray",
        class = "Vasodilator",
        desc = "Spray under the tongue. Lowers the blood pressure fast and clears fluid from the lungs "
            .. "(pulmonary oedema). Never with a low pressure.",
        route = "oral",
        systolic = -30,
        treats = { "pulmonary_edema" },
        duration = 600,
    },
    glucose = {
        name = "Glucose 40%",
        class = "Blood sugar raising",
        desc = "Raises a low blood sugar within seconds (about +100 mg/dL). Check the glucometer before "
            .. "and after - it wears off, measure again.",
        glucose = 100,
        duration = 60,
    },
    glucose_gel = {
        name = "Oral glucose gel",
        class = "Blood sugar raising",
        desc = "Sugar gel into the cheek for an AWAKE patient who can swallow (about +40 mg/dL). "
            .. "Unconscious patient: give Glucose 40% IV.",
        route = "oral",
        awake = true,
        glucose = 40,
        duration = 60,
    },
    insulin = {
        name = "Insulin (Actrapid)",
        class = "Blood sugar lowering",
        desc = "Slowly lowers a very high blood sugar (ketoacidosis). Given to a patient with a normal "
            .. "or low sugar it causes a dangerous hypoglycaemia.",
        glucoseRate = -0.35,
        duration = 900,
    },
    naloxone = {
        name = "Naloxone (Narcan)",
        class = "Opioid antidote - nasal",
        desc = "Nasal spray. Reverses an opioid (heroin, fentanyl) overdose: the breathing and the "
            .. "consciousness come back. No effect on other poisonings.",
        route = "nasal",
        treats = { "opioid" },
        duration = 1800,
    },
    salbutamol = {
        name = "Salbutamol (Ventolin)",
        class = "Bronchodilator - nebuliser",
        desc = "Nebulised: opens the airways in an asthma or COPD attack (wheezing). Raises the pulse a little.",
        route = "inhaled",
        heartRate = 12,
        treats = { "asthma", "copd" },
        duration = 900,
    },
    midazolam = {
        name = "Midazolam (Dormicum)",
        class = "Sedative",
        desc = "Calms an agitated patient (cocaine, amphetamine): lowers the pulse and the pressure. "
            .. "Makes the breathing weaker - watch the SpO2.",
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
