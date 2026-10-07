-- web_api :: client/sites.lua
-- Registers every app that asked for a ui_browser site (registerApp { site = ... }). The server
-- sends the list; the page is opened through the loader (loader.html) so a restarted resource
-- never shows a stale, cached CEF page.

local apps = {}

local function registerAll()
    local res = getResourceFromName("ui_browser")
    if not res or getResourceState(res) ~= "running" then return end
    for _, app in ipairs(apps) do
        exports.ui_browser:registerBrowserSite(app.site, {
            title    = app.title,
            category = app.category,
            desc     = app.desc,
            web      = string.format("http://mta/%s/loader.html?app=%s&page=%s&v=%s",
                getResourceName(resource), app.name, app.page, app.v),
        })
    end
end

addEvent("osa:apps", true)
addEventHandler("osa:apps", resourceRoot, function(list)
    apps = type(list) == "table" and list or {}
    registerAll()
end)

addEventHandler("onClientResourceStart", root, function(res)
    if res == resource then
        triggerServerEvent("osa:requestApps", resourceRoot)
    elseif getResourceName(res) == "ui_browser" then
        registerAll()
    end
end)
