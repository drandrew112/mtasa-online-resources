-- v_customs :: tuning catalogue (shared)
--
-- Top level is an alphabetically sorted list of entries. An entry is either:
--   folder : { name, folder = true, items = { <part>, ... } }
--   part   : static { name, options = { <option leaf>, ... } }
--            group  { name, group = "optical"|"color", slot?, price }
--
-- Option leaf : { name, price, kind, data, ... }
--
-- Paths are "/"-joined 1-based indices down to the option ("wheels/2/3"). The
-- server (server/tuning.lua) is authoritative for price and every effect.
--
-- Handling deltas ({prop} = reset to stock, {prop, n} = stock + n) come from the
-- original SA Customs resource (see old/sourceG.lua).

Customs = Customs or {}

--------------------------------------------------------------------------------
-- Respray palette
--------------------------------------------------------------------------------

Customs.PALETTE = {
    { name = "Black",       rgb = {  10,  10,  10 } },
    { name = "White",       rgb = { 245, 245, 245 } },
    { name = "Silver",      rgb = { 170, 175, 180 } },
    { name = "Gunmetal",    rgb = {  55,  60,  68 } },
    { name = "Red",         rgb = { 190,  30,  30 } },
    { name = "Crimson",     rgb = { 120,  15,  25 } },
    { name = "Orange",      rgb = { 235, 120,  20 } },
    { name = "Yellow",      rgb = { 240, 210,  40 } },
    { name = "Lime",        rgb = { 130, 210,  50 } },
    { name = "Green",       rgb = {  30, 130,  55 } },
    { name = "Teal",        rgb = {  20, 130, 130 } },
    { name = "Sky Blue",    rgb = {  80, 170, 235 } },
    { name = "Blue",        rgb = {  35,  70, 190 } },
    { name = "Navy",        rgb = {  20,  30,  80 } },
    { name = "Purple",      rgb = { 110,  45, 170 } },
    { name = "Pink",        rgb = { 230, 110, 180 } },
    { name = "Brown",       rgb = {  90,  60,  35 } },
    { name = "Beige",       rgb = { 210, 195, 160 } },
}

--------------------------------------------------------------------------------
-- Performance packs helper (Default + Upgrade 1..4)
--------------------------------------------------------------------------------

local function pack(name, deltaSets, prices)
    local labels = { "Default", "Upgrade 1", "Upgrade 2", "Upgrade 3", "Upgrade 4" }
    local opts = {}
    for i = 1, 5 do
        opts[i] = { name = labels[i], price = prices[i], kind = "performance", data = deltaSets[i] }
    end
    return { name = name, options = opts }
end

local function wheelSize(name, side)
    return { name = name, options = {
        { name = "Very Narrow", price = 20000, kind = "wheelWidth", side = side, data = "verynarrow" },
        { name = "Narrow",      price = 10000, kind = "wheelWidth", side = side, data = "narrow" },
        { name = "Default",     price = 5000,  kind = "wheelWidth", side = side, data = "default" },
        { name = "Wide",        price = 10000, kind = "wheelWidth", side = side, data = "wide" },
        { name = "Very Wide",   price = 20000, kind = "wheelWidth", side = side, data = "verywide" },
    }}
end

--------------------------------------------------------------------------------
-- Catalogue
--------------------------------------------------------------------------------

