-- Server exports (meta.xml). import() lives in shared/loader.lua. `L` is
-- v_locals' own lib instance (lib/server.lua, published by server/ready.lua).
-- Do not call translate() in a loop where the imported lib would do (D4, 4.6).

function getPlayerLanguage(player)
    return locGetPlayerLanguage(player)
end

function setPlayerLanguage(player, code)
    return locSetPlayerLanguage(player, code)
end

-- { { value = "en", label = "English" }, ... } of the enabled languages
function getLanguages()
    return Catalog.choices()
end

function getLanguageInfo()
    return Catalog.info()
end

-- translate(player | languageCode, key [, params]) -> text in that language (D4)
function translate(who, key, params)
    if type(key) ~= "string" then return "" end
    if type(who) == "string" then return L.forLang(who, key, params) end
    return L.forPlayer(who, key, params)
end

-- resolve(player | languageCode, stringOrMessage) -> text
function resolve(who, x)
    return L.resolveFor(who, x)
end

function getCatalog(lang, ns)
    return Catalog.get(lang, ns)
end

function getFile(lang, path)
    return Catalog.getFile(lang, path)
end

function hasKey(key, lang)
    return L.has(key, lang)
end

function utf8Upper(s)
    return L.upper(s)
end

function utf8Lower(s)
    return L.lower(s)
end

-- { key = resourceName } of every key reported missing on the server
function getMissingKeys()
    local out = {}
    for k, v in pairs(LocMissing) do out[k] = v end
    return out
end

function reportMissing(key, resName)
    if type(key) == "string" then LOCALS_INTERNAL.reportMissing(key, resName or (sourceResource and getResourceName(sourceResource))) end
end

addEvent("v_locals:onCatalogReload")

-- re-reads the server catalogs, revalidates and makes every imported server lib
-- resync. Client catalogs only change with a resource restart (downloaded files).
function reloadCatalogs()
    Catalog.reload()
    L._reload()
    locValidateCatalogs()
    triggerEvent("v_locals:onCatalogReload", root)
    return true
end
