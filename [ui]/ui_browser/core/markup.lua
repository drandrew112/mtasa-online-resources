-- ui_browser :: core/markup.lua
-- Egyszerusitett, HTML-szeru markup elemzo. Nem valodi HTML: csak a bongeszo
-- altal ismert cimkeket ertelmezi, es sajat komponensei vannak
-- (searchbox, catbtn, sitecard, hero). Az eredmeny egy fa:
--   node = { tag = "p", attrs = {...}, children = { ... } }
--   szoveg-csomopont = { tag = "#text", text = "..." }

-- Ezek a cimkek nem tartalmaznak gyerekeket (nincs zaro parjuk).
local VOID = {
    img = true, hr = true, br = true, space = true,
    searchbox = true, input = true, logo = true,
    swatch = true, productimage = true,
}

local ENTITIES = {
    ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">",
    ["&quot;"] = '"', ["&#39;"] = "'", ["&nbsp;"] = " ",
}

local function decodeEntities(s)
    return (s:gsub("&#?%w+;", function(e) return ENTITIES[e] or e end))
end

local function parseAttrs(s)
    local a = {}
    for k, v in s:gmatch('([%w_%-:]+)%s*=%s*"([^"]*)"') do
        a[k:lower()] = decodeEntities(v)
    end
    for k, v in s:gmatch("([%w_%-:]+)%s*=%s*'([^']*)'") do
        if a[k:lower()] == nil then a[k:lower()] = decodeEntities(v) end
    end
    return a
end

local function addText(parent, raw)
    local text = raw:gsub("%s+", " ")
    if text == "" or text == " " then return end
    parent.children[#parent.children + 1] = { tag = "#text", text = decodeEntities(text) }
end

function BR.parseMarkup(src)
    src = tostring(src or "")
    src = src:gsub("<!%-%-.-%-%->", "")

    local root = { tag = "page", attrs = {}, children = {} }
    local stack = { root }
    local pos, n = 1, #src

    while pos <= n do
        local lt = src:find("<", pos, true)
        if not lt then
            addText(stack[#stack], src:sub(pos))
            break
        end
        if lt > pos then
            addText(stack[#stack], src:sub(pos, lt - 1))
        end

        local gt = src:find(">", lt + 1, true)
        if not gt then break end

        local inner = src:sub(lt + 1, gt - 1)
        pos = gt + 1

        if inner:sub(1, 1) == "/" then
            local name = inner:match("^/%s*([%w_%-]+)")
            if name then
                name = name:lower()
                for i = #stack, 2, -1 do
                    if stack[i].tag == name then
                        for j = #stack, i, -1 do stack[j] = nil end
                        break
                    end
                end
            end
        else
            local selfClose = inner:sub(-1) == "/"
            if selfClose then inner = inner:sub(1, -2) end

            local name, rest = inner:match("^%s*([%w_%-]+)%s*(.-)%s*$")
            if name then
                name = name:lower()
                local node = { tag = name, attrs = parseAttrs(rest or ""), children = {} }
                local parent = stack[#stack]
                parent.children[#parent.children + 1] = node
                if not selfClose and not VOID[name] then
                    stack[#stack + 1] = node
                end
            end
        end
    end

    -- Ha az egesz tartalmat egyetlen <page> fogja kozre, azt tesszuk gyokerre.
    if #root.children == 1 and root.children[1].tag == "page" then
        return root.children[1]
    end
    return root
end

-- Egy csomopont osszes leszarmazott szovege osszefuzve (inline szoveghez).
function BR.nodeText(node)
    if node.tag == "#text" then return node.text end
    local parts = {}
    for _, c in ipairs(node.children or {}) do
        parts[#parts + 1] = BR.nodeText(c)
    end
    return table.concat(parts)
end

-- Csak az elem-gyerekek (a szokoz-szoveg csomopontok kihagyasaval).
function BR.elementChildren(node)
    local t = {}
    for _, c in ipairs(node.children or {}) do
        if c.tag ~= "#text" then t[#t + 1] = c end
    end
    return t
end
