-- bt_core configuration. Other blood transport resources read it with exports.bt_core:getConfig().
-- Institution names are proper nouns and are not translated.

BT = {
    -- The blood transporter right (element data RIGHT_KEY on the player). work_bloodtransport gives
    -- it on duty. false = everybody counts as a transporter (for testing, until the work is used).
    REQUIRE_RIGHT = true,
    RIGHT_KEY = "bt.right",

    -- admin_level (v_mysql accData) needed for /btadmin and the web admin
    ADMIN_LEVEL = 2,

    -- Blood groups and how common they are (weights, used for consumption and random requests)
    GROUPS = { "0-", "0+", "A-", "A+", "B-", "B+", "AB-", "AB+" },
    GROUP_WEIGHT = { ["0-"] = 7, ["0+"] = 38, ["A-"] = 6, ["A+"] = 34, ["B-"] = 2, ["B+"] = 9, ["AB-"] = 1, ["AB+"] = 3 },

    -- Blood products. One unit = 450 ml. item = the v_inventory item (kg and icon are defined there).
    PRODUCT_ORDER = { "rbc", "ffp", "platelets" },
    PRODUCTS = {
        rbc = { item = "bt_rbc", short = "RBC" },
        ffp = { item = "bt_ffp", short = "FFP" },
        platelets = { item = "bt_platelets", short = "PLT" },
    },

    -- Institutions. kind = "bank" (blood supply center) | "hospital". x, y, z = the port marker.
    INSTITUTIONS = {
        { id = "ls_bank", kind = "bank", city = "LS", name = "Los Santos Blood Bank", x = 933.25, y = -1443.04, z = 12.55 },
        { id = "ls_allsaints", kind = "hospital", city = "LS", name = "All Saints General Hospital", x = 1177.76, y = -1320.54, z = 13.09 },
        { id = "ls_country", kind = "hospital", city = "LS", name = "Country General Hospital", x = 2025.39, y = -1404.18, z = 16.21 },
        { id = "lv_bank", kind = "bank", city = "LV", name = "Las Venturas Blood Bank", x = 1365.85, y = 1897.09, z = 10.47 },
        { id = "lv_general", kind = "hospital", city = "LV", name = "Las Venturas General Hospital", x = 1610.86, y = 1817.01, z = 9.82 },
        { id = "sf_bank", kind = "bank", city = "SF", name = "San Fierro Blood Bank", x = -2720.08, y = 127.60, z = 6.04 },
        { id = "sf_medical", kind = "hospital", city = "SF", name = "San Fierro Medical Center", x = -2656.08, y = 637.47, z = 13.45 },
    },

    PORT_COLORS = { bank = { 215, 55, 65 }, hospital = { 0, 140, 200 } },
    PORT_ICONS = { bank = "B", hospital = "H" },
}
