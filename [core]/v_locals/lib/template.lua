-- v_locals lib: text templates.
--
--   "You were paid {amount|money} for {work}."
--
--   {name}        parameter, tostring() / nested message object
--   {name|fmt}    typed parameter, see lib/formats.lua (money, num, int, 1f, pct,
--                 time, dist, upper, lower)
--   {{ and }}     literal braces
--
-- A template is parsed once and the parts are cached by text, so formatting a
-- known text is a table walk plus one table.concat.
do
    local T = {}
    LIB.template = T

    local concat, tostring, type = table.concat, tostring, type

    -- text -> parts array, or false when the text has no braces at all
    local compiled = {}

    -- called with (name, text) when a parameter is missing; the engine sets it
    T.onMissing = nil

    local function compile(text)
        if not text:find("[{}]") then return false end
        local parts, buf, i, n = {}, {}, 1, #text

        local function flush()
            if #buf > 0 then
                parts[#parts + 1] = concat(buf)
                buf = {}
            end
        end

        while i <= n do
            local s = text:find("[{}]", i)
            if not s then
                buf[#buf + 1] = text:sub(i)
                break
            end
            if s > i then buf[#buf + 1] = text:sub(i, s - 1) end
            local c, nxt = text:sub(s, s), text:sub(s + 1, s + 1)
            if c == nxt then                         -- "{{" or "}}"
                buf[#buf + 1] = c
                i = s + 2
            elseif c == "{" then
                local name, fmt, e = text:match("^{([%w_]+)|?([%w_]*)}()", s)
                if name then
                    flush()
                    parts[#parts + 1] = { name = name, fmt = fmt ~= "" and fmt or nil, raw = text:sub(s, e - 1) }
                    i = e
                else
                    buf[#buf + 1] = "{"
                    i = s + 1
                end
            else
                buf[#buf + 1] = "}"
                i = s + 1
            end
        end
        flush()
        return parts
    end

    local function getParts(text)
        local parts = compiled[text]
        if parts == nil then
            parts = compile(text)
            compiled[text] = parts
        end
        return parts
    end

    -- nested(lang, value) turns a message object parameter into a string
    function T.format(text, params, lang, nested)
        local parts = getParts(text)
        if not parts then return text end
        local F = LIB.formats
        local buf = {}
        for i = 1, #parts do
            local p = parts[i]
            if type(p) == "string" then
                buf[i] = p
            else
                local v = params and params[p.name]
                if v == nil then
                    buf[i] = p.raw
                    if T.onMissing then T.onMissing(p.name, text) end
                else
                    if type(v) == "table" then v = nested(lang, v) end
                    if p.fmt then
                        buf[i] = F.apply(lang, p.fmt, v)
                    else
                        buf[i] = tostring(v)
                    end
                end
            end
        end
        return concat(buf)
    end

    -- set of placeholder names ("name" -> fmt or true); used by the validator
    function T.placeholders(text)
        local out = {}
        local parts = getParts(text)
        if parts then
            for _, p in ipairs(parts) do
                if type(p) == "table" then out[p.name] = p.fmt or true end
            end
        end
        return out
    end
end
