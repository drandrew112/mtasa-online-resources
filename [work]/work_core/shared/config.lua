-- work_core - shared configuration. The works themselves are registered by their own
-- resources through the exports (see README.md); nothing is stored here.

WORK = {
    -- Duty marker (go on / off duty, outfit selector). Cylinder, z = ground level.
    DUTY_MARKER_SIZE = 1.2,
    DUTY_MARKER_ALPHA = 140,

    -- Duty vehicle marker (request a work vehicle). Cylinder, z = ground level.
    VEHICLE_MARKER_SIZE = 2.5,
    VEHICLE_MARKER_ALPHA = 110,

    DEFAULT_COLOR = { 245, 166, 35 },  -- work colour when registerWork gets none

    -- A player counts as "in" a marker within size / 2 + this (metres, 2D) ...
    MARKER_EXTRA_RADIUS = 0.5,
    -- ... and when the player's feet are between marker z - 1 and marker z + this
    MARKER_HEIGHT = 3,
    -- Server-side tolerance for requests (lag): size / 2 + this
    REQUEST_EXTRA_RADIUS = 3,
    REQUEST_COOLDOWN = 750,           -- ms between two requests of one player

    -- Work vehicles
    SPAWN_CLEAR_RADIUS = 3.5,         -- a spawn point is blocked by any vehicle this close
    SPAWN_Z_OFFSET = 1.0,             -- added when the vehicle spawns at the marker itself
    EXPLODED_CLEANUP = 8000,          -- ms after which an exploded work vehicle is removed

    -- Payment receipt (client/payment.lua), shown after a successful payWork()
    PAYMENT_DURATION = 7000,          -- ms on screen before it fades out on its own
    PAYMENT_FADE = 350,               -- ms fade in / fade out

    -- /workpos (prints marker / spawn positions)
    ADMIN_LEVEL = 3,

    KEY = "e",                        -- interact key in a marker
    POLL = 200,                       -- ms, client marker detection

    -- Client 3D labels
    LABEL_DISTANCE = 25,
    LABEL_FULL_DISTANCE = 8,
    LABEL_MIN_SCALE = 0.55,
    LABEL_HEIGHT = 1.25,
}

-- Element data keys
WORK_DATA = {
    PLAYER_WORK = "work.id",          -- player: id of the work he is on duty in (synced) / false
    CIVIL_SKIN  = "work.civilSkin",   -- player: model before duty (server only, read by v_accounts save)
    MARKER_KIND = "work.marker",      -- marker: "duty" | "vehicle"
    MARKER_WORK = "work.markerWork",  -- marker: work id
    MARKER_VEHICLES = "work.vehicles",-- vehicle marker: { { model, name }, ... }
    VEHICLE_WORK  = "work.vehicle",   -- vehicle: work id
    VEHICLE_OWNER = "work.owner",     -- vehicle: player who requested it
}
