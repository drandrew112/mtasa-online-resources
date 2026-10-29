if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- What creators may place / pick. The server only accepts models listed here.
-- Object models were checked against the game's model table (dff names in the
-- comments, from the data/maps IDE files). Many are dynamic in GTA (object.dat):
-- matches freeze every placed object and the clients make them unbreakable
-- (v_jobmanager core/client/objects.lua).

CATALOG = {}

CATALOG.objects = {
    { name = L.text("v_jobcreator.catalog.ramps_jumps"), items = {
        { 1633, L.text("v_jobcreator.catalog.land_jump") },            -- landjump
        { 1634, L.text("v_jobcreator.catalog.land_jump_wide") },       -- landjump2
        { 1632, L.text("v_jobcreator.catalog.water_jump") },           -- waterjump1
        { 1631, L.text("v_jobcreator.catalog.water_jump_2") },         -- waterjump2
        { 1655, L.text("v_jobcreator.catalog.water_jump_double") },    -- waterjumpx2
        { 1660, L.text("v_jobcreator.catalog.ramp") },                 -- ramp
        { 1503, L.text("v_jobcreator.catalog.small_ramp") },           -- DYN_RAMP
        { 1245, L.text("v_jobcreator.catalog.wooden_ramp") },          -- newramp
        { 2893, L.text("v_jobcreator.catalog.car_ramp") },             -- kmb_ramp
        { 3080, L.text("v_jobcreator.catalog.billboard_jump") },       -- ad_jump
        { 2931, L.text("v_jobcreator.catalog.jump_ramp") },            -- kmb_jump1
        { 5152, L.text("v_jobcreator.catalog.stunt_ramp") },           -- stuntramp1_las2
        { 5153, L.text("v_jobcreator.catalog.stunt_ramp_2") },         -- stuntramp7_las2
        { 3069, L.text("v_jobcreator.catalog.dozer_ramp") },           -- d9_ramp
        { 3852, L.text("v_jobcreator.catalog.sf_jump") },              -- sf_jump
        { 8302, L.text("v_jobcreator.catalog.jump_box") },             -- jumpbox01_lvs01
        { 12956, L.text("v_jobcreator.catalog.trailer_jump") },        -- sw_trailerjump
        { 16401, L.text("v_jobcreator.catalog.dirt_jump") },           -- desn2_peckjump
        { 16303, L.text("v_jobcreator.catalog.quarry_ramp") },         -- des_quarryramp01
        { 16367, L.text("v_jobcreator.catalog.quay_ramp") },           -- des_quayramp
        { 18367, L.text("v_jobcreator.catalog.bike_log") },            -- cw2_bikelog
    } },
    { name = L.text("v_jobcreator.catalog.stunt"), items = {
        { 13592, L.text("v_jobcreator.catalog.loop") },                -- loopbig
        { 13637, L.text("v_jobcreator.catalog.tube_ramp") },           -- tuberamp
        { 13593, L.text("v_jobcreator.catalog.kicker_ramp") },         -- kickramp03
        { 13641, L.text("v_jobcreator.catalog.kicker_ramp_2") },       -- kickramp04
        { 13604, L.text("v_jobcreator.catalog.kicker_ramp_3") },       -- kickramp05
        { 13645, L.text("v_jobcreator.catalog.kicker_ramp_4") },       -- kickramp06
        { 13646, L.text("v_jobcreator.catalog.landing_pad") },         -- ramplandpad
        { 5400, L.text("v_jobcreator.catalog.skate_tube") },           -- laeskatetube1
        { 3502, L.text("v_jobcreator.catalog.concrete_tube") },        -- vgsN_con_tube
    } },
    { name = L.text("v_jobcreator.catalog.racing"), items = {
        { 2993, L.text("v_jobcreator.catalog.go_flag") },              -- kmb_goflag
        { 2914, L.text("v_jobcreator.catalog.race_flag") },            -- kmb_rcflag
        { 13003, L.text("v_jobcreator.catalog.start_banner") },        -- cunte_racestart
        { 3078, L.text("v_jobcreator.catalog.finish_banner") },        -- ad_finish
        { 18275, L.text("v_jobcreator.catalog.finish_gate") },         -- cw2_mtbfinish
        { 8843, L.text("v_jobcreator.catalog.chevron_arrows") },       -- arrows01_lvs
        { 7090, L.text("v_jobcreator.catalog.flag_pole") },            -- vegasflag1
        { 16101, L.text("v_jobcreator.catalog.windsock") },            -- des_windsockpole
        { 1327, L.text("v_jobcreator.catalog.junk_tire") },            -- junk_tyre
        { 3091, L.text("v_jobcreator.catalog.track_barrier") },        -- imy_track_barrier
    } },
    { name = L.text("v_jobcreator.catalog.barriers_fences"), items = {
        { 1228, L.text("v_jobcreator.catalog.roadwork_barrier") },     -- roadworkbarrier1
        { 1237, L.text("v_jobcreator.catalog.street_barrier") },       -- strtbarrier01
        { 1282, L.text("v_jobcreator.catalog.barrier_with_light") },   -- Barrierm
        { 1422, L.text("v_jobcreator.catalog.road_barrier") },         -- DYN_ROADBARRIER_5
        { 1434, L.text("v_jobcreator.catalog.road_barrier_long") },    -- DYN_ROADBARRIER_5a
        { 1423, L.text("v_jobcreator.catalog.road_barrier_2") },       -- DYN_ROADBARRIER_4
        { 1424, L.text("v_jobcreator.catalog.road_barrier_3") },       -- DYN_ROADBARRIER_2
        { 1425, L.text("v_jobcreator.catalog.road_barrier_4") },       -- DYN_ROADBARRIER_3
        { 1459, L.text("v_jobcreator.catalog.road_barrier_5") },       -- DYN_ROADBARRIER_6
        { 1427, L.text("v_jobcreator.catalog.concrete_barrier") },     -- CJ_ROADBARRIER
        { 973, L.text("v_jobcreator.catalog.highway_barrier") },       -- sub_roadbarrier
        { 2920, L.text("v_jobcreator.catalog.police_barrier") },       -- police_barrier
        { 1214, L.text("v_jobcreator.catalog.bollard") },              -- bollard
        { 970, L.text("v_jobcreator.catalog.small_fence") },           -- fencesmallb
        { 974, L.text("v_jobcreator.catalog.tall_fence") },            -- tall_fence
        { 1652, L.text("v_jobcreator.catalog.wooden_fence") },         -- fencehaiti
        { 1407, L.text("v_jobcreator.catalog.plank_fence") },          -- DYN_F_R_WOOD_1
        { 1419, L.text("v_jobcreator.catalog.iron_fence") },           -- DYN_F_IRON_1
        { 1411, L.text("v_jobcreator.catalog.mesh_fence") },           -- DYN_MESH_1
        { 3936, L.text("v_jobcreator.catalog.barbed_wire_fence") },    -- bwire_fence
        { 987, L.text("v_jobcreator.catalog.electric_fence") },        -- elecfence_BAR
    } },
    { name = L.text("v_jobcreator.catalog.road_signs"), items = {
        { 1238, L.text("v_jobcreator.catalog.traffic_cone") },         -- trafficcone
        { 1662, L.text("v_jobcreator.catalog.roadblock") },            -- nt_roadblockCI
        { 1315, L.text("v_jobcreator.catalog.traffic_light") },        -- trafficlight1
        { 1229, L.text("v_jobcreator.catalog.bus_stop_sign") },        -- bussign1
        { 1233, L.text("v_jobcreator.catalog.no_parking_sign") },      -- noparkingsign1
        { 1311, L.text("v_jobcreator.catalog.road_sign") },            -- gen_roadsign1
        { 1312, L.text("v_jobcreator.catalog.road_sign_2") },          -- gen_roadsign2
        { 1443, L.text("v_jobcreator.catalog.street_sign") },          -- DYN_STREET_SIGN_1
        { 1444, L.text("v_jobcreator.catalog.street_sign_2") },        -- DYN_STREET_SIGN_2
        { 3335, L.text("v_jobcreator.catalog.country_road_sign") },    -- CE_roadsign1
        { 1211, L.text("v_jobcreator.catalog.fire_hydrant") },         -- fire_hydrant
    } },
    { name = L.text("v_jobcreator.catalog.lights"), items = {
        { 1226, L.text("v_jobcreator.catalog.lamp_post") },            -- lamppost3
        { 1290, L.text("v_jobcreator.catalog.lamp_post_2") },          -- lamppost2
        { 1297, L.text("v_jobcreator.catalog.lamp_post_3") },          -- lamppost1
        { 1294, L.text("v_jobcreator.catalog.light_post") },           -- mlamppost
        { 3460, L.text("v_jobcreator.catalog.vegas_lamp_post") },      -- vegaslampost
        { 1568, L.text("v_jobcreator.catalog.chinese_lamp_post") },    -- chinalamp_sf
        { 3534, L.text("v_jobcreator.catalog.chinese_lamp") },         -- trdlamp01
        { 1215, L.text("v_jobcreator.catalog.bollard_light") },        -- bollardlight
        { 3864, L.text("v_jobcreator.catalog.floodlight") },           -- WS_floodlight
    } },
    { name = L.text("v_jobcreator.catalog.containers_crates"), items = {
        { 2932, L.text("v_jobcreator.catalog.container_blue") },       -- kmb_container_blue
        { 2934, L.text("v_jobcreator.catalog.container_red") },        -- kmb_container_red
        { 2935, L.text("v_jobcreator.catalog.container_yellow") },     -- kmb_container_yel
        { 3043, L.text("v_jobcreator.catalog.container_open") },       -- kmb_container_open
        { 3073, L.text("v_jobcreator.catalog.container_broken") },     -- kmb_container_broke
        { 944, L.text("v_jobcreator.catalog.crate") },                 -- Packing_carates04
        { 960, L.text("v_jobcreator.catalog.crate_2") },               -- CJ_ARM_CRATE
        { 1224, L.text("v_jobcreator.catalog.crate_3") },              -- woodenbox
        { 1448, L.text("v_jobcreator.catalog.wooden_crate") },         -- DYN_CRATE_1
        { 1449, L.text("v_jobcreator.catalog.wooden_crate_2") },       -- DYN_CRATE_2
        { 964, L.text("v_jobcreator.catalog.metal_crate") },           -- CJ_METAL_CRATE
        { 2669, L.text("v_jobcreator.catalog.large_crate") },          -- CJ_CHRIS_CRATE
        { 2912, L.text("v_jobcreator.catalog.wooden_box") },           -- temp_crate1
        { 2977, L.text("v_jobcreator.catalog.military_crate") },       -- kmilitary_crate
        { 3576, L.text("v_jobcreator.catalog.dock_crates") },          -- DockCrates2_LA
        { 3577, L.text("v_jobcreator.catalog.dock_crates_2") },        -- DockCrates1_LA
        { 1271, L.text("v_jobcreator.catalog.gun_box") },              -- gunbox
        { 1685, L.text("v_jobcreator.catalog.pallet_block") },         -- blockpallet
        { 1219, L.text("v_jobcreator.catalog.pallet") },               -- palette
        { 1421, L.text("v_jobcreator.catalog.boxes") },                -- DYN_BOXES
        { 1431, L.text("v_jobcreator.catalog.box_pile") },             -- DYN_BOX_PILE
        { 1438, L.text("v_jobcreator.catalog.box_pile_2") },           -- DYN_BOX_PILE_2
        { 2890, L.text("v_jobcreator.catalog.skip") },                 -- kmb_skip
        { 1365, L.text("v_jobcreator.catalog.big_skip") },             -- CJ_BIG_SKIP1
        { 1345, L.text("v_jobcreator.catalog.dumpster") },             -- CJ_Dumpster
        { 1343, L.text("v_jobcreator.catalog.dumpster_2") },           -- CJ_Dumpster3
        { 1684, L.text("v_jobcreator.catalog.portakabin") },           -- portakabin
    } },
    { name = L.text("v_jobcreator.catalog.cover"), items = {
        { 2060, L.text("v_jobcreator.catalog.sandbag") },              -- CJ_SANDBAG
        { 1218, L.text("v_jobcreator.catalog.barrel") },               -- barrel1
        { 1217, L.text("v_jobcreator.catalog.barrel_2") },             -- barrel2
        { 1222, L.text("v_jobcreator.catalog.barrel_3") },             -- barrel3
        { 1225, L.text("v_jobcreator.catalog.explosive_barrel") },     -- barrel4
        { 3046, L.text("v_jobcreator.catalog.wooden_barrel") },        -- kb_barrel
        { 3632, L.text("v_jobcreator.catalog.oil_drums") },            -- imoildrum_LAS
        { 12913, L.text("v_jobcreator.catalog.fuel_drum") },           -- sw_fueldrum03
        { 2651, L.text("v_jobcreator.catalog.skate_wall") },           -- CJ_Skate_wall1
        { 2650, L.text("v_jobcreator.catalog.skate_wall_2") },         -- CJ_Skate_wall2
        { 2652, L.text("v_jobcreator.catalog.skate_cubes") },          -- CJ_SKATE_CUBES
        { 1368, L.text("v_jobcreator.catalog.blocker_bench") },        -- CJ_BLOCKER_BENCH
        { 3374, L.text("v_jobcreator.catalog.hay_bale") },             -- SW_haybreak02
        { 1453, L.text("v_jobcreator.catalog.hay_bale_2") },           -- DYN_H_BALE1
        { 12917, L.text("v_jobcreator.catalog.hay_pile") },            -- sw_haypile03
        { 1462, L.text("v_jobcreator.catalog.woodpile") },             -- DYN_woodpile
        { 929, L.text("v_jobcreator.catalog.generator") },             -- GENERATOR
        { 934, L.text("v_jobcreator.catalog.big_generator") },         -- GENERATOR_BIG
        { 2984, L.text("v_jobcreator.catalog.portaloo") },             -- portaloo
        { 12957, L.text("v_jobcreator.catalog.pickup_wreck") },        -- sw_pickupwreck01
        { 3255, L.text("v_jobcreator.catalog.oil_tank") },             -- ref_oiltank01
        { 5836, L.text("v_jobcreator.catalog.water_tank") },           -- ci_watertank
    } },
    { name = L.text("v_jobcreator.catalog.structures"), items = {
        { 3458, L.text("v_jobcreator.catalog.long_slab") },            -- vgncarshade1
        { 8838, L.text("v_jobcreator.catalog.wide_slab") },            -- vgEhshade01_lvs
        { 18449, L.text("v_jobcreator.catalog.road_bridge") },         -- cs_roadbridge01
        { 18450, L.text("v_jobcreator.catalog.road_bridge_2") },       -- cs_roadbridge04
        { 8171, L.text("v_jobcreator.catalog.airport_plate") },        -- vgsSairportland06
        { 8172, L.text("v_jobcreator.catalog.airport_plate_2") },      -- vgsSairportland07
        { 8357, L.text("v_jobcreator.catalog.airport_plate_3") },      -- vgsSairportland14
        { 3925, L.text("v_jobcreator.catalog.wooden_bridge") },        -- bridge_1
        { 3406, L.text("v_jobcreator.catalog.wooden_jetty") },         -- cxref_woodjetty
        { 3879, L.text("v_jobcreator.catalog.jetty") },                -- ws_jetty_SFX
        { 2937, L.text("v_jobcreator.catalog.plank") },                -- kmb_plank
        { 2960, L.text("v_jobcreator.catalog.steel_beam") },           -- kmb_beam
        { 3529, L.text("v_jobcreator.catalog.construction_beams") },   -- vgsN_constrbeam
        { 1426, L.text("v_jobcreator.catalog.scaffold") },             -- DYN_SCAFFOLD
        { 1436, L.text("v_jobcreator.catalog.scaffold_2") },           -- DYN_SCAFFOLD_2
        { 1464, L.text("v_jobcreator.catalog.scaffold_3") },           -- DYN_SCAFFOLD_3
        { 1465, L.text("v_jobcreator.catalog.scaffold_4") },           -- DYN_SCAFFOLD_4
        { 3361, L.text("v_jobcreator.catalog.wooden_stairs") },        -- cxref_woodstair
        { 3865, L.text("v_jobcreator.catalog.concrete_pipe") },        -- concpipe_SFXRF
        { 17043, L.text("v_jobcreator.catalog.concrete_arch") },       -- concretearch1
        { 16082, L.text("v_jobcreator.catalog.quarry_platform") },     -- des_quarryplatform
        { 18284, L.text("v_jobcreator.catalog.canopy") },              -- cw_tscanopy
        { 4891, L.text("v_jobcreator.catalog.billboard") },            -- billboard_LAS
        { 1595, L.text("v_jobcreator.catalog.satellite_dish") },       -- satdishbig
    } },
    { name = L.text("v_jobcreator.catalog.nature"), items = {
        { 615, L.text("v_jobcreator.catalog.tree") },                  -- veg_tree3
        { 616, L.text("v_jobcreator.catalog.tree_2") },                -- veg_treea1
        { 617, L.text("v_jobcreator.catalog.tree_3") },                -- veg_treeb1
        { 703, L.text("v_jobcreator.catalog.big_tree") },              -- sm_veg_tree7_big
        { 671, L.text("v_jobcreator.catalog.bushy_tree") },            -- sm_bushytree
        { 654, L.text("v_jobcreator.catalog.pine_tree") },             -- pinetree08
        { 659, L.text("v_jobcreator.catalog.pine_tree_2") },           -- pinetree01
        { 621, L.text("v_jobcreator.catalog.palm") },                  -- veg_palm02
        { 645, L.text("v_jobcreator.catalog.big_palm") },              -- veg_palmbig14
        { 710, L.text("v_jobcreator.catalog.vegas_palm") },            -- vgs_palm01
        { 759, L.text("v_jobcreator.catalog.large_bush") },            -- sm_bush_large_1
        { 760, L.text("v_jobcreator.catalog.small_bush") },            -- sm_bush_small_1
        { 800, L.text("v_jobcreator.catalog.bush") },                  -- genVEG_bush07
        { 744, L.text("v_jobcreator.catalog.rock") },                  -- sm_scrub_rock4
        { 745, L.text("v_jobcreator.catalog.rock_2") },                -- sm_scrub_rock5
        { 897, L.text("v_jobcreator.catalog.sea_rock") },              -- searock01
        { 898, L.text("v_jobcreator.catalog.sea_rock_2") },            -- searock02
        { 1303, L.text("v_jobcreator.catalog.quarry_rock") },          -- dyn_quarryrock03
        { 1304, L.text("v_jobcreator.catalog.quarry_rock_2") },        -- dyn_quarryrock02
        { 1305, L.text("v_jobcreator.catalog.quarry_rock_3") },        -- dyn_quarryrock01
        { 3929, L.text("v_jobcreator.catalog.desert_rock") },          -- d_rock
        { 2936, L.text("v_jobcreator.catalog.boulder") },              -- kmb_rock
    } },
    { name = L.text("v_jobcreator.catalog.decoration"), items = {
        { 1280, L.text("v_jobcreator.catalog.park_bench") },           -- parkbench1
        { 1256, L.text("v_jobcreator.catalog.stone_bench") },          -- Stonebench1
        { 1281, L.text("v_jobcreator.catalog.picnic_table") },         -- parktable1
        { 1594, L.text("v_jobcreator.catalog.chairs_and_table") },     -- chairsntable
        { 1481, L.text("v_jobcreator.catalog.barbecue") },             -- DYN_BAR_B_Q
        { 1291, L.text("v_jobcreator.catalog.post_box") },             -- postbox1
        { 1234, L.text("v_jobcreator.catalog.phone_sign") },           -- phonesign
        { 1209, L.text("v_jobcreator.catalog.vending_machine") },      -- vendmach
        { 1574, L.text("v_jobcreator.catalog.trash_can") },            -- trashcan
        { 1338, L.text("v_jobcreator.catalog.wheelie_bin") },          -- BinNt08_LA
        { 638, L.text("v_jobcreator.catalog.planter_with_bush") },     -- kb_planter+bush
        { 1361, L.text("v_jobcreator.catalog.bush_prop") },            -- CJ_BUSH_PROP2
        { 2898, L.text("v_jobcreator.catalog.fun_turf") },             -- funturf_law
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

-- missions: ped skins by group (any skin 0..312 is accepted by the server)
CATALOG.skins = {
    { name = L.text("v_jobcreator.catalog.skins_gangs"), items = { 102, 103, 104, 105, 106, 107, 108, 109, 110, 114, 115, 116, 117, 118, 120, 173, 174, 175 } },
    { name = L.text("v_jobcreator.catalog.skins_mafia"), items = { 111, 112, 113, 124, 125, 126, 127 } },
    { name = L.text("v_jobcreator.catalog.skins_bikers"), items = { 100, 247, 248, 254 } },
    { name = L.text("v_jobcreator.catalog.skins_security"), items = { 71, 163, 164, 165, 166, 286 } },
    { name = L.text("v_jobcreator.catalog.skins_police"), items = { 280, 281, 282, 283, 284, 285, 287 } },
    { name = L.text("v_jobcreator.catalog.skins_civilians"), items = { 7, 15, 17, 22, 29, 40, 46, 56, 59, 93, 98, 141, 147, 150, 187, 240 } },
}

-- missions: pick-up items (v_inventory item ids; the model is the editor's preview)
CATALOG.missionItems = {
    { "mission_package", 1271, L.text("v_jobcreator.catalog.item_package") },
    { "mission_briefcase", 1210, L.text("v_jobcreator.catalog.item_briefcase") },
    { "mission_money_bag", 1550, L.text("v_jobcreator.catalog.item_money_bag") },
    { "mission_documents", 2894, L.text("v_jobcreator.catalog.item_documents") },
    { "mission_crate", 2912, L.text("v_jobcreator.catalog.item_crate") },
}

CATALOG.pedBehaviours = { "guard", "patrol", "attack", "civilian" }
CATALOG.vehicleRoles = { "loot", "crew", "prop", "enemy" }
CATALOG.objectiveTypes = { "enterZone", "stayInZone", "enterVehicle", "deliverVehicle", "collectItem", "deliverItem",
    "killPeds", "destroyVehicle", "interact", "survive", "scriptEvent" }
CATALOG.failTypes = { "vehicleDestroyed", "pedDied", "leaveZone" }
CATALOG.teamLives = { 0, 1, 2, 3, 4, 5, 6, 8, 10 }
CATALOG.missionMinutes = { 0, 5, 10, 15, 20, 30, 45, 60 }           -- 0 = no time limit
CATALOG.stageSeconds = { 0, 30, 60, 90, 120, 180, 300, 600 }         -- 0 = no time limit
CATALOG.holdSeconds = { 10, 15, 20, 30, 45, 60, 90, 120, 180, 300 }  -- stay in zone / survive
CATALOG.rewardMoney = { 0, 1000, 2500, 5000, 10000, 15000, 25000, 50000, 100000 }  -- 0 = automatic
CATALOG.rewardXp = { 0, 250, 500, 1000, 2000, 4000, 8000 }
CATALOG.zoneRadii = { 3, 5, 8, 12, 16, 20, 30, 45, 60 }
CATALOG.zoneHeights = { 3, 5, 8, 12, 20, 40 }
CATALOG.aggroRadii = { 15, 25, 35, 50, 75 }
CATALOG.accuracies = { 0.2, 0.3, 0.4, 0.55, 0.7, 0.85 }
CATALOG.pedHealth = { 50, 100, 150, 200 }
CATALOG.crewSizes = { 0, 1, 2, 3 }
CATALOG.interactSeconds = { 1, 2, 3, 5, 8 }

CATALOG.ammo = { 30, 60, 120, 250, 500, 1000, 9999 }
CATALOG.armour = { 0, 25, 50, 75, 100 }
CATALOG.checkpointSizes = { 3, 4, 5, 6, 7, 8, 10, 12, 15 }
CATALOG.offRoute = { 0, 100, 150, 250 }     -- m off the route before a racer is put back; 0 = off

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
CATALOG.missionItem = {}
for _, entry in ipairs(CATALOG.missionItems) do CATALOG.missionItem[entry[1]] = { model = entry[2], name = entry[3] } end
end)
