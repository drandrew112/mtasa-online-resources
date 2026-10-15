-- work_bloodtransport tutorial module - shared configuration. The texts of the steps are in
-- client/steps.lua. Positions: /workpos of work_core (in a vehicle it prints { x, y, z, rot }).

TUTORIAL = {
    -- true: the tutorial is offered on EVERY duty start, even when it was completed / skipped
    DEBUG = false,

    COMMAND = "tutorial_bt",           -- /tutorial_bt starts it, /tutorial_bt skip ends it
    ACC_KEY = "bt.tutorial",           -- v_mysql account data: true once completed or skipped
    DIMENSION_BASE = 43000,            -- every session gets its own dimension from here
    FADE_TIME = 1.2,                   -- seconds of a camera fade
    CURSOR_KEY = "F2",                 -- shows / hides the cursor for the tutorial card buttons
    POLL = 500,                        -- ms, server check of the drive step

    -- The tutorial starts in this blood transport vehicle (driver seat), a few metres from the
    -- port of the pickup institution
    VEHICLE = { 924.64, -1440.80, 13.35, 0 },

    -- The one tutorial task (bt_dispatch createTutorialTask). from / to = bt_core institution ids;
    -- only these two get a tutorial port. The player drives from one to the other.
    TASK = { type = "urgent_blood", product = "rbc", group = "0-", units = 4, from = "ls_bank", to = "ls_allsaints" },

    -- The drive step ends when the vehicle is this close to the destination port (m)
    ARRIVE_RANGE = 30,
    TASK_DELAY = 1500,                 -- ms after sign on until the task arrives

    -- Keys named in the texts (bt_dispatch panel, v_inventory INV.KEY_*)
    KEYS = { panel = "J", inventory = "I", drop = "H", port = "E" },
}
