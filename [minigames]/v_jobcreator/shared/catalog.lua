if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- What creators may place / pick. The server only accepts models listed here.
-- Object models were checked against the game's model table (dff names in the
-- comments) through the claude-mcp probe.

CATALOG = {}

CATALOG.objects = {
    { name = L.text("v_jobcreator.catalog.ramps_jumps"), items = {
        { 1633, L.text("v_jobcreator.catalog.land_jump") },              -- landjump
        { 1634, L.text("v_jobcreator.catalog.land_jump_wide") },       -- landjump2
        { 1632, L.text("v_jobcreator.catalog.water_jump") },             -- waterjump1
        { 1631, L.text("v_jobcreator.catalog.water_jump_2") },           -- waterjump2
        { 1655, L.text("v_jobcreator.catalog.water_jump_double") },    -- waterjumpx2
        { 1660, L.text("v_jobcreator.catalog.ramp") },                   -- ramp
        { 1503, L.text("v_jobcreator.catalog.small_ramp") },             -- DYN_RAMP
        { 1245, L.text("v_jobcreator.catalog.wooden_ramp") },            -- newramp
        { 2893, L.text("v_jobcreator.catalog.car_ramp") },               -- kmb_ramp
        { 3080, L.text("v_jobcreator.catalog.billboard_jump") },         -- ad_jump
        { 2931, L.text("v_jobcreator.catalog.jump_ramp") },              -- kmb_jump1
        { 5152, L.text("v_jobcreator.catalog.stunt_ramp") },             -- stuntramp1_las2
        { 5153, L.text("v_jobcreator.catalog.stunt_ramp_2") },           -- stuntramp7_las2
        { 13593, L.text("v_jobcreator.catalog.kicker_ramp") },           -- kickramp03
        { 13641, L.text("v_jobcreator.catalog.kicker_ramp_2") },         -- kickramp04
        { 13604, L.text("v_jobcreator.catalog.kicker_ramp_3") },         -- kickramp05
        { 13645, L.text("v_jobcreator.catalog.kicker_ramp_4") },         -- kickramp06
        { 13637, L.text("v_jobcreator.catalog.tube_ramp") },             -- tuberamp
        { 13646, L.text("v_jobcreator.catalog.landing_pad") },           -- ramplandpad
        { 13592, L.text("v_jobcreator.catalog.loop") },                  -- loopbig
        { 18367, L.text("v_jobcreator.catalog.bike_log") },              -- cw2_bikelog
        { 16367, L.text("v_jobcreator.catalog.quay_ramp") },             -- des_quayramp
    } },
    { name = L.text("v_jobcreator.catalog.barriers_fences"), items = {
        { 1228, L.text("v_jobcreator.catalog.roadwork_barrier") },       -- roadworkbarrier1
        { 1237, L.text("v_jobcreator.catalog.street_barrier") },         -- strtbarrier01
        { 1282, L.text("v_jobcreator.catalog.barrier_with_light") },     -- Barrierm
        { 1422, L.text("v_jobcreator.catalog.road_barrier") },           -- DYN_ROADBARRIER_5
        { 1423, L.text("v_jobcreator.catalog.road_barrier_2") },         -- DYN_ROADBARRIER_4
        { 1424, L.text("v_jobcreator.catalog.road_barrier_3") },         -- DYN_ROADBARRIER_2
        { 1425, L.text("v_jobcreator.catalog.road_barrier_4") },         -- DYN_ROADBARRIER_3
        { 1459, L.text("v_jobcreator.catalog.road_barrier_5") },         -- DYN_ROADBARRIER_6
        { 1427, L.text("v_jobcreator.catalog.concrete_barrier") },       -- CJ_ROADBARRIER
        { 973, L.text("v_jobcreator.catalog.highway_barrier") },         -- sub_roadbarrier
        { 2920, L.text("v_jobcreator.catalog.police_barrier") },         -- police_barrier
        { 3091, L.text("v_jobcreator.catalog.track_barrier") },          -- imy_track_barrier
        { 970, L.text("v_jobcreator.catalog.small_fence") },             -- fencesmallb
        { 974, L.text("v_jobcreator.catalog.tall_fence") },              -- tall_fence
        { 1652, L.text("v_jobcreator.catalog.wooden_fence") },           -- fencehaiti
        { 3936, L.text("v_jobcreator.catalog.barbed_wire_fence") },      -- bwire_fence
        { 987, L.text("v_jobcreator.catalog.electric_fence") },          -- elecfence_BAR
    } },
    { name = L.text("v_jobcreator.catalog.road_signs"), items = {
        { 1238, L.text("v_jobcreator.catalog.traffic_cone") },           -- trafficcone
        { 1215, L.text("v_jobcreator.catalog.bollard_light") },          -- bollardlight
        { 1662, L.text("v_jobcreator.catalog.roadblock") },              -- nt_roadblockCI
        { 1315, L.text("v_jobcreator.catalog.traffic_light") },          -- trafficlight1
        { 1229, L.text("v_jobcreator.catalog.bus_stop_sign") },          -- bussign1
        { 1233, L.text("v_jobcreator.catalog.no_parking_sign") },        -- noparkingsign1
        { 1311, L.text("v_jobcreator.catalog.road_sign") },              -- gen_roadsign1
        { 1312, L.text("v_jobcreator.catalog.road_sign_2") },            -- gen_roadsign2
        { 3335, L.text("v_jobcreator.catalog.country_road_sign") },      -- CE_roadsign1
        { 1226, L.text("v_jobcreator.catalog.lamp_post") },              -- lamppost3
        { 1290, L.text("v_jobcreator.catalog.lamp_post_2") },            -- lamppost2
        { 1297, L.text("v_jobcreator.catalog.lamp_post_3") },            -- lamppost1
        { 3460, L.text("v_jobcreator.catalog.vegas_lamp_post") },        -- vegaslampost
        { 3864, L.text("v_jobcreator.catalog.floodlight") },             -- WS_floodlight
    } },
    { name = L.text("v_jobcreator.catalog.containers_crates"), items = {
        { 2932, L.text("v_jobcreator.catalog.container_blue") },       -- kmb_container_blue
        { 2934, L.text("v_jobcreator.catalog.container_red") },        -- kmb_container_red
        { 2935, L.text("v_jobcreator.catalog.container_yellow") },     -- kmb_container_yel
        { 3043, L.text("v_jobcreator.catalog.container_open") },       -- kmb_container_open
        { 3073, L.text("v_jobcreator.catalog.container_broken") },     -- kmb_container_broke
        { 944, L.text("v_jobcreator.catalog.crate") },                   -- Crate1
        { 960, L.text("v_jobcreator.catalog.crate_2") },                 -- Crate2
        { 1224, L.text("v_jobcreator.catalog.crate_3") },                -- Crate4
        { 964, L.text("v_jobcreator.catalog.metal_crate") },             -- CJ_METAL_CRATE
        { 2669, L.text("v_jobcreator.catalog.large_crate") },            -- CJ_CHRIS_CRATE
        { 2912, L.text("v_jobcreator.catalog.wooden_box") },             -- temp_crate1
        { 2977, L.text("v_jobcreator.catalog.military_crate") },         -- kmilitary_crate
        { 3576, L.text("v_jobcreator.catalog.dock_crates") },            -- DockCrates2_LA
        { 3577, L.text("v_jobcreator.catalog.dock_crates_2") },          -- DockCrates1_LA
        { 1271, L.text("v_jobcreator.catalog.gun_box") },                -- gunbox
        { 1685, L.text("v_jobcreator.catalog.pallet_block") },           -- blockpallet
        { 1421, L.text("v_jobcreator.catalog.boxes") },                  -- DYN_BOXES
        { 1431, L.text("v_jobcreator.catalog.box_pile") },               -- DYN_BOX_PILE
    } },
    { name = L.text("v_jobcreator.catalog.cover"), items = {
        { 2060, L.text("v_jobcreator.catalog.sandbag") },                -- CJ_SANDBAG
        { 1218, L.text("v_jobcreator.catalog.barrel") },                 -- barrel1
        { 1217, L.text("v_jobcreator.catalog.barrel_2") },               -- barrel2
        { 1222, L.text("v_jobcreator.catalog.barrel_3") },               -- barrel3
        { 1225, L.text("v_jobcreator.catalog.explosive_barrel") },       -- barrel4
        { 3046, L.text("v_jobcreator.catalog.wooden_barrel") },          -- kb_barrel
        { 1327, L.text("v_jobcreator.catalog.junk_tire") },              -- JunkTire
        { 2651, L.text("v_jobcreator.catalog.skate_wall") },             -- CJ_Skate_wall1
        { 2650, L.text("v_jobcreator.catalog.skate_wall_2") },           -- CJ_Skate_wall2
        { 2652, L.text("v_jobcreator.catalog.skate_cubes") },            -- CJ_SKATE_CUBES
        { 1368, L.text("v_jobcreator.catalog.blocker_bench") },          -- CJ_BLOCKER_BENCH
        { 3374, L.text("v_jobcreator.catalog.hay_bale") },               -- SW_haybreak02
        { 12917, L.text("v_jobcreator.catalog.hay_pile") },              -- sw_haypile03
    } },
    { name = L.text("v_jobcreator.catalog.structures"), items = {
        { 3458, L.text("v_jobcreator.catalog.long_slab") },              -- vgncarshade1
        { 8838, L.text("v_jobcreator.catalog.wide_slab") },              -- vgEhshade01_lvs
        { 18449, L.text("v_jobcreator.catalog.road_bridge") },           -- cs_roadbridge01
        { 18450, L.text("v_jobcreator.catalog.road_bridge_2") },         -- cs_roadbridge04
        { 8171, L.text("v_jobcreator.catalog.airport_plate") },          -- vgsSairportland06
        { 8172, L.text("v_jobcreator.catalog.airport_plate_2") },        -- vgsSairportland07
        { 8357, L.text("v_jobcreator.catalog.airport_plate_3") },        -- vgsSairportland14
        { 3925, L.text("v_jobcreator.catalog.wooden_bridge") },          -- bridge_1
        { 1426, L.text("v_jobcreator.catalog.scaffold") },               -- DYN_SCAFFOLD
        { 1436, L.text("v_jobcreator.catalog.scaffold_2") },             -- DYN_SCAFFOLD_2
        { 3361, L.text("v_jobcreator.catalog.wooden_stairs") },          -- cxref_woodstair
        { 3502, L.text("v_jobcreator.catalog.concrete_tube") },          -- vgsN_con_tube
        { 5400, L.text("v_jobcreator.catalog.skate_tube") },             -- laeskatetube1
        { 3865, L.text("v_jobcreator.catalog.concrete_pipe") },          -- concpipe_SFXRF
        { 17043, L.text("v_jobcreator.catalog.concrete_arch") },         -- concretearch1
        { 16082, L.text("v_jobcreator.catalog.quarry_platform") },       -- des_quarryplatform
        { 18284, L.text("v_jobcreator.catalog.canopy") },                -- cw_tscanopy
    } },
    { name = L.text("v_jobcreator.catalog.nature"), items = {
        { 615, L.text("v_jobcreator.catalog.tree") },                    -- veg_tree3
        { 616, L.text("v_jobcreator.catalog.tree_2") },                  -- veg_treea1
        { 617, L.text("v_jobcreator.catalog.tree_3") },                  -- veg_treeb1
        { 703, L.text("v_jobcreator.catalog.big_tree") },                -- sm_veg_tree7_big
        { 671, L.text("v_jobcreator.catalog.bushy_tree") },              -- sm_bushytree
        { 654, L.text("v_jobcreator.catalog.pine_tree") },               -- pinetree08
        { 659, L.text("v_jobcreator.catalog.pine_tree_2") },             -- pinetree01
        { 621, L.text("v_jobcreator.catalog.palm") },                    -- veg_palm02
        { 645, L.text("v_jobcreator.catalog.big_palm") },                -- veg_palmbig14
        { 710, L.text("v_jobcreator.catalog.vegas_palm") },              -- vgs_palm01
        { 759, L.text("v_jobcreator.catalog.large_bush") },              -- sm_bush_large_1
        { 760, L.text("v_jobcreator.catalog.small_bush") },              -- sm_bush_small_1
        { 800, L.text("v_jobcreator.catalog.bush") },                    -- genVEG_bush07
        { 744, L.text("v_jobcreator.catalog.rock") },                    -- sm_scrub_rock4
        { 745, L.text("v_jobcreator.catalog.rock_2") },                  -- sm_scrub_rock5
        { 897, L.text("v_jobcreator.catalog.sea_rock") },                -- searock01
        { 898, L.text("v_jobcreator.catalog.sea_rock_2") },              -- searock02
        { 1303, L.text("v_jobcreator.catalog.quarry_rock") },            -- dyn_quarryrock03
        { 3929, L.text("v_jobcreator.catalog.desert_rock") },            -- d_rock
        { 2936, L.text("v_jobcreator.catalog.boulder") },                -- kmb_rock
    } },
    { name = L.text("v_jobcreator.catalog.decoration"), items = {
        { 1280, L.text("v_jobcreator.catalog.park_bench") },             -- parkbench1
        { 1256, L.text("v_jobcreator.catalog.stone_bench") },            -- Stonebench1
        { 1291, L.text("v_jobcreator.catalog.post_box") },               -- postbox1
        { 1234, L.text("v_jobcreator.catalog.phone_sign") },             -- phonesign
        { 1294, L.text("v_jobcreator.catalog.light_post") },             -- mlamppost
        { 3534, L.text("v_jobcreator.catalog.chinese_lamp") },           -- trdlamp01
        { 1568, L.text("v_jobcreator.catalog.chinese_lamp_post") },      -- chinalamp_sf
        { 638, L.text("v_jobcreator.catalog.planter_with_bush") },       -- kb_planter+bush
        { 1361, L.text("v_jobcreator.catalog.bush_prop") },              -- CJ_BUSH_PROP2
        { 1338, L.text("v_jobcreator.catalog.plastic_crates") },         -- PlasticCrates
        { 2898, L.text("v_jobcreator.catalog.fun_turf") },               -- funturf_law
    } },
}

