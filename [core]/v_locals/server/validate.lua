-- Catalog validation (server): runs on start and on /locreload.
--
-- Reads every locales/... file listed in meta.xml and checks:
--   * the language folder is a language of languages.json
--   * JSON parses, keys are valid and inside the file's namespace, values are strings
--   * a non-default language has the same {placeholders} and #RRGGBB colour
--     codes as the default language text of the same key
--   * keys missing from the default language (orphans)
-- Results go to the server log; nothing is changed or refused at run time.

local function log(fmt, ...)
    outputServerLog("[v_locals] " .. fmt:format(...))
end

local function colourCodes(text)
    local list = {}
    for code in text:gmatch("#%x%x%x%x%x%x") do list[#list + 1] = code:upper() end
    table.sort(list)
    return table.concat(list, ",")
end

local function placeholderSig(text)
    local list = {}
    for name, fmt in pairs(L._template.placeholders(text)) do
        list[#list + 1] = name .. "|" .. tostring(fmt)
    end
    table.sort(list)
    return table.concat(list, ",")
end

-- locales/<lang>/<ns>.json entries of meta.xml -> { { lang, ns }, ... }
local function metaCatalogs()
    local out, files = {}, 0
    local xml = xmlLoadFile("meta.xml")
    if not xml then return out, files end
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        if xmlNodeGetName(node) == "file" then
            local src = xmlNodeGetAttribute(node, "src") or ""
            local lang, ns = src:match("^locales/([%w_]+)/([%w_]+)%.json$")
            if lang then
                out[#out + 1] = { lang = lang, ns = ns }
            elseif src:match("^locales/[%w_]+/files/") then
                files = files + 1
            end
        end
    end
    xmlUnloadFile(xml)
    return out, files
end

function locValidateCatalogs()
    local list, fileCount = metaCatalogs()
    local warnings, keys = 0, 0
    local byLang = {}

    for _, c in ipairs(list) do
        if not Catalog.langs[c.lang] then
            log("WARNING: locales/%s/%s.json: language '%s' is not in languages.json", c.lang, c.ns, c.lang)
            warnings = warnings + 1
        elseif not fileExists(("locales/%s/%s.json"):format(c.lang, c.ns)) then
            log("WARNING: meta.xml lists locales/%s/%s.json but the file does not exist", c.lang, c.ns)
            warnings = warnings + 1
        else
            local data = Catalog.get(c.lang, c.ns)
            if data then
                byLang[c.lang] = byLang[c.lang] or {}
                for k, v in pairs(data) do
                    byLang[c.lang][k] = v
                    keys = keys + 1
                end
            end
        end
    end

    local base = byLang[LOC.DEFAULT_LANG] or {}
    for lang, entries in pairs(byLang) do
        if lang ~= LOC.DEFAULT_LANG then
            for k, v in pairs(entries) do
                local b = base[k]
                if not b then
                    log("WARNING: [%s] %s is not in the default language (orphan)", lang, k)
                    warnings = warnings + 1
                else
                    if placeholderSig(b) ~= placeholderSig(v) then
                        log("WARNING: [%s] %s: placeholders differ from %s", lang, k, LOC.DEFAULT_LANG)
                        warnings = warnings + 1
                    end
                    if colourCodes(b) ~= colourCodes(v) then
                        log("WARNING: [%s] %s: colour codes differ from %s", lang, k, LOC.DEFAULT_LANG)
                        warnings = warnings + 1
                    end
                end
            end
        end
    end

    log("catalogs: %d languages (%s), %d namespace files, %d text files, %d keys, %d warnings",
        #Catalog.order, table.concat(Catalog.order, ","), #list, fileCount, keys, warnings)
    return warnings
end
