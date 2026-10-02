-- Med Scene Manager - shared configuration

MSM = {
    ERM = "med_erm",            -- dispatch resource (tasks, units)
    MEDSYS = "medsys",          -- medical resource (injuries, vitals)

    SCENE_DIR = "scenes/",      -- one <name>.json per scene
    INDEX_FILE = "scenes/index.json", -- list of scene names (MTA cannot list a directory)
    NAME_PATTERN = "^[%w_%-]+$",
    NAME_MAX = 40,

    MIN_ADMIN_LEVEL = 4,        -- v_mysql admin_level for every command / the editor

    -- Commands
    CMD_EDITOR = "medsceneeditor",
    CMD_RANDOM = "medscenerandom",   -- /medscenerandom [scene name]
    CMD_AUTO = "medsceneauto",       -- /medsceneauto [on|off]
    CMD_LIST = "medscenelist",       -- active scenes
    CMD_CLEAR = "medsceneclear",     -- /medsceneclear [instance id | all]
    CMD_RELOAD = "medscenereload",   -- re-read the scene files

    -- Defaults of a new scene's ERM task
    DEFAULT_ERM = {
        title = "Medical emergency",
        description = "",
        caller = "SceneManager",
        priority = 2,
    },

    -- Live scenes
    DATA_NAME = "medic.name",    -- random first name of a live scene ped (shared/names.lua), shown by medsys
    MEDSYS_DELAY = 300,          -- ms after spawning before the injuries are applied (client sync)
    CLEANUP_DELAY = 30,          -- s after the task closed before the scene may be removed...
    CLEANUP_RANGE = 120,         -- ...once no player is within this many metres of it
    CLEANUP_FORCE = 600,         -- s after the task closed: removed even with players around
    MAX_LIFETIME = 60 * 60,      -- s, a scene whose task never closes is closed + removed
    CHECK_INTERVAL = 5000,       -- ms, cleanup + generator tick

    -- Automatic generator. It only works while med_erm has free units, and the
    -- average gap between two scenes is divided by the number of free units.
    AUTO = {
        INTERVAL_MIN = 90,       -- s between two scenes with ONE free unit
        INTERVAL_MAX = 240,
        PENDING_PER_UNIT = 1,    -- waiting (not yet assigned) scene tasks allowed per free unit
        MAX_ACTIVE = 12,         -- live scenes at once (any source)
        MIN_PLAYER_DISTANCE = 150, -- no scene closer than this to any player (pop-in)
        MIN_SCENE_DISTANCE = 60, -- no scene closer than this to another live scene
        UNIT_TYPES = nil,        -- nil = every unit type counts as free, or e.g. { "ALS", "BLS" }
    },

    -- Editor
    EDITOR_DIMENSION = 47000,    -- + session number; every editor works in a private dimension
    LABEL_RANGE = 35,            -- m, 3D labels over the scene elements
    INTERACT_RANGE = 6,          -- m, ui_interactobject menus on the scene elements
    KEY_MENU = "r",              -- not E: that is ui_interactobject's key (KEY_NEXT)
    PED_SKINS = { 7, 9, 10, 11, 12, 13, 14, 15, 17, 19, 20, 21, 22, 23, 24, 25, 26, 29, 30, 40, 41 }, -- new peds get one of these
}

-- Ped poses (setPedAnimation). id is stored in the JSON.
-- loop = false: played once and frozen on the last frame (lying poses).
-- medsys plays its own KO animation on unconscious / arrested patients.
MSM_ANIMS = {
    { id = "none",      label = "None (standing)" },
    { id = "ko_front",  label = "Lying face down",   anim = { "PED", "KO_shot_front" }, loop = false },
    { id = "ko_back",   label = "Lying on back",     anim = { "CRACK", "crckdeth2" }, loop = false },
    { id = "injured",   label = "Injured, rolling",  anim = { "SWEET", "Sweet_injuredloop" }, loop = true },
    { id = "sit",       label = "Sitting on ground", anim = { "BEACH", "ParkSit_M_loop" }, loop = true },
    { id = "crouch",    label = "Crouching",         anim = { "PED", "cower" }, loop = true },
    { id = "hold_side", label = "Holding side",      anim = { "CRACK", "crckidle2" }, loop = true },
    { id = "lean",      label = "Leaning",           anim = { "GANGS", "leanIDLE" }, loop = true },
}

-- Injury types / severities offered by the editor (medsys applyInjury)
MSM_INJURIES = {
    { id = "gunshot",     label = "Gunshot wound / laceration" },
    { id = "fracture",    label = "Fracture" },
    { id = "burn",        label = "Burn" },
    { id = "suffocation", label = "Suffocation" },
}
MSM_SEVERITY = { "Minor", "Serious", "Critical" }

