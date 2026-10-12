-- Catalog store of v_locals (both sides).
--
--   locales/languages.json             language list (code, names, fallback, plural rule, enabled)
--   locales/<lang>/<namespace>.json    flat { "namespace.key": "text" }
--   locales/<lang>/files/<path>        long texts (L.file)
--
-- Namespaces are read lazily on the first request and cached. On the client
-- only the files listed in meta.xml exist (downloaded), on the server every
-- file of the folder is readable.

Catalog = {
    langs   = {},   -- code -> info table
    order   = {},   -- codes in languages.json order
    data    = {},   -- data[lang][ns] = table | false
    files   = {},   -- files[lang][path] = string | false
}

local function readFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local text = fileRead(f, fileGetSize(f)) or ""
    fileClose(f)
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end   -- UTF-8 BOM
    return text
end
Catalog.readFile = readFile

local function readJSON(path)
    local text = readFile(path)
    if not text then return nil, "missing" end
    if text:match("^%s*{%s*}%s*$") then return {} end
    local data = fromJSON(text)
    if type(data) ~= "table" then return nil, "invalid JSON" end
    return data
end
Catalog.readJSON = readJSON

local function warn(fmt, ...)
    outputDebugString("[v_locals] " .. fmt:format(...), 2)
end

function Catalog.loadLanguages()
    Catalog.langs, Catalog.order = {}, {}
    local data, err = readJSON("locales/languages.json")
    local list = data and data.languages
    if type(list) ~= "table" then
        warn("locales/languages.json: %s, only '%s' is available", tostring(err or "no languages list"), LOC.DEFAULT_LANG)
        list = { { code = LOC.DEFAULT_LANG, name = "English", nativeName = "English", plural = "one_other", enabled = true } }
    end
    for _, l in ipairs(list) do
        if type(l) == "table" and locIsLangCode(l.code) and not Catalog.langs[l.code] then
            Catalog.langs[l.code] = {
                code       = l.code,
                name       = tostring(l.name or l.code),
                nativeName = tostring(l.nativeName or l.name or l.code),
                fallback   = locIsLangCode(l.fallback) and l.fallback or nil,
                plural     = type(l.plural) == "string" and l.plural or "one_other",
                enabled    = l.enabled ~= false,
            }
            Catalog.order[#Catalog.order + 1] = l.code
        else
            warn("locales/languages.json: bad or duplicate language entry %s", tostring(type(l) == "table" and l.code or l))
        end
    end
    if not Catalog.isEnabled(LOC.DEFAULT_LANG) then
        warn("default language '%s' is not enabled in languages.json", LOC.DEFAULT_LANG)
    end
end

function Catalog.isEnabled(code)
    local l = type(code) == "string" and Catalog.langs[code]
    return l and l.enabled or false
end

-- { code = { fallback, plural, name, nativeName, enabled } } for the libs
function Catalog.info()
    local out = {}
    for code, l in pairs(Catalog.langs) do
        out[code] = { fallback = l.fallback, plural = l.plural, name = l.name, nativeName = l.nativeName, enabled = l.enabled }
    end
    return out
end

-- enabled languages as choice options: { { value = "en", label = "English" }, ... }
function Catalog.choices()
    local out = {}
    for _, code in ipairs(Catalog.order) do
        local l = Catalog.langs[code]
        if l.enabled then out[#out + 1] = { value = code, label = l.nativeName } end
    end
    return out
end

-- flat { key = text } of one namespace, or false; invalid entries are dropped
function Catalog.get(lang, ns)
    if not Catalog.isEnabled(lang) or type(ns) ~= "string" or not ns:match("^[%w_]+$") then return false end
    local byLang = Catalog.data[lang]
    if not byLang then byLang = {}; Catalog.data[lang] = byLang end
    local cached = byLang[ns]
    if cached ~= nil then return cached end

    local path = ("locales/%s/%s.json"):format(lang, ns)
    local data, err = readJSON(path)
    if not data then
        if err ~= "missing" then warn("%s: %s", path, err) end
        byLang[ns] = false
        return false
    end
    local out, prefix = {}, ns .. "."
    for k, v in pairs(data) do
        if type(k) ~= "string" or not k:match("^[a-z0-9_]+%.[a-z0-9_.]+$") or k:sub(-1) == "." or k:find("..", 1, true) then
            warn("%s: invalid key %s", path, tostring(k))
        elseif k:sub(1, #prefix) ~= prefix then
            warn("%s: key %s is outside namespace '%s'", path, k, ns)
        elseif type(v) ~= "string" then
            warn("%s: value of %s is not a string", path, k)
        else
            out[k] = v
        end
    end
    byLang[ns] = out
    return out
end

-- long text file with the language fallback chain, or false
function Catalog.getFile(lang, path)
    if type(path) ~= "string" or path:find("..", 1, true) or not path:match("^[%w_%-/%.]+$") then return false end
    local tried = 0
    while lang and tried < 4 do
        if Catalog.isEnabled(lang) then
            local byLang = Catalog.files[lang]
            if not byLang then byLang = {}; Catalog.files[lang] = byLang end
            local text = byLang[path]
            if text == nil then
                text = readFile(("locales/%s/files/%s"):format(lang, path)) or false
                if text then text = text:gsub("\r", "") end
                byLang[path] = text
            end
            if text then return text end
        end
        local l = Catalog.langs[lang]
        local fb = l and l.fallback
        if not fb and lang ~= LOC.DEFAULT_LANG then fb = LOC.DEFAULT_LANG end
        if fb == lang then fb = nil end
        lang = fb
        tried = tried + 1
    end
    return false
end

function Catalog.reload()
    Catalog.data, Catalog.files = {}, {}
    Catalog.loadLanguages()
end

Catalog.loadLanguages()
