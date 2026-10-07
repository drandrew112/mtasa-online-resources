-- web_api :: server/main.lua
-- Registry of web apps. An "app" is a resource that serves a web UI built on this toolkit.
-- Registering is optional for HTTP-only apps; it is needed for a ui_browser site or a custom
-- page path. The app is the resource that calls registerApp.

WebApi = {
    apps = {},   -- [resourceName] = app
}

local thisName = getResourceName(resource)

-- Raised after web_api (re)started, so running apps can register again.
addEvent("onWebApiStart", false)

local function isSafeRelPath(p)
    return type(p) == "string" and p ~= "" and #p < 200 and not p:find("%.%.") and not p:find("^[/\\]")
        and not p:find("[%c\"'<>?&#%%]")
end

function WebApi.version(res)
    return tostring(getResourceLastStartTime(res) or 0) .. tostring(getResourceLastStartTime(resource) or 0)
end

-- Entries sent to the clients (ui_browser sites only).
local function clientList()
    local list = {}
    for name, app in pairs(WebApi.apps) do
        local res = getResourceFromName(name)
        if app.site and res and getResourceState(res) == "running" then
            list[#list + 1] = {
                name = name, title = app.title, site = app.site, category = app.category,
                desc = app.desc, page = app.page, v = WebApi.version(res),
            }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

-- players whose web_api client script is running (it asks for the list when it starts)
local ready = {}

function WebApi.broadcast(player)
    local list = clientList()
    if player then
        triggerClientEvent(player, "osa:apps", resourceRoot, list)
        return
    end
    for p in pairs(ready) do triggerClientEvent(p, "osa:apps", resourceRoot, list) end
end

-- registerApp { title=, site=, category=, description=, page= }
--   site     ui_browser address (e.g. "ems-dispatch.eu"); omit for an HTTP-only app
--   category ui_browser category id (default "services")
--   page     the page inside the resource, default "web/index.html"
function registerApp(def)
    local res = sourceResource
    if not res or type(def) ~= "table" then return false end
    local name = getResourceName(res)

    local page = def.page == nil and "web/index.html" or def.page
    if not isSafeRelPath(page) then
        outputDebugString("[web_api] " .. name .. ": invalid page path", 2)
        return false
    end

    WebApi.apps[name] = {
        name     = name,
        resource = res,
        title    = tostring(def.title or name):sub(1, 80),
        site     = type(def.site) == "string" and def.site ~= "" and def.site:lower():sub(1, 100) or nil,
        category = tostring(def.category or "services"):sub(1, 30),
        desc     = tostring(def.description or def.desc or ""):sub(1, 300),
        page     = page,
    }
    WebApi.broadcast()
    return true
end

function unregisterApp()
    local res = sourceResource
    if not res then return false end
    local name = getResourceName(res)
    if not WebApi.apps[name] then return false end
    WebApi.apps[name] = nil
    WebApi.broadcast()
    return true
end

-- Public info about the registered apps (no resource elements).
function getApps()
    local list = {}
    for name, app in pairs(WebApi.apps) do
        list[#list + 1] = { name = name, title = app.title, site = app.site or false, page = app.page, desc = app.desc }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

addEvent("osa:requestApps", true)
addEventHandler("osa:requestApps", resourceRoot, function()
    if isElement(client) then
        ready[client] = true
        WebApi.broadcast(client)
    end
end)

addEventHandler("onPlayerQuit", root, function() ready[source] = nil end)

addEventHandler("onResourceStop", root, function(res)
    local name = getResourceName(res)
    if res ~= resource and WebApi.apps[name] then
        WebApi.apps[name] = nil
        WebApi.broadcast()
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    triggerEvent("onWebApiStart", root)
    outputServerLog("[" .. thisName .. "] web toolkit ready")
end)
