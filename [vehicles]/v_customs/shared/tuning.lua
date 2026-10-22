if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- v_customs :: tuning catalogue (shared)
--
-- Top level is an alphabetically sorted list of entries. An entry is either:
--   folder : { name, folder = true, items = { <part>, ... } }
--   part   : static { name, options = { <option leaf>, ... } }
--            group  { name, group = "optical"|"color", slot?, price }
--
-- Option leaf : { name, price, kind, data, ... }
--
-- A part may carry `types` (set of getVehicleType values it applies to) and
-- `needs` (a vehicle component it needs); Customs.isPartAvailable hides it
-- otherwise. Optical groups are hidden when the slot has no compatible upgrade.
--
-- Paths are "/"-joined 1-based indices down to the option ("wheels/2/3"). The
-- server (server/tuning.lua) is authoritative for price and every effect.
--
-- Handling deltas ({prop} = reset to stock, {prop, n} = stock + n) come from the
-- original SA Customs resource (see old/sourceG.lua).

Customs = Customs or {}

-- getVehicleType sets used by a part's `types`
local CARS  = { Automobile = true, ["Monster Truck"] = true }
local MOTOR = { Automobile = true, ["Monster Truck"] = true, Quad = true, Bike = true }

--------------------------------------------------------------------------------
-- Respray palette
--------------------------------------------------------------------------------

Customs.PALETTE = {
    { name = L.text("v_customs.tuning.black"),       rgb = {  10,  10,  10 } },
    { name = L.text("v_customs.tuning.white"),       rgb = { 245, 245, 245 } },
    { name = L.text("v_customs.tuning.silver"),      rgb = { 170, 175, 180 } },
    { name = L.text("v_customs.tuning.gunmetal"),    rgb = {  55,  60,  68 } },
    { name = L.text("v_customs.tuning.red"),         rgb = { 190,  30,  30 } },
    { name = L.text("v_customs.tuning.crimson"),     rgb = { 120,  15,  25 } },
    { name = L.text("v_customs.tuning.orange"),      rgb = { 235, 120,  20 } },
    { name = L.text("v_customs.tuning.yellow"),      rgb = { 240, 210,  40 } },
    { name = L.text("v_customs.tuning.lime"),        rgb = { 130, 210,  50 } },
    { name = L.text("v_customs.tuning.green"),       rgb = {  30, 130,  55 } },
    { name = L.text("v_customs.tuning.teal"),        rgb = {  20, 130, 130 } },
    { name = L.text("v_customs.tuning.sky_blue"),    rgb = {  80, 170, 235 } },
    { name = L.text("v_customs.tuning.blue"),        rgb = {  35,  70, 190 } },
    { name = L.text("v_customs.tuning.navy"),        rgb = {  20,  30,  80 } },
    { name = L.text("v_customs.tuning.purple"),      rgb = { 110,  45, 170 } },
    { name = L.text("v_customs.tuning.pink"),        rgb = { 230, 110, 180 } },
    { name = L.text("v_customs.tuning.brown"),       rgb = {  90,  60,  35 } },
    { name = L.text("v_customs.tuning.beige"),       rgb = { 210, 195, 160 } },
}

--------------------------------------------------------------------------------
-- Performance packs helper (Default + Upgrade 1..4)
--------------------------------------------------------------------------------

local function pack(name, deltaSets, prices, types)
    local labels = { L.text("v_customs.menu.default"), L.text("v_customs.tuning.upgrade_1"), L.text("v_customs.tuning.upgrade_2"), L.text("v_customs.tuning.upgrade_3"), L.text("v_customs.tuning.upgrade_4") }
    local opts = {}
    for i = 1, 5 do
        opts[i] = { name = labels[i], price = prices[i], kind = "performance", data = deltaSets[i] }
    end
    return { name = name, options = opts, types = types }
end

local function wheelSize(name, side)
    return { name = name, types = CARS, options = {
        { name = L.text("v_customs.tuning.very_narrow"), price = 2400, kind = "wheelWidth", side = side, data = "verynarrow" },
        { name = L.text("v_customs.tuning.narrow"),      price = 1400, kind = "wheelWidth", side = side, data = "narrow" },
        { name = L.text("v_customs.menu.default"),     price = 600,  kind = "wheelWidth", side = side, data = "default" },
        { name = L.text("v_customs.tuning.wide"),        price = 1400, kind = "wheelWidth", side = side, data = "wide" },
        { name = L.text("v_customs.tuning.very_wide"),   price = 2400, kind = "wheelWidth", side = side, data = "verywide" },
    }}
