JOB_TYPE_RACE, JOB_TYPE_DM = "race", "deathmatch"
-- Server: filled by core/storage.lua from MySQL (jobs_official / jobs_community). Client: filled by the
-- "jobmanager:markers" event (only what the world markers need).
jobs, jobsById = {}, {}
