if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Help search: case and accent insensitive, every query word must match.
--
--   Search.run(query) -> nil (empty query) | { { id, topic, title, category, snippet, score }, ... }
--
-- Score per word: title (word start 12 / inside 7), keywords (6 / 3),
-- category name 3, page text 1 per hit (at most 5).

Search = {}

local FOLD = {
    ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ö"] = "o", ["ő"] = "o",
    ["ú"] = "u", ["ü"] = "u", ["ű"] = "u",
}

local SNIPPET_BEFORE, SNIPPET_LEN = 24, 120

-- one character in, one character out (except colour codes), so character
-- positions of a stripped text and its normalized form line up
local function norm(s)
    s = L.lower(tostring(s or ""))
    s = s:gsub("#%x%x%x%x%x%x", "")
    s = s:gsub("[\195\197][\128-\191]", FOLD)
    s = s:gsub("[!-/:-@%[-`{-~]", " ") -- ASCII punctuation (%p depends on the C locale)
    return s
end
Search.norm = norm

local function index(t)
    local lang = L.lang()
    local ix = t.sindex
    if ix and ix.lang == lang then return ix end
    local d = Help.topicData(t)
    local lines = {}
    for i, l in ipairs(d.doc.plain) do lines[i] = { orig = l, norm = norm(l) } end
    ix = {
        lang  = lang,
        title = norm(d.title),
        kw    = norm(d.keywords),
        lines = lines,
    }
    t.sindex = ix
    return ix
end

local function count(s, tok, limit, n)
    local pos = 1
    while n < limit do
        local a, b = s:find(tok, pos, true)
        if not a then break end
        n, pos = n + 1, b + 1
    end
    return n
end

local function snippet(ix, tok)
    for _, l in ipairs(ix.lines) do
        local a = tok and l.norm:find(tok, 1, true)
        if a then
            local ci = L.len(l.norm:sub(1, a - 1)) + 1
            local start = math.max(1, ci - SNIPPET_BEFORE)
            local s = L.sub(l.orig, start, start + SNIPPET_LEN)
            if start == 1 then return s end
            -- start at a word boundary when there is one before the hit
            local sp = L.sub(l.orig, start, ci - 1):find(" ", 1, true)
            if sp then s = s:sub(sp + 1) end
            return "…" .. s
        end
    end
    local first = ix.lines[1]
    return first and L.sub(first.orig, 1, SNIPPET_LEN) or ""
end

function Search.run(query)
    local tokens = {}
    for w in norm(query):gmatch("%S+") do tokens[#tokens + 1] = w end
    if #tokens == 0 then return nil end

    local out = {}
    for _, t in pairs(Help.topics) do
        local ix = index(t)
        local cat = norm(Help.categoryTitle(t.category))
        local total, bodyTok = 0, nil
        for _, tok in ipairs(tokens) do
            local s = 0
            if (" " .. ix.title):find(" " .. tok, 1, true) then s = s + 12
            elseif ix.title:find(tok, 1, true) then s = s + 7 end
            if (" " .. ix.kw):find(" " .. tok, 1, true) then s = s + 6
            elseif ix.kw:find(tok, 1, true) then s = s + 3 end
            if cat:find(tok, 1, true) then s = s + 3 end
            local n = 0
            for _, l in ipairs(ix.lines) do
                n = count(l.norm, tok, 5, n)
                if n >= 5 then break end
            end
            if n > 0 then
                s = s + n
                bodyTok = bodyTok or tok
            end
            if s == 0 then total = nil break end
            total = total + s
        end
        if total then
            out[#out + 1] = {
                id       = t.id,
                topic    = t,
                title    = Help.topicData(t).title,
                category = Help.categoryTitle(t.category),
                snippet  = snippet(ix, bodyTok),
                score    = total,
            }
        end
    end

    table.sort(out, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        return L.lower(a.title) < L.lower(b.title)
    end)
    return out
end
