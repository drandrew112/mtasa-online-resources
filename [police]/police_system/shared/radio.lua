-- police_system / shared/radio.lua
-- Radio messages. Every message has a name id: Radio.handle(player, id, args) on the server is the only entry point,
-- the later voice client calls the same through exports.police_system:radioCommand(player, id, args).
-- Text: police_system.radio.<id lowercase>, categories police_system.radio.cat_<id>.

RADIO_CATEGORIES = {
    { id = "status", items = { "STATUS_AVAILABLE", "STATUS_RESPONDING", "STATUS_BUSY", "STATUS_PURSUIT", "CODE_4" } },
    { id = "services", items = { "REQUEST_BACKUP", "REQUEST_AMBULANCE", "REQUEST_TOW" } },
    { id = "lookup", items = { "QUERY_PERSON", "QUERY_VEHICLE" } },
}

RADIO_IDS = {
    STATUS_AVAILABLE = { status = "available" },
    STATUS_RESPONDING = { status = "responding" },
    STATUS_BUSY = { status = "busy" },
    STATUS_PURSUIT = { status = "pursuit" },
    CODE_4 = {},
    REQUEST_BACKUP = {},
    REQUEST_AMBULANCE = {},
    REQUEST_TOW = {},
    QUERY_PERSON = {},
    QUERY_VEHICLE = {},
}

-- unit status -> colour and F key (mini panel, MDC)
UNIT_STATUS = {
    pursuit    = { key = "F4", color = { 235, 64, 64 },  radio = "STATUS_PURSUIT" },
    available  = { key = "F5", color = { 64, 200, 110 }, radio = "STATUS_AVAILABLE" },
    responding = { key = "F6", color = { 240, 200, 60 }, radio = "STATUS_RESPONDING" },
    busy       = { key = "F7", color = { 245, 140, 50 }, radio = "STATUS_BUSY" },
}
UNIT_STATUS_ORDER = { "pursuit", "available", "responding", "busy" }

-- text keys (literal list for the v_locals build)
RADIO_TEXT_KEYS = {
    "police_system.radio.cat_status", "police_system.radio.cat_services", "police_system.radio.cat_lookup",
    "police_system.radio.status_available", "police_system.radio.status_responding", "police_system.radio.status_busy",
    "police_system.radio.status_pursuit", "police_system.radio.code_4", "police_system.radio.request_backup",
    "police_system.radio.request_ambulance", "police_system.radio.request_tow", "police_system.radio.query_person",
    "police_system.radio.query_vehicle",
    "police_system.status.pursuit", "police_system.status.available", "police_system.status.responding",
    "police_system.status.busy", "police_system.status.short_pursuit", "police_system.status.short_available",
    "police_system.status.short_responding", "police_system.status.short_busy",
}
