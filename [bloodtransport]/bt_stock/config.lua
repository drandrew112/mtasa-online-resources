-- bt_stock configuration. Amounts are in units (one unit = 450 ml).

BTS = {
    FILE = "data/stock.json",            -- created automatically, not versioned
    SAVE_DELAY = 20,                     -- s, a changed stock is written at most this late

    -- Capacity of one product (all blood groups together); a group's share follows BT.GROUP_WEIGHT
    BANK_TOTAL = 300,
    HOSPITAL_TOTAL = 60,
    BANK_MIN_LINE = 4,
    HOSPITAL_MIN_LINE = 2,
    START_FILL = { 0.55, 0.85 },         -- a new stock file starts every line at this share of the capacity

    -- Blood supply centers: every REFILL_INTERVAL s each line gets REFILL_SHARE of its capacity,
    -- never above REFILL_MAX (a center is never 100 % full). Runs without transporters too.
    REFILL_INTERVAL = 3600,
    REFILL_SHARE = { 0.10, 0.35 },
    REFILL_MAX = 0.90,

    -- Hospitals only consume, and only while a transporter is on duty: every interval one unit of a
    -- random product / group (weighted by the group frequency) is used up.
    CONSUME_INTERVAL = { 90, 240 },

    -- Night: the consumption interval is divided by the activity (hour -> 0..1, linear in between),
    -- so at night the hospitals use up far less. Lowest between 00:00 and 04:00.
    NIGHT_ACTIVITY = { {0, 0.10}, {4, 0.10}, {7, 1.0}, {21, 1.0}, {24, 0.10} },

    -- Resupply: a hospital line below LOW asks for a delivery up to FILL_TO. When the serving
    -- center line is below URGENT_LEVEL the delivery is urgent and comes in small batches.
    LOW = 0.40,
    FILL_TO = 0.80,
    URGENT_LEVEL = 0.25,
    BATCH = 8,
    URGENT_BATCH = 3,
    MAX_PENDING_TASKS = 3,               -- open resupply tasks per hospital
    CHECK_INTERVAL = 20,                 -- s
}
