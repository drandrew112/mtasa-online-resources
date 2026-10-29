-- Every item that can exist. createItem refuses an unknown id, so every item has its texts in
-- v_locals: v_inventory.item.<id>.name and v_inventory.item.<id>.desc.
--
--   category    colour of the icon tile and the `accepts` filter of containers (ITEM_CATEGORIES)
--   weight      kg per piece (a container: empty)
--   holdable    may be held in a hand (every holdable item is one-handed)
--   hand        preferred hand when picked up ("left" | "right")
--   back        may be worn on the back (and only there, unless holdable too)
--   storable    false: cannot be put into a container, port or trunk by a player (scripts may
--               still store it in a vehicle / attach it)
--   stackable   pieces of the same item merge into one stack (amount)
--   container   { capacity = kg, accepts = { category = true } | nil (any simple item) }
--               containers hold simple items only, never another container
--   model, fallback, scale   world object (hand, back, ground, attached)
--   offsets     right / left = from the hand bone in the carrier's frame (x right, y forward,
--               z up, rz added to the heading); left is the mirrored right when missing.
--               back = from the spine bone, the same frame. ground = from the ground point.
--   icon        optional PNG (in this resource); without it a lettered tile (glyph) is drawn
--   lockControls  controls switched off while held (default INV.CARRY_LOCKED_CONTROLS)

ITEM_CATEGORIES = {
    container = { 215, 55, 65 },
    device = { 80, 190, 120 },
    drug = { 90, 150, 240 },
    iv = { 180, 120, 230 },
    o2 = { 60, 190, 220 },
    tool = { 150, 156, 175 },
    blood = { 200, 40, 60 },
    sample = { 230, 150, 60 },
    cargo = { 150, 110, 60 },
}

