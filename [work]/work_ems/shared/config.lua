-- work_ems - shared configuration.
-- Positions are placeholders around All Saints: fine-tune them with work_core's /workpos
-- (on foot: marker point, in a vehicle: spawn point { x, y, z, rot }).

EMS = {
    WORK_ID = "ems",
    NAME = "EMS",
    DESCRIPTION = "Emergency Medical Services",
    COLOR = { 220, 50, 50 },

    -- Outfits (276 = OMSZ shirt, replaced by v_modloader)
    SKINS = {
        { model = 276, name = "Paramedic (OMSZ)" },
        { model = 274, name = "Paramedic 1" },
        { model = 275, name = "Paramedic 2" },
    },

    -- Vehicles offered at the duty vehicle markers. Plates: PLATE_PREFIX + PLATE_DIGITS random digits.
    -- Ambulances only for now (no emergency doctor car / helicopter yet).
    PLATE_PREFIX = "A-",
    PLATE_DIGITS = 4,
    VEHICLES = {
        { model = 416, name = "Mercedes Sprinter (HU)" },
        { model = 456, name = "Mission Row Ambulance" },
    },

    -- Stations: a duty marker and (optionally) a duty vehicle marker with spawn points.
    -- z = ground level for the markers.
    STATIONS = {
        {
            name = "LS All Saints General Hospital",
            duty = { 1182.82, -1330.80, 12.58 },
            blip = 22,
            vehicle = {
                marker = { 1184.0, -1323.6, 12.6 },
                spawns = {
                    { 1185.5, -1316.0, 13.6, 0 },
                    { 1185.5, -1331.0, 13.6, 180 },
                },
            },
        },
        {
            name = "LS Country General Hospital",
            duty = { 2011.27, -1436.85, 12.55 },
            blip = 22,
            vehicle = {
                marker = { 2003.23, -1444.75, 12.56 },
                spawns = {
                    { 1993.78, -1445.92, 13.62, 180 },
                    { 2012.09, -1453.29, 13.60, 90 },
                    { 2002.36, -1453.56, 13.61, 90 },
                },
            },
        },
    },
}
