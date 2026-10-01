-- med_hospitals - shared configuration. The hospitals themselves are in hospitals.json.

HOSP = {
    FILE = "hospitals.json",

    TICK = 250,                    -- ms, server check of bays / markers / running processes

    -- Ambulance bay (parking marker). The unit's handover starts when its vehicle stops in one.
    BAY_SIZE = 4.0,                -- default marker size (JSON "size" overrides)
    BAY_HEIGHT = 4.0,              -- height of the detection tube
    BAY_MAX_SPEED = 6,             -- km/h: the vehicle counts as parked below this
    BAY_COLOR = { 230, 190, 40, 110 },

    -- Ambulances only: any vehicle in a bay that is not an on-duty ERM unit's turns the marker
    -- red, and its driver is fined (v_bank forceTakeMoney, bank may go negative) every interval until it leaves.
    -- Not enforced while med_erm is stopped (on-duty units cannot be told apart).
    BAY_RESTRICTED_COLOR = { 218, 54, 51, 150 },
    BAY_FINE = 500,                -- $ per interval
    BAY_FINE_INTERVAL = 10000,     -- ms; the first fine comes one interval after the warning

    -- Stretcher handover marker: the medic pushes the patient in, 5 s
    HANDOVER_SIZE = 1.6,
    HANDOVER_TIME = 5000,
    HANDOVER_COLOR = { 56, 132, 244, 110 },

    -- Free treatment (heal) marker: 15 s, medsys healCompletely
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

-- Element data on the markers (read by client/labels.lua)
HOSP_DATA = {
    KIND = "hosp.kind",            -- "bay" | "handover" | "heal"
    NAME = "hosp.name",            -- hospital name
    OCCUPIED = "hosp.occupied",    -- bay: a vehicle is parked in it
    RESTRICTED = "hosp.restricted",-- bay: a non-ambulance vehicle is in it (red marker)
}

HOSP_TEXT = {
    bay      = { title = "Ambulance Bay",    hint = "Park here to start the handover" },
    handover = { title = "Patient Handover", hint = "Push the patient in on the stretcher" },
    bayRestricted = { title = "Ambulances Only",
                      hint = ("Leave the bay · $%d fine every %d s"):format(HOSP.BAY_FINE, HOSP.BAY_FINE_INTERVAL / 1000) },
    heal     = { title = "Treatment",       hint = ("Stand here · %d s · free of charge"):format(HOSP.HEAL_TIME / 1000) },
}
