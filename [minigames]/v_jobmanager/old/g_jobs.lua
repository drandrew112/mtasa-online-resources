
jobs = {

    {
        -- details 1
        name = "Casino tour",
        desc = "Discover Las Venturas casinos and take part in an amazing race that covers the most casinos.",
        creator = "DrAndrew112",
        rating = 100,
        min_players = 1,
        max_players = 8,
        openrank = 2,
        type = job_types.race,
        -- type spec values
        race_id = 1,
        ctf_id = false,
        dm_id = false,
        -- join & leave
        join_marker = {
            pos = {2080.498046875,880.37799072266,7.2779870033264},
            size = 2,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {2080.1149902344,866.00476074219,6.9432435035706},
        -- lobby
        lobby = {
            camera = {
                pos = {2056.4643554688,1750.1185302734,21.734375},
                lookAt = {2057.4016113281,1700.0270996094,10.943309783936},
                roll = 0,
                fov = 90,
            },
            exit = {2080.1149902344,866.00476074219,6.9432435035706},
            bg_img = "images/job_bg_1.jpg",
        },
        endCamera = {
            pos = {2026.0142822266,1006.1462402344,10.8203125},
            lookAt = {2069.3852539062,1017.8234863281,31.8203125},
            roll = 0,
            fov = 90,
        },
    },
    
    {
        -- details 2
        name = "Los Santos Canal Tour",
        desc = "",
        creator = "DrAndrew112",
        rating = 100,
        min_players = 1,
        max_players = 8,
        openrank = 1,
        type = job_types.race,
        -- type spec values
        race_id = 2,
        ctf_id = false,
        dm_id = false,
        -- join
        join_marker = {
            pos = {2603.912109375,-1504.3862304688,15.5},
            size = 4,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {1416.259765625,-1327.1859130859,13.5546875},
        -- lobby
        lobby = {
            camera = {
                pos = {1479.8425292969,-1735.7847900391,8.4},
                lookAt = {1437.1546630859,-1712.8570556641,6.859375},
                roll = 0,
                fov = 90,
            },
            exit = {2621.5832519531,-1489.671875,16.481575012207},
            bg_img = "images/job_bg_2.jpg",
        },
        endCamera = {
            pos = {1415.4281005859,-1325.3720703125,18},
            lookAt = {1409.0793457031,-1360.8499755859,8},
            roll = 0,
            fov = 900,
        },
    },

    {
        -- details 3
        name = "Los Santos Ambulance",
        desc = "Turn on the sirens! You'll transport some patients from the Los Santos East Hospital to the LS General Hospital.",
        creator = "DrAndrew112",
        rating = 70,
        min_players = 1,
        max_players = 8,
        openrank = 1,
        type = job_types.race,
        -- type spec values
        race_id = 3,
        ctf_id = false,
        dm_id = false,
        -- join
        join_marker = {
            pos = {2002.2019042969,-1445.7503662109,13.561367034912},
            size = 2,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {1182.9545898438,-1313.3201904297,13.568015098572},
        -- lobby
        lobby = {
            camera = {
                pos = {1991.6333007812,-1456.3760986328,31.5546875},
                lookAt = {2033.7987060547,-1415.2940673828,16.9921875},
                roll = 0,
                fov = 90,
            },
            exit = {1996.1431884766,-1451.8377685547,13.5546875},
            bg_img = "images/job_bg_3.jpg",
        },
        endCamera = {
            pos = {1216.8253173828,-1311.7437744141,18.390625},
            lookAt = {1176.6218261719,-1325.4665527344,14.030390739441},
            roll = 0,
            fov = 90,
        },
    },
    
    {
        -- details 4
        name = "LS Beach motorcycling",
        desc = "",
        creator = "DrAndrew112",
        rating = 100,
        min_players = 1,
        max_players = 8,
        openrank = 1,
        type = job_types.race,
        -- type spec values
        race_id = 4,
        ctf_id = false,
        dm_id = false,
        -- join
        join_marker = {
            pos = {1032.8123779297,-1847.3607177734,13.511821746826},
            size = 2,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {167.71728515625,-1952.2193603516,3.7734375},
        -- lobby
        lobby = {
            camera = {
                pos = {755.55651855469,-1814.2392578125,15.586297988892},
                lookAt = {809.51721191406,-1814.8460693359,15.376152038574},
                roll = 0,
                fov = 90,
            },
            exit = {1027.1990966797,-1840.6617431641,13.586297988892},
            bg_img = "images/job_bg_4.jpg",
        },
        endCamera = {
            pos = {146.66709899902,-1940.5430908203,4.7734375},
            lookAt = {157.10388183594,-1908.9576416016,3.7734375},
            roll = 0,
            fov = 90,
        },
    },

    {
        -- details 5
        name = '"Follow The Damn Train, CJ!"',
        desc = "An iconic GTA San Andreas mission gave the idea for this race. The mission involved killing enemy gang members fleeing on the top of the train. But here you just have to race and have fun!",
        creator = "DrAndrew112",
        rating = 100,
        min_players = 1,
        max_players = 8,
        openrank = 1,
        type = job_types.race,
        -- type spec values
        race_id = false,
        ctf_id = false,
        dm_id = false,
        -- join
        join_marker = {
            pos = {1795.7633056641,-1900.0275878906,13.400864601135},
            size = 3,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {},
        -- lobby
        lobby = {
            camera = {
                pos = {2203.6232910156,-1883.1629638672,17.6100730896},
                lookAt = {2195.3225097656,-1909.2009277344,13.546875},
                roll = 0,
                fov = 90,
            },
            exit = {1808.6444091797,-1898.6468505859,13.579278945923},
            bg_img = "images/job_bg_default.jpg",
        },
        endCamera = {
            pos = {},
            lookAt = {},
            roll = 0,
            fov = 90,
        },
    },
    
    {
        -- details 6
        name = "Mt. Chiliad",
        desc = "Motorcycles only",
        creator = "DrAndrew112",
        rating = 100,
        min_players = 1,
        max_players = 8,
        openrank = 1,
        type = job_types.race,
        -- type spec values
        race_id = false,
        ctf_id = false,
        dm_id = false,
        -- join
        join_marker = {
            pos = {-2391.5197753906,-2204.5004882812,33.2},
            size = 4,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {-2236.884765625,-1723.1350097656,480.85095214844},
        -- lobby
        lobby = {
            camera = {
                pos = {-2353.5895996094,-1835.1394042969,434.2890625},
                lookAt = {-2280.1020507812,-1763.6729736328,456.88409423828},
                roll = 0,
                fov = 90,
            },
            exit = {-2382.8952636719,-2215.9558105469,33.2890625},
            bg_img = "images/job_bg_default.jpg",
        },
        endCamera = {
            pos = {},
            lookAt = {},
            roll = 0,
            fov = 90,
        },
    },
    
    {
        -- details 7
        name = "",
        desc = "",
        creator = "DrAndrew112",
        rating = 100,
        min_players = 1,
        max_players = 8,
        openrank = 1,
        type = job_types.race,
        -- type spec values
        race_id = false,
        ctf_id = false,
        dm_id = false,
        -- join
        join_marker = {
            pos = {},
            size = 2,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {},
        -- lobby
        lobby = {
            camera = {
                pos = {},
                lookAt = {},
                roll = 0,
                fov = 90,
            },
            exit = {},
            bg_img = "images/job_bg_default.jpg",
        },
        endCamera = {
            pos = {},
            lookAt = {},
            roll = 0,
            fov = 90,
        },
    },

}

--[[
    {
        -- details
        name = "Job name",
        desc = "",
        creator = "DrAndrew112",
        rating = 100,
        min_players = 1,
        max_players = 8,
        openrank = 1,
        type = job_types.race,
        -- type spec values
        race_id = false,
        ctf_id = false,
        dm_id = false,
        -- join
        join_marker = {
            pos = {},
            size = 2,
            rgba = {0,150,200, 150},
            blip_icon = 9,
        },
        exit = {},
        -- lobby
        lobby = {
            camera = {
                pos = {},
                lookAt = {},
                roll = 0,
                fov = 90,
            },
            exit = {},
            bg_img = "images/job_bg_default.jpg",
        },
        endCamera = {
            pos = {},
            lookAt = {},
            roll = 0,
            fov = 90,
        },
    },
]]