-- medsys setMedicalState keys the editor can preset, applied in this order.
-- presets = values offered in the menu (the last word of the label is the value).
-- The vitals go after pain / bleeding and systolic before diastolic / heart rate: they are set as
-- lasting resting values (MSM_STATE_RESTING) computed from what is already applied.
MSM_STATE_ORDER = { "bloodVolume", "pain", "bleeding", "ivAccess", "spo2", "systolic", "diastolic", "heartRate", "consciousness" }

-- Editor keys sent to medsys as its lasting "resting" keys: a plain systolic / heartRate / ...
-- only sets the current value and the simulation drifts it back to normal within seconds.
MSM_STATE_RESTING = {
    spo2 = "restingSpo2",
    systolic = "restingSystolic",
    diastolic = "restingDiastolic",
    heartRate = "restingHeartRate",
}
MSM_STATE = {
    consciousness = { label = "Consciousness", presets = {
        { "Stable", "stable" }, { "Dazed", "dazed" }, { "Unconscious", "unconscious" },
        { "Clinical death (cardiac arrest)", "clinical_death" } } },
    bloodVolume = { label = "Blood volume", presets = {
        { "5000 ml (full)", 5000 }, { "4250 ml (-15%)", 4250 }, { "3750 ml (-25%)", 3750 },
        { "3250 ml (-35%)", 3250 }, { "2800 ml (-44%)", 2800 } } },
    -- min / max: the menu also offers "Custom value..." in this range (= medsys resting* limits)
    spo2 = { label = "SpO2", min = 1, max = 100, unit = "%", presets = {
        { "98 %", 98 }, { "90 %", 90 }, { "82 %", 82 }, { "72 %", 72 }, { "60 %", 60 } } },
    heartRate = { label = "Heart rate", min = 30, max = 190, unit = "bpm", presets = {
        { "45 bpm", 45 }, { "72 bpm", 72 }, { "110 bpm", 110 }, { "135 bpm", 135 }, { "160 bpm", 160 } } },
    -- the diastolic follows the systolic (about 2/3 of it) unless it is set as well
    systolic = { label = "Systolic BP", min = 40, max = 260, unit = "mmHg", presets = {
        { "60 mmHg", 60 }, { "80 mmHg", 80 }, { "100 mmHg", 100 }, { "120 mmHg", 120 }, { "150 mmHg", 150 },
        { "170 mmHg", 170 }, { "190 mmHg", 190 }, { "210 mmHg", 210 }, { "230 mmHg", 230 } } },
    diastolic = { label = "Diastolic BP", min = 20, max = 160, unit = "mmHg", presets = {
        { "40 mmHg", 40 }, { "55 mmHg", 55 }, { "80 mmHg", 80 }, { "100 mmHg", 100 }, { "115 mmHg", 115 },
        { "130 mmHg", 130 }, { "145 mmHg", 145 } } },
    pain = { label = "Extra pain", presets = {
        { "0", 0 }, { "30", 30 }, { "60", 60 }, { "90", 90 } } },
    bleeding = { label = "Extra bleeding", presets = {
        { "None", 0 }, { "Mild", 1 }, { "Severe", 2 }, { "Critical", 3 } } },
    ivAccess = { label = "IV access", presets = { { "No", false }, { "Yes", true } } },
}

-- Vehicle damage presets of the editor (health + door/panel/light states)
MSM_DAMAGE = {
    { id = "repair", label = "Repaired" },
    { id = "light",  label = "Light damage" },
    { id = "heavy",  label = "Heavy damage (smoking)" },
    { id = "wreck",  label = "Wrecked (doors off)" },
}

-- Vehicle colour presets (primary RGB)
MSM_COLORS = {
    { "White", 245, 245, 245 }, { "Black", 20, 20, 20 }, { "Silver", 165, 170, 175 },
    { "Red", 170, 20, 20 }, { "Blue", 25, 60, 150 }, { "Green", 30, 110, 50 },
    { "Yellow", 220, 190, 30 }, { "Brown", 95, 60, 35 },
}

function msmAnimById(id)
    for _, a in ipairs(MSM_ANIMS) do
        if a.id == id then return a end
    end
    return nil
end

function msmInjuryLabel(id)
    for _, i in ipairs(MSM_INJURIES) do
        if i.id == id then return i.label end
    end
    return tostring(id)
end

function msmStateValueLabel(key, value)
    local def = MSM_STATE[key]
    if not def then return tostring(value) end
    for _, p in ipairs(def.presets) do
        if p[2] == value then return p[1] end
    end
    return def.unit and (tostring(value) .. " " .. def.unit) or tostring(value)
end
