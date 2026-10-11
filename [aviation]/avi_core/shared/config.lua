AVI = {
    -- ATC rights: three separate rights, one per kind of position. Everybody has the tower right by
    -- default; work_atc will hand out the others (setPlayerATCRight) from the work level.
    --   TWR   = <ICAO>_TWR positions
    --   APP   = <ICAO>_APP positions
    --   RADAR = SACC_CTR (centre / radar)
    RIGHTS = { "TWR", "APP", "RADAR" },
    DEFAULT_RIGHTS = { TWR = true },
    POSITION_RIGHT = { TWR = "TWR", APP = "APP", CTR = "RADAR" },   -- avi_controller position type -> right

    DATA_RIGHTS = "avi.atcRights",   -- player element data mirror of the rights (server-owned)
    ADMIN_LEVEL = 3,                 -- v_mysql admin_level for /atcright, /avipos and the data editors
    TAG         = "ATC",             -- notification title / chat prefix

    -- ATC markers: they open the position login of avi_controller (this replaces /atc).
    -- Visible only to the players on duty in the work MARKER_WORK (work_core setElementVisibleToWork);
    -- false = visible to everybody (testing, work_atc does not exist yet).
    MARKER_WORK = "atc",
    MARKER_SIZE = 1.4,
    MARKER_COLOR = { 70, 130, 210, 150 },
    MARKER_KEY = "e",
    MARKER_LABEL_DISTANCE = 20,
    MARKERS = {
        -- SF control tower, in front of the wall screens (v_monitors, controller spot u = -4.9)
        {
            name = "ACC",
            available_positions = { "SACC_CTR" },
            x = 204.25883, y = 185.98024, z = 1057.15161,
            interior = 3, dimension = 0
        },
        {
            name = "Los Santos",
            available_positions = { "SALS_TWR", "SALS_APP" },
            x = 204.95752, y = 203.44545, z = 1057.15942,
            interior = 3, dimension = 0
        },
        {
            name = "San Fierro",
            available_positions = { "SASF_TWR", "SASF_APP" },
            x = 210.30901, y = 204.13286, z = 1057.15942,
            interior = 3, dimension = 0
        },
        {
            name = "Las Venturas",
            available_positions = { "SALV_TWR", "SALV_APP" },
            x = 198.86751, y = 204.19948, z = 1057.15942,
            interior = 3, dimension = 0
        },
        -- more: add { name = "...", x, y, z [, interior, dimension] [, available_positions] } (/avipos prints the position, z - 1)
        -- available_positions: the position ids (<ICAO>_TWR / <ICAO>_APP / SACC_CTR) the login of that
        -- marker offers; left out = every position the player has the right for
    },

    -- SA Control interior, registered in world_interiors (server/interior.lua).
    -- enterMarker (outside) / exitMarker (inside) are player positions (world_interiors puts the
    -- marker 1 m lower); entrance = arrival point inside, exit = arrival point outside.
    INTERIOR = {
        id = "avi_sacontrol",
        name = "San Andreas Control",
        int = 3,
        dim = 0,
        enterMarker = { x = -2169.45, y = 252.03, z = 35.33 },
        entrance = { x = 215.20518, y = 199.86151, z = 1058.15942, rot = 0 },
        exitMarker = { x = 215.21815, y = 202.22147, z = 1058.15942 },
        exit = { x = -2166.14, y = 252.08, z = 34.32, rot = 270 },
    }
}
