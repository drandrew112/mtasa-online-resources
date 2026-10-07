-- web_api :: server/page.lua
-- HTTP page builder. MTA serves client files with "application/octet-stream" (browsers refuse
-- such a stylesheet), so the HTTP page is sent as ONE document with its css / js inlined from
-- the very same source files the in-game page loads.
--
-- A resource may not read another resource's files (ACL ModifyOtherObjects), so the app's own
-- <html> script reads its files and hands them over - see the standard web/http.html in
-- README.md:
--     local refs = exports.web_api:getAssetRefs(html, PAGE)      -- which files the page links
--     httpWrite(exports.web_api:renderPage(html, files, PAGE))   -- files[path] = content
--
-- Shared files are referenced as /web_api/osa.css and /web_api/osa.js (the same URL works in
-- game: http://mta/web_api/osa.css). The app's own files are relative to its page.

local thisName = getResourceName(resource)

local function readOwn(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local size = fileGetSize(f)
    local content = size > 0 and fileRead(f, size) or ""
    fileClose(f)
    return content
end

-- "web/" + "../x.css" -> "x.css"
local function resolve(dir, rel)
    local parts = {}
    for seg in (dir .. rel):gmatch("[^/]+") do
        if seg == ".." then parts[#parts] = nil
        elseif seg ~= "." then parts[#parts + 1] = seg end
    end
    return table.concat(parts, "/")
end

local function dirOf(path)
    return path:match("^(.*/)[^/]*$") or ""
end

local function escapeAttr(s)
    return (s:gsub('[&<>"]', { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

local function errorPage(msg)
    return "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Web API</title></head>" ..
        "<body style=\"font:15px sans-serif;background:#0f1216;color:#e8ecf1;padding:30px\">" ..
        "<h2>Web API</h2><p>" .. escapeAttr(msg) .. "</p></body></html>"
end

-- Calls fn(kind, ref, tag) for every stylesheet link / script src of the page; a string
-- returned by fn replaces the tag.
local function eachAsset(html, fn)
    html = html:gsub("<link%s[^>]*>", function(tag)
        if not tag:find('rel%s*=%s*"stylesheet"') then return nil end
        local href = tag:match('href%s*=%s*"([^"]+)"')
        if href then return fn("css", href) end
    end)
    html = html:gsub('<script%s+src%s*=%s*"([^"]+)"%s*></script>', function(src)
        return fn("js", src)
    end)
    return html
end

local function isExternal(ref)
    return ref:find("^//") or ref:find("^%a[%w+.-]*:") or (ref:find("^/") and not ref:find("^/" .. thisName .. "/"))
end

-- Files of the app a page links (relative paths, resource root based), for renderPage's `files`.
function getAssetRefs(html, page)
    local dir = dirOf(type(page) == "string" and page or "web/index.html")
    local list, seen = {}, {}
    if type(html) ~= "string" then return list end
    eachAsset(html, function(_, ref)
        if not isExternal(ref) then
            local path = resolve(dir, (ref:gsub("[?#].*$", "")))
            if not seen[path] then seen[path] = true; list[#list + 1] = path end
        end
        return nil
    end)
    return list
end

-- renderPage(html, files, page) -> the complete HTML document
--   html   the source of the app's page (e.g. web/index.html)
--   files  { [path] = content } of the files getAssetRefs listed
--   page   path of that page, default "web/index.html" (its folder is the base for relative urls)
function renderPage(html, files, page)
    local res = sourceResource
    if not res then return errorPage("renderPage must be called from a resource.") end
    if type(html) ~= "string" or html == "" then return errorPage("The page file could not be read.") end
    files = type(files) == "table" and files or {}
    page = type(page) == "string" and page ~= "" and page or "web/index.html"
    local app = getResourceName(res)
    local dir = dirOf(page)
    local missing = {}

    html = eachAsset(html, function(kind, ref)
        local content
        local own = ref:match("^/" .. thisName .. "/(.+)$")
        if own then
            content = readOwn(own)
        elseif not isExternal(ref) then
            content = files[resolve(dir, (ref:gsub("[?#].*$", "")))]
        else
            return nil
        end
        if not content then
            missing[#missing + 1] = ref
            return nil
        end
        if kind == "css" then
            return "<style>\n" .. content:gsub("</style", "<\\/style") .. "\n</style>"
        end
        return "<script>\n" .. content:gsub("</script", "<\\/script") .. "\n</script>"
    end)

    if #missing > 0 then
        outputDebugString("[web_api] " .. app .. ": page files not found: " .. table.concat(missing, ", "), 2)
    end

    -- tell osa.js where it runs; relative urls resolve against the page's folder, as in game
    local head = '<meta name="osa-app" content="' .. escapeAttr(app) .. '">' ..
        '<meta name="osa-mode" content="http">' ..
        '<base href="/' .. escapeAttr(app) .. "/" .. escapeAttr(dir) .. '">'
    local replaced
    html, replaced = html:gsub("(<head[^>]*>)", function(open) return open .. head end, 1)
    if replaced == 0 then html = head .. html end
    return html
end
