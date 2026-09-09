-- v_customs :: tuning catalogue (shared)
--
-- One data tree that both sides use:
--   * the client (client/menu.lua) turns it into a ui_inac temp menu,
--   * the server (server/tuning.lua) resolves an item by its path and applies /
--     charges it - the server is authoritative, the client never sets a price.
--
-- Node shapes
--   category : { name, camera?, items = { ...nodes... } }
--   leaf     : { name, price, kind, ... }          -- a single buyable option
--   group    : { name, price, kind = "opticalGroup" | "colorGroup", ... }
--              expanded into option leaves at menu-build time; the server maps
--              the chosen option index back through the same rule.
--
-- Paths are "/"-joined 1-based indices into `.items` ("1/3/2"). For a group the
-- path gets one extra trailing segment: the option index ("4/1/2").
--
-- Handling deltas ({prop} = reset to stock, {prop, n} = stock + n) are copied
-- from the original SA Customs resource (see old/sourceG.lua).

Customs = Customs or {}

--------------------------------------------------------------------------------
-- Palettes
--------------------------------------------------------------------------------

-- Respray palette (primary / secondary / headlight all pick from this list).
Customs.PALETTE = {
    { name = "Black",        rgb = {  10,  10,  10 } },
    { name = "White",        rgb = { 245, 245, 245 } },
    { name = "Silver",       rgb = { 170, 175, 180 } },
    { name = "Gunmetal",     rgb = {  55,  60,  68 } },
    { name = "Red",          rgb = { 190,  30,  30 } },
    { name = "Crimson",      rgb = { 120,  15,  25 } },
    { name = "Orange",       rgb = { 235, 120,  20 } },
    { name = "Yellow",       rgb = { 240, 210,  40 } },
    { name = "Lime",         rgb = { 130, 210,  50 } },
    { name = "Green",        rgb = {  30, 130,  55 } },
    { name = "Teal",         rgb = {  20, 130, 130 } },
    { name = "Sky Blue",     rgb = {  80, 170, 235 } },
    { name = "Blue",         rgb = {  35,  70, 190 } },
    { name = "Navy",         rgb = {  20,  30,  80 } },
    { name = "Purple",       rgb = { 110,  45, 170 } },
    { name = "Pink",         rgb = { 230, 110, 180 } },
    { name = "Brown",        rgb = {  90,  60,  35 } },
    { name = "Beige",        rgb = { 210, 195, 160 } },
}

-- Neon underglow colours -> the replacement model ids the neon module loads.
Customs.NEONS = {
    { name = "White",     id = "white"     },
    { name = "Blue",      id = "blue"      },
    { name = "Green",     id = "green"     },
    { name = "Red",       id = "red"       },
    { name = "Yellow",    id = "yellow"    },
    { name = "Pink",      id = "pink"      },
    { name = "Orange",    id = "orange"    },
    { name = "Light Blue", id = "lightblue" },
    { name = "Rasta",     id = "rasta"     },
    { name = "Ice",       id = "ice"       },
}

--------------------------------------------------------------------------------
-- Helpers for the performance packs (Default + Upgrade 1..4)
--------------------------------------------------------------------------------

local function packs(kind, camera, deltaSets, prices)
    local names = { "Default", "Upgrade 1", "Upgrade 2", "Upgrade 3", "Upgrade 4" }
    local out = {}
    for i = 1, 5 do
        out[i] = {
            name  = names[i],
            price = prices[i],
            kind  = kind,
            data  = deltaSets[i],
        }
    end
    return { camera = camera, items = out }
end

--------------------------------------------------------------------------------
-- The tree
--------------------------------------------------------------------------------

