-- Local per-player settings stored in userdata.xml (remembered login, music).

UserData = {}

local FILE = "userdata.xml"
local KEYS = { "username", "password", "music" }
local cache = {}

local function ensureFile()
    local xml = xmlLoadFile(FILE)
    if xml then return xml end

    xml = xmlCreateFile(FILE, "userdata")
    if not xml then return nil end
    for _, key in ipairs(KEYS) do
        xmlCreateChild(xml, key)
    end
    xmlSaveFile(xml)
    return xml
end

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

local function load()
    local xml = ensureFile()
    if not xml then return end
    for _, key in ipairs(KEYS) do
        local node = xmlFindChild(xml, key, 0)
        cache[key] = (node and xmlNodeGetValue(node)) or ""
    end
    xmlUnloadFile(xml)
end

load()
