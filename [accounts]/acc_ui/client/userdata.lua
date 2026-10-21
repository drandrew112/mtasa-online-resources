-- Local per-player UI settings in this resource's private userdata.xml (menu music).

UserData = {}

local FILE = "userdata.xml"
local cache = {}

function UserData.get(key)
    return cache[key] or ""
end

function UserData.set(key, value)
    value = tostring(value)
    cache[key] = value
    local xml = xmlLoadFile(FILE) or xmlCreateFile(FILE, "userdata")
    if not xml then return end
    local node = xmlFindChild(xml, key, 0) or xmlCreateChild(xml, key)
    xmlNodeSetValue(node, value)
    xmlSaveFile(xml)
    xmlUnloadFile(xml)
end

local xml = xmlLoadFile(FILE)
if xml then
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        cache[xmlNodeGetName(node)] = xmlNodeGetValue(node) or ""
    end
    xmlUnloadFile(xml)
end