Customs.categories = {
    ----------------------------------------------------------------------------
    { name = "Performance", camera = "engine", items = {
        (function()
            local p = packs("performance", "engine", {
                { {"engineAcceleration"},    {"maxVelocity"} },
                { {"engineAcceleration", 2}, {"maxVelocity", 10} },
                { {"engineAcceleration", 4}, {"maxVelocity", 16} },
                { {"engineAcceleration", 6}, {"maxVelocity", 23} },
                { {"engineAcceleration", 8}, {"maxVelocity", 30} },
            }, { 0, 1500, 3000, 4500, 6000 })
            p.name = "Engine"
            return p
        end)(),

        (function()
            local p = packs("performance", "engine", {
                { {"engineInertia"} },
                { {"engineInertia", -8} },
                { {"engineInertia", -16} },
                { {"engineInertia", -24} },
                { {"engineInertia", -32} },
            }, { 0, 6000, 12000, 18000, 24000 })
            p.name = "Turbo"
            return p
        end)(),

        (function()
            local p = packs("performance", "wheel_rf", {
                { {"brakeDeceleration"},       {"brakeBias"} },
                { {"brakeDeceleration", 0.05}, {"brakeBias", 0.10} },
                { {"brakeDeceleration", 0.10}, {"brakeBias", 0.17} },
                { {"brakeDeceleration", 0.15}, {"brakeBias", 0.24} },
                { {"brakeDeceleration", 0.20}, {"brakeBias", 0.30} },
            }, { 0, 4500, 9000, 12500, 16000 })
            p.name = "Brakes"
            return p
        end)(),

        (function()
            local p = packs("performance", "wheel_rb", {
                { {"tractionMultiplier"},       {"tractionLoss"} },
                { {"tractionMultiplier", 0.05}, {"tractionLoss", 0.02} },
                { {"tractionMultiplier", 0.10}, {"tractionLoss", 0.03} },
                { {"tractionMultiplier", 0.15}, {"tractionLoss", 0.04} },
                { {"tractionMultiplier", 0.20}, {"tractionLoss", 0.05} },
            }, { 0, 4500, 9000, 12500, 16000 })
            p.name = "Tires"
            return p
        end)(),

        (function()
            local p = packs("performance", "engine", {
                { {"mass"} },
                { {"mass", -100} },
                { {"mass", -200} },
                { {"mass", -300} },
                { {"mass", -400} },
            }, { 0, 4250, 7500, 11000, 15000 })
            p.name = "Weight Reduction"
            return p
        end)(),

        { name = "Nitro", camera = "boot", items = {
            { name = "Remove",  price = 0,     kind = "nitro", data = 0 },
            { name = "25%",     price = 10000, kind = "nitro", data = 25 },
            { name = "50%",     price = 15000, kind = "nitro", data = 50 },
            { name = "75%",     price = 25000, kind = "nitro", data = 75 },
            { name = "100%",    price = 30000, kind = "nitro", data = 100 },
        }},
    }},

    ----------------------------------------------------------------------------
    { name = "Optical", camera = "side", items = {
        { name = "Front Bumper", camera = "bump_front", kind = "opticalGroup", slot = 14, price = 1000 },
        { name = "Rear Bumper",  camera = "bump_rear",  kind = "opticalGroup", slot = 15, price = 1000 },
        { name = "Hood",         camera = "engine",     kind = "opticalGroup", slot = 0,  price = 1000 },
        { name = "Exhaust",      camera = "boot",       kind = "opticalGroup", slot = 13, price = 2000 },
        { name = "Spoiler",      camera = "boot",       kind = "opticalGroup", slot = 2,  price = 1500 },
        { name = "Wheels",       camera = "wheel_rf",   kind = "opticalGroup", slot = 12, price = 5000 },
        { name = "Side Skirt",   camera = "side",       kind = "opticalGroup", slot = 3,  price = 1000 },
        { name = "Roof Scoop",   camera = "engine",     kind = "opticalGroup", slot = 7,  price = 1000 },
        { name = "Hydraulics",   camera = "wheel_rf",   kind = "opticalGroup", slot = 9,  price = 15000 },
    }},

    ----------------------------------------------------------------------------
    { name = "Neon", camera = "under", kind = "neonGroup", price = 5000 },

    ----------------------------------------------------------------------------
    { name = "Extras", camera = "side", items = {
        { name = "Front Wheel Size", camera = "bump_front", items = {
            { name = "Very Narrow", price = 20000, kind = "wheelWidth", side = "front", data = "verynarrow" },
            { name = "Narrow",      price = 10000, kind = "wheelWidth", side = "front", data = "narrow" },
            { name = "Default",     price = 5000,  kind = "wheelWidth", side = "front", data = "default" },
            { name = "Wide",        price = 10000, kind = "wheelWidth", side = "front", data = "wide" },
            { name = "Very Wide",   price = 20000, kind = "wheelWidth", side = "front", data = "verywide" },
        }},
        { name = "Rear Wheel Size", camera = "bump_rear", items = {
            { name = "Very Narrow", price = 20000, kind = "wheelWidth", side = "rear", data = "verynarrow" },
            { name = "Narrow",      price = 10000, kind = "wheelWidth", side = "rear", data = "narrow" },
            { name = "Default",     price = 5000,  kind = "wheelWidth", side = "rear", data = "default" },
            { name = "Wide",        price = 10000, kind = "wheelWidth", side = "rear", data = "wide" },
            { name = "Very Wide",   price = 20000, kind = "wheelWidth", side = "rear", data = "verywide" },
        }},
        { name = "Offroad", items = {
            { name = "Default", price = 2500, kind = "offroad", data = "default" },
            { name = "Dirt",    price = 5000, kind = "offroad", data = "dirt" },
            { name = "Sand",    price = 5000, kind = "offroad", data = "sand" },
        }},
        { name = "Drive Type", items = {
            { name = "Front Wheel Drive", price = 10000, kind = "handlingProp", prop = "driveType", data = "fwd" },
            { name = "All Wheel Drive",   price = 10000, kind = "handlingProp", prop = "driveType", data = "awd" },
            { name = "Rear Wheel Drive",  price = 10000, kind = "handlingProp", prop = "driveType", data = "rwd" },
        }},
        { name = "Steering Lock", items = {
            { name = "Default",  price = 7500, kind = "handlingProp", prop = "steeringLock", data = false },
            { name = "30 deg",   price = 7500, kind = "handlingProp", prop = "steeringLock", data = 30 },
            { name = "40 deg",   price = 7500, kind = "handlingProp", prop = "steeringLock", data = 40 },
            { name = "50 deg",   price = 7500, kind = "handlingProp", prop = "steeringLock", data = 50 },
            { name = "60 deg",   price = 7500, kind = "handlingProp", prop = "steeringLock", data = 60 },
        }},
        { name = "Bulletproof Tires", items = {
            { name = "Off", price = 0,     kind = "flagToggle", flag = "bulletproof", data = false },
            { name = "On",  price = 85000, kind = "flagToggle", flag = "bulletproof", data = true },
        }},
        { name = "LSD Doors", camera = "side", items = {
            { name = "Off", price = 0,     kind = "flagToggle", flag = "lsdDoor", data = false },
            { name = "On",  price = 35000, kind = "flagToggle", flag = "lsdDoor", data = true },
        }},
        { name = "Air Ride", camera = "wheel_rf", items = {
            { name = "Remove",  price = 0,     kind = "airride", data = 0 },
            { name = "Level 1", price = 12000, kind = "airride", data = 1 },
            { name = "Level 2", price = 14000, kind = "airride", data = 2 },
            { name = "Level 3", price = 16000, kind = "airride", data = 3 },
            { name = "Level 4", price = 18000, kind = "airride", data = 4 },
            { name = "Level 5", price = 20000, kind = "airride", data = 5 },
        }},
        { name = "License Plate", camera = "bump_rear", items = {
            { name = "Random Plate",     price = 5000,  kind = "plate", data = "random" },
            { name = "Custom Plate...",  price = 15000, kind = "plate", data = "custom" },
            { name = "Reset To Default", price = 0,     kind = "plate", data = "default" },
        }},
    }},

    ----------------------------------------------------------------------------
    { name = "Respray", camera = "front", items = {
        { name = "Primary Color",   kind = "colorGroup", slot = "primary",   price = 10000 },
        { name = "Secondary Color", kind = "colorGroup", slot = "secondary", price = 10000 },
        { name = "Headlight Color", kind = "colorGroup", slot = "headlight", price = 8000, camera = "front" },
    }},

    ----------------------------------------------------------------------------
    { name = "Horn", camera = "engine", items = {
        { name = "Horn 1", price = 0, kind = "horn", data = 1 },
        { name = "Horn 2", price = 0, kind = "horn", data = 2 },
        { name = "Horn 3", price = 0, kind = "horn", data = 3 },
        { name = "Horn 4", price = 0, kind = "horn", data = 4 },
        { name = "Horn 5", price = 0, kind = "horn", data = 5 },
    }},
}

Customs.root = { items = Customs.categories }

--------------------------------------------------------------------------------
-- Path resolution (shared)
--------------------------------------------------------------------------------

-- Splits "1/3/2" -> { 1, 3, 2 }
function Customs.splitPath(path)
    local out = {}
    for seg in tostring(path):gmatch("[^/]+") do
        out[#out + 1] = tonumber(seg)
    end
    return out
end

-- Walks the tree to the node named by `path`. Returns node, remainingIndex
-- where remainingIndex is set only when the path dived one step past a
-- group node (the option index).
function Customs.resolve(path)
    local segs = Customs.splitPath(path)
    local node = Customs.root
    for i, idx in ipairs(segs) do
        if node.items and node.items[idx] then
            node = node.items[idx]
        elseif node.kind and (node.kind == "opticalGroup" or node.kind == "colorGroup" or node.kind == "neonGroup") then
            -- past a group: this segment is the option index
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