ITEMS = {
    -- ----------------------------------------------------------------------- medical (med_equipments)
    medical_bag = {
        category = "container", weight = 2.0, holdable = true, hand = "left", storable = false,
        container = { capacity = 10, accepts = { drug = true, iv = true, o2 = true, tool = true } },
        model = 1210, scale = 1.0,                          -- briefcase placeholder, 0.50 x 0.07 x 0.37 m
        offsets = {
            left = { 0.02, 0.0, -0.35, 0, 0, -90 },        -- long side along the leg, handle in the hand
            ground = { 0, 0, 0, 0, 0, -90 },
        },
        icon = "icons/medical_bag.png", glyph = "MB",
    },
    lifepak15 = {
        category = "device", weight = 5.5, holdable = true, hand = "right", storable = false,
        model = 1581, scale = 1.0,                         -- PC_1 monitor placeholder
        offsets = {
            right = { 0, 0, -0.3, 0, 0, 90 },
            ground = { 0, 0, 0, 0, 0, 0 },
        },
        icon = "icons/lifepak15.png", glyph = "LP",
    },
    medical_oxygen_cylinder = { category = "o2", weight = 3.0, icon = "icons/oxygen.png", glyph = "O2" },
    iv_kit = { category = "iv", weight = 0.1, stackable = true, icon = "icons/iv_kit.png", glyph = "IV" },
    airway_kit = { category = "tool", weight = 0.6, icon = "icons/airway_kit.png", glyph = "AW" },
    glucometer = { category = "tool", weight = 0.2, icon = "icons/glucometer.png", glyph = "GL" },
    bandage = { category = "tool", weight = 0.05, stackable = true, icon = "icons/bandage.png", glyph = "BD" },
    splint = { category = "tool", weight = 0.4, stackable = true, icon = "icons/splint.png", glyph = "SP" },

    -- ----------------------------------------------------------------------- blood transport (bt_items)
    bt_blood_box = {
        category = "container", weight = 1.5, holdable = true, hand = "right",
        container = { capacity = 10, accepts = { blood = true, sample = true, tool = true } },
        model = 2969, fallback = 1210, scale = 1.0,         -- small ammo box placeholder (untested)
        offsets = {
            right = { 0.12, -0.04, -0.35, 0, 0, 0 },        -- tuned in game from { 0.10, 0.15, -0.10 }
            ground = { 0, 0, 0, 0, 0, 0 },
        },
        icon = "icons/bt_blood_box.png", glyph = "BX",
    },

    -- Cargo of the blood transport (bt_items): one item per task, amount = units, meta = { task, group, ... }
    bt_ffp = { category = "blood", weight = 0.5, stackable = true, glyph = "FF" },
    bt_rbc = { category = "blood", weight = 0.5, stackable = true, glyph = "RB" },
    bt_platelets = { category = "blood", weight = 0.5, stackable = true, glyph = "PL" },
    bt_lab_sample = { category = "sample", weight = 0.05, stackable = true, glyph = "LB" },
    bt_urgent_medicine = { category = "sample", weight = 0.3, stackable = true, icon = "icons/drug.png", glyph = "MD" },

    -- ----------------------------------------------------------------------- job missions (v_jobmanager mode_mission)
    -- picked up in a mission and carried to the drop-off; meta = { mission = matchId, label }
    mission_package = {
        category = "cargo", weight = 3, holdable = true, hand = "right", storable = false,
        model = 1271, scale = 0.6,                          -- gunbox scaled down (untested)
        offsets = { right = { 0.12, 0.2, -0.12, 0, 0, 0 }, ground = { 0, 0, 0, 0, 0, 0 } },
        glyph = "PK",
    },
    mission_briefcase = {
        category = "cargo", weight = 2, holdable = true, hand = "left", storable = false,
        model = 1210, scale = 1.0,                          -- briefcase
        offsets = { left = { 0.02, 0.0, -0.35, 0, 0, -90 }, ground = { 0, 0, 0, 0, 0, -90 } },
        glyph = "BC",
    },
    mission_money_bag = {
        category = "cargo", weight = 8, holdable = true, hand = "right", storable = false,
        model = 1550, scale = 0.8,                          -- CJ_MONEY_BAG (untested)
        offsets = { right = { 0.1, 0.05, -0.3, 0, 0, 0 }, ground = { 0, 0, 0.25, 0, 0, 0 } },
        glyph = "$",
    },
    mission_documents = {
        category = "cargo", weight = 0.5, holdable = true, hand = "left", storable = false,
        model = 2894, scale = 1.0,                          -- kmb_rhymesbook (untested)
        offsets = { left = { 0.05, 0.05, -0.05, 0, 0, 0 }, ground = { 0, 0, 0, 0, 0, 0 } },
        glyph = "DC",
    },
    mission_crate = {
        category = "cargo", weight = 25, holdable = true, hand = "right", storable = false,
        model = 2912, fallback = 1271, scale = 0.6,         -- temp_crate1 scaled down (untested)
        offsets = { right = { 0.15, 0.25, -0.15, 0, 0, 0 }, ground = { 0, 0, 0, 0, 0, 0 } },
        glyph = "CR",
    },

    -- ----------------------------------------------------------------------- organizations (biz_missions)
    -- stolen supply of a supply mission: carried to the property's entrance in the hands
    biz_supply_crate = {
        category = "cargo", weight = 20, holdable = true, hand = "right", storable = false,
        model = 2912, fallback = 1271, scale = 0.6,         -- temp_crate1 scaled down (untested)
        offsets = {
            right = { 0.15, 0.25, -0.15, 0, 0, 0 },
            ground = { 0, 0, 0, 0, 0, 0 },
        },
        glyph = "SC",
    },

    -- ----------------------------------------------------------------------- general
    backpack = {
        category = "container", weight = 1.2, back = true,
        container = { capacity = 8 },
        model = 371, scale = 1.0,                           -- parachute pack placeholder (untested)
        offsets = {
            back = { 0, -0.12, 0.05, 0, 0, 180 },
            ground = { 0, 0, 0.15, 90, 0, 0 },
        },
        icon = "icons/backpack.png", glyph = "BP",
    },
}

-- Medicines: one stackable item per medsys MEDIC_DRUGS id, all with the same icon
MEDICAL_DRUGS = {
    "ketamine", "rocuronium", "fentanyl", "epinephrine", "captopril", "nitroglycerin",
    "glucose", "glucose_gel", "insulin", "naloxone", "salbutamol", "midazolam",
}
for _, id in ipairs(MEDICAL_DRUGS) do
    ITEMS["drug_" .. id] = { category = "drug", weight = 0.05, stackable = true, icon = "icons/drug.png",
        glyph = id:sub(1, 2):upper() }
end

-- Defaults
for id, def in pairs(ITEMS) do
    def.id = id
    if def.storable == nil then def.storable = true end
    if def.container then def.stackable = false end
end

function getItemDefinition(id)
    return ITEMS[id]
end
