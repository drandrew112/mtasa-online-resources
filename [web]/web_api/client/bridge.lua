-- web_api :: client/bridge.lua
-- Relays the calls of a page inside the in-game browser (ui_browser) to the server and the
-- answers back:   page  mta.triggerEvent("osa:web:call", id, fn, argsJson)
--                 -> here -> server (server/bridge.lua) -> here -> OSA._resolve(id, json)
-- The app is taken from the browser's own URL (the loader's ?app=), never from the page.

local LOADER_PREFIX = "http://mta/" .. getResourceName(resource) .. "/loader.html?"
local TIMEOUT_MS = 60000

local requests = {}   -- [localId] = { browser, jsId, tick }
local nextId = 0

local function appOf(browser)
    local url = getBrowserURL(browser) or ""
    if url:sub(1, #LOADER_PREFIX) ~= LOADER_PREFIX then return nil end
    return url:match("[?&]app=([%w_%-]+)")
end

local function purge()
    local t = getTickCount()
    for id, req in pairs(requests) do
        if t - req.tick > TIMEOUT_MS or not isElement(req.browser) then requests[id] = nil end
    end
end

-- page -> server
addEvent("osa:web:call", false)
addEventHandler("osa:web:call", root, function(jsId, fn, argsJson)
    local browser = source
    if getElementType(browser) ~= "webbrowser" then return end
    local app = appOf(browser)
    if not app or type(fn) ~= "string" or type(argsJson) ~= "string" then return end

    purge()
    nextId = nextId + 1
    requests[nextId] = { browser = browser, jsId = tonumber(jsId) or 0, tick = getTickCount() }
    triggerServerEvent("osa:web:call", resourceRoot, nextId, app, fn, argsJson)
end)

-- server -> page
addEvent("osa:web:result", true)
addEventHandler("osa:web:result", resourceRoot, function(localId, json)
    local req = requests[localId]
    requests[localId] = nil
    if not req or not isElement(req.browser) or type(json) ~= "string" then return end
    executeBrowserJavascript(req.browser, string.format("OSA._resolve(%d, %s)", req.jsId, json))
end)
