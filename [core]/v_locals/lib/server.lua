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
    LIB.curLang = function() return LIB.defaultLang end
    function L.msg(key, params) return C.msg(key, params) end
    L.isMsg = C.isMsg
    -- shared scripts (config tables): a message object here, plain text on the
    -- client; it becomes the receiving player's language when it is sent
    L.text = L.msg
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

    ----------------------------------------------------------------------------
    -- Send-time resolution (DESIGN.md 4.6, D4): message objects handed to
    -- triggerClientEvent / triggerLatentClientEvent / outputChatBox / kickPlayer
    -- become text in the language of EACH receiving player. Without a message in
    -- the arguments the original function is called unchanged.
    ----------------------------------------------------------------------------
    local isMsg = C.isMsg

    -- true when v is or (up to depth 8) contains a message object
    local function hasMsg(v, depth)
        if isMsg(v) then return true end
        if type(v) ~= "table" or depth > 8 then return false end
        for k, w in pairs(v) do
            if type(w) == "table" and hasMsg(w, depth + 1) then return true end
        end
        return false
    end

    -- copy of v with every message object resolved in lang (unchanged parts shared)
    local function resolveDeep(v, lang, depth)
        if isMsg(v) then return C.resolve(lang, v) end
        if type(v) ~= "table" or depth > 8 or not hasMsg(v, depth) then return v end
        local out = {}
        for k, w in pairs(v) do out[k] = resolveDeep(w, lang, depth + 1) end
        return out
    end

    local function anyMsg(args, from, n)
        for i = from, n do
            if type(args[i]) == "table" and hasMsg(args[i], 1) then return true end
        end
        return false
    end

    -- players behind a sendTo argument (player / table of players / element tree)
    local function receivers(to)
        if to == nil then return getElementsByType("player") end
        if isElement(to) then
            if getElementType(to) == "player" then return { to } end
            return getElementsByType("player", to)
        end
        if type(to) == "table" then return to end
        return {}
    end

    -- triggerClientEvent([sendTo,] name, source, ...) and
    -- triggerLatentClientEvent([sendTo,] name, [bandwidth, persist,] source, ...):
    -- every argument after the optional receiver is resolved (non-messages stay as
    -- they are), one send per receiving player
    local function wrapTrigger(orig)
        return function(...)
            local n = select("#", ...)
            local args = { ... }
            local hasTo = type(args[1]) ~= "string"
            local k0 = hasTo and 2 or 1
            if not anyMsg(args, k0, n) then return orig(...) end
            local ok = true
            for _, p in ipairs(receivers(hasTo and args[1] or nil)) do
                local lang = langOf(p)
                local copy, c = { p }, 1
                for i = k0, n do
                    c = c + 1
                    copy[c] = resolveDeep(args[i], lang, 1)
                end
                ok = orig(unpack(copy, 1, c)) and ok
            end
            return ok
        end
    end

    if not internal then
        triggerClientEvent = wrapTrigger(triggerClientEvent)
        if triggerLatentClientEvent then triggerLatentClientEvent = wrapTrigger(triggerLatentClientEvent) end

        local origChat = outputChatBox
        outputChatBox = function(text, to, ...)
            if not isMsg(text) then return origChat(text, to, ...) end
            local ok = true
            for _, p in ipairs(receivers(to)) do
                ok = origChat(C.resolve(langOf(p), text), p, ...) and ok
            end
            return ok
        end

        -- string.format("%s") and table.concat do not call __tostring: give them
        -- the text (default language) instead of failing on a message object
        local origFormat, origConcat = string.format, table.concat
        string.format = function(fmt, ...)
            if isMsg(fmt) then fmt = tostring(fmt) end
            local n = select("#", ...)
            for i = 1, n do
                if isMsg((select(i, ...))) then
                    local args = { ... }
                    for j = i, n do if isMsg(args[j]) then args[j] = tostring(args[j]) end end
                    return origFormat(fmt, unpack(args, 1, n))
                end
            end
            return origFormat(fmt, ...)
        end
        table.concat = function(t, sep, i, j)
            for k = i or 1, j or #t do
                if isMsg(t[k]) then
                    local copy = {}
                    for m = i or 1, j or #t do copy[m] = isMsg(t[m]) and tostring(t[m]) or t[m] end
                    return origConcat(copy, sep, i, j)
                end
            end
            return origConcat(t, sep, i, j)
        end

        local origKick = kickPlayer
        kickPlayer = function(player, a, b)
            if isMsg(a) then a = C.resolve(langOf(player), a) end
            if isMsg(b) then b = C.resolve(langOf(player), b) end
            return origKick(player, a, b)
        end
    end

    L.resolveDeep = function(v, who) return resolveDeep(v, langOf(who), 1) end

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
