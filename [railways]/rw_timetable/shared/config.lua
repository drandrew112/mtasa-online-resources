if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
L.config(function()  -- texts are refreshed once the player is loaded (v_locals L.config)
-- rw_timetable settings (server + client)

TT = {
    -- Stations. (x, y) = platform centre, projected onto every route track within 40 m;
    -- length = platform zone along the track (m). A train stops "at" the station when its
    -- lead stands inside the zone. platform = a point on the platform per track, used to
    -- tell the door side (left / right of the train); no entry = both sides open.
    -- tracks = the track number passengers see per GTA track (station displays).
    STATIONS = {
        { id = "unity",      name = L.text("rw_timetable.config.unity_station"),       city = "Los Santos",   x = 1745,    y = -1955.9, length = 230,
          platform = { [0] = { x = 1745, y = -1946 } }, tracks = { [0] = "1", [3] = "2" } },
        { id = "market",     name = L.text("rw_timetable.config.market_station"),      city = "Los Santos",   x = 815,     y = -1366,   length = 180,
          tracks = { [0] = "1", [3] = "2" } },
        { id = "cranberry",  name = L.text("rw_timetable.config.cranberry_station"),   city = "San Fierro",   x = -1946,   y = 140,     length = 260,
          platform = { [0] = { x = -1938, y = 150 } }, tracks = { [0] = "1", [3] = "2", [5] = "3", [6] = "4" } },
        { id = "yellowbell", name = L.text("rw_timetable.config.yellow_bell_station"), city = "Las Venturas", x = 1433,    y = 2632.3,  length = 220,
          tracks = { [0] = "1", [3] = "2" } },
        { id = "linden",     name = L.text("rw_timetable.config.linden_station"),      city = "Las Venturas", x = 2854.6,  y = 1292,    length = 220,
          tracks = { [0] = "1", [3] = "2" } },
    },
    ROUTE_TRACKS = { 0, 3, 5, 6 },    -- 5 / 6 = Cranberry hall tracks 3 / 4 (dead ends)

    -- Lines = the fixed routes. Times in minutes from the departure at the first stop. WHEN a
    -- line runs is the timetable in MySQL `rw_timetable` (server/schedule.lua, edited on the
    -- /gov Railways page; TT.SEED below fills an empty table). Trip numbers: base + 2*n.
    -- origins = the other stations a trip of the line may start at: station -> rw_core spawn
    -- point (the line's own `from` uses auto.spawn). A trip may end at any later stop.
    -- chain = the line whose next trip the same train runs on from the terminus (rw_auto
    -- keeps the train instead of removing it; `chainWindow` minutes at most).
    --
    -- Timetable (README "Timetable"): a 30 minute cycle, directional double-track running -
    -- SF-bound / clockwise trains (Unity - Market - Cranberry - Yellow Bell - Linden - Unity)
    -- use the main line (track 0), LS-bound / anticlockwise trains the second track (3).
    -- Running times (rw_auto runs at line speed, ~120 km/h, and waits at the platform when early):
    -- Unity-Market 2, Market-Cranberry 4, Cranberry-Yellow Bell 4, Yellow Bell-Linden 3,
    -- Linden-Unity 4 min, 1 min dwell.
    --   * RB SL1 Unity :00/:15/:30/:45 -> Cranberry track 4 (dead end, keeps the main line free)
    --   * RB SL2 Cranberry track 3 :10/:25/:40/:55 -> Unity (crosses to the second track at W19)
    --   * IC SL3 clockwise Unity :06/:36, IC SL4 anticlockwise Unity :05/:35 - 6-9 min between
    --     them and the regionals on the shared LS - SF tracks
    --   * IC SL5 clockwise Cranberry track 1 :10/:40 (Unity :24, 6 min after the RB),
    --     IC SL6 anticlockwise Cranberry track 2 :15/:45 (5 min after the RB, 4 before SL4).
    --     They end on the same through track (:01 / :06) and are removed; the next train is
    --     created 55 s before :10 / :15 - the hall tracks 3 / 4 are too short for the 4-coach ICs
    --   * the two single-track stretches between Yellow Bell and Linden (rw_signals SINGLE):
    --     SL4 :10-:13, SL5 :15-:18, SL3 :19-:22, SL6 :28-:31 (+30) - opposing ICs never meet there
    --   * Cranberry throat: SL5 arrives ~:01, SL1 enters track 4 ~:07, SL2 leaves track 3 ~:10,
    --     SL3 passes ~:13, SL6 leaves ~:15, SL4 leaves ~:19 (+30)
    -- auto = what rw_auto spawns for the trip (rw_core preset + spawn point).
    -- track = the line the trip normally uses, a stop's own track overrides it (station
    -- displays; a train standing in the station shows its real track, e.g. after a diversion).
    LINES = {
        -- RB: LS -> SF on the main line, into Cranberry track 4
        { id = "SL1", prefix = "RB", base = 1101, name = L.text("rw_timetable.config.sunline_regional"), from = "unity", to = "cranberry",
          track = 0,
          stops = { { station = "unity", dep = 0 }, { station = "market", arr = 2, dep = 3 }, { station = "cranberry", arr = 7, track = 6 } },
          consist = { locos = { "br232" }, minPassenger = 1, maxPassenger = 4 }, auto = { preset = "re3", spawn = "unity_1" } },
        -- RB: SF -> LS from Cranberry track 3 (W21, main line, W19 onto the second track)
        { id = "SL2", prefix = "RB", base = 1102, name = L.text("rw_timetable.config.sunline_regional"), from = "cranberry", to = "unity",
          track = 3,
          stops = { { station = "cranberry", dep = 0, track = 5 }, { station = "market", arr = 4, dep = 5 }, { station = "unity", arr = 7 } },
          consist = { locos = { "br232" }, minPassenger = 1, maxPassenger = 4 }, auto = { preset = "re3", spawn = "cranb_3" } },
        -- IC clockwise circle: Unity - Market - Cranberry - Yellow Bell - Linden - Unity (main line)
        { id = "SL3", prefix = "IC", base = 2101, name = L.text("rw_timetable.config.sunline_circle"), from = "unity", to = "unity",
          track = 0,
          stops = { { station = "unity", dep = 0 }, { station = "market", arr = 2, dep = 3 }, { station = "cranberry", arr = 7, dep = 8 },
                    { station = "yellowbell", arr = 12, dep = 13 }, { station = "linden", arr = 16, dep = 17 }, { station = "unity", arr = 21 } },
          consist = { locos = { "br232" }, minPassenger = 2, maxPassenger = 4 }, origins = { cranberry = "cranb_1", yellowbell = "yb_lv", linden = "lin_ls" },
          auto = { preset = "re4", spawn = "unity_1" } },
        -- IC anticlockwise circle: Unity - Linden - Yellow Bell - Cranberry - Market - Unity (second track)
        { id = "SL4", prefix = "IC", base = 2102, name = L.text("rw_timetable.config.sunline_circle"), from = "unity", to = "unity",
          track = 3,
          stops = { { station = "unity", dep = 0 }, { station = "linden", arr = 4, dep = 5 }, { station = "yellowbell", arr = 8, dep = 9 },
                    { station = "cranberry", arr = 13, dep = 14 }, { station = "market", arr = 18, dep = 19 }, { station = "unity", arr = 21 } },
          consist = { locos = { "br232" }, minPassenger = 2, maxPassenger = 4 }, origins = { cranberry = "cranb_2t" },
          auto = { preset = "re4", spawn = "unity_2" } },
        -- IC clockwise circle from SF: Cranberry - Yellow Bell - Linden - Unity - Market - Cranberry (main line, track 1)
        { id = "SL5", prefix = "IC", base = 2201, name = L.text("rw_timetable.config.sunline_circle"), from = "cranberry", to = "cranberry",
          track = 0,
          stops = { { station = "cranberry", dep = 0 }, { station = "yellowbell", arr = 4, dep = 5 }, { station = "linden", arr = 8, dep = 9 },
                    { station = "unity", arr = 13, dep = 14 }, { station = "market", arr = 16, dep = 17 }, { station = "cranberry", arr = 21 } },
          consist = { locos = { "br232" }, minPassenger = 2, maxPassenger = 4 }, origins = { unity = "unity_1", yellowbell = "yb_lv", linden = "lin_ls" },
          auto = { preset = "re4", spawn = "cranb_1" } },
        -- IC anticlockwise circle from SF: Cranberry - Market - Unity - Linden - Yellow Bell - Cranberry (second track, track 2)
        { id = "SL6", prefix = "IC", base = 2202, name = L.text("rw_timetable.config.sunline_circle"), from = "cranberry", to = "cranberry",
          track = 3,
          stops = { { station = "cranberry", dep = 0 }, { station = "market", arr = 4, dep = 5 }, { station = "unity", arr = 7, dep = 8 },
                    { station = "linden", arr = 12, dep = 13 }, { station = "yellowbell", arr = 16, dep = 17 }, { station = "cranberry", arr = 21 } },
          consist = { locos = { "br232" }, minPassenger = 2, maxPassenger = 4 }, origins = { unity = "unity_2" },
          auto = { preset = "re4", spawn = "cranb_2t" } },
    },

    -- The timetable that fills an empty `rw_timetable` table (= the timetable before the table
    -- existed, TIMETABLE.md). Minutes after midnight (last = the last departure); the whole line, every day.
    SEED = {
        { line = "SL1", kind = "interval", first = 0, last = 1425, headway = 15 },
        { line = "SL2", kind = "interval", first = 10, last = 1435, headway = 15 },
        { line = "SL3", kind = "interval", first = 6, last = 1416, headway = 30 },
        { line = "SL4", kind = "interval", first = 5, last = 1415, headway = 30 },
        { line = "SL5", kind = "interval", first = 10, last = 1420, headway = 30 },
        { line = "SL6", kind = "interval", first = 15, last = 1425, headway = 30 },
    },
    SCHEDULE = {
        RELOAD = 60,         -- s: the table is re-read (the other instance / a /gov change)
        MIN_HEADWAY = 3,     -- min: the shortest interval of a row
    },

    TAKE_BEFORE = 15 * 60,   -- a trip can be taken this long before its departure (s)
    TAKE_LEAD   = 60,        -- ...and at the latest this long before it (s). Later the trip
                             -- belongs to rw_auto, which creates its train 55 s before departure.
    APPLY_GRACE = 60,        -- s: a service applied for at a depot must have left its first station
                             -- this long after the departure time, else it is cancelled and the
                             -- train removed
    DOOR_MIN    = 15,        -- doors must stay open this long for a stop to count (s)
    STOP_SPEED  = 2,         -- km/h: below this the train counts as standing
    LOG_DELAY_WARN = 3,      -- rw_core railway log: a delay growing to this many minutes is a warning
    EARLY_DEP   = 30,        -- leaving more than this before the departure time is "early" (s)
    FINAL_WAIT  = 60,        -- at the last stop the trip completes after this standing (s)...
                             -- ...or once the doors were open for DOOR_MIN
    REMOVE_AFTER = 10,       -- s after a service ends (completed / ended by the driver) the train is
                             -- removed, once it stands; people on board are put on the platform
    TICK        = 500,       -- server interval (ms)
    SYNC_EVERY  = 1,       -- element data refresh of a running service (s)

    -- Station displays (passenger departure / arrival boards, dx drawn on walls).
    -- x, y, z = centre of the board ON the wall, nx, ny = the wall's normal (the side the
    -- board faces), w / h in metres (the picture is 2:1), off = distance from the wall (default
    -- 0.05; more where a poster without collision would show through). /rwboardpos prints a line for the
    -- wall the camera looks at.
    DISPLAYS = {
        -- Unity: west end wall of the station building, on the brick strip beside track 1
        { station = "unity",      x = 1726.4,  y = -1939.3,  z = 15.5,  nx = -1,     ny = 0,      w = 5.4, h = 2.7 },
        -- Market: tiled wall behind the main platform (underground hall), below the ceiling slope
        { station = "market",     x = 810.06,  y = -1341.37, z = 0.5,   nx = -0.667, ny = -0.745, w = 5.4, h = 2.7 },
        -- Cranberry: inside the station building, on the pillar between the two platform doors
        { station = "cranberry",  x = -1961.6, y = 143.5,    z = 29.25, nx = -1,     ny = 0,      w = 5.0, h = 2.5, off = 0.15 },
        -- Yellow Bell: south platform wall, east of the passage (clear of the poster)
        { station = "yellowbell", x = 1451.5,  y = 2623.3,   z = 12.9,  nx = 0,      ny = 1,      w = 6.0, h = 3.0 },
        -- Linden: platform wall north of the passage (y 1292)
        { station = "linden",     x = 2855.8,  y = 1305,     z = 13.05, nx = 1,      ny = 0,      w = 7.0, h = 3.5 },
    },
    BOARD = {
        DRAW_DIST  = 90,     -- m: boards are drawn within this distance
        KEEP_DIST  = 140,    -- m: a station's render target is released beyond this
        REFRESH    = 5,      -- s: board data refresh while near a board
        ROWS       = 8,      -- rows per column
        PAST_DEP   = 60,     -- s: a departed train stays on the board this long
        PAST_ARR   = 120,    -- s: an arrived train stays on the board this long
        CANCEL_AFTER = 180,  -- s: a trip nobody runs this long after its time = cancelled
        AHEAD      = 120,    -- min: how far ahead the board looks
    },
}
end)