end

--------------------------------------------------------------------------------
-- Catalogue
--------------------------------------------------------------------------------

Customs.parts = {
    pack(L.text("v_customs.tuning.engine"), {
        { {"engineAcceleration"},    {"maxVelocity"} },
        { {"engineAcceleration", 2}, {"maxVelocity", 10} },
        { {"engineAcceleration", 4}, {"maxVelocity", 16} },
        { {"engineAcceleration", 6}, {"maxVelocity", 23} },
        { {"engineAcceleration", 8}, {"maxVelocity", 30} },
    }, { 0, 700, 1800, 4800, 11000 }, MOTOR),

    pack(L.text("v_customs.tuning.turbo"), {
        { {"engineInertia"} },
        { {"engineInertia", -8} },
        { {"engineInertia", -16} },
        { {"engineInertia", -24} },
        { {"engineInertia", -32} },
    }, { 0, 3000, 5500, 9000, 14500 }, MOTOR),

    pack(L.text("v_customs.tuning.brakes"), {
        { {"brakeDeceleration"},       {"brakeBias"} },
        { {"brakeDeceleration", 0.05}, {"brakeBias", 0.10} },
        { {"brakeDeceleration", 0.10}, {"brakeBias", 0.17} },
        { {"brakeDeceleration", 0.15}, {"brakeBias", 0.24} },
        { {"brakeDeceleration", 0.20}, {"brakeBias", 0.30} },
    }, { 0, 500, 1400, 3600, 10500 }),

    pack(L.text("v_customs.tuning.tires"), {
        { {"tractionMultiplier"},       {"tractionLoss"} },
        { {"tractionMultiplier", 0.05}, {"tractionLoss", 0.02} },
        { {"tractionMultiplier", 0.10}, {"tractionLoss", 0.03} },
        { {"tractionMultiplier", 0.15}, {"tractionLoss", 0.04} },
        { {"tractionMultiplier", 0.20}, {"tractionLoss", 0.05} },
    }, { 0, 700, 1200, 1800, 2600 }),

    pack(L.text("v_customs.tuning.weight_reduction"), {
        { {"mass"} },
        { {"mass", -100} },
        { {"mass", -200} },
        { {"mass", -300} },
        { {"mass", -400} },
    }, { 0, 1000, 3000, 7000, 14000 }),

    -- Optical (flat) ----------------------------------------------------
    { name = L.text("v_customs.tuning.hood"),       group = "optical", slot = 0,  price = 1200 },
    { name = L.text("v_customs.tuning.exhaust"),    group = "optical", slot = 13, price = 1800 },
    { name = L.text("v_customs.tuning.spoiler"),    group = "optical", slot = 2,  price = 950 },
    { name = L.text("v_customs.tuning.side_skirt"), group = "optical", slot = 3,  price = 700 },
    { name = L.text("v_customs.tuning.roof_scoop"), group = "optical", slot = 7,  price = 500 },
    { name = L.text("v_customs.tuning.hydraulics"), group = "optical", slot = 9,  price = 4800 },

    -- Folders --------------------------------------------------------
    { name = L.text("v_customs.tuning.bumpers"), folder = true, items = {
        { name = L.text("v_customs.tuning.front_bumper"), group = "optical", slot = 14, price = 1100 },
        { name = L.text("v_customs.tuning.rear_bumper"),  group = "optical", slot = 15, price = 1100 },
    }},

    { name = L.text("v_customs.tuning.wheels"), folder = true, items = {
        wheelSize(L.text("v_customs.tuning.front_wheel_size"), "front"),
        wheelSize(L.text("v_customs.tuning.rear_wheel_size"), "rear"),
        { name = L.text("v_customs.tuning.wheel_types"), group = "optical", slot = 12, price = 1800 },
        { name = L.text("v_customs.tuning.drive_type"), types = CARS, options = {
            { name = L.text("v_customs.tuning.front_wheel_drive"), price = 9500, kind = "handlingProp", prop = "driveType", data = "fwd" },
            { name = L.text("v_customs.tuning.all_wheel_drive"),   price = 9500, kind = "handlingProp", prop = "driveType", data = "awd" },
            { name = L.text("v_customs.tuning.rear_wheel_drive"),  price = 9500, kind = "handlingProp", prop = "driveType", data = "rwd" },
        }},
        { name = L.text("v_customs.tuning.bulletproof_tires"), options = {
            { name = L.text("v_customs.tuning.off"), price = 0,     kind = "flagToggle", flag = "bulletproof", data = false },
            { name = L.text("v_customs.tuning.on"),  price = 6000,  kind = "flagToggle", flag = "bulletproof", data = true },
        }},
    }},

    { name = L.text("v_customs.tuning.respray"), folder = true, items = {
        { name = L.text("v_customs.tuning.primary_color"),   group = "color", slot = "primary",   price = 4000 },
        { name = L.text("v_customs.tuning.secondary_color"), group = "color", slot = "secondary", price = 2400 },
        { name = L.text("v_customs.tuning.headlight_color"), group = "color", slot = "headlight", price = 350, types = MOTOR },
    }},

    -- Extras (flat) ------------------------------------------------
    { name = L.text("v_customs.tuning.steering_lock"), options = {
        { name = L.text("v_customs.menu.default"), price = 1200, kind = "handlingProp", prop = "steeringLock", data = false },
        { name = "30 deg",  price = 1200, kind = "handlingProp", prop = "steeringLock", data = 30 },
        { name = "40 deg",  price = 1200, kind = "handlingProp", prop = "steeringLock", data = 40 },
        { name = "50 deg",  price = 1200, kind = "handlingProp", prop = "steeringLock", data = 50 },
        { name = "60 deg",  price = 1200, kind = "handlingProp", prop = "steeringLock", data = 60 },
    }},
    { name = L.text("v_customs.tuning.lsd_doors"), types = CARS, needs = "door_lf_dummy", options = {
        { name = L.text("v_customs.tuning.off"), price = 0,     kind = "flagToggle", flag = "lsdDoor", data = false },
        { name = L.text("v_customs.tuning.on"),  price = 2800,  kind = "flagToggle", flag = "lsdDoor", data = true },
    }},
    { name = L.text("v_customs.tuning.license_plate"), types = MOTOR, options = {
        { name = L.text("v_customs.tuning.random_plate"),     price = 120, kind = "plate", data = "random" },
        { name = L.text("v_customs.tuning.custom_plate"),  price = Customs.CUSTOM_PLATE_PRICE, kind = "plate", data = "custom" },
        { name = L.text("v_customs.tuning.reset_to_default"), price = 0,   kind = "plate", data = "default" },
    }},
    { name = L.text("v_customs.tuning.horn"), options = {
        { name = L.text("v_customs.tuning.horn_1"), price = 0, kind = "horn", data = 1 },
        { name = L.text("v_customs.tuning.horn_2"), price = 0, kind = "horn", data = 2 },
        { name = L.text("v_customs.tuning.horn_3"), price = 0, kind = "horn", data = 3 },
        { name = L.text("v_customs.tuning.horn_4"), price = 0, kind = "horn", data = 4 },
        { name = L.text("v_customs.tuning.horn_5"), price = 0, kind = "horn", data = 5 },
    }},
}

-- Never sort this table: paths are catalogue indices shared with the server, and
-- the L.config rerun merges texts by index, so the order must be the same on
-- both sides and in every language. client/menu.lua sorts what it shows.

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

-- false when the part can't be used on `veh` at all (the menu hides it).
-- `needs` is only checked where getVehicleComponents exists (client).
function Customs.isPartAvailable(veh, part)
    if part.types and not part.types[getVehicleType(veh)] then return false end
    if part.needs and getVehicleComponents then
        local comps = getVehicleComponents(veh)
        if type(comps) ~= "table" or comps[part.needs] == nil then return false end
    end
    if part.group == "optical" then
        local ups = getVehicleCompatibleUpgrades(veh, part.slot)
        if not ups or #ups == 0 then return false end
    end
    return true
end

-- Applies Customs.PRICE_MULT (rounded to whole euros).
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
end)
