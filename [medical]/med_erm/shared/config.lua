if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- Emergency Response Manager - shared configuration

Config = {}

-- Key that opens/closes the unit tablet.
Config.TABLET_KEY = "j"

-- Vehicle models the tablet can be opened in while NOT signed in.
-- 416 = Mercedes Sprinter (HU), 456 = Mission Row Ambulance, 563 = Raindance (air ambulance for HELI units).
Config.TABLET_VEHICLES = {
    [416] = true,
    [456] = true,
    [487] = true,
    [563] = true,
    [598] = true,
    [582] = true,
    [483] = true,
}

-- Unit types selectable on the sign-in screen.
Config.UNIT_TYPES = { "SOLO", "DOC", "BLS", "ALS", "HELI", "SUP" }

-- Supervisor units: never get tasks from auto dispatch and do not count as free units for v_scenemanager
-- (getFreeUnits skips these types unless the caller names them in its type filter).
Config.NON_DISPATCH_TYPES = { SUP = true }

-- Unit types allowed per vehicle model (sign-in screen + server check).
-- 598 = Skoda Octavia (SOLO/DOC), 487/563 = helicopters (HELI); any other
-- tablet vehicle (ambulance) gets UNIT_TYPES_DEFAULT.
Config.UNIT_VEHICLE_TYPES = {
    [598] = { "SOLO", "DOC", "SUP" },
    [487] = { "HELI" },
    [563] = { "HELI" },
}
Config.UNIT_TYPES_DEFAULT = { "BLS", "ALS" }

-- Competencies (work_core, registered by work_ems). A unit type needs at least ONE crew member with
-- this competency (or higher); lower competencies can always be added to the crew. Without work_core
-- / without the work's competencies nothing is required.
Config.COMPETENCY_WORK = "ems"
Config.UNIT_COMPETENCY = { BLS = "a", SOLO = "b", ALS = "bplus", DOC = "c", HELI = "c", SUP = "e" }  -- SUP: chief physician (E) only

-- med_equipments level put into the unit's vehicle at sign-in ("basic" = only the stretcher again at
-- sign-out). Only vehicles that already carry an equipment level (work_ems duty vehicles) get one.
Config.UNIT_EQUIPMENT = { BLS = "bls", SOLO = "bls", ALS = "als", DOC = "als", HELI = "als", SUP = "als" }
Config.EQUIPMENT_SIGNED_OUT = "basic"

-- Unit types selectable in a vehicle of the given model.
function Config.unitTypesFor(model)
    return Config.UNIT_VEHICLE_TYPES[model] or Config.UNIT_TYPES_DEFAULT
end

-- Supervisor (SUP unit) fines (server/fines.lua, tablet page "Supervisor"): a SUP unit fines any other signed-in
-- unit. Fines live only on the unit (gone after its shift) and are deducted from the shift-end pay as separate
-- items (server/payment.lua). label = v_locals key.
Config.FINES = {
    { id = "harm",      amount = 1500, label = "med_erm.fine.harm" },
    { id = "neglect",   amount = 1000, label = "med_erm.fine.neglect" },
    { id = "protocol",  amount = 800,  label = "med_erm.fine.protocol" },
    { id = "drugs",     amount = 700,  label = "med_erm.fine.drugs" },
    { id = "equipment", amount = 800,  label = "med_erm.fine.equipment" },
    { id = "vehicle",   amount = 500,  label = "med_erm.fine.vehicle" },
    { id = "handover",  amount = 900,  label = "med_erm.fine.handover" },
    { id = "response",  amount = 900,  label = "med_erm.fine.response" },
}
Config.FINE_BY_ID = {}
for _, f in ipairs(Config.FINES) do Config.FINE_BY_ID[f.id] = f end
Config.FINE_MAX_PER_UNIT = 30

-- Backup request on the Active Case page: the crew picks one option, the nearest free unit of its
-- types (by distance to the scene) is assigned to the case. label = v_locals key.
Config.BACKUP_OPTIONS = {
    { id = "AMB",  types = { "BLS", "ALS" }, label = "med_erm.backup.opt_ambulance" },
    { id = "BLS",  types = { "BLS" },        label = "med_erm.backup.opt_bls" },
    { id = "ALS",  types = { "ALS" },        label = "med_erm.backup.opt_als" },
    { id = "DOC",  types = { "DOC" },        label = "med_erm.backup.opt_doc" },
    { id = "HELI", types = { "HELI" },       label = "med_erm.backup.opt_heli" },
    { id = "SOLO", types = { "SOLO" },       label = "med_erm.backup.opt_solo" },
}
-- Minimum time (ms) between two successful backup requests of a unit.
Config.BACKUP_COOLDOWN = 15000