Customs.parts = {
    pack("Engine", {
        { {"engineAcceleration"},    {"maxVelocity"} },
        { {"engineAcceleration", 2}, {"maxVelocity", 10} },
        { {"engineAcceleration", 4}, {"maxVelocity", 16} },
        { {"engineAcceleration", 6}, {"maxVelocity", 23} },
        { {"engineAcceleration", 8}, {"maxVelocity", 30} },
    }, { 0, 1500, 3000, 4500, 6000 }),

    pack("Turbo", {
        { {"engineInertia"} },
        { {"engineInertia", -8} },
        { {"engineInertia", -16} },
        { {"engineInertia", -24} },
        { {"engineInertia", -32} },
    }, { 0, 6000, 12000, 18000, 24000 }),

    pack("Brakes", {
        { {"brakeDeceleration"},       {"brakeBias"} },
        { {"brakeDeceleration", 0.05}, {"brakeBias", 0.10} },
        { {"brakeDeceleration", 0.10}, {"brakeBias", 0.17} },
        { {"brakeDeceleration", 0.15}, {"brakeBias", 0.24} },
        { {"brakeDeceleration", 0.20}, {"brakeBias", 0.30} },
    }, { 0, 4500, 9000, 12500, 16000 }),

    pack("Tires", {
        { {"tractionMultiplier"},       {"tractionLoss"} },
        { {"tractionMultiplier", 0.05}, {"tractionLoss", 0.02} },
        { {"tractionMultiplier", 0.10}, {"tractionLoss", 0.03} },
        { {"tractionMultiplier", 0.15}, {"tractionLoss", 0.04} },
        { {"tractionMultiplier", 0.20}, {"tractionLoss", 0.05} },
    }, { 0, 4500, 9000, 12500, 16000 }),

    pack("Weight Reduction", {
        { {"mass"} },
        { {"mass", -100} },
        { {"mass", -200} },
        { {"mass", -300} },
        { {"mass", -400} },
    }, { 0, 4250, 7500, 11000, 15000 }),

    -- Optical (flat) ----------------------------------------------------
    { name = "Hood",       group = "optical", slot = 0,  price = 1000 },
    { name = "Exhaust",    group = "optical", slot = 13, price = 2000 },
    { name = "Spoiler",    group = "optical", slot = 2,  price = 1500 },
    { name = "Side Skirt", group = "optical", slot = 3,  price = 1000 },
    { name = "Roof Scoop", group = "optical", slot = 7,  price = 1000 },
    { name = "Hydraulics", group = "optical", slot = 9,  price = 15000 },

    -- Folders --------------------------------------------------------
    { name = "Bumpers", folder = true, items = {
        { name = "Front Bumper", group = "optical", slot = 14, price = 1000 },
        { name = "Rear Bumper",  group = "optical", slot = 15, price = 1000 },
    }},

    { name = "Wheels", folder = true, items = {
        wheelSize("Front Wheel Size", "front"),
        wheelSize("Rear Wheel Size", "rear"),
        { name = "Wheel Types", group = "optical", slot = 12, price = 5000 },
        { name = "Drive Type", options = {
            { name = "Front Wheel Drive", price = 10000, kind = "handlingProp", prop = "driveType", data = "fwd" },
            { name = "All Wheel Drive",   price = 10000, kind = "handlingProp", prop = "driveType", data = "awd" },
            { name = "Rear Wheel Drive",  price = 10000, kind = "handlingProp", prop = "driveType", data = "rwd" },
        }},
        { name = "Bulletproof Tires", options = {
            { name = "Off", price = 0,     kind = "flagToggle", flag = "bulletproof", data = false },
            { name = "On",  price = 85000, kind = "flagToggle", flag = "bulletproof", data = true },
        }},
    }},

    { name = "Respray", folder = true, items = {
        { name = "Primary Color",   group = "color", slot = "primary",   price = 10000 },
        { name = "Secondary Color", group = "color", slot = "secondary", price = 10000 },
        { name = "Headlight Color", group = "color", slot = "headlight", price = 8000 },
    }},

    -- Extras (flat) ------------------------------------------------
    { name = "Steering Lock", options = {
        { name = "Default", price = 7500, kind = "handlingProp", prop = "steeringLock", data = false },
        { name = "30 deg",  price = 7500, kind = "handlingProp", prop = "steeringLock", data = 30 },
        { name = "40 deg",  price = 7500, kind = "handlingProp", prop = "steeringLock", data = 40 },
        { name = "50 deg",  price = 7500, kind = "handlingProp", prop = "steeringLock", data = 50 },
        { name = "60 deg",  price = 7500, kind = "handlingProp", prop = "steeringLock", data = 60 },
    }},
    { name = "LSD Doors", options = {
        { name = "Off", price = 0,     kind = "flagToggle", flag = "lsdDoor", data = false },
        { name = "On",  price = 35000, kind = "flagToggle", flag = "lsdDoor", data = true },
    }},
    { name = "License Plate", options = {
        { name = "Random Plate",     price = 5000,  kind = "plate", data = "random" },
        { name = "Custom Plate...",  price = 15000, kind = "plate", data = "custom" },
        { name = "Reset To Default", price = 0,     kind = "plate", data = "default" },
    }},
    { name = "Horn", options = {
        { name = "Horn 1", price = 0, kind = "horn", data = 1 },
        { name = "Horn 2", price = 0, kind = "horn", data = 2 },
        { name = "Horn 3", price = 0, kind = "horn", data = 3 },
        { name = "Horn 4", price = 0, kind = "horn", data = 4 },
        { name = "Horn 5", price = 0, kind = "horn", data = 5 },
    }},
}

table.sort(Customs.parts, function(a, b) return a.name < b.name end)

--------------------------------------------------------------------------------
-- Path resolution (shared)
--------------------------------------------------------------------------------

-- Walks the tree. Returns:
--   static part option -> the option leaf
--   group  part        -> the part table + the option index
function Customs.resolve(path)
    local node = { items = Customs.parts }
    for seg in tostring(path):gmatch("[^/]+") do
        local idx = tonumber(seg)
        local children = node.items or node.options
        if children then
            node = children[idx]
            if not node then return nil end
        elseif node.group then
            return node, idx
        else
            return nil
        end
    end
    return node
end

-- Applies Customs.PRICE_MULT (rounded to whole dollars).
function Customs.price(base)
    return math.floor((tonumber(base) or 0) * (Customs.PRICE_MULT or 1) + 0.5)
end

--------------------------------------------------------------------------------
-- Handling-flag / value maps used by preview (client) and apply (server)
--------------------------------------------------------------------------------

Customs.WHEEL_SIZE = { verynarrow = 1, narrow = 2, default = 0, wide = 4, verywide = 8 }

-- Byte-addressable handlingFlags editor (ported from old/sourceS.lua). `byte` is
-- 1-based; front-wheel width = 3, rear = 4.
function Customs.setHandlingFlagByte(veh, byte, value)
    local hex      = string.format("%X", getVehicleHandling(veh)["handlingFlags"])
    local reversed = string.reverse(hex) .. string.rep("0", 8 - string.len(hex))
    local cur, out = 1, ""
    for ch in string.gmatch(reversed, ".") do
        if cur == byte then ch = string.format("%X", tonumber(value)) end
        out = out .. ch
        cur = cur + 1
    end
    setVehicleHandling(veh, "handlingFlags", tonumber("0x" .. string.reverse(out)), false)
end
