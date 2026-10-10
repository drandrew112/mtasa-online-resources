-- v_monitors (server): collects what the wall screens show (traffic, staffed positions, the
-- scope views of the controllers) and sends it every 5 s to the players standing near the wall.
-- Data comes from avi_* through exports; never keep an exports table in a local.

local watchers = {}     -- [player] = true

local function running(name)
    local res = getResourceFromName(name)
    return res and getResourceState(res) == "running"
end

local function call(resName, fn, ...)
    if not running(resName) then return nil end
    local ok, a = pcall(function(...) return exports[resName][fn](exports[resName], ...) end, ...)
    if not ok then
        outputDebugString(("[v_monitors] %s:%s failed: %s"):format(resName, fn, tostring(a)), 2)
        return nil
    end
    return a
end

local function staticData()
    local nav = call("avi_nav", "getNavData") or {}
    return {
        airspaces = call("avi_airspace", "getAirspaces") or {},
        nav = { fixes = nav.fixes or {}, ndbs = nav.ndbs or {}, vors = nav.vors or {} },
        airports = call("avi_airports", "getAirports") or {},
    }
end

local function dynamicData()
    return {
        positions = call("avi_controller", "getPositions") or {},
        staffed = call("avi_controller", "getStaffedPositions") or {},
        views = call("avi_controller", "getPositionViews") or {},
        traffic = call("avi_traffic", "getTrafficSnapshot") or {},
        runways = call("avi_airports", "getActiveRunways") or {},
        wind = call("avi_airports", "getWind") or { dir = 0, speed = 0 },
    }
end

local function list()
    local out = {}
    for p in pairs(watchers) do
        if isElement(p) then out[#out + 1] = p else watchers[p] = nil end
    end
    return out
end

local function sendStatic(players)
    triggerLatentClientEvent(players, "vmon:static", 500000, false, resourceRoot, staticData())
end

local function sendDynamic(players)
    triggerClientEvent(players, "vmon:data", resourceRoot, dynamicData())
end

addEvent("vmon:watch", true)
addEventHandler("vmon:watch", resourceRoot, function(on)
    if on then
        watchers[client] = true
        sendStatic({ client })
        sendDynamic({ client })
    else
        watchers[client] = nil
    end
end)

addEventHandler("onPlayerQuit", root, function() watchers[source] = nil end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        local players = list()
        if #players > 0 then sendDynamic(players) end
    end, MON.REFRESH_MS, 0)
end)

-- nav data edited (/avinav): the watchers get the new static layers
addEvent("onAviNavChange")
addEventHandler("onAviNavChange", root, function()
    local players = list()
    if #players > 0 then sendStatic(players) end
end)
