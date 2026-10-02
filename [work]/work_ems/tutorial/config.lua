-- work_ems tutorial module - shared configuration. The texts of the steps are in client/steps.lua.
-- Positions are placeholders: fine-tune them with work_core's /workpos (in a vehicle it prints
-- { x, y, z, rot }).

TUTORIAL = {
    -- true: the tutorial is offered on EVERY duty start, even when it was completed / skipped
    DEBUG = false,

    COMMAND = "tutorial_ems",          -- /tutorial_ems starts it, /tutorial_ems skip ends it
    ACC_KEY = "ems.tutorial",          -- v_mysql account data: true once completed or skipped
    DIMENSION_BASE = 42000,            -- every session gets its own dimension from here
    FADE_TIME = 1.2,                   -- seconds of a camera fade
    CURSOR_KEY = "m",                  -- shows / hides the cursor for the tutorial card buttons
    POLL = 300,                        -- ms, server check of the stretcher steps

    -- The scene: the tutorial starts in this ambulance (driver seat). The patients stand at
    -- vehicle-local offsets { x (right), y (forward) } from it, at the vehicle's height.
    SCENE = {
        vehicle = { 1703.37, -1052.38, 23.96, 110 },
        patientOffset = { 3.2, 0.5 },          -- burn patient, next to the right side
        stretcherPatientOffset = { 2.5, -6.5 }, -- healthy patient, behind the ambulance
    },
    PATIENT_SKINS = { 7, 12, 15, 19, 24, 40, 41, 46, 56, 93 },

    -- After loading the patient the camera fades and the ambulance is parked here
    -- (med_hospitals hospital id; its handover markers are copied into the tutorial dimension)
    HOSPITAL = {
        id = "ls_allsaints",
        vehicle = { 1199.67, -1308.04, 13.45, 90 },
    },

    -- Demo case on the tablet
    CASE = {
        title = "Burned hand",
        description = "A man scalded his hand with boiling water. He is conscious and in pain. "
            .. "The caller is waiting next to him.",
        caller = "Bystander",
        priority = 3,
    },

    -- Minigames of the practice step (no patient). At least MIN_GAMES successful runs are
    -- needed before Continue.
    MIN_GAMES = 1,
    GAMES = {
        { id = "arrows", label = "Bandage", resource = "mg_arrows",
          desc = "Press the arrow keys when the arrows reach the target. Used for bandages, "
              .. "dressings and splints." },
        { id = "cpr", label = "CPR", resource = "mg_cpr",
          desc = "Press SPACE in a steady rhythm (100-120 per minute). Used when the heart has stopped." },
        { id = "iv", label = "IV access", resource = "mg_intravenous",
          desc = "Push the needle into the vein, then pull it back. Needed for fluids and medicines." },
        { id = "airway", label = "Intubation", resource = "mg_airway",
          desc = "Place the breathing tube while the oxygen level falls. On a patient put to sleep (Ketamine) "
              .. "and relaxed (Rocuronium), or in cardiac arrest." },
    },
}
