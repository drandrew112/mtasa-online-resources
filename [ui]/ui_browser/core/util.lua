-- ui_browser :: core/util.lua
-- Kozos segedfuggvenyek a virtualis bongeszohoz (szin- es URL-elemzes,
-- szoveg-tordeles). Minden a globalis BR tablaba kerul, hogy a tobbi
-- core-fajl elerhesse.

BR = BR or {}

function BR.clamp(v, a, b)
    if v < a then return a end
    if v > b then return b end
    return v
end

-- "#rrggbb", "#rrggbbaa", "rgb(r,g,b)", "rgba(r,g,b,a)" -> tocolor. Ha nem
-- ertelmezheto, a megadott alapertelmezett szint adja vissza.
function BR.parseColor(str, default)
    if type(str) ~= "string" then return default end
    str = str:gsub("%s+", "")

    local hex8 = str:match("^#?(%x%x%x%x%x%x%x%x)$")
    if hex8 then
        return tocolor(
            tonumber(hex8:sub(1, 2), 16), tonumber(hex8:sub(3, 4), 16),
            tonumber(hex8:sub(5, 6), 16), tonumber(hex8:sub(7, 8), 16))
    end

    local hex6 = str:match("^#?(%x%x%x%x%x%x)$")
    if hex6 then
        return tocolor(
            tonumber(hex6:sub(1, 2), 16), tonumber(hex6:sub(3, 4), 16),
            tonumber(hex6:sub(5, 6), 16), 255)
    end

    local r, g, b, a = str:match("^rgba?%((%d+),(%d+),(%d+),?(%d*)%)$")
    if r then
        return tocolor(tonumber(r), tonumber(g), tonumber(b),
            (a ~= "" and tonumber(a)) or 255)
    end

    return default
end

-- URL-t normalizal es szetszed: sema levagasa, "?a=b&c=d" query elemzese.
-- Az ures / "start" / "home" utvonal mind a fooldalt jelenti.
function BR.parseUrl(url)
    url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
    url = url:gsub("^%a[%w%+%-%.]*://", "")

    local path, q = url:match("^([^?]*)%??(.*)$")
    path = (path or ""):gsub("/+$", ""):lower()
    if path == "" or path == "start" or path == "kereso" then
        path = "home"
    end

    local query = {}
    for k, v in (q or ""):gmatch("([^&=]+)=([^&=]*)") do
        query[k:lower()] = v
    end

    return { path = path, query = query, raw = url }
end

local function splitLines(s)
    local t, pos = {}, 1
    while true do
        local nl = s:find("\n", pos, true)
        if not nl then
            t[#t + 1] = s:sub(pos)
            break
        end
        t[#t + 1] = s:sub(pos, nl - 1)
        pos = nl + 1
    end
    return t
end

-- Szoszintu tordeles adott pixelszelessegre. A tenyleges "\n" karaktereket
-- megtartja (ures sor = bekezdestores).
function BR.wrapText(text, maxW, scale, font)
    local out = {}
    for _, raw in ipairs(splitLines(tostring(text))) do
        if raw:match("^%s*$") then
            out[#out + 1] = ""
        else
            local line = ""
            for word in raw:gmatch("%S+") do
                local try = (line == "") and word or (line .. " " .. word)
                if line == "" or dxGetTextWidth(try, scale, font) <= maxW then
                    line = try
                else
                    out[#out + 1] = line
                    line = word
                end
            end
            out[#out + 1] = line
        end
    end
    if #out == 0 then out[1] = "" end
    return out
end

function BR.pointInRect(px, py, r)
    return r and px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

-- Rough perceived-lightness test for a "#rrggbb" string.
function BR.isDark(str)
    if type(str) ~= "string" then return false end
    local h = str:match("#?(%x%x%x%x%x%x)")
    if not h then return false end
    local r = tonumber(h:sub(1, 2), 16)
    local g = tonumber(h:sub(3, 4), 16)
    local b = tonumber(h:sub(5, 6), 16)
    return (0.299 * r + 0.587 * g + 0.114 * b) < 130
end

-- Depth-first search of a parsed markup tree for the first node matching pred.
function BR.findNode(node, pred)
    if pred(node) then return node end
    for _, c in ipairs(node.children or {}) do
        local found = BR.findNode(c, pred)
        if found then return found end
    end
    return nil
end

-- Group digits: 48000 -> "48,000".
function BR.groupDigits(n)
    local s = tostring(math.floor(math.abs(tonumber(n) or 0)))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
