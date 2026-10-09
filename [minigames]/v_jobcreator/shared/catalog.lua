-- What creators may place / pick. The server only accepts models listed here.
-- Object models were checked against the game's model table (dff names in the
-- comments) through the claude-mcp probe.

CATALOG = {}

CATALOG.objects = {
    { name = "Ramps & Jumps", items = {
        { 1633, "Land jump" },              -- landjump
        { 1634, "Land jump (wide)" },       -- landjump2
        { 1632, "Water jump" },             -- waterjump1
        { 1631, "Water jump 2" },           -- waterjump2
        { 1655, "Water jump (double)" },    -- waterjumpx2
        { 1660, "Ramp" },                   -- ramp
        { 1503, "Small ramp" },             -- DYN_RAMP
        { 1245, "Wooden ramp" },            -- newramp
        { 2893, "Car ramp" },               -- kmb_ramp
        { 3080, "Billboard jump" },         -- ad_jump
        { 2931, "Jump ramp" },              -- kmb_jump1
        { 5152, "Stunt ramp" },             -- stuntramp1_las2
        { 5153, "Stunt ramp 2" },           -- stuntramp7_las2
        { 13593, "Kicker ramp" },           -- kickramp03
        { 13641, "Kicker ramp 2" },         -- kickramp04
        { 13604, "Kicker ramp 3" },         -- kickramp05
        { 13645, "Kicker ramp 4" },         -- kickramp06
        { 13637, "Tube ramp" },             -- tuberamp
        { 13646, "Landing pad" },           -- ramplandpad
        { 13592, "Loop" },                  -- loopbig
        { 18367, "Bike log" },              -- cw2_bikelog
        { 16367, "Quay ramp" },             -- des_quayramp
    } },
    { name = "Barriers & Fences", items = {
        { 1228, "Roadwork barrier" },       -- roadworkbarrier1
        { 1237, "Street barrier" },         -- strtbarrier01
        { 1282, "Barrier with light" },     -- Barrierm
        { 1422, "Road barrier" },           -- DYN_ROADBARRIER_5
        { 1423, "Road barrier 2" },         -- DYN_ROADBARRIER_4
        { 1424, "Road barrier 3" },         -- DYN_ROADBARRIER_2
        { 1425, "Road barrier 4" },         -- DYN_ROADBARRIER_3
        { 1459, "Road barrier 5" },         -- DYN_ROADBARRIER_6
        { 1427, "Concrete barrier" },       -- CJ_ROADBARRIER
        { 973, "Highway barrier" },         -- sub_roadbarrier
        { 2920, "Police barrier" },         -- police_barrier
        { 3091, "Track barrier" },          -- imy_track_barrier
        { 970, "Small fence" },             -- fencesmallb
        { 974, "Tall fence" },              -- tall_fence
        { 1652, "Wooden fence" },           -- fencehaiti
        { 3936, "Barbed wire fence" },      -- bwire_fence
        { 987, "Electric fence" },          -- elecfence_BAR
    } },
    { name = "Road & Signs", items = {
        { 1238, "Traffic cone" },           -- trafficcone
        { 1215, "Bollard light" },          -- bollardlight
        { 1662, "Roadblock" },              -- nt_roadblockCI
        { 1315, "Traffic light" },          -- trafficlight1
        { 1229, "Bus stop sign" },          -- bussign1
        { 1233, "No parking sign" },        -- noparkingsign1
        { 1311, "Road sign" },              -- gen_roadsign1
        { 1312, "Road sign 2" },            -- gen_roadsign2
        { 3335, "Country road sign" },      -- CE_roadsign1
        { 1226, "Lamp post" },              -- lamppost3
        { 1290, "Lamp post 2" },            -- lamppost2
        { 1297, "Lamp post 3" },            -- lamppost1
        { 3460, "Vegas lamp post" },        -- vegaslampost
        { 3864, "Floodlight" },             -- WS_floodlight
    } },
    { name = "Containers & Crates", items = {
        { 2932, "Container (blue)" },       -- kmb_container_blue
        { 2934, "Container (red)" },        -- kmb_container_red
        { 2935, "Container (yellow)" },     -- kmb_container_yel
        { 3043, "Container (open)" },       -- kmb_container_open
        { 3073, "Container (broken)" },     -- kmb_container_broke
        { 944, "Crate" },                   -- Crate1
        { 960, "Crate 2" },                 -- Crate2
        { 1224, "Crate 3" },                -- Crate4
        { 964, "Metal crate" },             -- CJ_METAL_CRATE
        { 2669, "Large crate" },            -- CJ_CHRIS_CRATE
        { 2912, "Wooden box" },             -- temp_crate1
        { 2977, "Military crate" },         -- kmilitary_crate
        { 3576, "Dock crates" },            -- DockCrates2_LA
        { 3577, "Dock crates 2" },          -- DockCrates1_LA
        { 1271, "Gun box" },                -- gunbox
        { 1685, "Pallet block" },           -- blockpallet
        { 1421, "Boxes" },                  -- DYN_BOXES
        { 1431, "Box pile" },               -- DYN_BOX_PILE
    } },
    { name = "Cover", items = {
        { 2060, "Sandbag" },                -- CJ_SANDBAG
        { 1218, "Barrel" },                 -- barrel1
        { 1217, "Barrel 2" },               -- barrel2
        { 1222, "Barrel 3" },               -- barrel3
        { 1225, "Explosive barrel" },       -- barrel4
        { 3046, "Wooden barrel" },          -- kb_barrel
        { 1327, "Junk tire" },              -- JunkTire
        { 2651, "Skate wall" },             -- CJ_Skate_wall1
        { 2650, "Skate wall 2" },           -- CJ_Skate_wall2
        { 2652, "Skate cubes" },            -- CJ_SKATE_CUBES
        { 1368, "Blocker bench" },          -- CJ_BLOCKER_BENCH
        { 3374, "Hay bale" },               -- SW_haybreak02
        { 12917, "Hay pile" },              -- sw_haypile03
    } },
    { name = "Structures", items = {
        { 3458, "Long slab" },              -- vgncarshade1
        { 8838, "Wide slab" },              -- vgEhshade01_lvs
        { 18449, "Road bridge" },           -- cs_roadbridge01
        { 18450, "Road bridge 2" },         -- cs_roadbridge04
        { 8171, "Airport plate" },          -- vgsSairportland06
        { 8172, "Airport plate 2" },        -- vgsSairportland07
        { 8357, "Airport plate 3" },        -- vgsSairportland14
        { 3925, "Wooden bridge" },          -- bridge_1
        { 1426, "Scaffold" },               -- DYN_SCAFFOLD
        { 1436, "Scaffold 2" },             -- DYN_SCAFFOLD_2
        { 3361, "Wooden stairs" },          -- cxref_woodstair
        { 3502, "Concrete tube" },          -- vgsN_con_tube
        { 5400, "Skate tube" },             -- laeskatetube1
        { 3865, "Concrete pipe" },          -- concpipe_SFXRF
        { 17043, "Concrete arch" },         -- concretearch1
        { 16082, "Quarry platform" },       -- des_quarryplatform
        { 18284, "Canopy" },                -- cw_tscanopy
    } },
    { name = "Nature", items = {
        { 615, "Tree" },                    -- veg_tree3
        { 616, "Tree 2" },                  -- veg_treea1
        { 617, "Tree 3" },                  -- veg_treeb1
        { 703, "Big tree" },                -- sm_veg_tree7_big
        { 671, "Bushy tree" },              -- sm_bushytree
        { 654, "Pine tree" },               -- pinetree08
        { 659, "Pine tree 2" },             -- pinetree01
        { 621, "Palm" },                    -- veg_palm02
        { 645, "Big palm" },                -- veg_palmbig14
        { 710, "Vegas palm" },              -- vgs_palm01
        { 759, "Large bush" },              -- sm_bush_large_1
        { 760, "Small bush" },              -- sm_bush_small_1
        { 800, "Bush" },                    -- genVEG_bush07
        { 744, "Rock" },                    -- sm_scrub_rock4
        { 745, "Rock 2" },                  -- sm_scrub_rock5
        { 897, "Sea rock" },                -- searock01
        { 898, "Sea rock 2" },              -- searock02
        { 1303, "Quarry rock" },            -- dyn_quarryrock03
        { 3929, "Desert rock" },            -- d_rock
        { 2936, "Boulder" },                -- kmb_rock
    } },
    { name = "Decoration", items = {
        { 1280, "Park bench" },             -- parkbench1
        { 1256, "Stone bench" },            -- Stonebench1
        { 1291, "Post box" },               -- postbox1
        { 1234, "Phone sign" },             -- phonesign
        { 1294, "Light post" },             -- mlamppost
        { 3534, "Chinese lamp" },           -- trdlamp01
        { 1568, "Chinese lamp post" },      -- chinalamp_sf
        { 638, "Planter with bush" },       -- kb_planter+bush
        { 1361, "Bush prop" },              -- CJ_BUSH_PROP2
        { 1338, "Plastic crates" },         -- PlasticCrates
        { 2898, "Fun turf" },               -- funturf_law
    } },
}

