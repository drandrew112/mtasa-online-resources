JOB_TYPE_RACE, JOB_TYPE_DM = "race", "deathmatch"
-- Server: filled by core/games.lua from games/*.json. Client: filled by the
-- "jobmanager:markers" event (only what the world markers need).
jobs, jobsById = {}, {}
