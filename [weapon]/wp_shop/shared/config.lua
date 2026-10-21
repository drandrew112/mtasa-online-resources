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
        [2] = {
            name     = "Ammu-Nation",
            interior = 4,
            -- measured live 2026-10-21: floor z 1000.52, glass counter top z 1001.53,
            -- x 292.18..293.19, y -82..-86.5 (faces west); door (1537) in the south wall, y -87.14
            exit     = { x = 285.60, y = -86.30, z = 1001.52, rot = 180 },
            inside   = { x = 286.20, y = -84.50, z = 1001.52, rot = 0 },
            clerk    = { x = 293.89, y = -84.25, z = 1001.52, rot = 90 },
            counter  = { x = 291.46, y = -84.25, z = 1001.52 },
            preview  = { x = 292.69, y = -84.25, z = 1001.88 },
            camera   = { x = 290.89, y = -84.25, z = 1002.45 },
        },
        [3] = {
            name     = "Ammu-Nation",
            interior = 6,
            -- measured live 2026-10-21: floor z 1000.52, counter top z 1001.53,
            -- x 286..293.5, y -110.13..-111.16 (faces north), clerk stool at (290, -112);
            -- door (1533) at the end of the south vestibule, y -112.42
            exit     = { x = 296.90, y = -111.60, z = 1001.52, rot = 180 },
            inside   = { x = 296.90, y = -109.80, z = 1001.52, rot = 90 },
            clerk    = { x = 291.00, y = -111.86, z = 1001.52, rot = 0 },
            counter  = { x = 291.00, y = -109.41, z = 1001.52 },
            preview  = { x = 291.00, y = -110.65, z = 1001.88 },
            camera   = { x = 291.00, y = -108.85, z = 1002.45 },
        },
        [4] = {
            name     = "Ammu-Nation",
            interior = 6,
            -- measured live 2026-10-21: floor z 998.59, counter top z 999.67,
            -- x 310..314.5, y -166.49..-167.41 (faces north, L arm down x 314.5);
            -- door (1533) in the south wall, y -170.65
            exit     = { x = 316.50, y = -169.80, z = 999.59, rot = 180 },
            inside   = { x = 316.50, y = -168.00, z = 999.59, rot = 0 },
            clerk    = { x = 312.25, y = -168.11, z = 999.59, rot = 0 },
            counter  = { x = 312.25, y = -165.77, z = 999.59 },
            preview  = { x = 312.25, y = -166.95, z = 1000.02 },
            camera   = { x = 312.25, y = -165.15, z = 1000.59 },
        },
        -- Two-floor shop with the shooting range: no stock entrance in the world, not measured.
        [5] = { name = "Ammu-Nation", interior = 7, exit = { x = 315.39, y = -142.24, z = 1000.55, rot = 180 } },
    },

    -- Shops: entrance outside, template, fixed inside dimension, catalog.
    -- outside = arrival point when leaving (default: the entrance marker).
    -- Every stock Ammu-Nation entrance of the map, measured live 2026-10-21: enter = stock enex
    -- point on the ground (+1 m, moved out to ~0.8 m from the door where it touched it),
    -- outside = 1.6 m further out, facing away from the door.
    shops = {
        -- template 1 (AMMUN1)
        {
            id = "ammu_ls_market", interior = 1, dimension = 2201, catalog = "default",
            enter   = { x = 1368.35, y = -1279.06, z = 13.55 },
            outside = { x = 1366.75, y = -1279.06, z = 13.55, rot = 90 },
        },
        {
            id = "ammu_sf_oceanflats", interior = 1, dimension = 2202, catalog = "default",
            enter   = { x = -2625.85, y = 208.35, z = 4.81 },
            outside = { x = -2625.85, y = 209.95, z = 4.62, rot = 0 },
        },
        -- template 2 (AMMUN2)
        {
            id = "ammu_rc_blueberry", interior = 2, dimension = 2203, catalog = "default",
            enter   = { x = 242.67, y = -178.48, z = 1.58 },
            outside = { x = 241.07, y = -178.48, z = 1.58, rot = 90 },
        },
        {
            id = "ammu_rc_palomino", interior = 2, dimension = 2204, catalog = "default",
            enter   = { x = 2333.43, y = 61.52, z = 26.71 },
            outside = { x = 2335.03, y = 61.52, z = 26.48, rot = 270 },
        },
        {
            id = "ammu_lv_comealot", interior = 2, dimension = 2205, catalog = "default",
            enter   = { x = 2159.10, y = 943.33, z = 10.82 },
            outside = { x = 2157.50, y = 943.33, z = 10.82, rot = 90 },
        },
        {
            id = "ammu_lv_oldstrip", interior = 2, dimension = 2206, catalog = "default",
            enter   = { x = 2539.04, y = 2083.56, z = 10.82 },
            outside = { x = 2537.44, y = 2083.56, z = 10.82, rot = 90 },
        },
        -- template 3 (AMMUN3)
        {
            id = "ammu_bc_bonecounty", interior = 3, dimension = 2207, catalog = "default",
            enter   = { x = 777.23, y = 1871.47, z = 4.91 },
            outside = { x = 778.83, y = 1871.47, z = 4.91, rot = 270 },
        },
        {
            id = "ammu_bc_fortcarson", interior = 3, dimension = 2208, catalog = "default",
            enter   = { x = -315.68, y = 829.87, z = 14.24 },
            outside = { x = -314.08, y = 829.87, z = 14.24, rot = 270 },
        },
        {
            id = "ammu_ws_angelpine", interior = 3, dimension = 2209, catalog = "default",
            enter   = { x = -2093.35, y = -2464.59, z = 30.63 },
            outside = { x = -2092.34, y = -2463.34, z = 30.63, rot = 321 },
        },
        {
            id = "ammu_ls_willowfield", interior = 3, dimension = 2210, catalog = "default",
            enter   = { x = 2400.50, y = -1981.48, z = 13.55 },
            outside = { x = 2400.50, y = -1979.88, z = 13.55, rot = 0 },
        },
        -- template 4 (AMMUN5)
        {
            id = "ammu_tr_elquebrados", interior = 4, dimension = 2211, catalog = "default",
            enter   = { x = -1508.89, y = 2610.20, z = 55.84 },
            outside = { x = -1508.89, y = 2608.60, z = 55.84, rot = 180 },
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
