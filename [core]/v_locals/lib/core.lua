-- v_locals lib: lookup engine (shared by the client and the server lib).
--
-- Catalogs are fetched from v_locals once per (language, namespace) and kept in
-- this resource, so a lookup is a local table index, never an export call
-- (DESIGN.md 4.7, 7). The namespace is the first key segment:
-- "ui_pause.tab.settings" -> namespace "ui_pause" -> locales/<lang>/ui_pause.json.
--
-- Fallback chain: language -> its fallback -> LIB.defaultLang -> the key itself
-- ("[missing:key]" in debug mode). Every missing key is reported once.
do
    local U, T, F = LIB.utf8, LIB.template, LIB.formats
    local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs

    local C = {}
    LIB.engine = C

    -- debug mode, client only: nil | "keys" | "pseudo"
    C.mode = nil

    local store       = {}   -- store[lang][key]  = text   (all loaded namespaces merged)
    local loaded      = {}   -- loaded[lang][ns]  = true | false (false: no such catalog)
    local misses      = {}   -- misses[lang][key] = true   (negative cache)
    local pseudoCache = {}
    local missingSeen = {}
    local paramSeen   = {}

    -- drops every cached catalog (v_locals restart, /locreload)
    function C.reset()
        store, loaded, misses, pseudoCache = {}, {}, {}, {}
    end

    -- puts strings straight into the store (benchmarks / tests)
    function C.inject(lang, tbl)
        local s = store[lang]
        if not s then s = {}; store[lang] = s end
        for k, v in pairs(tbl) do s[k] = v end
        misses[lang] = nil
    end

    -- removes every key starting with prefix from every language
    function C.forget(prefix)
        for _, s in pairs(store) do
            for k in pairs(s) do
                if k:sub(1, #prefix) == prefix then s[k] = nil end
            end
        end
    end

    local function loadNamespace(lang, ns)
        local l = loaded[lang]
        if not l then l = {}; loaded[lang] = l end
        local cat = LIB.backend.getCatalog(lang, ns)
        local s = store[lang]
        if not s then s = {}; store[lang] = s end
        if type(cat) == "table" then
            for k, v in pairs(cat) do
                if type(k) == "string" and type(v) == "string" and s[k] == nil then s[k] = v end
            end
            l[ns] = true
        else
            l[ns] = false
        end
    end

    local function raw(lang, key)
        local s = store[lang]
        local v = s and s[key]
        if v then return v end
        local m = misses[lang]
        if m and m[key] then return nil end
        local ns = key:match("^([%w_]+)%.")
        local l = loaded[lang]
        if ns and not (l and l[ns] ~= nil) then
            loadNamespace(lang, ns)
            s = store[lang]
            v = s and s[key]
            if v then return v end
        end
        if not m then m = {}; misses[lang] = m end
        m[key] = true
        return nil
    end

    function C.fallbackOf(lang)
        local info = LIB.langs and LIB.langs[lang]
        local fb = info and info.fallback
        if fb == lang or fb == "" then fb = nil end
        if not fb and lang ~= LIB.defaultLang then fb = LIB.defaultLang end
        return fb
    end

    -- raw catalog text of key in lang or one of its fallbacks
    function C.find(lang, key)
        local depth = 0
        while lang and depth < 4 do
            local v = raw(lang, key)
            if v then return v end
            lang = C.fallbackOf(lang)
            depth = depth + 1
        end
        return nil
    end
    local find = C.find

    -- plural text: key.<form>, key.other, key - all in one language before the
    -- next language of the chain (a language without plural forms keeps its own
    -- plain key instead of falling back to another language's plural)
    local function findPlural(lang, key, form)
        local depth = 0
        while lang and depth < 4 do
            local v = raw(lang, key .. "." .. form)
                or (form ~= "other" and raw(lang, key .. ".other"))
                or raw(lang, key)
            if v then return v end
            lang = C.fallbackOf(lang)
            depth = depth + 1
        end
        return nil
    end

    local function reportMissing(key)
        if missingSeen[key] then return end
        missingSeen[key] = true
        outputDebugString(("[v_locals] missing key '%s' (%s)"):format(key, tostring(LIB.resName)), 2)
        if LIB.backend.reportMissing then LIB.backend.reportMissing(key, LIB.resName) end
    end

    T.onMissing = function(name, text)
        if not C.mode then return end
        local id = name .. "\0" .. text
        if paramSeen[id] then return end
        paramSeen[id] = true
        outputDebugString(("[v_locals] missing parameter {%s} in \"%s\" (%s)"):format(name, text, tostring(LIB.resName)), 2)
    end

    -- pseudo-localisation: accented letters (incl. Hungarian ő/ű) + ~35% padding,
    -- placeholders and #RRGGBB colour codes stay intact
    local PSEUDO = {
        a = "á", e = "é", i = "î", o = "ő", u = "ű", c = "ç", n = "ñ", s = "š", z = "ž", y = "ý",
        A = "Á", E = "É", I = "Î", O = "Ő", U = "Ű", C = "Ç", N = "Ñ", S = "Š", Z = "Ž", Y = "Ý",
    }

    function C.pseudo(text)
        local r = pseudoCache[text]
        if r then return r end
        local out, i, n = {}, 1, #text
        while i <= n do
            local ch = text:sub(i, i)
            if ch == "{" and text:sub(i + 1, i + 1) ~= "{" then
                local e = text:find("}", i, true) or n
                out[#out + 1] = text:sub(i, e)
                i = e + 1
            elseif ch == "#" and text:match("^#%x%x%x%x%x%x", i) then
                out[#out + 1] = text:sub(i, i + 6)
                i = i + 7
            else
                out[#out + 1] = PSEUDO[ch] or ch
                i = i + 1
            end
        end
        local pad = string.rep("~", math.ceil(U.len(text) * 0.35))
        r = "[" .. table.concat(out) .. " " .. pad .. "]"
        pseudoCache[text] = r
        return r
    end

    local translate

    -- parameter value -> string (message objects are translated in lang)
    local function nested(lang, v)
        if type(v) == "table" then
            if type(v.t) == "string" then return translate(lang, v.t, v.p) end
            return ""
        end
        return tostring(v)
    end
    C.nested = nested

    translate = function(lang, key, params)
        if type(key) ~= "string" then return "" end
        if C.mode == "keys" then return key end
        local text
        local count = params and params.count
        if count ~= nil then
            text = findPlural(lang, key, F.pluralForm(lang, tonumber(count) or 0, LIB.langs))
        else
            text = find(lang, key)
        end
        if not text then
            reportMissing(key)
            return C.mode and ("[missing:" .. key .. "]") or key
        end
        if C.mode == "pseudo" then text = C.pseudo(text) end
        return T.format(text, params, lang, nested)
    end
    C.translate = translate

    -- string -> unchanged; { t = key, p = params } -> translated; nil -> ""
    function C.resolve(lang, x)
        local tx = type(x)
        if tx == "string" then return x end
        if tx == "table" then
            if type(x.t) == "string" then return translate(lang, x.t, x.p) end
            return ""
        end
        if x == nil then return "" end
        return tostring(x)
    end

    -- Message objects: { t = key, p = params, __loc = true }. The marker survives a
    -- copy across resources (exports) so every lib recognises them. Used where the
    -- receiver is not known yet (server, DESIGN.md 4.5 / 4.6). Safety net: when a
    -- message is used like a string by mistake (concatenation, tostring, string
    -- methods) it turns into the text of LIB.curLang() instead of raising an error.
    local MSG_MT = {}
    MSG_MT.__tostring = function(m) return translate(LIB.curLang(), m.t, m.p) end
    MSG_MT.__concat = function(a, b) return tostring(a) .. tostring(b) end
    MSG_MT.__lt = function(a, b) return tostring(a) < tostring(b) end      -- table.sort by name
    MSG_MT.__le = function(a, b) return tostring(a) <= tostring(b) end
    MSG_MT.__index = function(_, k)
        local f = (k == "upper" and U.upper) or (k == "lower" and U.lower) or (k == "len" and U.len)
            or (k == "sub" and U.sub) or string[k]
        if f then return function(self, ...) return f(tostring(self), ...) end end
    end
    C.MSG_MT = MSG_MT

    function C.msg(key, params)
        return setmetatable({ t = key, p = params, __loc = true }, MSG_MT)
    end

    function C.isMsg(x)
        return type(x) == "table" and rawget(x, "__loc") == true and type(rawget(x, "t")) == "string"
    end

    -- message objects that crossed a resource boundary (exports copy tables and
    -- drop the metatable) get their safety net back; tables are walked (depth 8)
    function C.adopt(x, depth)
        depth = depth or 1
        if type(x) ~= "table" or depth > 8 then return x end
        if C.isMsg(x) then
            if getmetatable(x) ~= MSG_MT then setmetatable(x, MSG_MT) end
            return x
        end
        for _, v in pairs(x) do
            if type(v) == "table" then C.adopt(v, depth + 1) end
        end
        return x
    end
end
