if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- rw_signals settings (server + client)

-- console debug output (outputDebugString) of this resource; the rail log file is not affected
DEBUG_ENABLED = false

SIG = {
    -- Signalled stretches (block sections). from/to are world points projected onto the
    -- track; the stretch runs in increasing track position from `from` to `to`.
    ROUTES = {
        -- the main line is a loop: signalled all the way round (loop = true, no ends)
        { track = 0, prefix = "M", loop = true },
        -- the second track is a loop too (LS - SF - LV - LS, on the main line through the two
        -- single-track stretches in LV)
        { track = 3, prefix = "S", loop = true },
    },

    -- Single-track stretches shared by both lines (main line segments in LV). a / b = the
    -- switches where the two tracks join. Each end gets an entry signal on both approaching
    -- tracks; the stretch holds one train at a time (any line, any direction), and the first
    -- train inside or approaching (SIG.APPROACH) claims its direction, so two trains never
    -- enter from both ends.
    SINGLE = {
        { name = L.text("rw_signals.config.yellow_bell_east"), prefix = "YE", a = { x = 1625.0, y = 2636.0 }, b = { x = 2154.0, y = 2694.0 } },
        { name = L.text("rw_signals.config.las_venturas_ne"),  prefix = "NE", a = { x = 2553.0, y = 2460.0 }, b = { x = 2785.0, y = 1962.0 } },
    },
    SINGLE_TRACKS = { 0, 3 },
    SINGLE_ENTRY  = 25,    -- entry signal this far before the joining switch (m)

    -- Block boundaries every stretch gets (projected onto each route track within 15 m).
    -- type "station" also ends a direction-lock section (see server/signals.lua).
    BOUNDARIES = {
        { name = L.text("rw_signals.config.unity_east"),      x = 2125,   y = -1955.9, type = "block" },
        { name = L.text("rw_signals.config.unity_home"),      x = 1935,   y = -1955.9, type = "station" },
        { name = L.text("rw_signals.config.unity_west"),      x = 1690,   y = -1955.9, type = "station" },
        { name = L.text("rw_signals.config.market_east"),     x = 876,    y = -1426,   type = "station" },
        { name = L.text("rw_signals.config.market_west"),     x = 752,    y = -1314,   type = "station" },
        { name = L.text("rw_signals.config.cranberry_south"), x = -1946,  y = 55,      type = "station" },
        -- the Cranberry South scissors (W17-W20) get their own short section
        { name = L.text("rw_signals.config.cranberry_junction"), x = -1946.0, y = -160, type = "station" },
        { name = L.text("rw_signals.config.cranberry_north"), x = -1924.8, y = 267.7,  type = "station" },
        { name = L.text("rw_signals.config.yellow_bell_west"), x = 1303.0, y = 2632.3, type = "station" },
        { name = L.text("rw_signals.config.yellow_bell_east"), x = 1563.0, y = 2632.3, type = "station" },
        { name = L.text("rw_signals.config.linden_north"),    x = 2864.8, y = 1420.0,  type = "station" },
        { name = L.text("rw_signals.config.linden_south"),    x = 2844.3, y = 1163.7,  type = "station" },
    },
    AUTO_BLOCK = 800,      -- longer gaps are split into automatic blocks of about this length
    APPROACH   = 900,      -- a train this close to a section claims its direction (m)

    LATERAL    = 3.1,      -- pole distance from the track centre (m)
    POLE_MODEL = 1214,     -- bollard, scaled up into a thin mast
    POLE_SCALE = { 0.38, 0.38, 3.3 },
    HEAD_HEIGHT = 4.1,     -- lamp head centre above the rail (m)

    TICK = 500,            -- server interval (ms)
    DRAW_DISTANCE = 450,   -- client drawing distance (m)

    ASPECT = { RED = 0, YELLOW = 1, GREEN = 2 },
    ASPECT_NAMES = { [0] = L.text("rw_signals.config.stop"), [1] = L.text("rw_signals.config.caution"), [2] = L.text("rw_signals.config.clear") },
}
end)
