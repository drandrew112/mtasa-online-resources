-- v_inventory tunables. Offsets are { x, y, z, rx, ry, rz }. See DESIGN.md.

INV = {
    -- Keys (client)
    KEY_INVENTORY = "i",           -- own inventory window
    KEY_DROP = "h",                -- put the hand items down (not G: "enter as passenger" in GTA)
    KEY_PORT = "e",                -- open the storage while standing in a port marker

    -- Player slots
    SLOTS = { "left", "right", "back" },
    HANDS = { "left", "right" },
    BONES = { left = 35, right = 25, back = 3 },   -- left hand, right hand, spine
    DROP_OFFSETS = { left = { -0.35, 0.6 }, right = { 0.35, 0.6 }, back = { 0, -0.6 } }, -- player-local x, y
    -- switched off while something is in a hand (an item def can override it with lockControls)
    CARRY_LOCKED_CONTROLS = { "jump", "fire", "aim_weapon", "next_weapon", "previous_weapon" },
    TAKE_ANIM = { "CARRY", "liftup", 600 },
    PUT_ANIM = { "CARRY", "putdwn", 600 },

    -- Ground items (ui_interactobject menu)
    GROUND_MENU_RANGE = 2.0,
    GROUND_MIN_Z = -50,            -- an item below this falls back to the dropper's feet

    -- Windows
    SESSION_RANGE = 6.0,           -- the window closes this far from where it was opened
    OPEN_RANGE = 3.0,              -- trunk / ground container: the player must be this close to open it

    -- Ports
    PORT_RADIUS = 1.5,
    PORT_COLOR = { 215, 55, 65 },
    PORT_LABEL_HEIGHT = 1.6,
    PORT_LABEL_DISTANCE = 25,
    PORT_LABEL_FULL_DISTANCE = 8,
    PORT_LABEL_MIN_SCALE = 0.6,

    -- Trunks
    TRUNK_ANCHOR_MODEL = 1598,     -- invisible prop the trunk menu hangs on
    TRUNK_OFFSET = { 0, -2.5, -0.2 },  -- vehicle-local default (the rear); per trunk: opts.offset
    TRUNK_MENU_RANGE = 2.0,
}

-- Element data
INV_DATA = {
    SLOTS = "inv.slots",           -- on a player: { left = { d = defId, u = uid, m = model }, right = ..., back = ... }
    ITEM = "inv.item",             -- on a ground / attached item object: uid
    PORT = "inv.port",             -- on a port marker: port id
    OPEN = "inventoryOpen",        -- local on the player while the window is open (other UIs check it)
}

-- UI colours (the med_equipments / ui_interactobject palette)
INV_COLORS = {
    bg = { 16, 18, 24, 232 },
    head = { 22, 26, 34, 255 },
    tile = { 28, 31, 40, 255 },
    tile2 = { 36, 40, 52, 255 },
    accent = { 215, 55, 65 },
    blue = { 0, 140, 200 },
    text = { 235, 238, 245 },
    muted = { 140, 146, 160 },
    off = { 95, 100, 112 },
    good = { 80, 210, 120 },
    warn = { 255, 185, 60 },
    bad = { 235, 70, 70 },
    key = { 240, 184, 74 },
}
