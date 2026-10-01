-- Web Manager: collects the resources that serve web pages over MTA HTTP
-- (non-raw <html> items in their meta.xml). index.html renders the list.

local thisName = getResourceName(resource)

-- [resourceName] = { name, page, title, description, author }
local webResources = {}

-- Reads the meta.xml of a resource and returns the page to link to, or nil
-- when the resource has no browsable page. Prefers the default html item
-- (served on /<resource>/), otherwise the first non-raw one.
local function findWebPage(resName)
    local xml = xmlLoadFile(":" .. resName .. "/meta.xml", true)
    if not xml then return nil end

    local first, default
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        if xmlNodeGetName(node) == "html" then
            local src = xmlNodeGetAttribute(node, "src")
            local raw = xmlNodeGetAttribute(node, "raw") == "true"
            if src and not raw then
                first = first or src
                if xmlNodeGetAttribute(node, "default") == "true" then
                    default = src
                end
            end
        end
    end
    xmlUnloadFile(xml)

    if default then return "" end
    return first
end

local function scanResource(res)
    local resName = getResourceName(res)
    if resName == thisName then return end

    local page = findWebPage(resName)
    if not page then
        webResources[resName] = nil
        return
    end

    webResources[resName] = {
        name        = resName,
        page        = page,
        title       = getResourceInfo(res, "name") or resName,
        description = getResourceInfo(res, "description") or "",
        author      = getResourceInfo(res, "author") or "",
    }
end

local function scanAll()
    webResources = {}
    for _, res in ipairs(getResources()) do
        scanResource(res)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    scanAll()
    local count = 0
    for _ in pairs(webResources) do count = count + 1 end
    outputServerLog("[web_manager] " .. count .. " web resource(s) found")
end)

-- a restarted resource may have a changed meta.xml
addEventHandler("onResourceStart", root, function(res)
    if res ~= resource then scanResource(res) end
end)

-- ------------------------------------- export, index.html calls it via call()

function getWebResourceList()
    local list = {}
    for resName, entry in pairs(webResources) do
        local res = getResourceFromName(resName)
        list[#list + 1] = {
            name        = entry.name,
            url         = "/" .. entry.name .. "/" .. entry.page,
            title       = entry.title,
            description = entry.description,
            author      = entry.author,
            running     = res and getResourceState(res) == "running" or false,
        }
    end
    table.sort(list, function(a, b)
        if a.running ~= b.running then return a.running end
        return a.title:lower() < b.title:lower()
    end)
    return list
end
