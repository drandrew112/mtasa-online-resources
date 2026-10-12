-- v_locals lib: UTF-8 helpers (len, sub, upper, lower).
--
-- Part of the injected library: shared/loader.lua concatenates the lib/*.lua
-- files into one chunk, so every module lives in its own do-block and publishes
-- itself on the chunk-local LIB table.
--
-- string.upper / string.lower / #s / s:sub work on bytes and break multi-byte
-- characters (ő, ű, ...). Everything that is shown on screen must go through
-- these instead (DESIGN.md 5.1, 5.6).
do
    local U = {}
    LIB.utf8 = U

    local floor, schar = math.floor, string.char
    local concat = table.concat

    -- one UTF-8 character (lead byte + continuation bytes)
    local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
    U.CHAR = CHAR

    -- MTA ships a utf8 library; plain Lua (tests) does not.
    local nativeLen = type(utf8) == "table" and utf8.len or nil
    local nativeSub = type(utf8) == "table" and utf8.sub or nil

    function U.encode(cp)
        if cp < 0x80 then
            return schar(cp)
        elseif cp < 0x800 then
            return schar(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
        elseif cp < 0x10000 then
            return schar(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
        end
        return schar(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
            0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end

    -- case tables for the non-ASCII letters: Latin-1, Latin Extended-A (Hungarian
    -- ő/ű live here), basic Greek and Cyrillic
    local UP, LO = {}, {}
    local function pair(lower, upper)
        local l, u = U.encode(lower), U.encode(upper)
        UP[l] = u
        LO[u] = l
    end
    for cp = 0xE0, 0xFE do
        if cp ~= 0xF7 then pair(cp, cp - 0x20) end          -- à..þ (not ÷)
    end
    pair(0xFF, 0x178)                                       -- ÿ Ÿ
    for cp = 0x100, 0x136, 2 do
        if cp ~= 0x130 then pair(cp + 1, cp) end            -- Ā ā .. Ķ ķ (not İ ı)
    end
    for cp = 0x139, 0x147, 2 do pair(cp + 1, cp) end        -- Ĺ ĺ .. Ň ň
    for cp = 0x14A, 0x176, 2 do pair(cp + 1, cp) end        -- Ŋ ŋ .. Ő ő .. Ű ű .. Ŷ ŷ
    for cp = 0x179, 0x17D, 2 do pair(cp + 1, cp) end        -- Ź ź .. Ž ž
    for cp = 0x391, 0x3A9 do
        if cp ~= 0x3A2 then pair(cp + 0x20, cp) end         -- Greek
    end
    UP[U.encode(0x3C2)] = U.encode(0x3A3)                   -- final sigma
    for cp = 0x410, 0x42F do pair(cp + 0x20, cp) end        -- Cyrillic А..Я
    for cp = 0x400, 0x40F do pair(cp + 0x50, cp) end        -- Cyrillic Ѐ..Џ

    local function isAscii(s)
        return not s:find("[\128-\255]")
    end

    function U.len(s)
        s = tostring(s or "")
        if isAscii(s) then return #s end
        if nativeLen then
            local n = nativeLen(s)
            if n then return n end
        end
        local _, n = s:gsub(CHAR, "")
        return n
    end

    -- same index rules as string.sub, counted in characters
    function U.sub(s, i, j)
        s = tostring(s or "")
        i = i or 1
        if isAscii(s) then return s:sub(i, j) end
        if nativeSub then return nativeSub(s, i, j) end
        local n = U.len(s)
        j = j or -1
        if i < 0 then i = n + i + 1 end
        if j < 0 then j = n + j + 1 end
        if i < 1 then i = 1 end
        if j > n then j = n end
        if i > j then return "" end
        local out, k = {}, 0
        for c in s:gmatch(CHAR) do
            k = k + 1
            if k > j then break end
            if k >= i then out[#out + 1] = c end
        end
        return concat(out)
    end

    local upCache, loCache, upCount, loCount = {}, {}, 0, 0

    local function upChar(c) return UP[c] or (#c == 1 and c:upper()) or c end
    local function loChar(c) return LO[c] or (#c == 1 and c:lower()) or c end

    function U.upper(s)
        s = tostring(s or "")
        if isAscii(s) then return s:upper() end
        local r = upCache[s]
        if r then return r end
        r = (s:gsub(CHAR, upChar))
        if upCount >= LIB.cacheMax then upCache, upCount = {}, 0 end
        upCache[s] = r
        upCount = upCount + 1
        return r
    end

    function U.lower(s)
        s = tostring(s or "")
        if isAscii(s) then return s:lower() end
        local r = loCache[s]
        if r then return r end
        r = (s:gsub(CHAR, loChar))
        if loCount >= LIB.cacheMax then loCache, loCount = {}, 0 end
        loCache[s] = r
        loCount = loCount + 1
        return r
    end
end
