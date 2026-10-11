-- Wall signs inside the SA Control interior (int 3), typically above the doors.
-- Every sign is a flat plate on a wall:
--   x, y      point on the wall face (centre of the sign horizontally)
--   z         centre height of the sign
--   nx, ny    wall normal, pointing toward the viewer (into the room)
--   w, h      size in metres
--   lines     { text, size = relative font size (1 = default), bold = true/false, color = {r,g,b} }
-- Optional per sign: int, dim, bg = {r,g,b,a}, border = {r,g,b,a}

WS = {
    INT = 3,
    DIM = 0,
    OFFSET = 0.02,          -- distance from the wall face (avoid z-fighting)
    PPM = 256,              -- render target pixels per metre
    DRAW_DIST = 30,
    BG = { 18, 30, 52, 235 },
    BORDER = { 200, 210, 225, 255 },
    TEXT = { 255, 255, 255 },
}

WS.SIGNS = {
    -- door frame opposite DrAndrew112's spot: opening x 209.6..211.6, top z 1059.63, ceiling 1060.87
    {
        id = "sf_room",
        x = 210.60, y = 199.46, z = 1060.10, nx = 0, ny = -1,
        w = 1.80, h = 0.60,
        lines = {
            { text = "San Fierro room", size = 1.0, bold = true },
            { text = "SA Control REMOTE", size = 0.6, color = { 170, 190, 220 } },
        },
    },
    -- same wall, door opening x 205.6..207.6
    {
        id = "ls_room",
        x = 206.60, y = 199.46, z = 1060.10, nx = 0, ny = -1,
        w = 1.80, h = 0.60,
        lines = {
            { text = "Los Santos room", size = 1.0, bold = true },
            { text = "SA Control REMOTE", size = 0.6, color = { 170, 190, 220 } },
        },
    },
    -- same wall, door opening x 197.6..199.6
    {
        id = "lv_room",
        x = 198.60, y = 199.46, z = 1060.10, nx = 0, ny = -1,
        w = 1.80, h = 0.60,
        lines = {
            { text = "Las Venturas room", size = 1.0, bold = true },
            { text = "SA Control REMOTE", size = 0.6, color = { 170, 190, 220 } },
        },
    },
    -- opposite (south) wall y 195.46 facing north, door opening x 205.6..207.6, same heights
    {
        id = "acc_room",
        x = 206.60, y = 195.46, z = 1060.10, nx = 0, ny = 1,
        w = 1.80, h = 0.60,
        lines = {
            { text = "ACC room", size = 1.0, bold = true },
            { text = "SA Control", size = 0.6, color = { 170, 190, 220 } },
        },
    },
}
