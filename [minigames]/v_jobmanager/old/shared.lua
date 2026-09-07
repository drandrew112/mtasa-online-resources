
job_types = {
    ctf = "Capture the Flag",
    dm = "Deathmatch",
    mission = "Mission",
    race = "Race",
}

active_jobs = {}
active_lobbys = {}

function getJobDim(job_id)
    return 1000+job_id
end

function getJobPlayers(job_id)
    return active_jobs[job_id].players
end
