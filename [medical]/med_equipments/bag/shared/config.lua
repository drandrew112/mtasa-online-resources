if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- bag module tunables. Offsets are { x, y, z, rx, ry, rz } in the parent's local space
-- (x = right, y = forward, z = up). See DESIGN.md. The items themselves (models, hand / ground
-- offsets, weights) are v_inventory items: medical_bag and lifepak15 (v_inventory/shared/items.lua).

-- A full ALS bag (v_inventory items in it): every tool and medicine. A medsys drug without an item
-- is unlimited, so every medsys drug has an item and is listed here (BAG.STOCK = the counted drugs).
local STOCK_ALS = {
    drugs = {
        ketamine = 2, rocuronium = 2, fentanyl = 3, epinephrine = 5, captopril = 3,
        nitroglycerin = 3, glucose = 2, glucose_gel = 2, insulin = 1, naloxone = 2,
        salbutamol = 2, midazolam = 2,
    },
    ivKits = 6,                -- one per IV attempt
    bandages = 6,              -- one per dressing
    splints = 2,               -- one per fracture
    glucometers = 1,           -- not used up
    airwayKits = 1,            -- not used up
    oxygen = 100,              -- percent of the cylinder
    oxygenMinutes = 25,        -- a full cylinder lasts this many minutes of mask time
}

-- A full BLS bag: the basic medicines of the "B" competency exam + glucose, glucose gel, insulin,
-- naloxone and midazolam; no intubation kit; the normal 15 minute cylinder. A drug left out here is
-- out of stock (0) in a BLS bag, never unlimited (getReachableStock counts every BAG.STOCK drug).
local STOCK_BLS = {
    drugs = {
        captopril = 3, nitroglycerin = 2, salbutamol = 2, glucose = 2, glucose_gel = 2, insulin = 1,
        naloxone = 2, midazolam = 1,
    },
    ivKits = 4,
    bandages = 6,
    splints = 2,
    glucometers = 1,
    airwayKits = 0,
    oxygen = 100,
    oxygenMinutes = 15,
}

BAG = {
    -- Models that can carry a kit. Only vehicles with an equipment level (shared/equipment.lua,
    -- set by work_ems) get one; the level picks the kit in LEVELS below.
    VEHICLE_MODELS = {
        [416] = true,              -- Mercedes Sprinter (HU)
        [483] = true,              -- Mercedes Sprinter 2018
        [582] = true,              -- Toyota Hiace
        [456] = true,              -- Mission Row Ambulance
        [598] = true,              -- Skoda Octavia (doctor car): no stretcher, kit in the boot
        [487] = true,              -- Maverick (rescue helicopter): kit at the right rear door
    },

    -- Side-door menu point, vehicle-local { x, y, z }. Positioned by hand: /bagpos prints the
    -- player's offset relative to the nearest ambulance.
    SIDE_POINT = {
        [416] = { 0.9, 0.3, -0.2 },
        [483] = { 0.9, 0.3, -0.2 },
        [582] = { 0.9, 0.15, 0.05 },
        [456] = { 1.40, -0.9, 0.0 },
        [598] = { 0.0, -2.75, 0.0 },   -- behind the boot (guess, tune with /bagpos)
        [487] = { 1.6, 0.0, -0.3 },    -- right rear door (guess, tune with /bagpos)
    },
    DEFAULT_SIDE_POINT = { 1.35, -0.6, 0.0 },
    SIDE_DOOR = {                  -- [model] = door id opened while taking / putting back, nil = none
        [598] = 1,                 -- boot
        [487] = 5,                 -- right rear door
    },
    DOOR_TIME = 400,               -- ms
    ANCHOR_MODEL = 1598,           -- small invisible prop the side-door menu hangs on
    MENU_RANGE = 1.8,              -- metres from the side point
    PUT_BACK_RANGE = 2.5,          -- a ground item this close to the side point can be put back

    -- The kit: kind -> v_inventory item id. KINDS = every kind any level may carry.
    ITEM_DEFS = { bag = "medical_bag", monitor = "lifepak15" },
    KINDS = { "bag", "monitor" },

    -- Kit per equipment level (EQUIPMENT.LEVELS): the kinds in it and the bag's full stock.
    -- A level may leave a kind out (no Lifepak) or use its own item defs later (ITEM_DEFS per level).
    -- "basic" has no kit (only the stretcher). Fill and restock use only the kit's own level, so a BLS
    -- bag never gets ALS items.
    LEVELS = {
        als = { kinds = { "bag", "monitor" }, stock = STOCK_ALS },
        bls = { kinds = { "bag", "monitor" }, stock = STOCK_BLS },
    },
    ITEM_NAMES = { bag = L.text("med_bag.config.medical_bag"), monitor = L.text("med_bag.config.monitor_defibrillator") },

    -- On the side of the stretcher (stretcher module, object 2146, local space: y = its long axis).
    -- The stretcher is scaled on the clients, these offsets are not: tune them in-game.
    STRETCHER_OFFSETS = {
        bag = { 0.0, 0.2, -0.35, 0, 0, 0 },      -- lower shelf, foot end
        monitor = { 0.0, 1.10, 0.20, 0, 0, 180 },   -- side rail, head end, screen outwards
    },

    AUTO_DROP_ON_TREAT = true,      -- a medsys procedure starts: carried items go down by the patient
    TAKE_ANIM = { "CARRY", "liftup", 600 },
    PUT_ANIM = { "CARRY", "putdwn", 600 },

    -- Use (medsys)
    USE_RANGE = 4.0,               -- an item serves a patient within this (3D, same dim / int)
    CONNECT_RANGE = 6.0,           -- a connected item (the bag feeding the oxygen, the linked monitor)
                                   -- keeps working up to this; starting an action needs USE_RANGE

    -- The widest stock (ALS): its drug list = the counted drugs. A bag's own full stock is
    -- LEVELS[kit.level].stock (bagStock() in server/stock.lua).
    STOCK = STOCK_ALS,
    -- stock category -> v_inventory item id (drugs: DRUG_PREFIX .. id, oxygen: the cylinder's meta)
    STOCK_ITEMS = {
        ivKits = "iv_kit", bandages = "bandage", splints = "splint",
        glucometers = "glucometer", airwayKits = "airway_kit",
    },
    OXYGEN_ITEM = "medical_oxygen_cylinder",
    DRUG_PREFIX = "drug_",
    -- emptied when an abandoned bag is recovered (with the drugs; the tools stay, the cylinder is emptied)
    CONSUMABLES = { "ivKits", "bandages", "splints" },
    OXYGEN_MINUTES = 15,           -- mask minutes of a full cylinder without its own meta.minutes (level stock oxygenMinutes)
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
    MONITOR_MODEL = 2190,          -- the lifepak15 model (v_inventory) that gets the static screen
    MONITOR_SCREEN_TEXTURE = "CJ_TV_SCREEN", -- nil = guess from the model's texture names;
                                   -- /bagscreen cycles through the model's textures to find the right one

    ADMIN_LEVEL = 3,               -- /bagreset: account admin_level above this
}

-- Element data
BAG_DATA = {
    KIND = "medbag.kind",          -- on the anchor: "anchor"
    MISSING = "medbag.missing",    -- on an anchor: "Medical bag, Monitor" while in a hospital bay with items out
    ON_STRETCHER = "medbag.onStretcher", -- on a stretcher object: { bag = true, monitor = true } riding on it
}
end)
