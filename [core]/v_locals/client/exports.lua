-- Client exports (meta.xml). import() lives in shared/loader.lua.
-- `L` is v_locals' own lib instance (shared/loader.lua loads it on start).
-- Do not call these from onClientRender: use the imported lib (DESIGN.md 7).

function getLanguage()
    return locGetLanguage()
end

-- the player's choice (pause menu -> Settings -> Display -> Language)
function setLanguage(code)
    return locSetLanguage(code)
end

-- { { value = "en", label = "English" }, ... } of the enabled languages
function getLanguages()
    return Catalog.choices()
end

function getLanguageInfo()
    return Catalog.info()
end

function translate(key, params)
    return L(key, params)
end

function resolve(x)
    return L.resolve(x)
end

function getCatalog(lang, ns)
    return Catalog.get(lang, ns)
end

function getFile(lang, path)
    return Catalog.getFile(lang, path)
end

function hasKey(key)
    return L.has(key)
end

function utf8Upper(s)
    return L.upper(s)
end

function utf8Lower(s)
    return L.lower(s)
end

function getDebugMode()
    return locGetDebugMode()
end

function reportMissing(key, resName)
    if type(key) == "string" then LOCALS_INTERNAL.reportMissing(key, resName or (sourceResource and getResourceName(sourceResource))) end
end
