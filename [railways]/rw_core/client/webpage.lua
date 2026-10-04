-- The network map inside the in-game virtual browser (ui_browser, "services" category).
-- Same page as the HTTP one (web/index.html) as a local CEF page; it has no HTTP access in
-- game, so its calls come here via mta.triggerEvent("rw:web:call", id, fn) and the answer
-- goes back with RWWEB._bridgeResolve(id, result).

local PAGE_URL = "http://mta/" .. getResourceName(resource) .. "/web/game.html"
local PAGE_PREFIX = "http://mta/" .. getResourceName(resource) .. "/"

-- CEF caches local pages: web/game.html is opened with ?v=<hash of the web files> and loads
-- index.html + css / js under the same ?v=, so an updated resource never shows the old page
local WEB_FILES = { "web/game.html", "web/index.html", "web/css/style.css", "web/js/api.js", "web/js/map.js", "web/js/app.js" }
local function webVersion()
    local parts = {}
    for _, path in ipairs(WEB_FILES) do
        local f = fileOpen(path, true)
        if f then
            parts[#parts + 1] = fileRead(f, fileGetSize(f))
            fileClose(f)
        end
    end
    return md5(table.concat(parts)):sub(1, 12):lower()
end

local requests = {}
local nextId = 0

local function registerSite()
    local res = getResourceFromName("ui_browser")
    if not res or getResourceState(res) ~= "running" then return end
    exports.ui_browser:registerBrowserSite(RW.SITE_URL, {
        title    = RW.COMPANY,
        category = "services",
        desc     = RW.COMPANY .. " - live network map: trains, stations and timetables.",
        web      = PAGE_URL .. "?v=" .. webVersion(),
    })
end

addEventHandler("onClientResourceStart", root, function(res)
    if res == resource or getResourceName(res) == "ui_browser" then registerSite() end
end)

addEvent("rw:web:call", false)
addEventHandler("rw:web:call", root, function(jsId, fn)
    local browser = source
    if getElementType(browser) ~= "webbrowser" then return end
    if (getBrowserURL(browser) or ""):sub(1, #PAGE_PREFIX) ~= PAGE_PREFIX then return end
    nextId = nextId + 1
    requests[nextId] = { browser = browser, jsId = tonumber(jsId) or 0 }
    triggerServerEvent("rw:web:call", resourceRoot, nextId, tostring(fn))
end)

addEvent("rw:web:result", true)
addEventHandler("rw:web:result", resourceRoot, function(localId, result)
    local req = requests[localId]
    requests[localId] = nil
    if not req or not isElement(req.browser) then return end
    local json = toJSON(result or { ok = false, error = "No response" }, true) or "[ null ]"
    executeBrowserJavascript(req.browser, string.format("RWWEB._bridgeResolve(%d, %s)", req.jsId, json))
end)
