-- wp_shop / shared/config.lua
-- Weapon shops (Ammu-Nation). Interior templates are registered through world_interiors, one
-- fixed dimension per shop. Inside: a clerk ped behind the counter and a shop marker in front of
-- it. E in the shop marker = the camera looks at a 3D weapon above the counter (arrows switch,
-- Enter picks, Backspace leaves); the picked weapon and its ammo are bought in a ui_inac temp menu.
-- All x/y/z values are player positions (feet ~1 m lower); the markers are put 1 m lower.

WS = {
    key        = "e",                    -- open the weapon browser in a shop marker
    blip       = 6,                      -- v_radar blip icon (Ammu-Nation) on the entrances
    blipRange  = 300,
    markerSize = 1.0,
    markerColor = { 255, 90, 60, 140 },
    clerkModel = 179,                    -- Ammu-Nation salesman
    maxAmmo    = 9999,                   -- wp_manager WP.MAX_AMMO
    ammoPacks  = { 1, 5 },               -- magazines / boxes per ammo row of the temp menu
    thrownPacks = { 1, 5 },              -- pieces per row for thrown weapons

    -- 3D weapon preview above the counter. The camera looks at the weapon from the
    -- template's `camera` point direction; its distance follows the model size.
    preview = {
        swing      = 35,                 -- degrees the weapon turns left/right
        swingSpeed = 0.0011,             -- radians per ms
        distK      = 3.4,                -- camera distance = model radius * distK
        minDist    = 1.2,
        maxDist    = 3.2,
        fov        = 70,
    },

    -- Marker UI (3D label above the shop markers, work_core label look)
    label = {
        color        = { 255, 90, 60 },
        distance     = 12,
        fullDistance = 4,
        minScale     = 0.6,
        height       = 1.4,              -- above the marker base
    },

    -- Interior templates, by number: 1 = Ammu-Nation 1 (stock AMMUN1), ...
    -- Several shops may use one template, each in its own dimension.
    --   exit    = inside marker (to leave), inside = arrival point when entering
    --   clerk   = clerk ped (rot = facing), counter = shop marker (the buyer stands here)
    --   preview = the 3D weapon, camera = the camera looks at the weapon from this direction
    -- Only templates with clerk/counter/preview/camera can host a shop.
    interiors = {
        [1] = {
            name     = "Ammu-Nation",
            interior = 1,
            -- measured live 2026-10-21: counter top z 1001.53, x 292.6..297.4, y -38.87..-40.2;
            -- door (Gen_doorEXT12) in the south wall at x 285.7
            exit     = { x = 285.95, y = -41.25, z = 1001.52, rot = 180 },
            inside   = { x = 286.70, y = -39.60, z = 1001.52, rot = 0 },
            clerk    = { x = 295.00, y = -40.90, z = 1001.52, rot = 0 },
            counter  = { x = 295.00, y = -38.15, z = 1001.52 },
            preview  = { x = 295.00, y = -39.50, z = 1001.88 },
            camera   = { x = 295.00, y = -37.70, z = 1002.45 },
        },
        -- Not measured yet: only the stock arrival points (floor z + 0.95). Fill in
        -- clerk / counter / preview / camera before a shop uses them.
        [2] = { name = "Ammu-Nation", interior = 4, exit = { x = 285.80, y = -85.45, z = 1001.49, rot = 270 } },
        [3] = { name = "Ammu-Nation", interior = 6, exit = { x = 296.92, y = -111.97, z = 1001.52, rot = 121 } },
        [4] = { name = "Ammu-Nation", interior = 6, exit = { x = 316.53, y = -169.61, z = 999.61, rot = 0 } },
        [5] = { name = "Ammu-Nation", interior = 7, exit = { x = 315.39, y = -142.24, z = 1000.55, rot = 180 } },
    },

    -- Shops: entrance outside, template, fixed inside dimension, catalog.
    -- outside = arrival point when leaving (default: the entrance marker).
    -- Other stock entrances of template 1: San Fierro (-2625.85, 208.35, 4.99).
    shops = {
        {
            id = "ammu_ls_market", interior = 1, dimension = 1, catalog = "default",
            enter   = { x = 1368.35, y = -1279.06, z = 13.55 },
            outside = { x = 1368.35, y = -1280.70, z = 13.55, rot = 180 },
        },
    },

    -- Weapons for sale, in browser order
    catalogs = {
        default = { 22, 23, 24, 25, 26, 27, 28, 29, 32, 30, 31, 33, 34, 16, 18, 4, 5 },
    },

    -- model = weapon object for the preview, price = the weapon,
    -- mag = rounds in one magazine / box, magPrice = one magazine / box, box = sold as a box
    -- thrown weapons: price = one piece (no separate ammo)
    weapons = {
        [4]  = { model = 335, price = 500 },                                    -- knife
        [5]  = { model = 336, price = 400 },                                    -- baseball bat
        [22] = { model = 346, price = 1500,  mag = 17, magPrice = 80 },          -- colt 45
        [23] = { model = 347, price = 2000,  mag = 17, magPrice = 90 },          -- silenced pistol
        [24] = { model = 348, price = 5000,  mag = 7,  magPrice = 120 },         -- desert eagle
        [25] = { model = 349, price = 4000,  mag = 10, magPrice = 150, box = true }, -- shotgun
        [26] = { model = 350, price = 5500,  mag = 10, magPrice = 150, box = true }, -- sawn-off
        [27] = { model = 351, price = 9500,  mag = 7,  magPrice = 200 },         -- combat shotgun
        [28] = { model = 352, price = 3500,  mag = 50, magPrice = 150 },         -- uzi
        [29] = { model = 353, price = 5000,  mag = 30, magPrice = 160 },         -- mp5
        [32] = { model = 372, price = 3800,  mag = 50, magPrice = 150 },         -- tec-9
        [30] = { model = 355, price = 10000, mag = 30, magPrice = 250 },         -- ak-47
        [31] = { model = 356, price = 12000, mag = 50, magPrice = 320 },         -- m4
        [33] = { model = 357, price = 7500,  mag = 10, magPrice = 200, box = true }, -- country rifle
        [34] = { model = 358, price = 20000, mag = 5,  magPrice = 300, box = true }, -- sniper rifle
        [16] = { model = 342, price = 800,   thrown = true },                    -- grenade
        [18] = { model = 344, price = 400,   thrown = true },                    -- molotov
    },
}

-- shop id -> shop
WS.shopById = {}
for _, shop in ipairs(WS.shops) do WS.shopById[shop.id] = shop end

-- a template can host a shop when every inside point is given
function WS.isComplete(int)
    return int and int.exit and int.clerk and int.counter and int.preview and int.camera and true or false
end

-- weapon list of a shop (only ids that have a weapons entry)
function WS.catalog(shop)
    local out = {}
    for _, id in ipairs(WS.catalogs[shop and shop.catalog or ""] or {}) do
        if WS.weapons[id] then out[#out + 1] = id end
    end
    return out
end

function WS.sells(shop, id)
    for _, w in ipairs(WS.catalog(shop)) do
        if w == id then return true end
    end
    return false
end
