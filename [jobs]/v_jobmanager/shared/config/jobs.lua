JOB_TYPE_RACE, JOB_TYPE_DM, JOB_TYPE_MISSION = "race", "deathmatch", "mission"
-- Server: filled by core/storage.lua from MySQL (jobs_official / jobs_community). Client: filled by the
-- "jobmanager:markers" event (only what the world markers need). scriptOnly missions are only in
-- jobsById (server): they never show in a list, a marker or /quickjob.
jobs, jobsById = {}, {}

-- Keys and timings shared by the client and server parts.
JOBS_CONFIG = {
    KEYS = {
        jobMenu = "f2",         -- job menu during a match (leave, reset to checkpoint)
        spectate = "space",     -- reopens the spectator menu
    },
    SPECTATE_DELAY = 3000,      -- ms of death camera before a dead DM player becomes a spectator
    RACE = {
        finishLimit = 60,       -- s after the first finisher; then everyone still racing is DNF
        offRoute = 150,         -- m from the route before the warning (race.offRoute overrides, 0 = off)
        offRouteGrace = 5,      -- s of warning before the racer is put back
        fallBelow = 40,         -- m below the lowest route point = fell under the map
        waterMs = 1000,         -- ms in the water before the racer is put back
        recoverCooldown = 3000, -- ms between two automatic recoveries
        manualCooldown = 10000, -- ms between two "Reset to checkpoint" from the job menu
        ghostMs = 3000,         -- no collisions with other racers after a recovery
    },
    MISSION = {
        respawnMs = 10000,      -- dead mission player comes back after this (while Team lives > 0)
        tickMs = 250,           -- zone / position checks
    },
}
