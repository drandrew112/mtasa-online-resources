-- med_bag tunables. Offsets are { x, y, z, rx, ry, rz } in the parent's local space
-- (x = right, y = forward, z = up). See DESIGN.md.

BAG = {
    -- Ambulances that carry a kit (one medical bag + one monitor each)
    VEHICLE_MODELS = {
        [416] = true,              -- Mercedes Sprinter (HU)
        [456] = true,              -- Mission Row Ambulance
    },

    -- Side-door menu point, vehicle-local { x, y, z }. Positioned by hand: /bagpos prints the
    -- player's offset relative to the nearest ambulance.
    SIDE_POINT = {
        [416] = { 0.9, 0.3, -0.2 },
        [456] = { 1.40, -0.9, 0.0 },
    },
    DEFAULT_SIDE_POINT = { 1.35, -0.6, 0.0 },
    SIDE_DOOR = {},                -- [model] = door id opened while taking / putting back, nil = none
    DOOR_TIME = 400,               -- ms
    ANCHOR_MODEL = 1598,           -- small invisible prop the side-door menu hangs on
    MENU_RANGE = 1.8,              -- metres from the side point
    PUT_BACK_RANGE = 2.5,          -- a ground item this close to the side point can be put back

    -- Item models (placeholders until the custom models arrive; the SA-MP ids the user suggested,
    -- 11738 MedicCase / 19787 LCD, do not exist in MTA). If `id` cannot be created, `fallback` is used.
    --   hand    { x, y, z, rx, ry, rz }: from the hand bone, in the CARRIER's frame (x = right,
    --           y = forward, z = up, rz added to the carrier's heading): the item hangs from the hand
    --   ground  the same from the ground point (z = origin height above the ground)
    -- Both models have their origin off-centre, the offsets compensate for it (measured bboxes).
    MODELS = {
        bag = {
            id = 1210, fallback = nil, scale = 1.0,       -- briefcase, 0.50 x 0.07 x 0.37 m
            hand = { 0.126, 0.0, -0.25, 0, 0, -90 },      -- long side along the leg, handle in the hand
            ground = { 0, 0, 0.112, 0, 0, -90 },
        },
        monitor = {
            id = 2190, fallback = nil, scale = 0.55,      -- PC_1 monitor, ~0.30 x 0.25 x 0.30 m scaled
            hand = { -0.227, 0.241, -0.39, 0, 0, 90 },
            ground = { 0, 0, -0.153, 0, 0, 0 },
        },
    },
    -- On the side of the stretcher (med_stretcher object 2146, local space: y = its long axis).
    -- The stretcher is scaled on the clients, these offsets are not: tune them in-game.
    STRETCHER_OFFSETS = {
        bag = { 0.0, -0.55, -0.30, 0, 0, 90 },      -- lower shelf, foot end
        monitor = { 0.30, 0.55, 0.20, 0, 0, 90 },   -- side rail, head end, screen outwards
    },
    BONES = { bag = 35, monitor = 25 },   -- left hand / right hand
    ITEM_NAMES = { bag = "Medical bag", monitor = "Monitor / defibrillator" },
    KINDS = { "bag", "monitor" },

    -- Putting down
    DROP_KEY = "h",              -- not G: that is "enter as passenger" in GTA
    DROP_OFFSETS = { bag = { -0.35, 0.6 }, monitor = { 0.35, 0.6 } },  -- player-local x, y
    DROP_PATIENT_DISTANCE = 0.9,    -- auto drop: this far from the patient, towards the medic
    AUTO_DROP_ON_TREAT = true,      -- a medsys procedure starts: carried items go down by the patient
    TAKE_ANIM = { "CARRY", "liftup", 600 },
    PUT_ANIM = { "CARRY", "putdwn", 600 },
    CARRY_LOCKED_CONTROLS = { "jump", "fire", "aim_weapon", "next_weapon", "previous_weapon" },
    GROUND_MENU_RANGE = 2.0,

    -- Use (medsys)
    USE_RANGE = 4.0,               -- an item serves a patient within this (3D, same dim / int)
    CONNECT_RANGE = 6.0,           -- a connected item (the bag feeding the oxygen, the linked monitor)
                                   -- keeps working up to this; starting an action needs USE_RANGE

    -- Consumables of a full bag. A medsys drug that is not listed is unlimited.
    STOCK = {
        drugs = {
            ketamine = 2, rocuronium = 2, fentanyl = 3, epinephrine = 5, captopril = 3,
            nitroglycerin = 3, glucose = 2, glucose_gel = 2, insulin = 1, naloxone = 2,
            salbutamol = 2, midazolam = 2,
        },
        ivKits = 6,                -- one per IV attempt
        oxygen = 100,              -- percent of the cylinder
    },
    OXYGEN_DRAIN = 100 / 900,      -- % per second per mask: a full cylinder lasts 15 min of mask time
    OXYGEN_LOW = 20,               -- % warning
    LOW_STOCK_FRACTION = 0.25,     -- warn once when a counted item drops to this share
    RESTOCK_TIME = 6,              -- seconds, in a hospital bay

    -- Left-behind watch
    WATCH_INTERVAL = 2000,         -- ms
    LEFT_DISTANCE = 60,            -- ground item this far from its ambulance = left behind
    LEFT_MOVING_DISTANCE = 20,     -- ...or this far while the ambulance moves
    LEFT_MOVING_SPEED = 15,        -- km/h
    LEFT_GUARD_RADIUS = 10,        -- a medic this close to the item = not left behind
    WARN_REPEAT = 45,              -- seconds between repeated warnings
    ABANDON_TIME = 600,            -- seconds left behind -> back into the ambulance with an empty stock
    BLIP = { icon = 0, size = 2, color = { 230, 60, 60 } },

    SCAN_INTERVAL = 3000,          -- ms, fallback scan for ambulances the debug hook missed
    STATIC_SCREEN = true,          -- static picture on the monitor model (client/screen.lua)
    MONITOR_SCREEN_TEXTURE = "CJ_TV_SCREEN", -- nil = guess from the model's texture names;
                                   -- /bagscreen cycles through the model's textures to find the right one

    ADMIN_LEVEL = 3,               -- /bagreset: account admin_level above this
}

-- Element data
BAG_DATA = {
    HANDS = "medbag.hands",        -- on a player: { bag = model|nil, monitor = model|nil } (carried items)
    KIND = "medbag.kind",          -- on an item object / anchor: "bag" | "monitor" | "anchor"
    ITEM = "medbag.item",          -- on an item object: item id
    MISSING = "medbag.missing",    -- on an anchor: "Medical bag, Monitor" while in a hospital bay with items out
    ON_STRETCHER = "medbag.onStretcher", -- on a stretcher object: { bag = true, monitor = true } riding on it
}
