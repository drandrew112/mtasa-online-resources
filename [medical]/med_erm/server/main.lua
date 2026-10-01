-- Startup / shutdown.

addEventHandler("onResourceStart", resourceRoot, function()
    if not DB.init() then
        cancelEvent(true, "Database could not be opened")
        return
    end
    Tasks.load()

    local port = getServerHttpPort()
    outputServerLog(string.format("[erm] Dispatcher console: http://<server-ip>:%d/%s/", port, getResourceName(resource)))
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, u in pairs(Units.list) do
        DB.endShift(u)
    end
end)