CATALOG.vehicles = {
    { name = L.text("v_jobcreator.catalog.sports"), items = { 411, 541, 415, 429, 451, 477, 494, 502, 503, 506, 559, 560, 562, 565, 603, 402, 480, 587, 558 } },
    { name = L.text("v_jobcreator.catalog.muscle"), items = { 475, 474, 536, 535, 534, 567, 576, 412, 517, 518, 542, 600 } },
    { name = L.text("v_jobcreator.catalog.off_road"), items = { 495, 500, 444, 556, 557, 568, 424, 470, 489, 579, 400, 554, 543, 471 } },
    { name = L.text("v_jobcreator.catalog.bikes"), items = { 522, 521, 461, 463, 468, 581, 586, 462, 448, 509, 481, 510 } },
    { name = L.text("v_jobcreator.catalog.sedans"), items = { 405, 426, 445, 507, 529, 540, 546, 547, 550, 551, 516, 585, 418, 482 } },
    { name = L.text("v_jobcreator.catalog.special"), items = { 457, 539, 571, 572, 531, 583, 574, 485, 530, 431, 437, 408, 403, 515, 514 } },
    { name = L.text("v_jobcreator.catalog.boats"), items = { 446, 452, 453, 454, 472, 473, 484, 493, 595 } },
    { name = L.text("v_jobcreator.catalog.air"), items = { 513, 593, 512, 487, 469, 460, 511 } },
}

CATALOG.weapons = {
    { name = L.text("v_jobcreator.catalog.pistols"), items = { 22, 23, 24 } },
    { name = L.text("v_jobcreator.catalog.shotguns"), items = { 25, 26, 27 } },
    { name = L.text("v_jobcreator.catalog.sub_machine_guns"), items = { 28, 29, 32 } },
    { name = L.text("v_jobcreator.catalog.assault_rifles"), items = { 30, 31 } },
    { name = L.text("v_jobcreator.catalog.rifles"), items = { 33, 34 } },
    { name = L.text("v_jobcreator.catalog.melee"), items = { 4, 5, 8, 9 } },
    { name = L.text("v_jobcreator.catalog.heavy"), items = { 35, 37, 38 } },
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
end)
