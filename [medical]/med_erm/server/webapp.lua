-- Dispatcher console as a web_api app: the in-game console is the ui_browser site
-- "ems-dispatch.eu" (web_api relays the page's calls to the http="true" exports of
-- server/http.lua); the HTTP console is web/http.html.

local function registerSite()
    exports.web_api:registerApp({
        title       = "EMS Dispatch",
        site        = "ems-dispatch.eu",
        category    = "services",
        description = "Emergency Response Manager - dispatcher console. Dispatcher code required.",
    })
end

addEventHandler("onResourceStart", resourceRoot, registerSite)
addEventHandler("onWebApiStart", root, registerSite)
