-- Startup / shutdown.

addEvent("mysql:connected")

-- Creates the tables and loads the open tasks once the database is reachable.
local function startDb()
    if DB.ready or not DB.init() then return end
    Tasks.load()
end

addEventHandler("onResourceStart", resourceRoot, function()
    startDb()
    if not DB.ready then outputDebugString("[erm] v_mysql not connected yet, waiting for mysql:connected", 2) end

    local port = getServerHttpPort()
    outputServerLog(string.format("[erm] Dispatcher console: http://<server-ip>:%d/%s/", port, getResourceName(resource)))
end)

-- v_mysql (re)connected: the first time it also creates the tables and loads the tasks
addEventHandler("mysql:connected", root, startDb)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, u in pairs(Units.list) do
        DB.endShift(u, "resource stop")
        Units.untagVehicle(u)
    end
end)
