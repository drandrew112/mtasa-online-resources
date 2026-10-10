MON = {
    REFRESH_MS = 5000,          -- the screens (and the data they show) update this often

    -- The wall (measured in the SF control tower base, collision raycasts): a flat face on the line
    -- x - y = -1276.5. u runs along the wall (x and y both grow), the normal points into the room.
    -- This is the wide lower band of the wall (20 m x 3.5 m); above it the wall is narrower.
    WALL = {
        ox = -1245.79, oy = 30.70,      -- wall point at u = 0
        ux = 0.70711, uy = 0.70711,
        nx = -0.70711, ny = 0.70711,
        uMin = -14.8, uMax = 5.0,       -- solid span along the wall
        zMin = 13.2, zMax = 16.7,       -- floor .. top of the band
    },
    MARGIN = 0.15,              -- free space kept at the wall edges (m)
    EYE_Z = 15.0,               -- the picture centre is at eye height (standing ped: camera ~ 14.9)
    OFFSET = 0.03,              -- distance in front of the wall (m)

    -- the fixed radar hangs on the narrower upper part of the wall, centred on the spot where the
    -- controller stands (u -4.9); zBottom = bottom edge of its name plate
    RADAR = { width = 8.0, u = -4.9, zBottom = 17.1, rtW = 2048 },

    -- the position screens: one row across the whole lower band, each as wide as the wall allows
    GAP = 0.15,
    MAX_WIDTH = 3.2,            -- when there are only a few monitors
    PLATE_RATIO = 0.16,         -- name plate height / monitor width (picture is 16:9)

    FLIP_UV = false,            -- set true if the picture comes out upside down

    RANGE = 40,                 -- screens exist (render targets, data) within this distance (m)
    RT_W = 1280,
}