-- Request agency (Active Case, left of Request Backup): the police (police_system) with one of these reasons.
-- label = v_locals key; note = a text is required. The call text is made in every language of AGENCY_LANGS.
Config.AGENCY_REASONS = {
    { id = "security", label = "med_erm.agency.reason_security" },
    { id = "traffic",  label = "med_erm.agency.reason_traffic" },
    { id = "violent",  label = "med_erm.agency.reason_violent" },
    { id = "crime",    label = "med_erm.agency.reason_crime" },
    { id = "death",    label = "med_erm.agency.reason_death" },
    { id = "other",    label = "med_erm.agency.reason_other", note = true },
}
Config.AGENCY_LANGS = { "en", "hu" }
Config.AGENCY_COOLDOWN = 30000

-- Safe scene (meta.safety of v_scenemanager scenes): while "unsafe" the crew is warned when it gets within
-- STAGING_WARN of the scene (once, tablet window + sound), and every STAGING_REPEAT ms within STAGING_MIN;
-- the radar objective points at the staging point (meta.safety.staging) instead of the scene.
Config.STAGING_WARN = 200
Config.STAGING_MIN = 100
Config.STAGING_REPEAT = 15000

-- Radius (metres) in which other players can be added to a crew.
Config.ADD_MEMBER_RADIUS = 10

-- Scene radius (metres). Within it the radar objective of the task is removed
-- and the unit switches to On Scene automatically (only at its own task).
Config.ARRIVE_RADIUS = 30

-- Distance (metres) from the scene after which a unit that reached it counts as
-- departed: the crew gets a radar objective to the nearest hospital (med_hospitals),
-- removed when the unit gets the Handover status. Coming back within ARRIVE_RADIUS
-- sets On Scene again and removes it until the next departure.
Config.HOSPITAL_DEPART_RADIUS = 50

-- Speed (km/h) above which Start Response is switched on automatically when the
-- driver of a unit with an active case drives off (to the scene, or away from it).
Config.RESPONSE_AUTO_SPEED = 5

-- Minimum admin_level (v_mysql account data) for /ermadmin.
Config.ADMIN_LEVEL = 1

-- Hospital handover duration; afterwards the server frees the unit.
Config.HANDOVER_TIME = 30000

-- Chat history kept in memory (messages are not persisted).
Config.MAX_MESSAGES = 500

-- Closed tasks shown on the dispatcher page.
Config.RECENT_CLOSED = 30

-- Unit statuses.
Config.STATUS = {
    available = { label = L.text("med_erm.config.available"), color = { 46, 160, 67 } },   -- green
    enroute   = { label = L.text("med_erm.config.en_route"),  color = { 218, 54, 51 } },   -- red
    onscene   = { label = L.text("med_erm.config.on_scene"),  color = { 56, 132, 244 } },  -- blue
    handover  = { label = L.text("med_erm.config.handover"),  color = { 230, 190, 40 } },  -- yellow
    ["break"] = { label = L.text("med_erm.config.break"),     color = { 245, 140, 30 } },  -- orange
}

-- Break request (Requests on the tablet's Home page): an available unit can ask for a break every
-- COOLDOWN seconds (counted from the start of its last break); it lasts DURATION seconds and the unit can end it
-- any time. Auto dispatch grants it at once, otherwise a dispatcher approves it. A pending request expires when the
-- unit gets a case - no cooldown then.
Config.BREAK = { DURATION = 20 * 60, COOLDOWN = 2 * 60 * 60 }

Config.PRIORITY_COLORS = {
    [1] = { 229, 72, 77 },
    [2] = { 247, 107, 21 },
    [3] = { 255, 197, 61 },
    [4] = { 62, 155, 255 },
}

-- Shift-end payment (server/payment.lua): paid via work_core's payWork() export
-- when a unit signs out, one itemised line per task it worked (u.closedTasks),
-- split evenly among everyone who was ever part of the shift (u.roster). Needs
-- work_core running; WORK_ID only has to resolve a name/colour for the receipt.
Config.PAY = {
    WORK_ID = "ems",
    -- base money per minute spent on the task, by closedTasks outcome.
    -- "default" covers any outcome not listed here; base = perMinute = 0
    -- credits the task (it still counts on the unit's Home page) without
    -- paying anything for it.
    RATES = {
        handover        = { base = 1500, perMinute = 120 },  -- full hospital handover
        released        = { base = 600,   perMinute = 60  },  -- taken off the case by dispatch
        left            = { base = 600,   perMinute = 30  },  -- handed to another unit
        ["task closed"] = { base = 600,   perMinute = 30  },  -- case closed while still on it
        ["shift ended"] = { base = 300,   perMinute = 30  },  -- shift ended mid-case, no payout
        default         = { base = 300,   perMinute = 30  },
    },
}
end)
