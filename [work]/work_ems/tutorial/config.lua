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
    CURSOR_KEY = "F2",                 -- shows / hides the cursor for the tutorial card buttons
    POLL = 300,                        -- ms, server check of the stretcher steps

    -- The scene: the tutorial starts in this ambulance (driver seat). The patient stands at a
    -- vehicle-local offset { x (right), y (forward) } from it, at the vehicle's height: next to the
    -- right side, a few metres from the side door (med_bag) - the equipment must reach them (4 m).
    SCENE = {
        vehicle = { 1703.37, -1052.38, 23.96, 110 },
        patientOffset = { 3.2, 0.5 },
        injuries = { { "burn", 1 }, { "fracture", 1 } },   -- medsys applyInjury(type, severity)
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
        title = "Fall from a ladder",
        description = "A man fell off a ladder in his kitchen and knocked over a pot of boiling water. "
            .. "His arm is burned and his leg hurts badly. He is conscious. The caller is waiting next to him.",
        caller = "Bystander",
        priority = 3,
    },

    -- The treat step: every one of these must be done on the patient (s.done keys:
    -- medsys actions, "painkiller" = PAINKILLER given with Medication)
    TREATMENTS = { "bandage", "splint", "iv", "painkiller", "oxygen" },
    PAINKILLER = "fentanyl",

    -- Optional practice on the final card (no patient), any number of times
    GAMES = {
        { id = "arrows", label = "Bandage", resource = "mg_arrows",
          desc = "Press the arrow keys when the arrows reach the target. Used for bandages and dressings." },
        { id = "splinting", label = "Splint", resource = "mg_splinting",
          desc = "Press SPACE when the gauge needle is centred to cinch each wrap. Used for fractures." },
        { id = "cpr", label = "CPR", resource = "mg_cpr",
          desc = "Press SPACE in a steady rhythm (100-120 per minute). Used when the heart has stopped. "
              .. "On a patient, good compressions can change the heart rhythm: the game stops and the panel "
              .. "shows the new rhythm." },
        { id = "iv", label = "IV access", resource = "mg_intravenous",
          desc = "Push the needle into the vein, then pull it back. Needed for fluids and medicines." },
        { id = "airway", label = "Intubation", resource = "mg_airway",
          desc = "Place the breathing tube while the oxygen level falls. On a patient put to sleep (Ketamine) "
              .. "and relaxed (Rocuronium), or in cardiac arrest." },
    },
}
