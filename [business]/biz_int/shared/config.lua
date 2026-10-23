if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- biz_int / shared/config.lua
-- The organization interiors, independent of world_interiors. Buildings (the
-- doors) come from biz_core (BIZ.BUILDINGS); this file holds the insides.
--
-- One entrance can lead to many insides: every unit (a property owned by one
-- company) has its own dimension (biz_core: 30000 + unit id). A player only
-- gets into the units of his own company and of the company he is a
-- temporary associate of.
--
-- Template fields:
--   interior   GTA interior id
--   spawn      arrival point inside {x, y, z, rot}
--   exit       exit marker inside (defaults to spawn)
--   computer   desk position {x, y, z, rot}: a desk, a PC and a chair are
--              created there; the PC carries the "Use computer" menu
--   objects    extra props { model, x, y, z, rx, ry, rz, flag }
--   peds       { skin, x, y, z, rot, anim = {block, name}, flag }
--   flag       optional: only when the unit data key `flag` is true
--              (biz_core setUnitData, e.g. "capacity" / "staff" upgrades)
--
-- Positions marked "verify" are estimates: stand where they should be and use
--   /bizpos <template> <spawn|exit|computer>   (admin, saved in data/positions.json)

BINT = {
    key        = "e",
    fadeMs     = 400,
    cooldownMs = 1000,
    emptyKeepMs = 30000,            -- an empty inside is destroyed after this
    adminLevel = 5,                 -- /bizpos
    positionsFile = "data/positions.json",

    markerSize  = 1.4,
    markerType  = "cylinder",
    enterColor  = { 46, 160, 110, 140 },
    exitColor   = { 255, 170, 60, 140 },

    labelDistance     = 20,
    labelFullDistance = 6,
    labelMinScale     = 0.55,
    labelHeight       = 0.4,

    -- radar icons (v_radar draws the standard blips) of owned / accessible places
    blipIcons = { office = 31, weed = 62, casino = 25 },
    blipDistance = 99999,

    -- props
    deskModel  = 2008,   -- officedesk1
    pcModel    = 2190,   -- PC_1
    chairModel = 1714,   -- kb_swivelchair1
    pcOffset   = { 0.0, 0.05, 0.78 },     -- from the desk origin
    chairOffset = { 0.0, -0.95, 0.0 },
}

-- old template ids (a biz_core that was not restarted still sends these)
BINT.TEMPLATE_ALIASES = {
    office_executive = "office_exclusive",
    office_starter   = "office_standard",
}

local function grid(model, x0, y0, z, cols, rows, dx, dy, flag)
    local out = {}
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            out[#out + 1] = { model, x0 + c * dx, y0 + r * dy, z, 0, 0, (r * 37 + c * 53) % 360, flag = flag }
        end
    end
    return out
end

local function join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, v in ipairs(list) do out[#out + 1] = v end
    end
    return out
end

BINT.TEMPLATES = {
    -- Offices: one interior per tier, every exclusive office looks the same
    -- inside and so does every standard one.
    -- Exclusive: Wu Zi Mu's office (Chinatown betting place, upstairs)
    office_exclusive = {
        interior = 1,
        spawn    = { -2159.12, 641.52, 1052.38, 90 },
        computer = { -2162.60, 643.40, 1051.38, 270 },    -- verify
    },
    -- Standard: Las Venturas Planning Dep.
    office_standard = {
        interior = 3,
        spawn    = { 390.87, 173.81, 1007.39, 270 },
        computer = { 386.80, 175.60, 1007.38, 90 },       -- verify
    },
    -- Warehouse 2: grow room
    weed_farm = {
        interior = 18,
        spawn    = { 1296.63, 0.59, 1001.02, 0 },
        computer = { 1293.60, 2.60, 1000.02, 90 },        -- verify
        objects  = join(
            grid(3409, 1298.5, 3.0, 1000.05, 4, 3, 1.6, 1.8),                   -- base plants
            grid(3409, 1298.5, 8.4, 1000.05, 4, 2, 1.6, 1.8, "capacity"),       -- capacity upgrade
            {
                { 3761, 1293.2, 7.5, 1000.02, 0, 0, 90 },                       -- shelves
                { 2912, 1294.4, 5.2, 1000.02, 0, 0, 0 },                        -- crates
                { 2912, 1294.4, 5.2, 1000.72, 0, 0, 15 },
                { 1578, 1293.9, 2.6, 1000.81, 0, 0, 0 },                        -- product on the desk
            }
        ),
        peds = {
            { 162, 1299.3, 4.8, 1001.02, 180, anim = { "BOMBER", "BOM_Plant_Loop" }, flag = "staff" },
            { 202, 1302.5, 6.6, 1001.02, 90,  anim = { "BOMBER", "BOM_Plant_Loop" }, flag = "staff" },
            { 134, 1300.9, 10.2, 1001.02, 0,  anim = { "BOMBER", "BOM_Plant_Loop" }, flag = "staff" },
        },
    },
    -- The Casino (Redsands West), office corner
    casino = {
        interior = 12,
        spawn    = { 1133.07, -12.77, 999.75, 0 },
        computer = { 1130.60, -9.80, 999.10, 90 },        -- verify
    },
}
