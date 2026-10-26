if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Help text format (README.md): parser and layout. Drawing is in panel.lua.
--
--   Markup.parse(text)               -> doc { title, keywords, related, blocks, plain }
--   Markup.layout(blocks, w, st, hd) -> { items = { ... }, h }
--
-- Layout items use coordinates relative to the page origin:
--   text   { x, y, w, h, lines, lh, F, color }
--   marker { x, y, w, h, text, F, color }       list bullet / number
--   box    { x, y, w, h, kind }                 tip / warning background
--   rule   { x, y, w, h, color }
--   img    { x, y, w, h, tex }
--   link   { x, y, w, h, id, label, F, missing }

Markup = {}

local floor, max, min = math.floor, math.max, math.min

local function trim(s)
    return (s:match("^%s*(.-)%s*$"))
end

local function strip(s)
    return (s:gsub("%*%*", ""):gsub("`", ""):gsub("#%x%x%x%x%x%x", ""))
end

--------------------------------------------------------------------------------
-- parser
--------------------------------------------------------------------------------

function Markup.parse(text)
    local doc = { title = nil, keywords = "", related = {}, blocks = {}, plain = {} }
    local blocks = doc.blocks
    local open = nil    -- block the next plain line continues (p / li)
    local prevBox = nil -- kind of box the previous line belonged to

    local function add(b)
        blocks[#blocks + 1] = b
        return b
    end

    local function join(b, line)
        if b.text:sub(-1) == "\\" then
            b.text = b.text:sub(1, -2) .. "\n" .. line
        else
            b.text = b.text .. " " .. line
        end
    end

    text = tostring(text or ""):gsub("^\239\187\191", ""):gsub("\r", "")
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = trim(raw)
        local indent = #raw:match("^(%s*)")
        local hashes, htext = line:match("^(#+)%s+(.+)$")
        local imgH, imgPath = line:match("^!%[(%d*)%]%((.-)%)$")
        local linkInner = line:match("^%[%[(.-)%]%]$")
        local warn = line:match("^>!%s?(.*)$")
        local note = not warn and line:match("^>%s?(.*)$")
        local bInd, bText = raw:match("^(%s*)[%-%*%+]%s+(.*)$")
        local nInd, nNum, nText = raw:match("^(%s*)(%d+)[%.%)]%s+(.*)$")

        if line == "" then
            open = nil

        elseif line:sub(1, 1) == "@" then
            local k, v = line:match("^@(%a+)%s*:?%s*(.*)$")
            k = k and k:lower()
            if k == "keywords" then
                doc.keywords = (doc.keywords == "") and v or (doc.keywords .. ", " .. v)
            elseif k == "related" then
                for id in v:gmatch("[^,%s]+") do doc.related[#doc.related + 1] = id end
            elseif k == "title" then
                doc.title = v
            end
            open = nil

        elseif hashes then
            local n = #hashes
            if n == 1 and not doc.title and #blocks == 0 then
                doc.title = htext
            else
                add({ k = (n == 1 and "h1") or (n == 2 and "h2") or "h3", text = htext })
            end
            open = nil

        elseif line:match("^%-%-%-+$") or line:match("^%*%*%*+$") then
            add({ k = "hr" })
            open = nil

        elseif imgPath then
            add({ k = "img", path = trim(imgPath), h = tonumber(imgH) })
            open = nil

        elseif linkInner then
            local id, label = linkInner:match("^([^|]*)|?(.*)$")
            add({ k = "link", id = trim(id), label = trim(label) })
            open = nil

        elseif warn or note then
            local kind = warn and "warn" or "note"
            local body = warn or note
            local last = blocks[#blocks]
            if last and last.k == kind and prevBox == kind then
                last.text = last.text .. "\n" .. body
            else
                add({ k = kind, text = body })
            end
            open = nil

        elseif bText and not line:match("^%*%*") then
            open = add({ k = "li", level = min(3, 1 + floor(#bInd / 2)), text = trim(bText) })

        elseif nText then
            open = add({ k = "li", level = min(3, 1 + floor(#nInd / 2)), num = tonumber(nNum), text = trim(nText) })

        elseif open and (open.k == "p" or (open.k == "li" and indent > 0)) then
            join(open, line)

        else
            open = add({ k = "p", text = line })
        end

        -- a tip / warning box only continues on the very next line
        prevBox = (warn and "warn") or (note and "note") or nil
    end

    for _, b in ipairs(blocks) do
        if b.text then
            b.text = b.text:gsub("\\$", "")
            for l in (strip(b.text) .. "\n"):gmatch("([^\n]*)\n") do
                if l ~= "" then doc.plain[#doc.plain + 1] = l end
            end
        elseif b.k == "link" and b.label ~= "" then
            doc.plain[#doc.plain + 1] = strip(b.label)
        end
    end
    if doc.title then doc.title = trim(doc.title) end
    return doc
end

--------------------------------------------------------------------------------
-- images (loaded on layout, freed when the panel closes)
--------------------------------------------------------------------------------

local textures = {}

local function texture(path)
    local t = textures[path]
    if t == nil then
        t = fileExists(path) and dxCreateTexture(path, "argb", true, "clamp") or false
        if not t then outputDebugString("[ui_help] image not found: " .. tostring(path), 2) end
        textures[path] = t
    end
    return t or nil
end

function Markup.freeTextures()
    for _, t in pairs(textures) do
        if t and isElement(t) then destroyElement(t) end
    end
    textures = {}
end

--------------------------------------------------------------------------------
-- layout
--------------------------------------------------------------------------------

local function lastCode(s)
    local c
    for m in s:gmatch("#%x%x%x%x%x%x") do c = m end
    return c
end

-- L.wrap, but a colour started on one line carries over to the next
local function wrap(text, w, F)
    local src = L.wrap(text, w, F.s, F.f, true)
    local out, carry = {}, nil
    for i, line in ipairs(src) do
        if carry then line = carry .. line end
        out[i] = line
        carry = lastCode(line) or carry
    end
    return out
end

-- **strong** and `code` become colour codes
local function inline(text, st, base)
    text = text:gsub("%*%*(.-)%*%*", "#" .. st.hex.strong .. "%1#" .. base)
    text = text:gsub("`(.-)`", "#" .. st.hex.code .. "%1#" .. base)
    return text
end

local MARKERS = { "•", "–", "·" }

-- st = { fonts = F, hex = { text, h, strong, code }, S = scale function }
-- header = { crumb, title } drawn above the blocks (optional)
function Markup.layout(blocks, w, st, header)
    local F, S = st.fonts, st.S
    local items, y, pending = {}, 0, 0

    local function gap(top)
        if #items > 0 then y = y + max(pending, S(top)) end
        pending = 0
    end

    local function addText(x, text, font, color, tw)
        local lines = wrap(text, tw, font)
        local lh = floor(font.h * 1.32 + 0.5)
        local it = { k = "text", x = x, y = y, w = tw, h = #lines * lh, lines = lines, lh = lh, F = font, color = color }
        items[#items + 1] = it
        y = y + it.h
        return it
    end

    if header then
        if header.crumb and header.crumb ~= "" then
            addText(0, L.upper(header.crumb), F.smallB, "accent", w)
            y = y + S(4)
        end
        addText(0, header.title or "", F.title, "h", w)
        y = y + S(14)
        items[#items + 1] = { k = "rule", x = 0, y = y, w = w, h = 1, color = "line" }
        y = y + 1
        pending = S(22)
    end

    for i, b in ipairs(blocks) do
        local nxt = blocks[i + 1]
        local k = b.k

        if k == "h1" or k == "h2" or k == "h3" then
            gap(k == "h1" and 28 or k == "h2" and 24 or 16)
            addText(0, inline(b.text, st, st.hex.h), F[k], "h", w)
            if k ~= "h3" then
                y = y + S(6)
                items[#items + 1] = { k = "rule", x = 0, y = y, w = w, h = 1, color = "line" }
                y = y + 1
            end
            pending = S(k == "h3" and 8 or 12)

        elseif k == "p" then
            gap(0)
            addText(0, inline(b.text, st, st.hex.text), F.body, "text", w)
            pending = S(14)

        elseif k == "li" then
            local prev = blocks[i - 1]
            gap((prev and prev.k == "li") and 0 or 2)
            local ind = S(24) * b.level
            local mark = b.num and (b.num .. ".") or MARKERS[b.level]
            local lh = floor(F.body.h * 1.32 + 0.5)
            items[#items + 1] = { k = "marker", x = ind - S(34), y = y, w = S(24), h = lh, text = mark,
                F = b.num and F.bodyB or F.body, color = "accent" }
            addText(ind, inline(b.text, st, st.hex.text), F.body, "text", w - ind)
            pending = (nxt and nxt.k == "li") and S(5) or S(14)

        elseif k == "note" or k == "warn" then
            gap(8)
            local padX, padY = S(18), S(12)
            local at, y0 = #items + 1, y
            y = y + padY
            addText(padX, L(k == "warn" and "ui_help.block.warning" or "ui_help.block.tip"), F.smallB,
                k == "warn" and "warn" or "accent", w - padX * 2)
            y = y + S(4)
            addText(padX, inline(b.text, st, st.hex.text), F.body, "text", w - padX * 2)
            y = y + padY
            table.insert(items, at, { k = "box", x = 0, y = y0, w = w, h = y - y0, kind = k })
            pending = S(16)

        elseif k == "hr" then
            gap(12)
            items[#items + 1] = { k = "rule", x = 0, y = y, w = w, h = 1, color = "line" }
            y = y + 1
            pending = S(16)

        elseif k == "img" then
            local tex = texture(b.path)
            if tex then
                gap(8)
                local tw, th = dxGetMaterialSize(tex)
                local h = b.h and S(b.h) or th * S(1)
                local iw = tw * h / th
                if iw > w then iw, h = w, th * w / tw end
                items[#items + 1] = { k = "img", x = 0, y = y, w = iw, h = h, tex = tex }
                y = y + h
                pending = S(16)
            end

        elseif k == "link" then
            gap(0)
            local t = Help.topics[b.id]
            local label = b.label
            if label == "" then label = t and Help.topicData(t).title or b.id end
            local h = floor(F.body.h + S(14))
            items[#items + 1] = { k = "link", x = 0, y = y, w = w, h = h, id = b.id, label = label,
                F = F.body, missing = t == nil }
            y = y + h
            pending = (nxt and nxt.k == "link") and S(2) or S(14)
        end
    end

    return { items = items, h = y }
end
