-- Configuration of medsys_effects: what a player experiences from their own medical state, and
-- the animations forced on every patient (players and peds) by their consciousness.

MEDFX = {
    MEDSYS = "medsys",            -- resource name of the medical system
    EVENTS = "medsys_events",     -- body parts of the injuries come from here (optional)
    TICK = 1000,                  -- ms between two reads of the medical state of the tracked players

    -- Element data (written by the server, read by every client)
    DATA_STATUS = "medic.status", -- medsys: consciousness
    DATA_BREATH = "medic.breath", -- medsys: breathing key (nil = normal)
    DATA_ANIM = "medfx.anim",     -- key of MEDFX_ANIMS the element must play, nil = none
    DATA_BLOCK = "medfx.block",   -- set through setAnimationBlocked: no forced animation
    DATA_STRETCHER = "stretcher.on", -- med_stretcher: the patient lies on a stretcher

    ANIM_CHECK = 400,             -- ms, client: how often the forced animations are checked
    ANIM_STREAM_RANGE = 150,      -- metres, client: farther elements are not checked
}

-- Forced animations. anim = { block, name }, loop, hold = freeze on the last frame.
-- accept = other animations that are good enough for this state, they are left alone
-- (e.g. a med_scenemanager pose that is already lying, or the stretcher's down animation).
-- release = played once when the state ends (the element gets up), nil = just stop.
MEDFX_ANIMS = {
    down = {
        anim = { "PED", "KO_shot_front" }, loop = false, hold = true,
        accept = { { "PED", "KO_shot_front" }, { "PED", "KO_shot_face" }, { "PED", "KO_skid_back" },
            { "PED", "KO_skid_front" }, { "PED", "KO_spin_L" }, { "PED", "KO_spin_R" },
            { "CRACK", "crckdeth1" }, { "CRACK", "crckdeth2" }, { "CRACK", "crckdeth3" },
            { "CRACK", "crckdeth4" }, { "BEACH", "Lay_Bac_Loop" } },
        release = { "PED", "getup_front" },
    },
    -- a dazed ped sits on the ground (a dazed player can still move, see MEDFX_STATES)
    dazed_ped = {
        anim = { "BEACH", "ParkSit_M_loop" }, loop = true,
        accept = { { "BEACH", "ParkSit_M_loop" }, { "BEACH", "ParkSit_W_loop" }, { "PED", "cower" },
            { "SWEET", "Sweet_injuredloop" }, { "CRACK", "crckidle1" }, { "CRACK", "crckidle2" },
            { "CRACK", "crckidle3" }, { "CRACK", "crckidle4" }, { "PED", "IDLE_tired" }, { "PED", "gas_cwr" },
            { "FOOD", "EAT_Vomit_P" }, { "BAR", "dnk_stndM_loop" } },
    },
    -- a confused ped sways on its feet (intoxication, after a seizure, low glucose)
    confused_ped = {
        anim = { "BAR", "dnk_stndM_loop" }, loop = true,
        accept = { { "BAR", "dnk_stndM_loop" }, { "BAR", "dnk_stndF_loop" }, { "FOOD", "EAT_Vomit_P" },
            { "BEACH", "ParkSit_M_loop" }, { "BEACH", "ParkSit_W_loop" }, { "PED", "cower" },
            { "CRACK", "crckidle1" }, { "CRACK", "crckidle2" }, { "CRACK", "crckidle3" }, { "CRACK", "crckidle4" },
            { "GANGS", "leanIDLE" }, { "PED", "IDLE_tired" }, { "PED", "gas_cwr" }, { "SWEET", "Sweet_injuredloop" } },
    },
    -- struggling for air (asthma, COPD, pulmonary oedema, ketoacidosis): bent over, panting
    dyspnea_ped = {
        anim = { "PED", "IDLE_tired" }, loop = true,
        accept = { { "PED", "IDLE_tired" }, { "PED", "gas_cwr" }, { "BEACH", "ParkSit_M_loop" },
            { "BEACH", "ParkSit_W_loop" }, { "GANGS", "leanIDLE" }, { "PED", "cower" },
            { "CRACK", "crckidle1" }, { "CRACK", "crckidle2" }, { "CRACK", "crckidle3" }, { "CRACK", "crckidle4" } },
    },
}

-- Breathing keys (medsys MEDIC_BREATHING) of a patient visibly struggling for air
MEDFX_DYSPNEA = { wheeze = true, laboured = true, crackles = true, kussmaul = true, silent = true }
-- Animation of a dyspnoeic ped that is otherwise up (stable / confused); the down states keep theirs
MEDFX_DYSPNEA_ANIM = { ped = "dyspnea_ped" }
-- What a dyspnoeic player experiences (no running out of breath)
MEDFX_DYSPNEA_PLAYER = { controls = { "sprint", "jump" } }

-- Consciousness -> forced animation key, per element type (nil = no forced animation)
MEDFX_STATE_ANIM = {
    player = { unconscious = "down", clinical_death = "down" },
    ped = { confused = "confused_ped", dazed = "dazed_ped", unconscious = "down", clinical_death = "down" },
}

-- What the local player experiences in each consciousness state
--   lock      = every movement / action control is disabled
--   shake     = camera shake level (0-255)
--   walk      = walking style (server side, synced; 126 = drunk)
--   controls  = extra disabled controls
--   blackout  = black screen with a title / subtitle
MEDFX_STATES = {
    confused = { shake = 20, walk = 126 },
    dazed = { shake = 40, walk = 126, controls = { "sprint", "jump" } },
    unconscious = { lock = true, blackout = { title = "UNCONSCIOUS", sub = "You passed out. Wait for medical help." } },
    clinical_death = { lock = true, blackout = { title = "CLINICAL DEATH",
        sub = "Your heart has stopped. Resuscitation window: %02d:%02d", red = true } },
}

-- Controls disabled while the player is down
MEDFX_LOCK_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "sprint", "crouch", "walk",
    "fire", "aim_weapon", "enter_exit", "enter_passenger", "next_weapon", "previous_weapon",
    "look_behind", "action" }

