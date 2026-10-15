-- bt_dispatch configuration (server).

BTD = {
    WORK_ID = "bloodtransport",
    DB_FILE = "data/bloodtransport.db",

    -- Pay at the end of a service (work_core payWork, itemised receipt)
    PAY = {
        BASE = 2000,            -- only when at least one task was delivered
        DELIVERED = 4000,       -- per delivered task
        IN_TRANSIT = -1500,     -- per task still on its way (picked up, not delivered) at the end
    },
    XP_PER_DELIVERY = 40,       -- work_core XP of the work

    -- Task limits. The open tasks (waiting + in transit) of all transporters together are kept near
    -- OPEN_PER_UNIT * units on duty; one transporter never gets more than MAX_OPEN_PER_UNIT.
    OPEN_PER_UNIT = 2,
    MAX_OPEN_PER_UNIT = 4,
    MAX_UNITS_PER_TASK = 8,

    -- Random task generator (bt_stock asks for the resupply on its own)
    GEN_CHECK = 15,                         -- s
    GEN_INTERVAL = { 60, 150 },             -- s between two generated tasks
    -- Night: hour -> activity 0..1 (linear in between). The generation interval is divided by it and
    -- the open-task target is multiplied by it; fewest alerts between 00:00 and 04:00.
    NIGHT_ACTIVITY = { {0, 0.10}, {4, 0.10}, {7, 1.0}, {21, 1.0}, {24, 0.10} },
    GEN_WEIGHTS = { urgent_blood = 30, planned_blood = 25, lab_sample = 25, urgent_medicine = 5 },
    PRODUCT_WEIGHTS = { rbc = 50, ffp = 30, platelets = 20 },
    GEN_UNITS = { urgent_blood = { 2, 6 }, planned_blood = { 3, 8 } },

    -- Task types: where the cargo comes from and goes to; stock = taken from the centers' stock
    TYPES = {
        resupply = { from = "bank", to = "hospital", stock = true, urgency = "routine", only = "bt_stock" },
        urgent_blood = { from = "bank", to = "hospital", stock = true, urgency = "urgent" },
        planned_blood = { from = "bank", to = "hospital", stock = true, urgency = "planned" },
        lab_sample = { from = "hospital", to = "bank", stock = false, urgency = "routine" },
        urgent_medicine = { from = "hospital", to = "hospital", stock = false, urgency = "urgent", differ = true },
    },

    DONE_VISIBLE = 5,           -- s a delivered / cancelled task stays in the panel
    OFFER_RANGE = 6.0,          -- m between two transporters for a handover
    OFFER_TIMEOUT = 20,         -- s the other one has to accept
    NEARBY_INTERVAL = 2000,     -- ms, how often the nearby transporter is looked up
    VEHICLE_CHECK = 1000,       -- ms
    ADMIN_PAGE = 13,            -- rows per page of the admin lists
}
