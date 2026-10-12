-- v_locals lib: server API (the global `L` of the importing resource).
--
--   loadstring(exports.v_locals:import())()        -- once, at load time
--
-- Server-side loadstring needs the ACL right "function.loadstring" (currently
-- granted in the Default ACL). Without it the exports still work:
--   exports.v_locals:translate(player | lang, key, params)
-- v_locals itself runs this file as a plain server script (no loadstring).
--
--   L.forPlayer(player, key, params)   text in that player's language (D4)
--   L.forLang(lang, key, params)       text in a given language
--   L(key, params)                     text in the default language
--   L.msg(key, params)                 message object, resolved by the client
--   L.resolveFor(player, x)            string -> as is, message object -> text
--   L.lang(player) / L.has(key [, lang])
--   L.upper / L.lower / L.len / L.sub  UTF-8 safe
--   L.money(n, who) / L.num / L.int / L.time / L.dist   who = player or language
--   L.file(path, who)                  long text file
--
-- In other resources the player -> language map is cached and kept fresh by
-- the onPlayerLanguageChange event, so L.forPlayer does not call an export.
do
    local C, U, T, F = LIB.engine, LIB.utf8, LIB.template, LIB.formats
    local type, tostring = type, tostring

    LIB.resName = getResourceName(getThisResource())

    local internal = type(LOCALS_INTERNAL) == "table"

    local function running()
        local res = getResourceFromName("v_locals")
        return res and getResourceState(res) == "running"
    end

    if internal then
        LIB.backend = LOCALS_INTERNAL
    else
        LIB.backend = {
            getLanguageInfo   = function() if running() then return exports.v_locals:getLanguageInfo() end end,
            getCatalog        = function(lang, ns) if running() then return exports.v_locals:getCatalog(lang, ns) end end,
            getFile           = function(lang, path) if running() then return exports.v_locals:getFile(lang, path) end end,
            getPlayerLanguage = function(player) if running() then return exports.v_locals:getPlayerLanguage(player) end end,
            reportMissing     = function(key, res) if running() then exports.v_locals:reportMissing(key, res) end end,
        }
    end
    local B = LIB.backend

    LIB.langs = B.getLanguageInfo() or {}

    -- cache only outside v_locals (inside, the lookup is a direct table read)
    local playerLang = setmetatable({}, { __mode = "k" })

    local function langOf(who)
        if type(who) == "string" then return who end
        if isElement(who) then
            if internal then return B.getPlayerLanguage(who) or LIB.defaultLang end
            local lang = playerLang[who]
            if lang then return lang end
            lang = B.getPlayerLanguage(who) or LIB.defaultLang
            playerLang[who] = lang
            return lang
        end
        return LIB.defaultLang
    end

    local L = setmetatable({ __v_locals = true }, {
        __call = function(_, key, params) return C.translate(LIB.defaultLang, key, params) end,
    })
    LIB.L = L

    function L.forPlayer(player, key, params) return C.translate(langOf(player), key, params) end
    function L.forLang(lang, key, params) return C.translate(langOf(lang), key, params) end
    function L.msg(key, params) return { t = key, p = params } end
    function L.resolveFor(player, x) return C.resolve(langOf(player), x) end
    function L.lang(player) return langOf(player) end
    function L.has(key, lang) return C.find(langOf(lang or LIB.defaultLang), key) ~= nil end
    function L.template(text, params, who) return T.format(tostring(text or ""), params, langOf(who), C.nested) end

    L.upper, L.lower, L.len, L.sub = U.upper, U.lower, U.len, U.sub

    function L.money(n, who) return F.apply(langOf(who), "money", n) end
    function L.num(n, who)   return F.apply(langOf(who), "num", n) end
    function L.int(n, who)   return F.apply(langOf(who), "int", n) end
    function L.time(n, who)  return F.apply(langOf(who), "time", n) end
    function L.dist(n, who)  return F.apply(langOf(who), "dist", n) end

    local files = {}
    function L.file(path, who)
        local lang = langOf(who)
        local byLang = files[lang]
        if not byLang then byLang = {}; files[lang] = byLang end
        local text = byLang[path]
        if text == nil then
            text = B.getFile(lang, path) or ""
            byLang[path] = text
        end
        return text
    end

    -- catalogs reloaded (/locreload) or v_locals restarted: drop every cache
    function L._reload()
        C.reset()
        files = {}
        playerLang = setmetatable({}, { __mode = "k" })
        LIB.langs = B.getLanguageInfo() or LIB.langs
    end

    if not internal then
        addEvent("onPlayerLanguageChange")
        addEventHandler("onPlayerLanguageChange", root, function(newLang)
            if type(newLang) == "string" then playerLang[source] = newLang end
        end)

        addEventHandler("onPlayerQuit", root, function()
            playerLang[source] = nil
        end)

        addEvent("v_locals:onCatalogReload")
        addEventHandler("v_locals:onCatalogReload", root, function() L._reload() end)

        addEventHandler("onResourceStart", root, function(res)
            if getResourceName(res) == "v_locals" then L._reload() end
        end)
    end

    -- internal hooks (validator, benchmark, tests)
    L._engine = C
    L._template = T
end
