-- Configuration and shared constants of the medical system.
-- Everything that tunes the physiology, the interaction or the treatments lives here.

MEDIC = {
    TICK = 1000,                -- ms between two simulation steps (one global timer for every patient)

    -- Element data. STATUS is broadcast (it only changes on state transitions),
    -- the vitals are written in "subscribe" mode so only the players examining / treating
    -- the patient receive them (mg_airway reads SPO2 / HEART_RATE from the patient).
    DATA_STATUS = "medic.status",
    DATA_SPO2 = "spo2",
    DATA_HEART_RATE = "heartRate",

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

    -- Cardiac arrest (clinical death) triggers
    ARREST_SPO2 = 0,            -- SpO2 at or below this -> pulse 0
    ARREST_BLOOD = 0.5,         -- blood volume fraction at or below this -> pulse 0
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
    REQUIRE_MEDIC_ROLE = false, -- true: only players flagged with setPlayerMedic can examine / treat

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

    -- Animations
    ANIM_DOWN = { "PED", "KO_shot_front" },
    ANIM_GETUP = { "PED", "getup_front" },
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
        { id = "minor_burn", label = "Minor burn", desc = "Scalded hand, conscious and stable",
            injuries = { { "burn", 1 } } },
    },
}

-- Injury types. bleed[severity] = bleeding level, loss[severity] = extra fluid loss in ml/s,
-- pain[severity] = pain points, spo2[severity] = SpO2 the patient drifts to while untreated,
-- spo2Rate = how fast (%/s) the SpO2 falls towards that target.
-- treat = the procedure that resolves it, treatedPain = pain multiplier once treated.
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
        treat = "bandage", treatedLabel = "Splinted", treatedPain = 0.4,
    },
    burn = {
        label = "Burn",
        bleed = { 0, 0, 0 },
        loss = { 0.5, 1.5, 3 },         -- plasma loss
        treatedLoss = 0.3,
        pain = { 35, 65, 90 },
        spo2 = { nil, nil, 80 },        -- inhalation injury swells the airway
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
}

MEDIC_SEVERITY = { "Minor", "Serious", "Critical" }
MEDIC_BLEEDING = { [0] = "None", "Mild", "Severe", "Critical" }

-- Consciousness states from the best to the worst
MEDIC_CONSCIOUSNESS = {
    stable = "Stable",
    dazed = "Dazed",
    unconscious = "Unconscious",
    clinical_death = "Clinical death",
    dead = "Dead",
}

-- Treatment actions offered on the examination panel
MEDIC_ACTIONS = {
    bandage = { label = "Bandage", game = "Arrows" },
    cpr = { label = "CPR", game = "CPR" },
    iv = { label = "IV access", game = "IV" },
    airway = { label = "Intubate", game = "Airway" },
}
MEDIC_ACTION_ORDER = { "bandage", "cpr", "iv", "airway" }

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

function medicIsDown(status)
    return status == "unconscious" or status == "clinical_death" or status == "dead"
end
