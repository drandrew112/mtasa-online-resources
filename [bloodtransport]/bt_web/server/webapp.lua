-- The page as a web_api app: the ui_browser site "blood-transport.eu" (Services) and, through
-- web/http.html, the HTTP page http://<server>:<httpport>/bt_web/.

local function registerSite()
    exports.web_api:registerApp({
        title       = "Blood Transport",
        site        = "blood-transport.eu",
        category    = "services",
        description = "Blood transport service of San Andreas: live map, stock of the blood banks and hospitals, how to join.",
    })
end

addEventHandler("onResourceStart", resourceRoot, registerSite)
addEvent("onWebApiStart")
addEventHandler("onWebApiStart", root, registerSite)
