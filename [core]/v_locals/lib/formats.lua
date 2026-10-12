-- v_locals lib: per-language number / money / time formatting and plural rules.
--
-- The English output matches what the resources print today, so moving a text
-- into the catalog does not change it:
--   money  1234.9 -> "€1,234"   (ui_inac render.lua money(): floor + "," groups)
--   num    1234   -> "1,234"
--   int    2.7    -> "2"        (same as ("%d"):format(2.7))
--   1f     2.25   -> "2.3"      (any "<digits>f": fixed decimals)
--   pct    42.9   -> "42%"
--   time   75     -> "01:15"    (seconds; "%02d:%02d", hours -> "%02d:%02d:%02d")
--   dist   850    -> "850 m"    (metres; from 1000 -> "1.2 km")
--   upper / lower -> UTF-8 aware case change
do
    local F = {}
    LIB.formats = F

    local floor, abs, tostring, tonumber = math.floor, math.abs, tostring, tonumber

    -- per-language settings; missing languages / fields fall back to "en"
    F.conf = {
        en = { thousands = ",", decimal = ".", moneyPrefix = "€", moneySuffix = "" },
    }

    F.plural = {
        one_other = function(n) return n == 1 and "one" or "other" end,
        other     = function() return "other" end,
    }

    local function conf(lang)
        return F.conf[lang] or F.conf.en
    end

    -- integer part as a string, truncated toward zero; "%.0f" avoids the 32-bit
    -- long limit of "%d" on big money amounts
    local function intString(n)
        n = n >= 0 and floor(n) or -floor(-n)
        return ("%.0f"):format(n)
    end

    local function group(digits, sep)
        local s = digits:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
        if s:sub(1, #sep) == sep then s = s:sub(#sep + 1) end
        return s
    end

    local function sepDecimal(s, c)
        if c.decimal ~= "." then s = s:gsub("%.", c.decimal) end
        return s
    end

    local fns = {}

    fns.money = function(n, c)
        local neg = n < 0
        local s = group(intString(floor(abs(n))), c.thousands)
        return (neg and "-" or "") .. c.moneyPrefix .. s .. c.moneySuffix
    end

    fns.num = function(n, c)
        local s = intString(n)
        if s:sub(1, 1) == "-" then return "-" .. group(s:sub(2), c.thousands) end
        return group(s, c.thousands)
    end

    fns.int = function(n)
        return intString(n)
    end

    fns.pct = function(n)
        return intString(n) .. "%"
    end

    fns.time = function(n)
        local s = floor(n)
        if s < 0 then s = 0 end
        local h, m, sec = floor(s / 3600), floor(s / 60) % 60, s % 60
        if h > 0 then return ("%02d:%02d:%02d"):format(h, m, sec) end
        return ("%02d:%02d"):format(m, sec)
    end

    fns.dist = function(n, c)
        if abs(n) < 1000 then return intString(n) .. " m" end
        return sepDecimal(("%.1f"):format(n / 1000), c) .. " km"
    end

    F.fns = fns

    function F.apply(lang, fmt, v)
        if fmt == "upper" then return LIB.utf8.upper(tostring(v)) end
        if fmt == "lower" then return LIB.utf8.lower(tostring(v)) end
        local n = tonumber(v)
        if not n then return tostring(v) end
        local fn = fns[fmt]
        if fn then return fn(n, conf(lang)) end
        local digits = fmt:match("^(%d)f$")
        if digits then
            return sepDecimal(("%." .. digits .. "f"):format(n), conf(lang))
        end
        return tostring(v)
    end

    -- "one" / "other" for count n in lang; langs = language info table
    function F.pluralForm(lang, n, langs)
        local info = langs and langs[lang]
        local rule = F.plural[info and info.plural or "one_other"] or F.plural.one_other
        return rule(n)
    end
end
