-- v_voiceclient_connector / server/main.lua

addEventHandler("onResourceStart", resourceRoot, function()
    Codes.refreshAll()
    local ready = {}
    for workId in pairs(Codes.WORKS) do
        ready[#ready + 1] = workId .. (Codes.isReady(workId) and "" or " (target not running)")
    end
    outputServerLog("[v_voiceclient_connector] voice radio ready: " .. table.concat(ready, ", "))
end)
