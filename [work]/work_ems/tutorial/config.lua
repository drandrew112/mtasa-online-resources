if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
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
    -- right side, a few metres from the side door (med_equipments) - the equipment must reach them (4 m).
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
        title = L.text("work_ems.config.fall_from_ladder"),
        description = L.text("work_ems.config.man_fell_off_ladder_in_his"),
        caller = L.text("work_ems.config.bystander"),
        priority = 3,
    },

    -- The treat step: every one of these must be done on the patient (s.done keys:
    -- medsys actions, "painkiller" = PAINKILLER given with Medication)
    TREATMENTS = { "bandage", "splint", "iv", "painkiller", "oxygen" },
    PAINKILLER = "fentanyl",

    -- Optional practice on the final card (no patient), any number of times
    GAMES = {
        { id = "arrows", label = L.text("work_ems.config.bandage"), resource = "mg_arrows",
          desc = L.text("work_ems.config.press_arrow_keys_when_arrows_reach") },
        { id = "splinting", label = L.text("work_ems.config.splint"), resource = "mg_splinting",
          desc = L.text("work_ems.config.press_space_when_gauge_needle_is") },
        { id = "cpr", label = L.text("work_ems.config.cpr"), resource = "mg_cpr",
          desc = L.text("work_ems.config.press_space_in_steady_rhythm_100") },
        { id = "iv", label = L.text("work_ems.config.iv_access"), resource = "mg_intravenous",
          desc = L.text("work_ems.config.push_needle_into_vein_then_pull") },
        { id = "airway", label = L.text("work_ems.config.intubation"), resource = "mg_airway",
          desc = L.text("work_ems.config.place_breathing_tube_while_oxygen_level") },
    },
}
end)
