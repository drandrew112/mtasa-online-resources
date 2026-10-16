-- med_web :: server/pages.lua
-- HTTP pages and the in-game site. Every page is a web/*.html source file built on web_api:
-- the <html> entry at the resource root (index.html, dispatch.html, ...) only calls
-- MedWeb.render, which inlines the css / js the page links (MTA serves client files as
-- octet-stream, which browsers refuse as a stylesheet). In game the same web/*.html files load
-- through web_api's loader.html as local CEF pages.
--
--   /med_web/               web/index.html     public landing page of the ambulance service
--   /med_web/dispatch.html  web/dispatch.html  dispatcher console (dispatcher code)
--   /med_web/tablet.html    web/tablet.html    unit tablet (game account, unit crew)
--   /med_web/admin.html     web/admin.html     ERM admin (game account, admin level)

MedWeb = {}

local PAGES = {
    index    = "web/index.html",
    dispatch = "web/dispatch.html",
    tablet   = "web/tablet.html",
    admin    = "web/admin.html",
}

local function read(path)
    local f = fileExists(path) and fileOpen(path, true)
    if not f then return nil end
    local size = fileGetSize(f)
    local content = size > 0 and fileRead(f, size) or ""
    fileClose(f)
    return content
end

-- The complete HTTP document of a page (called from the root <html> entries).
function MedWeb.render(name)
    local page = PAGES[name] or PAGES.index
    local html = read(page)
    local files = {}
    if html then
        for _, path in ipairs(exports.web_api:getAssetRefs(html, page)) do files[path] = read(path) end
    end
    return exports.web_api:renderPage(html, files, page)
end

-- In game: the ui_browser site opens the landing page; its links go to the other pages
-- through the loader (web/js/common.js).
local function registerSite()
    exports.web_api:registerApp({
        title       = "San Andreas EMS",
        site        = "ems-dispatch.eu",
        category    = "services",
        description = "San Andreas Emergency Medical Services - dispatcher console, unit tablet, ERM admin.",
        page        = PAGES.index,
    })
end

addEventHandler("onResourceStart", resourceRoot, registerSite)
addEventHandler("onWebApiStart", root, registerSite)
