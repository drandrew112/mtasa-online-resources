if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- med_hospitals - shared configuration. The hospitals themselves are in hospitals.json.

HOSP = {
    FILE = "hospitals.json",

    TICK = 250,                    -- ms, server check of bays / markers / running processes

    -- Ambulance bay (parking marker). The unit's handover starts when its vehicle stops in one.
    BAY_SIZE = 4.0,                -- default marker size (JSON "size" overrides)
    BAY_HEIGHT = 4.0,              -- height of the detection tube
    BAY_MAX_SPEED = 6,             -- km/h: the vehicle counts as parked below this
    BAY_COLOR = { 230, 190, 40, 110 },

    -- Helicopter landing point (hospitals.json "heli"): a bay for helicopters only; the unit's
    -- handover starts when the helicopter has landed on it with a patient aboard, and the
    -- patient is pushed into the hospital's heli handover marker.
    HELI_SIZE = 12.0,
    HELI_HEIGHT = 6.0,
    HELI_COLOR = { 230, 190, 40, 110 },

    -- Ambulances only: any vehicle in a bay that is not an on-duty ERM unit's turns the marker
    -- red, and its driver is fined (v_bank forceTakeMoney, bank may go negative) every interval until it leaves.
    -- Not enforced while med_erm is stopped (on-duty units cannot be told apart).
    BAY_RESTRICTED_COLOR = { 218, 54, 51, 150 },
    BAY_FINE = 500,                -- € per interval
    BAY_FINE_INTERVAL = 10000,     -- ms; the first fine comes one interval after the warning

    -- Stretcher handover marker: the medic pushes the patient in, 5 s
    HANDOVER_SIZE = 1.6,
    HANDOVER_TIME = 5000,
    HANDOVER_COLOR = { 56, 132, 244, 110 },
    -- the marker (and its label) is visible only to the players on duty in this work_core work;
    -- false = visible to everyone. Everyone sees it while work_core is stopped.
    HANDOVER_WORK = "ems",

    -- Treatment (heal) marker: 15 s, medsys healCompletely; free unless the patient pays (gov_health)
    HEAL_SIZE = 1.4,
    HEAL_TIME = 15000,
    HEAL_COLOR = { 46, 160, 67, 110 },

    -- A player patient handed over is put here when the hospital has no "release" point:
    -- next to the heal marker
    RELEASE_OFFSET = { 1.5, 0, 0 },

    -- v_radar objective of setObjectiveToNearestHospital is removed within this distance
    ARRIVE_RADIUS = 30,

    -- /hospreload, /hosppos
    ADMIN_LEVEL = 3,

    -- Client 3D labels
    LABEL_DISTANCE = 30,           -- metres
    LABEL_FULL_DISTANCE = 8,       -- full size up to this distance
    LABEL_MIN_SCALE = 0.55,
    LABEL_HEIGHT = 1.25,           -- metres above the marker position
}

-- Element data on the markers (read by server/markerui.lua)
HOSP_DATA = {
    KIND = "hosp.kind",            -- "bay" | "handover" | "heal"
    NAME = "hosp.name",            -- hospital name
    OCCUPIED = "hosp.occupied",    -- bay: a vehicle is parked in it
    RESTRICTED = "hosp.restricted",-- bay: a non-ambulance vehicle is in it (red marker)
    TUTORIAL = "hosp.tutorial",    -- private tutorial marker: labelled regardless of HANDOVER_WORK
    HELI = "hosp.heli",            -- bay / handover: belongs to the helicopter handover
    PAID = "hosp.paid",            -- heal: the patient pays the treatment (gov_health payer "player")
}

HOSP_TEXT = {
    bay      = { title = L.text("med_hospitals.config.ambulance_bay"),    hint = L.text("med_hospitals.config.park_here_to_start_handover") },
    handover = { title = L.text("med_hospitals.config.patient_handover"), hint = L.text("med_hospitals.config.push_patient_in_on_stretcher") },
    bayRestricted = { title = L.text("med_hospitals.config.ambulances_only"),
                      hint = L.text("med_hospitals.config.leave_bay_fine_every_s", { bay_fine = HOSP.BAY_FINE, bay_fine_interval = HOSP.BAY_FINE_INTERVAL / 1000 }) },
    heliBay  = { title = L.text("med_hospitals.config.helipad"),          hint = L.text("med_hospitals.config.land_here_to_start_handover") },
    heliHandover = { title = L.text("med_hospitals.config.helicopter_patient_handover"), hint = L.text("med_hospitals.config.push_patient_in_on_stretcher") },
    heal     = { title = L.text("med_hospitals.config.treatment"),       hint = L.text("med_hospitals.config.stand_here_s_free_of_charge", { heal_time = HOSP.HEAL_TIME / 1000 }) },
    healPaid = { title = L.text("med_hospitals.config.treatment"),       hint = L.text("med_hospitals.config.stand_here_s_patient_pays", { heal_time = HOSP.HEAL_TIME / 1000 }) },
}
end)
