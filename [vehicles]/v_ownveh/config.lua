-- v_ownveh :: configuration
--
-- Shared namespace for this resource. spawnpoints.lua adds Vehicles.spawnpoints.

Vehicles = Vehicles or {}

Vehicles.config = {
    -- SQLite database file (relative to this resource folder). Holds every
    -- owned vehicle: model, colours, paintjob, upgrades, handling, plate and
    -- the isDestroyed flag. Health is intentionally NOT stored.
    dbFile = "vehicles.db",

    -- Periodic autosave of every spawned owned vehicle's state, in ms.
    autosaveInterval = 120000,

    -- After a vehicle explodes it is marked isDestroyed and the wreck is
    -- removed from the world this many ms later.
    wreckCleanupDelay = 45000,

    -- A spawn point counts as occupied when any vehicle is within this many
    -- units of it (spawnOwnedVehicle then tries the next nearest point).
    spawnpointClearDist = 4.0,

    -- LAND vehicles only: if the nearest FREE land spawn point is farther than
    -- this (or there is none), the vehicle is spawned right at the player and
    -- they are put straight into the driver seat (so no blip is shown). Other
    -- vehicle types always require a free spawn point.
    landDirectSpawnDistance = 150.0,

    -- Radar blip shown on a summoned vehicle. farShow / visibleDistance make it
    -- visible from across the map (v_radar renders native blips).
    blip = {
        icon            = 0,
        size            = 1,
        r               = 100,
        g               = 200,
        b               = 255,
        a               = 255,
        ordering        = 0,
        visibleDistance = 5000,
    },

    -- Minimum admin_level (account data) allowed to use /vehspawn and
    -- /showvehspawns.
    spawnpointAdminLevel = 5,

    -- Debug markers placed by /vehspawn (new point) and /showvehspawns (every
    -- configured point). "checkpoint" markers, only visible to the admin who
    -- ran the command. One colour per spawnpoint category.
    marker = {
        type = "checkpoint",
        size = 4,
        alpha = 120,
        colors = {
            land        = { 0,   200, 0   },
            boats       = { 0,   120, 255 },
            helicopters = { 255, 220, 0   },
            airplanes   = { 255, 60,  60  },
            new         = { 255, 255, 255 }, -- freshly placed via /vehspawn
        },
        -- Radar blip attached to each debug marker (tinted the category colour).
        blip = {
            icon            = 0,
            size            = 2,
            ordering        = 0,
            visibleDistance = 5000,
        },
    },

    -- /vehspawn appends "{x, y, z, rx, ry, rz}," lines here. Git-ignored;
    -- copy the lines into spawnpoints.lua by hand.
    spawnpointFile = "vehiclespawnpoints.txt",
}
