if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Loads the road geometry (data/runtime/geo.dat) in small steps, then tells the server it can
-- start sending traffic states.

local co

local function finish()
    outputDebugString(string.format("[ai_land_traffic] geometry loaded: %d lanes, %d curves", Geo.lanes, Geo.curves))
    triggerServerEvent(EV_READY, resourceRoot)
    Puppets.viewReady()
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local text = Geo.readFile(TRAFFIC.GEO_FILE)
    if not text then
        outputDebugString("[ai_land_traffic] missing " .. TRAFFIC.GEO_FILE, 1)
        return
    end
    co = coroutine.create(function() Geo.parse(text, 4000) end)
    local timer
    timer = setTimer(function()
        local ok, err = coroutine.resume(co)
        if not ok then
            killTimer(timer)
            outputDebugString("[ai_land_traffic] geometry load failed: " .. tostring(err), 1)
        elseif coroutine.status(co) == "dead" then
            killTimer(timer)
            text = nil
            finish()
        end
    end, 50, 0)
end)

addEvent("ai_traffic:notify", true)
addEventHandler("ai_traffic:notify", resourceRoot, function(text)
    if getResourceFromName("ui_core") and getResourceState(getResourceFromName("ui_core")) == "running" then
        exports.ui_core:addNotification(L("ai_land_traffic.network.traffic"), text)
    else
        outputDebugString("[ai_land_traffic] " .. text)
    end
end)
