JOB_TYPE_RACE, JOB_TYPE_DM = "race", "deathmatch"
jobs, jobsById = {}, {}

function registerJob(job)
    assert(type(job) == "table" and type(job.id) == "string", "Invalid job definition")
    assert(not jobsById[job.id], "Duplicate job id: " .. job.id)
    jobsById[job.id] = job
    table.insert(jobs, job)
end
