if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Scene Manager - shared configuration. Every label is a v_locals key (v_scenemanager.*): the client shows it with
-- L(), the server sends it as L.msg() and v_locals resolves it in the player's language.

VSM = {
    ERM = "med_erm",            -- EMS dispatch resource (tasks, units)
    POLICE = "police_system",   -- police resource (calls, units, records)
    MEDSYS = "medsys",          -- medical resource (injuries, vitals)
    AIPEDS = "ai_peds",         -- AI peds (fighters, hostiles)

    SCENE_DIR = "scenes/",      -- scenes/<Settlement>/[<category>/]<name>.json
    INDEX_FILE = "scenes/index.json", -- list of scene paths (MTA cannot list a directory)
    ISSUES_FILE = "scenes/issues.json", -- flagged scenes (/flagscene, web Flag)
    -- Settlement folder: the city (getZoneName citiesonly) for these, the zone name
    -- (village, area) anywhere else. Spaces -> _, apostrophes dropped: Los_Santos, Lil_Probe_Inn
    CITY_FOLDERS = { ["Los Santos"] = true, ["San Fierro"] = true, ["Las Venturas"] = true },
    INTERIOR_FOLDER = "Interiors", -- scenes with interior ~= 0 (zone names are meaningless there)
    NAME_PATTERN = "^[%w_%-]+$",
    NAME_MAX = 40,

    MIN_ADMIN_LEVEL = 4,        -- v_mysql admin_level for every command / the editor (not /flagscene)

    -- Commands
    CMD_EDITOR = "sceneeditor",
    CMD_RANDOM = "scenerandom",   -- /scenerandom [scene name]
    CMD_SUMMON = "scenesummon",   -- pick & spawn an exact scene from a menu
    CMD_AUTO = "sceneauto",       -- /sceneauto [on|off]
    CMD_LIST = "scenelist",       -- active scenes
    CMD_CLEAR = "sceneclear",     -- /sceneclear [instance id | all]
    CMD_RELOAD = "scenereload",   -- re-read the scene files
    CMD_VARIETY = "scenevariety", -- /scenevariety [sim [n] | clear]
    CMD_FLAG = "flagscene",       -- /flagscene <reason...> (everyone)

    DEFAULT_LANG = "en",
    LANGS = { "en", "hu" },     -- every agency text needs all of these (validation)
    DEFAULT_CALLER = "SceneManager",
    DEFAULT_PRIORITY = 2,

    -- Live scenes
    DATA_NAME = "medic.name",    -- random first name of a live scene ped (shared/names.lua), shown by medsys
    DATA_SCENE = "vsm.scene",    -- instance id on every live scene element (not synced)
    DATA_ROLLED = "vsm.rolled",  -- rolled record values of a ped (bac, drug, age), read by police_system + medsys
    MEDSYS_DELAY = 300,          -- ms after spawning before the injuries are applied (client sync)
    CLEANUP_DELAY = 30,          -- s after every task closed before the scene may be removed...
    CLEANUP_RANGE = 120,         -- ...once no player is within this many metres of it
    CLEANUP_FORCE = 600,         -- s after every task closed: removed even with players around
    MAX_LIFETIME = 60 * 60,      -- s, a scene whose tasks never close is closed + removed
    CHECK_INTERVAL = 5000,       -- ms, cleanup + generator + late join tick
    -- getSceneAt: a point within this many metres of an open scene (centre, peds,
    -- vehicles) belongs to it - e.g. ui_phone refuses an ambulance call there
    CALL_RADIUS = 80,
    FALSE_CALL_CLOSE = 45,       -- s after the first EMS unit is On Scene, a scene without patients closes its task

    -- Agencies, in this order (spawn, links, menus). need: 0 = not needed, 1 = needed (sent when a unit is free),
    -- 2 = mandatory (the generator spawns the scene only when a free unit is in range).
    AGENCY_ORDER = { "ems", "pd" },
    AGENCIES = {
        ems = {
            label = "v_scenemanager.agency.ems",
            MAX_UNIT_DISTANCE = 1500, -- 2D, m from the nearest free unit; 0 = no limit
            RATE = 1,                 -- weight of a free unit in the generator pace
            PENDING_PER_UNIT = 1,     -- waiting (not yet assigned) scene tasks allowed per free unit
            LATE_JOIN = 600,          -- s: a need-1 agency without a free unit at spawn still gets the task this long
            UNIT_TYPES = nil,         -- nil = every unit type counts as free, or e.g. { "ALS", "BLS" }
        },
        pd = {
            label = "v_scenemanager.agency.pd",
            MAX_UNIT_DISTANCE = 1800,
            RATE = 1,
            PENDING_PER_UNIT = 1,
            LATE_JOIN = 600,
        },
    },

    -- Safe scene (server/safety.lua): only a scene with EMS 2 + PD 2 can start "not safe" (scene.safe = false).
    SAFETY = {
        TICK = 1000,             -- ms
        CONFIRM_RADIUS = 40,     -- m: an officer this close to the centre makes the automatic "safe" possible
        ACTIVE_RADIUS = 50,      -- m: an active threat this close blocks the manual report
        FLED_RADIUS = 120,       -- m: a threat farther than this from the centre...
        FLED_TIME = 30,          -- s: ...for this long counts as gone
        SURRENDER_CONTROL = 15,  -- m: a surrendered threat counts as controlled with an officer this close
        TRACKER_RADIUS = 150,    -- m: officers of the call this close see the "not secured" HUD tracker
        STAGING_MIN = 100,       -- m: staging point distance from the centre (EMS waits there)
        STAGING_MAX = 170,
    },

    -- NPC roles (server/npc.lua)
    NPC = {
        FIGHT_START_RADIUS = 150, -- m: "unit_near" fights start when a dispatched unit is this close
        POLICE_REACT_RADIUS = 25, -- m: fighters react to an officer this close (stop / flee / continue)
        SURRENDER_ANIM = { "ped", "handsup" },
        TICK = 1000,              -- ms
        FLEE_SEEN_RADIUS = 30,    -- m: a suspect with a flee chance rolls it once when an officer gets this close
    },

    -- Flag scene (server/issues.lua)
    FLAG = {
        RADIUS = 80,             -- m from a live scene (centre, peds, vehicles)
        MIN_LEN = 5,
        MAX_LEN = 200,
        COOLDOWN = 60,           -- s between two reports of one player
        SAVE_DELAY = 2000,       -- ms, writes of a burst are merged
    },

    -- Automatic generator. It only works while an agency has free units; the average gap between two scenes is
    -- divided by the free units (each weighted by its agency's RATE).
    AUTO = {
        INTERVAL_MIN = 90,       -- s between two scenes with ONE free unit
        INTERVAL_MAX = 240,
        MAX_ACTIVE = 12,         -- live scenes at once (any source)
        MIN_PLAYER_DISTANCE = 150, -- no scene closer than this to any player (pop-in)
        MIN_SCENE_DISTANCE = 60, -- no scene closer than this to another live scene
    },

    -- Scene variety (server/variety.lua): history of the spawned scenes, global and per
    -- account, and the rules of the random pick. A "location" is a position: scenes whose
    -- centres are within LOCATION_RADIUS are the same location, whatever their names.
    -- The rules below exclude candidates; while nothing is left they are dropped in this
    -- order: category repeat -> global history -> player history -> geographic spread.
    -- The mandatory checks (agencies, players, live scenes, unit distance) are never dropped.
    VARIETY = {
        ENABLED = true,          -- false = plain weighted random pick (old behaviour)
        FILE = "data/variety.json", -- server side history file
        RETENTION = 24 * 60 * 60, -- s, history entries older than this are deleted
        SAVE_INTERVAL = 60,      -- s, the file is written this often when something changed
        GLOBAL_MAX = 400,        -- entries kept in the global history
        PLAYER_MAX = 60,         -- entries kept per account
        LOCATION_RADIUS = 35,    -- m (2D), two centres closer than this are the same location

        -- exclusion rules (windows = the last N entries of the history)
        GLOBAL = { scenes = 25, locations = 12, categoryRepeat = 1, categoryWindow = 20, spread = 3 },
        PLAYER = { scenes = 15, locations = 8, categoryRepeat = 2, categoryWindow = 10, spread = 2 },
        MIN_SPREAD = 250,        -- m (2D), no scene this close to the last `spread` locations

        -- weights of the remaining candidates (they never exclude anything)
        BALANCE_CATEGORIES = true, -- every category gets the same chance, whatever its scene count
        CATEGORY_WEIGHT = {},    -- extra multiplier per category, e.g. { ["false"] = 0.5 }
        CATEGORY_K_GLOBAL = 0.5, -- weight / (1 + k * uses of the category in its window)
        CATEGORY_K_PLAYER = 0.8,
        LOCATION_K = 1.0,        -- weight / (1 + k * decayed uses of the location)
        LOCATION_HALF_LIFE = 2 * 60 * 60, -- s, a location use counts half after this long
        SPREAD_BONUS_RANGE = 800, -- m, farther than this from the last locations = full weight
        SPREAD_BONUS_MIN = 0.25, -- weight multiplier right next to the last locations
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
VSM_ANIMS = {
    { id = "none",      label = "v_scenemanager.anim.none" },
    { id = "ko_front",  label = "v_scenemanager.anim.ko_front",  anim = { "PED", "KO_shot_front" }, loop = false },
    { id = "ko_back",   label = "v_scenemanager.anim.ko_back",   anim = { "CRACK", "crckdeth2" }, loop = false },
    { id = "injured",   label = "v_scenemanager.anim.injured",   anim = { "SWEET", "Sweet_injuredloop" }, loop = true },
    { id = "sit",       label = "v_scenemanager.anim.sit",       anim = { "BEACH", "ParkSit_M_loop" }, loop = true },
    { id = "crouch",    label = "v_scenemanager.anim.crouch",    anim = { "PED", "cower" }, loop = true },
    { id = "hold_side", label = "v_scenemanager.anim.hold_side", anim = { "CRACK", "crckidle2" }, loop = true },
    { id = "lean",      label = "v_scenemanager.anim.lean",      anim = { "GANGS", "leanIDLE" }, loop = true },
    -- breathing difficulty / intoxication
    { id = "tired",     label = "v_scenemanager.anim.tired",     anim = { "PED", "IDLE_tired" }, loop = true },
    { id = "cough",     label = "v_scenemanager.anim.cough",     anim = { "PED", "gas_cwr" }, loop = true },
    { id = "drunk",     label = "v_scenemanager.anim.drunk",     anim = { "BAR", "dnk_stndM_loop" }, loop = true },
    { id = "vomit",     label = "v_scenemanager.anim.vomit",     anim = { "FOOD", "EAT_Vomit_P" }, loop = true },
}

-- Scene categories: subfolder inside the settlement folder. "" = no category (no subfolder).
-- A file without a "category" key gets the first id found in its name.
VSM_CATEGORIES = {}
for _, id in ipairs({ "heartattack", "mva", "hypertension", "stroke", "diabetes", "hypoglycemia", "overdose",
        "breathing", "fall", "shooting", "hitbycar", "motorcycle", "drowning", "mci", "airport", "false", "deadbody",
        "brawl", "armed", "wanted",
        -- police scene types (2026-11-05)
        "dui", "hitandrun", "stolenvehicle", "abandoned", "robbery", "burglary",
        "shoplifting", "domestic", "disturbance", "drugs", "vandalism", "suspicious" }) do
    VSM_CATEGORIES[#VSM_CATEGORIES + 1] = { id = id, label = "v_scenemanager.cat." .. id }
end

-- Injury types / severities offered by the editor (medsys applyInjury)
VSM_INJURIES = {}
for _, id in ipairs({ "gunshot", "fracture", "burn", "suffocation", "head_injury",
        -- medical conditions (medsys shows only their findings)
        "stroke", "opioid", "sedative", "stimulant", "alcohol", "postictal", "asthma", "copd", "pulmonary_edema" }) do
    VSM_INJURIES[#VSM_INJURIES + 1] = { id = id, label = "v_scenemanager.injury." .. id }
end
VSM_SEVERITY = { "v_scenemanager.severity.1", "v_scenemanager.severity.2", "v_scenemanager.severity.3" }

-- Ped roles (editor, validation, safety). A threat is what can make a scene unsafe.
VSM_ROLES = {
    { id = "patient",   label = "v_scenemanager.role.patient" },
    { id = "bystander", label = "v_scenemanager.role.bystander" },
    { id = "fighter",   label = "v_scenemanager.role.fighter",  ai = true, threat = true },
    { id = "hostile",   label = "v_scenemanager.role.hostile",  ai = true, threat = true },
    { id = "suspect",   label = "v_scenemanager.role.suspect",  ai = true },
}

-- Drugs of a record: police flag + the medsys condition (nil = police only)
VSM_DRUGS = {
    { id = "stimulant", medsys = "stimulant", label = "v_scenemanager.drug.stimulant" },
    { id = "opioid",    medsys = "opioid",    label = "v_scenemanager.drug.opioid" },
    { id = "sedative",  medsys = "sedative",  label = "v_scenemanager.drug.sedative" },
    { id = "cannabis",  label = "v_scenemanager.drug.cannabis" },
}
VSM_BAC_MAX = 4.0     -- same unit as police_system flags.bac
-- medsys "alcohol" severity from the rolled value (>= value -> severity)
VSM_BAC_SEVERITY = { { 2.5, 3 }, { 1.5, 2 }, { 0.5, 1 } }

-- Editor presets of the record / AI menus
VSM_BAC_PRESETS = { { 0, 0 }, { 0.2, 0.5 }, { 0.5, 1.0 }, { 0.8, 1.6 }, { 1.5, 2.5 }, { 2.5, 3.5 } }
VSM_AGE_PRESETS = { { 18, 25 }, { 24, 38 }, { 35, 50 }, { 45, 65 }, { 60, 80 } }
VSM_DAYS_PRESETS = { { 10, 60 }, { 30, 180 }, { 180, 420 } }
VSM_WEAPONS = { 0, 4, 5, 8, 22, 24, 25, 28, 30 }   -- 0 = fists
VSM_LICENCES = { "valid", "suspended", "none" }
VSM_FIGHT_START = { "spawn", "unit_near" }
VSM_ON_POLICE = { "stop", "flee", "continue" }
VSM_TARGETS = { "police", "all" }
VSM_HOSTILE_TASKS = { "guard", "idle" }
VSM_INSPECTIONS = { "valid", "expired" }
VSM_PD_CLOSE = { "towed", "suspects" }   -- automatic PD call close conditions
VSM_FLEE_PRESETS = { 0, 0.2, 0.5, 1 }
VSM_SURRENDER_PRESETS = { 0, 20, 30, 50 }

-- medsys setMedicalState keys the editor can preset, applied in this order.
-- presets = values offered in the menu ({ label key | plain text, value }).
-- The vitals go after pain / bleeding and systolic before diastolic / heart rate: they are set as
-- lasting resting values (VSM_STATE_RESTING) computed from what is already applied.
-- rhythm goes last: a pulseless one is a cardiac arrest in that rhythm (medsys MEDIC_RHYTHMS)
-- glucose goes before the vitals: a low / high one moves the pulse and the consciousness
VSM_STATE_ORDER = { "bloodVolume", "pain", "bleeding", "ivAccess", "glucose", "spo2", "systolic", "diastolic", "heartRate", "consciousness", "rhythm" }

-- Editor keys sent to medsys as its lasting "resting" keys: a plain systolic / heartRate / ...
-- only sets the current value and the simulation drifts it back to normal within seconds.
VSM_STATE_RESTING = {
    spo2 = "restingSpo2",
    systolic = "restingSystolic",
    diastolic = "restingDiastolic",
    heartRate = "restingHeartRate",
}
local function K(s) return "v_scenemanager.state." .. s end
VSM_STATE = {
    consciousness = { label = K("consciousness"), presets = {
        { K("c_stable"), "stable" }, { K("c_confused"), "confused" }, { K("c_dazed"), "dazed" }, { K("c_unconscious"), "unconscious" },
        { K("c_clinical_death"), "clinical_death" }, { K("c_dead"), "dead" } } },
    bloodVolume = { label = K("bloodVolume"), presets = {
        { "5000 ml", 5000 }, { "4250 ml (-15%)", 4250 }, { "3750 ml (-25%)", 3750 },
        { "3250 ml (-35%)", 3250 }, { "2800 ml (-44%)", 2800 } } },
    -- min / max: the menu also offers "Custom value..." in this range (= medsys resting* limits)
    spo2 = { label = K("spo2"), min = 1, max = 100, unit = "%", presets = {
        { "98 %", 98 }, { "90 %", 90 }, { "82 %", 82 }, { "72 %", 72 }, { "60 %", 60 } } },
    heartRate = { label = K("heartRate"), min = 30, max = 190, unit = "bpm", presets = {
        { "45 bpm", 45 }, { "72 bpm", 72 }, { "110 bpm", 110 }, { "135 bpm", 135 }, { "160 bpm", 160 } } },
    -- the diastolic follows the systolic (about 2/3 of it) unless it is set as well
    systolic = { label = K("systolic"), min = 40, max = 260, unit = "mmHg", presets = {
        { "60 mmHg", 60 }, { "80 mmHg", 80 }, { "100 mmHg", 100 }, { "120 mmHg", 120 }, { "150 mmHg", 150 },
        { "170 mmHg", 170 }, { "190 mmHg", 190 }, { "210 mmHg", 210 }, { "230 mmHg", 230 } } },
    diastolic = { label = K("diastolic"), min = 20, max = 160, unit = "mmHg", presets = {
        { "40 mmHg", 40 }, { "55 mmHg", 55 }, { "80 mmHg", 80 }, { "100 mmHg", 100 }, { "115 mmHg", 115 },
        { "130 mmHg", 130 }, { "145 mmHg", 145 } } },
    -- blood glucose mg/dL (lasting: the patient drifts back to it), medsys "glucose"
    glucose = { label = K("glucose"), min = 10, max = 900, unit = "mg/dL", presets = {
        { "25 mg/dL", 25 }, { "40 mg/dL", 40 }, { "55 mg/dL", 55 }, { "95 mg/dL", 95 },
        { "280 mg/dL", 280 }, { "450 mg/dL", 450 }, { "600 mg/dL", 600 } } },
    pain = { label = K("pain"), presets = {
        { "0", 0 }, { "30", 30 }, { "60", 60 }, { "90", 90 } } },
    bleeding = { label = K("bleeding"), presets = {
        { K("b_none"), 0 }, { K("b_mild"), 1 }, { K("b_severe"), 2 }, { K("b_critical"), 3 } } },
    ivAccess = { label = K("ivAccess"), presets = { { "v_scenemanager.common.no", false }, { "v_scenemanager.common.yes", true } } },
    rhythm = { label = K("rhythm"), presets = {
        { K("r_sinus"), "SINUS" }, { K("r_sinus_brady"), "SINUS_BRADY" },
        { K("r_sinus_tachy"), "SINUS_TACHY" }, { "SVT", "SVT" }, { K("r_vt_pulse"), "VT_WITH_PULSE" },
        { K("r_vf"), "VF" }, { K("r_pvt"), "PULSELESS_VT" },
        { K("r_pea"), "PEA" }, { K("r_asystole"), "ASYSTOLE" } } },
}

-- Vehicle damage presets of the editor (health + door/panel/light states)
VSM_DAMAGE = {
    { id = "repair", label = "v_scenemanager.damage.repair" },
    { id = "light",  label = "v_scenemanager.damage.light" },
    { id = "heavy",  label = "v_scenemanager.damage.heavy" },
    { id = "wreck",  label = "v_scenemanager.damage.wreck" },
}

-- Vehicle colour presets (primary RGB)
VSM_COLORS = {
    { "v_scenemanager.color.white", 245, 245, 245 }, { "v_scenemanager.color.black", 20, 20, 20 },
    { "v_scenemanager.color.silver", 165, 170, 175 }, { "v_scenemanager.color.red", 170, 20, 20 },
    { "v_scenemanager.color.blue", 25, 60, 150 }, { "v_scenemanager.color.green", 30, 110, 50 },
    { "v_scenemanager.color.yellow", 220, 190, 30 }, { "v_scenemanager.color.brown", 95, 60, 35 },
}

---------------------------------------------------------------- lookups

local function byId(list, id)
    for _, e in ipairs(list) do
        if e.id == id then return e end
    end
    return nil
end

function vsmAnimById(id) return byId(VSM_ANIMS, id) end
function vsmRoleById(id) return byId(VSM_ROLES, id) end
function vsmDrugById(id) return byId(VSM_DRUGS, id) end

function vsmInjuryLabel(id)
    local i = byId(VSM_INJURIES, id)
    return i and i.label or tostring(id)
end

-- a label of the tables above: a v_locals key (translated) or a plain text (units, numbers)
function vsmText(label, params)
    if type(label) == "string" and label:find("^v_scenemanager%.") then
        if localPlayer then return L(label, params) end
        return L.msg(label, params)
    end
    return tostring(label)
end

function vsmStateValueLabel(key, value)
    local def = VSM_STATE[key]
    if not def then return tostring(value) end
    for _, p in ipairs(def.presets) do
        if p[2] == value then return vsmText(p[1]) end
    end
    return def.unit and (tostring(value) .. " " .. def.unit) or tostring(value)
end

function vsmRange(value)
    if type(value) == "table" then return value[1], value[2] or value[1] end
    return value, value
end
