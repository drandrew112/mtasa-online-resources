-- Hospital tutorial (plan: Kórházi bemutató): a walk through the All Saints ER on the first duty.
-- Every step: a text (work_hospital.tut.<id>_title / _text) and a point to walk to (nil = read and
-- press Enter). The Ápoló (nurse) rank is given at the end (server/tutorial.lua).

HOSPW_TUTORIAL = {
    hospital = "ls_allsaints", interior = 0, dimension = 0, range = 1.8, minSeconds = 60,
    steps = {
        { id = "welcome" },
        { id = "stretcher", pos = { 1168.86, -1315.92, 14.39 } },
        { id = "exam_centre", pos = { 1152.37, -1316.61, 14.38 } },
        { id = "pc", pos = { 1152.0, -1331.6, 14.39 } },
        { id = "corridor", pos = { 1158.81, -1344.55, 14.40 } },
        { id = "shock", pos = { 1155.4, -1348.6, 14.39 } },
        { id = "wound", pos = { 1155.5, -1359.7, 14.39 } },
        { id = "cast", pos = { 1166.4, -1359.3, 14.41 } },
        { id = "ct", pos = { 1154.75, -1300.20, 14.38 } },
        { id = "xray", pos = { 1158.90, -1292.70, 14.39 } },
        { id = "surgery", pos = { 1154.07, -1366.60, 14.39 } },
        { id = "icu", pos = { 1167.64, -1367.40, 14.41 } },
        { id = "ward", pos = { 1153.80, -1380.54, 14.40 } },
        { id = "morgue", pos = { 1169.88, -1300.71, 14.39 } },
        { id = "transfer", pos = { 1153.64, -1327.60, 14.39 } },
        { id = "ranks" },
        { id = "done" },
    },
}