-- Effects of the injuries. part = body part group (leg / arm / torso / pelvis / head), an exact
-- part ("left_leg") or nil for any part (injuries without a known part, e.g. not from medsys_events).
-- untreated / treated = { controls = {...}, walk = style, shake = level }
MEDFX_INJURY_EFFECTS = {
    { type = "fracture", part = "leg",
        untreated = { controls = { "sprint", "jump" }, walk = 120 },   -- 120 = old man (limping)
        treated = { controls = { "sprint" } } },
    { type = "fracture", part = "arm",
        untreated = { controls = { "aim_weapon", "fire" } } },
    { type = "fracture", part = "pelvis",
        untreated = { controls = { "sprint", "jump", "crouch" }, walk = 120 },
        treated = { controls = { "sprint", "jump" } } },
}

MEDFX_PART_GROUP = { head = "head", torso = "torso", pelvis = "pelvis", left_arm = "arm",
    right_arm = "arm", left_leg = "leg", right_leg = "leg" }

-- Screen effects of the vitals (client). A value between `from` and `to` gives 0-100% strength.
MEDFX_SCREEN = {
    pain = { from = 30, to = 100, alpha = 120 },     -- red edge pulsing with the heartbeat
    painShake = { from = 70, level = 15 },           -- camera shake above this pain
    bleeding = { alpha = { 50, 90, 140 } },          -- blood at the edges per bleeding level 1-3
    spo2 = { from = 93, to = 70, alpha = 200 },      -- the vision narrows (dark tunnel)
    blood = { from = 85, to = 55, alpha = 150 },     -- blood volume %: the picture goes pale / grey
    hit = { time = 450, alpha = 110, shake = 60, shakeTime = 300 }, -- flash when a new injury arrives
}

-- Admin test module (server/test.lua, client/test.lua)
--   /medfx           opens the menu: visual preview, real medsys changes on yourself, animation peds
MEDFX_TEST = {
    ENABLED = true,               -- turn off in production
    MIN_ADMIN_LEVEL = 4,          -- admin_level above 3 (v_mysql account data)
    COMMAND = "medfx",
    MAX_PEDS = 6,                 -- per admin
    SPAWN_DISTANCE = 2.0,
    SKINS = { 7, 9, 10, 11, 12, 15, 17, 19, 20, 21, 22, 23, 24, 25, 29, 30 },
}

function medfxPartMatches(effectPart, part)
    if effectPart == nil then return true end
    return effectPart == part or (part ~= nil and effectPart == MEDFX_PART_GROUP[part])
end
