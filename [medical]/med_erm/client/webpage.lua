-- The dispatcher console inside the in-game virtual browser (ui_browser).
--
-- It is the same page as the HTTP one (web/index.html), loaded as a local CEF
-- page (http://mta/erm/web/index.html) by ui_browser's "web" site type. The
-- page has no HTTP access in game, so its API calls come here through
-- mta.triggerEvent("erm:web:call", id, fn, argsJson), go to the server
-- (server/webbridge.lua) and the answer is handed back to the page with
-- ERM._bridgeResolve(id, result).

local SITE_URL = "ems-dispatch.eu"
local PAGE_URL = "http://mta/" .. getResourceName(resource) .. "/web/index.html"
local PAGE_PREFIX = "http://mta/" .. getResourceName(resource) .. "/"

local requests = {}   -- [localId] = { browser, jsId }
local nextId = 0

local function registerSite()
    local res = getResourceFromName("ui_browser")
    if not res or getResourceState(res) ~= "running" then return end
    exports.ui_browser:registerBrowserSite(SITE_URL, {
        title    = "EMS Dispatch",
        category = "services",
        desc     = "Emergency Response Manager - dispatcher console. Dispatcher code required.",
        web      = PAGE_URL,
    })
end

addEventHandler("onClientResourceStart", root, function(res)
    if res == resource or getResourceName(res) == "ui_browser" then registerSite() end
end)

-- page -> server
addEvent("erm:web:call", false)
addEventHandler("erm:web:call", root, function(jsId, fn, argsJson)
    local browser = source
    if getElementType(browser) ~= "webbrowser" then return end
    if (getBrowserURL(browser) or ""):sub(1, #PAGE_PREFIX) ~= PAGE_PREFIX then return end

    nextId = nextId + 1
    requests[nextId] = { browser = browser, jsId = tonumber(jsId) or 0 }
    triggerServerEvent("erm:web:call", resourceRoot, nextId, tostring(fn), tostring(argsJson))
end)

-- server -> page
addEvent("erm:web:result", true)
addEventHandler("erm:web:result", resourceRoot, function(localId, result)
    local req = requests[localId]
    requests[localId] = nil
    if not req or not isElement(req.browser) then return end
    local json = toJSON(result or { ok = false, error = "No response" }, true) or "[ null ]"
    executeBrowserJavascript(req.browser, string.format("ERM._bridgeResolve(%d, %s)", req.jsId, json))
end)
