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
        { name = "SA Control", x = -1261.47, y = 40.26, z = 13.14 },
        -- more: add { name = "...", x, y, z [, interior, dimension] } (/avipos prints the position, z - 1)
    },
}
