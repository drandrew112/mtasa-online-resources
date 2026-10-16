-- med_web :: server/pages.lua
-- In-game site. The HTTP pages are the <html> entries at the resource root (index.html,
-- dispatch.html, ...): each reads its web/*.html source and web_api inlines the css / js it links
-- (MTA serves client files as octet-stream, which browsers refuse as a stylesheet). <html> pages
-- run apart from the server scripts, so they cannot share a helper from here. In game the same
-- web/*.html files load through web_api's loader.html as local CEF pages.
--
--   /med_web/               web/index.html     public landing page of the ambulance service
--   /med_web/dispatch.html  web/dispatch.html  dispatcher console (dispatcher code)
--   /med_web/tablet.html    web/tablet.html    unit tablet (game account, unit crew)
--   /med_web/admin.html     web/admin.html     ERM admin (game account, admin level)

-- In game: the ui_browser site opens the landing page; its links go to the other pages
-- through the loader (web/js/common.js).
local function registerSite()
    exports.web_api:registerApp({
        title       = "San Andreas EMS",
        site        = "ems-dispatch.eu",
        category    = "services",
        description = "San Andreas Emergency Medical Services - dispatcher console, unit tablet, ERM admin.",
        page        = "web/index.html",
    })
end

addEventHandler("onResourceStart", resourceRoot, registerSite)
addEventHandler("onWebApiStart", root, registerSite)
