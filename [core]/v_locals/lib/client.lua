-- v_locals lib: client API (the global `L` of the importing resource).
--
--   loadstring(exports.v_locals:import())()        -- once, at load time
--
--   L(key, params)            text in the player's language
--   L.msg(key, params)        message object { t = key, p = params }
--   L.resolve(x)              string -> as is, message object -> text
--   L.has(key) / L.lang()
--   L.bind{ field = "key" | { "key", params } }   table kept up to date on
--                             language change (static labels)
--   L.onChange(fn)            fn(lang, reason) after a language / debug change
--   L.config(fn)              shared config with texts: texts refreshed after the player is loaded
--   L.file(path)              long text file (locales/<lang>/files/<path>)
--   L.upper / L.lower / L.len / L.sub      UTF-8 safe
--   L.width / L.fit / L.fitScale / L.wrap  cached DX measuring (DESIGN.md 5)
--   L.money / L.num / L.int / L.time / L.dist / L.template
do
    local C, U, T, F = LIB.engine, LIB.utf8, LIB.template, LIB.formats
    local type, tostring, pairs, ipairs, pcall = type, tostring, pairs, ipairs, pcall
    local floor, ceil = math.floor, math.ceil

    LIB.resName = getResourceName(getThisResource())

    ----------------------------------------------------------------------------
    -- backend: direct calls inside v_locals, exports everywhere else
    ----------------------------------------------------------------------------
    local function running()
        local res = getResourceFromName("v_locals")
        return res and getResourceState(res) == "running"
    end

    if type(LOCALS_INTERNAL) == "table" then
        LIB.backend = LOCALS_INTERNAL
    else
        LIB.backend = {
            getLanguage     = function() if running() then return exports.v_locals:getLanguage() end end,
            getLanguageInfo = function() if running() then return exports.v_locals:getLanguageInfo() end end,
            getCatalog      = function(lang, ns) if running() then return exports.v_locals:getCatalog(lang, ns) end end,
            getFile         = function(lang, path) if running() then return exports.v_locals:getFile(lang, path) end end,
            getDebugMode    = function() if running() then return exports.v_locals:getDebugMode() end end,
            reportMissing   = function(key, res) if running() then exports.v_locals:reportMissing(key, res) end end,
        }
    end
    local B = LIB.backend

    LIB.lang  = B.getLanguage() or LIB.defaultLang
    LIB.langs = B.getLanguageInfo() or {}

    local L = setmetatable({ __v_locals = true }, {
        __call = function(_, key, params) return C.translate(LIB.lang, key, params) end,
    })
    LIB.L = L

    LIB.curLang = function() return LIB.lang end
    function L.msg(key, params) return C.msg(key, params) end
    L.isMsg = C.isMsg
    L.adopt = C.adopt
    -- shared scripts: text on the client, message object on the server (see lib/server.lua)
    function L.text(key, params) return C.translate(LIB.lang, key, params) end
    function L.resolve(x) return C.resolve(LIB.lang, x) end
    function L.has(key) return C.find(LIB.lang, key) ~= nil end
    function L.lang() return LIB.lang end
    function L.template(text, params) return T.format(tostring(text or ""), params, LIB.lang, C.nested) end

    L.upper, L.lower, L.len, L.sub = U.upper, U.lower, U.len, U.sub

    function L.money(n) return F.apply(LIB.lang, "money", n) end
    function L.num(n)   return F.apply(LIB.lang, "num", n) end
    function L.int(n)   return F.apply(LIB.lang, "int", n) end
    function L.time(n)  return F.apply(LIB.lang, "time", n) end
    function L.dist(n)  return F.apply(LIB.lang, "dist", n) end

    local files = {}
    function L.file(path)
        local byLang = files[LIB.lang]
        if not byLang then byLang = {}; files[LIB.lang] = byLang end
        local text = byLang[path]
        if text == nil then
            text = B.getFile(LIB.lang, path) or ""
            byLang[path] = text
        end
        return text
    end

    ----------------------------------------------------------------------------
    -- DX measuring (cached; every cache is dropped when it reaches cacheMax and
    -- on language change)
    ----------------------------------------------------------------------------
    local dxGetTextWidth = dxGetTextWidth
    local ELLIPSIS = "…"
    local caches, cacheCount = {}, 0

    local function clearCaches()
        caches, cacheCount = {}, 0
    end

    -- caches[kind][font][scale][w][text]; no string building on a hit
    local function cget(kind, font, scale, w, text)
        local a = caches[kind];  if not a then return nil end
        local b = a[font];       if not b then return nil end
        local c = b[scale];      if not c then return nil end
        local d = c[w];          if not d then return nil end
        return d[text]
    end

    local function cset(kind, font, scale, w, text, value)
        if cacheCount >= LIB.cacheMax then clearCaches() end
        local a = caches[kind];  if not a then a = {}; caches[kind] = a end
        local b = a[font];       if not b then b = {}; a[font] = b end
        local c = b[scale];      if not c then c = {}; b[scale] = c end
        local d = c[w];          if not d then d = {}; c[w] = d end
        d[text] = value
        cacheCount = cacheCount + 1
        return value
    end

    -- width of text; colorCoded strips #RRGGBB codes from the measurement
    function L.width(text, scale, font, colorCoded)
        text = tostring(text or "")
        scale, font = scale or 1, font or "default"
        local kind = colorCoded and "wc" or "w"
        local w = cget(kind, font, scale, 0, text)
        if w then return w end
        return cset(kind, font, scale, 0, text, dxGetTextWidth(text, scale, font, colorCoded and true or false))
    end
    local width = L.width

    local function rawWidth(text, scale, font, cc)
        return dxGetTextWidth(text, scale, font, cc)
    end

    -- the longest UTF-8 prefix + "…" that fits maxW (binary search)
    local function truncate(text, maxW, scale, font, cc)
        local n = U.len(text)
        local lo, hi = 0, n - 1
        while lo < hi do
            local mid = ceil((lo + hi) / 2)
            if rawWidth(U.sub(text, 1, mid) .. ELLIPSIS, scale, font, cc) <= maxW then
                lo = mid
            else
                hi = mid - 1
            end
        end
        local head = lo > 0 and U.sub(text, 1, lo):gsub("%s+$", "") or ""
        return head .. ELLIPSIS
    end

    -- text cut with "…" so it fits maxW (med_erm Gfx.fit pattern, UTF-8 safe)
    function L.fit(text, maxW, scale, font, colorCoded)
        text = tostring(text or "")
        scale, font = scale or 1, font or "default"
        local kind = colorCoded and "fc" or "f"
        local r = cget(kind, font, scale, maxW, text)
        if r then return r end
        if width(text, scale, font, colorCoded) <= maxW then
            r = text
        else
            r = truncate(text, maxW, scale, font, colorCoded and true or false)
        end
        return cset(kind, font, scale, maxW, text, r)
    end

    -- returns text, scale: shrinks the scale down to scale * minFactor (default
    -- 0.8) to fit maxW, cuts with "…" below that (medsys panel.lua:413 pattern)
    function L.fitScale(text, maxW, scale, font, minFactor, colorCoded)
        text = tostring(text or "")
        scale, font = scale or 1, font or "default"
        local full = width(text, scale, font, colorCoded)
        if full <= maxW or full <= 0 then return text, scale end
        local s = scale * maxW / full
        local minS = scale * (minFactor or 0.8)
        if s >= minS then return text, s end
        return L.fit(text, maxW, minS, font, colorCoded), minS
    end

    -- word wrap into lines that fit maxW; words longer than a line are broken by
    -- characters (med_erm Gfx.wrap pattern, UTF-8 safe). "\n" starts a new
    -- paragraph. The returned table is shared: read it, do not modify it.
    function L.wrap(text, maxW, scale, font, colorCoded)
        text = tostring(text or "")
        scale, font = scale or 1, font or "default"
        local kind = colorCoded and "rc" or "r"
        local r = cget(kind, font, scale, maxW, text)
        if r then return r end
        local cc = colorCoded and true or false
        local lines = {}
        for para in (text .. "\n"):gmatch("(.-)\n") do
            local line = ""
            for word in para:gmatch("%S+") do
                local try = (line == "") and word or (line .. " " .. word)
                if rawWidth(try, scale, font, cc) <= maxW then
                    line = try
                else
                    if line ~= "" then lines[#lines + 1] = line end
                    while rawWidth(word, scale, font, cc) > maxW and U.len(word) > 1 do
                        local n = U.len(word)
                        while n > 1 and rawWidth(U.sub(word, 1, n), scale, font, cc) > maxW do n = n - 1 end
                        lines[#lines + 1] = U.sub(word, 1, n)
                        word = U.sub(word, n + 1)
                    end
                    line = word
                end
            end
            lines[#lines + 1] = line
        end
        return cset(kind, font, scale, maxW, text, lines)
    end

    ----------------------------------------------------------------------------
    -- bound tables + change callbacks
    ----------------------------------------------------------------------------
    local bindings  = setmetatable({}, { __mode = "k" })   -- out table -> source table
    local callbacks = {}

    local function fill(out, src)
        for k, v in pairs(src) do
            if type(v) == "string" then
                out[k] = C.translate(LIB.lang, v)
            elseif type(v) == "table" then
                if type(v.t) == "string" then
                    out[k] = C.resolve(LIB.lang, v)
                elseif type(v[1]) == "string" then
                    out[k] = C.translate(LIB.lang, v[1], v[2])
                end
            end
        end
    end

    function L.bind(src)
        local out = {}
        fill(out, src)
        bindings[out] = src
        return out
    end

    function L.onChange(fn)
        if type(fn) == "function" then callbacks[#callbacks + 1] = fn end
        return fn
    end

    -- L.config(fn): a shared config chunk that holds texts (L.text). It runs
    -- right away, so the tables exist for scripts that read them at load time.
    -- Once the player is loaded (onClientLoadingStarted) and on every language
    -- change it runs again in a sandbox and only the texts (strings) are
    -- written into the existing tables, so references to them stay valid.
    -- After the first rerun the resource reports exports.v_accounts:resourceReady().
    local function mergeTexts(old, new, seen)
        if seen[new] then return end
        seen[new] = true
        for k, v in pairs(new) do
            local o = old[k]
            if type(v) == "string" then
                if type(o) == "string" and o ~= v then old[k] = v end
            elseif type(v) == "table" and type(o) == "table" and o ~= v then
                mergeTexts(o, v, seen)
            end
        end
    end

    local STD_LIBS = { string = true, table = true, math = true, os = true, io = true,
        coroutine = true, debug = true, package = true, _G = true, L = true }
    local function deepCopy(v, map)
        if type(v) ~= "table" or getmetatable(v) ~= nil then return v end
        if map[v] then return map[v] end
        local c = {}
        map[v] = c
        for k, x in pairs(v) do c[k] = deepCopy(x, map) end
        return c
    end

    function L.config(fn)
        fn()
        local function rerun()
            -- global data tables the chunk reads are copied first, so the rerun
            -- never writes into (or replaces parts of) the live tables
            local map = {}
            local env = setmetatable({}, { __index = function(t, k)
                local v = _G[k]
                if type(v) == "table" and not STD_LIBS[k] then
                    v = deepCopy(v, map)
                    rawset(t, k, v)
                end
                return v
            end })
            setfenv(fn, env)
            local ok, err = pcall(fn)
            if not ok then
                outputDebugString(("[v_locals] L.config rerun failed in %s: %s"):format(LIB.resName, tostring(err)), 1)
                return
            end
            local seen = {}
            for k, v in pairs(env) do
                local o = rawget(_G, k)
                if type(v) == "string" then
                    if type(o) == "string" then rawset(_G, k, v) end
                elseif type(v) == "table" and type(o) == "table" then
                    mergeTexts(o, v, seen)
                end
            end
        end
        L.onChange(rerun)

        local reported = false
        local function ready()
            if reported then return end
            reported = true
            rerun()
            pcall(function() exports.v_accounts:resourceReady() end)
        end
        addEvent("onClientLoadingStarted", true)
        addEventHandler("onClientLoadingStarted", root, ready)
        -- v_accounts asks for the ready reports (also covers a resource that
        -- started after the loading screen was already shown)
        addEvent("onClientReadyCheck", false)
        addEventHandler("onClientReadyCheck", root, ready)
        addEventHandler("onClientResourceStart", getResourceRootElement(getThisResource()), function()
            if getElementData(localPlayer, "loaded") then ready() end
        end)
    end

    local function refresh(reason)
        clearCaches()
        files = {}
        for out, src in pairs(bindings) do fill(out, src) end
        for _, fn in ipairs(callbacks) do
            local ok, err = pcall(fn, LIB.lang, reason)
            if not ok then
                outputDebugString(("[v_locals] onChange callback failed in %s: %s"):format(LIB.resName, tostring(err)), 1)
            end
        end
    end

    ----------------------------------------------------------------------------
    -- debug: keys / pseudo (engine), overflow (dxDrawText wrapper in this
    -- resource only; the original function is back when it is switched off)
    ----------------------------------------------------------------------------
    local origDraw = dxDrawText
    local overflowSeen = {}

    local function checkedDraw(text, l, t, r, b, color, scale, a8, ...)
        local font, clip, wordBreak, cc
        local n9, n10, n11, n12, n13, n14, n15 = ...
        if type(a8) == "number" then     -- scaleX, scaleY form
            font, clip, wordBreak, cc = n9, n12, n13, n15
        else
            font, clip, wordBreak, cc = a8, n11, n12, n14
        end
        if type(text) == "string" and text ~= "" and type(l) == "number" and type(r) == "number"
            and r > l and not clip and not wordBreak then
            local w = dxGetTextWidth(text, type(scale) == "number" and scale or 1, font or "default", cc and true or false)
            if w > (r - l) + 1 and not overflowSeen[text] then
                overflowSeen[text] = true
                outputDebugString(("[v_locals] overflow in %s: %d px > %d px: \"%s\""):format(
                    LIB.resName, floor(w), floor(r - l), U.sub(text, 1, 60)), 2)
            end
        end
        return origDraw(text, l, t, r, b, color, scale, a8, ...)
    end

    local function setDebugMode(mode)
        C.mode = (mode == "keys" or mode == "pseudo") and mode or nil
        if mode == "overflow" then
            overflowSeen = {}
            dxDrawText = checkedDraw
        else
            dxDrawText = origDraw
        end
    end
    setDebugMode(B.getDebugMode())

    ----------------------------------------------------------------------------
    -- events
    ----------------------------------------------------------------------------
    addEvent("v_locals:onClientLanguageChange")
    addEventHandler("v_locals:onClientLanguageChange", root, function(newLang)
        if type(newLang) ~= "string" or newLang == LIB.lang then return end
        LIB.lang = newLang
        refresh("language")
    end)

    addEvent("v_locals:onClientDebugModeChange")
    addEventHandler("v_locals:onClientDebugModeChange", root, function(mode)
        setDebugMode(mode)
        refresh("debug")
    end)

    -- v_locals restarted: the catalogs may have changed, fetch everything again
    if B ~= LOCALS_INTERNAL then
        addEventHandler("onClientResourceStart", root, function(res)
            if getResourceName(res) ~= "v_locals" then return end
            C.reset()
            LIB.lang  = B.getLanguage() or LIB.lang
            LIB.langs = B.getLanguageInfo() or LIB.langs
            setDebugMode(B.getDebugMode())
            refresh("reload")
        end)
    end

    -- internal hooks for v_locals itself (benchmark, tests)
    L._engine = C
    L._template = T
    L._refresh = refresh
end
