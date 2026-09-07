

function syncTables()
    triggerClientEvent(getRootElement(), "syncTables", getRootElement(), active_jobs, active_lobbys)
end
setTimer(syncTables, 100, 0)
