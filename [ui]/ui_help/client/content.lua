if not L then loadstring(exports.v_locals:import())() end -- v_locals lib (DESIGN.md 4.7)
-- Help topic registry (client).
--
-- Sources:
--   * content/index.lua (HELP_INDEX): categories and topics whose text lives in
--     content/<lang>/<file> (falls back to content/en/<file>)
--   * other resources at runtime: exports.ui_help:addHelpTopic / addHelpCategory
--     (client/exports.lua); removed automatically when that resource stops
--
-- Text sources (title, text, keywords) may be a plain string, a v_locals
-- message object { t = key, p = params } or a per-language table
-- { en = "...", hu = "..." }.

Help = {
    categories = {}, -- id -> { id, order, title, owner }
    topics     = {}, -- id -> { id, category, order, file, title, text, keywords, related, hidden, owner, cache }
    revision   = 0,  -- bumped on every change, list caches compare against it
}

local FALLBACK_LANG = "en"
Help.OTHER = "other" -- built-in category for topics without a known category

local function changed()
    Help.revision = Help.revision + 1
end

function Help.resolve(src)
    if type(src) ~= "table" then return src end
    if L.isMsg(src) then return L.resolve(src) end
    local v = src[L.lang()] or src[FALLBACK_LANG]
    if v == nil then
        for _, x in pairs(src) do v = x break end
    end
    return v
end

local function keywordsText(src)
    local v = src
    if type(v) == "table" and v[1] == nil then v = Help.resolve(v) end
    if type(v) == "table" then v = table.concat(v, ", ") end
    return type(v) == "string" and v or ""
end

local function readFile(path)
    if not fileExists(path) then return nil end
    local f = fileOpen(path, true)
    if not f then return nil end
    local size = fileGetSize(f)
    local s = size > 0 and fileRead(f, size) or ""
    fileClose(f)
    return s or nil
end

-- content/<lang>/<file>, then the English file
function Help.readContent(file)
    return readFile("content/" .. L.lang() .. "/" .. file)
        or readFile("content/" .. FALLBACK_LANG .. "/" .. file)
end

--------------------------------------------------------------------------------
-- registry
--------------------------------------------------------------------------------

function Help.addCategory(id, def, owner)
    if type(id) ~= "string" or id == "" then return false end
    def = type(def) == "table" and def or {}
    Help.categories[id] = { id = id, order = tonumber(def.order) or 100, title = def.title or id, owner = owner }
    changed()
    return true
end

function Help.removeCategory(id)
    if not Help.categories[id] then return false end
    Help.categories[id] = nil
    changed()
    return true
end

function Help.addTopic(id, def, owner)
    if type(id) ~= "string" or id == "" or type(def) ~= "table" then return false end
    if not def.file and def.text == nil then return false end
    Help.topics[id] = {
        id       = id,
        category = type(def.category) == "string" and def.category or Help.OTHER,
        order    = tonumber(def.order) or 100,
        file     = def.file,
        title    = def.title,
        text     = def.text,
        keywords = def.keywords,
        related  = type(def.related) == "table" and def.related or nil,
        hidden   = def.hidden == true,
        owner    = owner,
    }
    changed()
    return true
end

function Help.removeTopic(id)
    if not Help.topics[id] then return false end
    Help.topics[id] = nil
    changed()
    return true
end

function Help.removeOwned(owner)
    local n = 0
    for id, t in pairs(Help.topics) do
        if t.owner == owner then Help.topics[id] = nil n = n + 1 end
    end
    for id, c in pairs(Help.categories) do
        if c.owner == owner then Help.categories[id] = nil n = n + 1 end
    end
    if n > 0 then changed() end
end

function Help.isEmpty()
    return next(Help.topics) == nil
end

--------------------------------------------------------------------------------
-- resolved data (cached per language)
--------------------------------------------------------------------------------

-- { lang, doc (Markup.parse), title, keywords, related = { id, ... } }
function Help.topicData(t)
    local lang = L.lang()
    local c = t.cache
    if c and c.lang == lang then return c end

    local text
    if t.file then text = Help.readContent(t.file) else text = Help.resolve(t.text) end
    local doc = Markup.parse(type(text) == "string" and text or "")

    local kw = keywordsText(t.keywords)
    if doc.keywords ~= "" then kw = (kw == "") and doc.keywords or (kw .. ", " .. doc.keywords) end

    local related, seen = {}, {}
    for _, list in ipairs({ t.related or {}, doc.related }) do
        for _, id in ipairs(list) do
            if type(id) == "string" and id ~= t.id and not seen[id] then
                seen[id] = true
                related[#related + 1] = id
            end
        end
    end

    local title = Help.resolve(t.title)
    c = {
        lang     = lang,
        doc      = doc,
        title    = (type(title) == "string" and title ~= "") and title or doc.title or t.id,
        keywords = kw,
        related  = related,
    }
    t.cache = c
    return c
end

function Help.categoryTitle(id)
    local cat = Help.categories[id]
    if not cat then return L("ui_help.category.other") end
    local title = Help.resolve(cat.title)
    return type(title) == "string" and title or id
end

-- categories that have listed topics, sorted:
-- { { id, title, order, topics = { topic, ... } }, ... }
local listCache, listKey
function Help.list()
    local key = Help.revision .. "|" .. L.lang()
    if listKey == key then return listCache end

    local groups = {}
    for _, t in pairs(Help.topics) do
        if not t.hidden then
            local cid = Help.categories[t.category] and t.category or Help.OTHER
            groups[cid] = groups[cid] or {}
            table.insert(groups[cid], t)
        end
    end

    local out = {}
    for cid, list in pairs(groups) do
        table.sort(list, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return L.lower(Help.topicData(a).title) < L.lower(Help.topicData(b).title)
        end)
        local cat = Help.categories[cid]
        out[#out + 1] = { id = cid, title = Help.categoryTitle(cid), order = cat and cat.order or math.huge, topics = list }
    end
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return L.lower(a.title) < L.lower(b.title)
    end)

    listCache, listKey = out, key
    return out
end

-- landing page from HELP_INDEX.home (nil when there is none)
local homeCache
function Help.homeDoc()
    local file = type(HELP_INDEX) == "table" and HELP_INDEX.home
    if not file then return nil end
    local lang = L.lang()
    if homeCache and homeCache.lang == lang then return homeCache.doc end
    local text = Help.readContent(file)
    homeCache = { lang = lang, doc = text and Markup.parse(text) or nil }
    return homeCache.doc
end

--------------------------------------------------------------------------------
-- startup
--------------------------------------------------------------------------------

if type(HELP_INDEX) == "table" then
    for _, c in ipairs(HELP_INDEX.categories or {}) do Help.addCategory(c.id, c) end
    for _, t in ipairs(HELP_INDEX.topics or {}) do
        if not Help.addTopic(t.id, t) then
            outputDebugString("[ui_help] invalid topic in content/index.lua: " .. tostring(t.id), 2)
        end
    end
end

L.onChange(function() changed() end)
