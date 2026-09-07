-- sync

function client_syncTables(_active_jobs, _active_lobbys)
    active_jobs = _active_jobs
    active_lobbys = _active_lobbys
end
addEvent("syncTables", true)
addEventHandler("syncTables", getResourceRootElement(), client_syncTables)
