-- Room titles: signs above the doorframes of the hospital rooms (like the SA Control wall signs).
-- Every sign is a flat plate on a wall:
--   x, y      point on the wall face (centre of the sign horizontally)
--   z         centre height of the sign
--   nx, ny    wall normal, pointing toward the viewer (into the corridor)
--   w, h      size in metres
--   lines     { text, size = relative font size (1 = default), bold = true/false, color = {r,g,b} }
-- Optional per sign: int, dim, bg = {r,g,b,a}
-- Measured live (probe raycasts): door opening tops 2.40-2.42 m above the corridor floor (14.40),
-- corridor ceiling z 18.10, sign centre 2.88 m above the floor = about 0.46 m over the doorframe.

L.config(function()
RT = {
    INT = 0,
    DIM = 0,
    OFFSET = 0.02,          -- distance from the wall face (avoid z-fighting)
    PPM = 256,              -- render target pixels per metre
    DRAW_DIST = 25,
    RADIUS = 0.2,           -- corner radius, fraction of the plate height
    BG = { 0, 0, 0, 235 },
    TEXT = { 255, 255, 255 },
}

local Z = 17.28

local function title(key, size, color)
    return { text = L.text("med_hospitals.roomtitles." .. key), size = size or 1.0, bold = size == nil, color = color }
end

-- west corridor wall (face x ~1157.5, normal +x) / east corridor wall (face x ~1163.3, normal -x)
local function west(id, x, y, key)
    return { id = id, x = x, y = y, z = Z, nx = 1, ny = 0, w = 1.80, h = 0.60, lines = { title(key) } }
end
local function east(id, x, y, key)
    return { id = id, x = x, y = y, z = Z, nx = -1, ny = 0, w = 1.80, h = 0.60, lines = { title(key) } }
end

local staff = west("as_staff", 1157.67, -1315.92, "staff")   -- staff room = the exam centre
staff.w = 2.0
staff.lines[2] = title("exam_centre", 0.6)

RT.SIGNS = {
    -- All Saints General Hospital (ls_allsaints), ER corridor, measured door centres
    west("as_shock1",  1157.48, -1348.39, "shock1"),
    east("as_shock2",  1163.23, -1348.46, "shock2"),
    west("as_wound",   1157.50, -1356.20, "wound"),
    east("as_cast",    1163.26, -1356.24, "cast"),
    west("as_surgery", 1157.55, -1366.26, "surgery"),
    east("as_icu",     1163.29, -1366.26, "icu"),
    west("as_ward1",   1157.61, -1382.81, "ward1"),
    east("as_ward2",   1163.36, -1382.71, "ward2"),
    west("as_ct",      1157.67, -1303.06, "ct"),
    -- X-ray door: south wall of the X-ray room (face y -1298.11), normal -y
    { id = "as_xray", x = 1159.07, y = -1298.11, z = Z, nx = 0, ny = -1, w = 1.80, h = 0.60,
      lines = { title("xray") } },
    staff,
}
for _, s in ipairs(RT.SIGNS) do s.hospital = "ls_allsaints" end
end)