CATALOG.vehicles = {
    { name = "Sports", items = { 411, 541, 415, 429, 451, 477, 494, 502, 503, 506, 559, 560, 562, 565, 603, 402, 480, 587, 558 } },
    { name = "Muscle", items = { 475, 474, 536, 535, 534, 567, 576, 412, 517, 518, 542, 600 } },
    { name = "Off-road", items = { 495, 500, 444, 556, 557, 568, 424, 470, 489, 579, 400, 554, 543, 471 } },
    { name = "Bikes", items = { 522, 521, 461, 463, 468, 581, 586, 462, 448, 509, 481, 510 } },
    { name = "Sedans", items = { 405, 426, 445, 507, 529, 540, 546, 547, 550, 551, 516, 585, 418, 482 } },
    { name = "Special", items = { 457, 539, 571, 572, 531, 583, 574, 485, 530, 431, 437, 408, 403, 515, 514 } },
    { name = "Boats", items = { 446, 452, 453, 454, 472, 473, 484, 493, 595 } },
    { name = "Air", items = { 513, 593, 512, 487, 469, 460, 511 } },
}

CATALOG.weapons = {
    { name = "Pistols", items = { 22, 23, 24 } },
    { name = "Shotguns", items = { 25, 26, 27 } },
    { name = "Sub-machine guns", items = { 28, 29, 32 } },
    { name = "Assault rifles", items = { 30, 31 } },
    { name = "Rifles", items = { 33, 34 } },
    { name = "Melee", items = { 4, 5, 8, 9 } },
    { name = "Heavy", items = { 35, 37, 38 } },
}

CATALOG.ammo = { 30, 60, 120, 250, 500, 1000, 9999 }
CATALOG.armour = { 0, 25, 50, 75, 100 }
CATALOG.checkpointSizes = { 3, 4, 5, 6, 7, 8, 10, 12, 15 }

-- lookups
CATALOG.objectName, CATALOG.vehicleAllowed, CATALOG.weaponAllowed = {}, {}, {}
for _, cat in ipairs(CATALOG.objects) do
    for _, item in ipairs(cat.items) do CATALOG.objectName[item[1]] = item[2] end
end
for _, cat in ipairs(CATALOG.vehicles) do
    for _, model in ipairs(cat.items) do CATALOG.vehicleAllowed[model] = true end
end
for _, cat in ipairs(CATALOG.weapons) do
    for _, id in ipairs(cat.items) do CATALOG.weaponAllowed[id] = true end
end
