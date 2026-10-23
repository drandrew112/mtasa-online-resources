-- News storage: the MySQL `news` + `news_texts` tables (through v_mysql) with
-- an in-memory copy.
--
-- An article is { id, date, author, texts = { [lang] = { title, body } } };
-- `date` is a unix timestamp the admin may set freely. An article may be
-- written in any of the enabled v_locals languages (at least one). A reader
-- gets its own language, else the language's fallback, else the default
-- language (English), else the first one written (resolve()).
-- An article whose date is in the future is "scheduled": it is listed in the
-- editor but getLatestNews() leaves it out until the date passes. Deleting is
-- soft (deleted_at > 0).
--
-- Articles from before the languages (title / body in `news` only) count as
-- English: load() copies them into `news_texts` once.

STORE = {}

local articles = {}   -- sorted newest first: { id, date, author, texts }
local loaded = false
local publicIds = ""  -- ids of the published articles, to notice a scheduled one going live

addEvent("onNewsChanged")

local function dbReady()
    local res = getResourceFromName("v_mysql")
    return res and getResourceState(res) == "running" and exports.v_mysql:mysqlIsConnected() == true
end

local function now() return getRealTime().timestamp end

--------------------------------------------------------------------------------
-- languages
--------------------------------------------------------------------------------

-- { order = { "en", "hu" }, enabled = { en = true }, fallback = { hu = "en" } } of v_locals
local function languages()
    local order, enabled, fallback = {}, {}, {}
    local ok, list = pcall(function() return exports.v_locals:getLanguages() end)
    for _, l in ipairs(ok and type(list) == "table" and list or {}) do
        order[#order + 1] = l.value
        enabled[l.value] = true
    end
    local ok2, info = pcall(function() return exports.v_locals:getLanguageInfo() end)
    for code, l in pairs(ok2 and type(info) == "table" and info or {}) do
        if type(l) == "table" and type(l.fallback) == "string" then fallback[code] = l.fallback end
    end
    if #order == 0 then order, enabled = { NEWS.DEFAULT_LANG }, { [NEWS.DEFAULT_LANG] = true } end
    return { order = order, enabled = enabled, fallback = fallback }
end
STORE.languages = languages

-- a player (its v_locals language) or a language code -> code | nil
local function langOf(who)
    if isElement(who) then
        local ok, code = pcall(function() return exports.v_locals:getPlayerLanguage(who) end)
        return ok and type(code) == "string" and code or nil
    end
    return type(who) == "string" and who ~= "" and who or nil
end

-- the language of `texts` a reader of `lang` gets
local function resolveLang(texts, lang, langs)
    local seen = {}
    while lang and not seen[lang] do
        if texts[lang] then return lang end
        seen[lang] = true
        lang = langs.fallback[lang]
    end
    if texts[NEWS.DEFAULT_LANG] then return NEWS.DEFAULT_LANG end
    for _, code in ipairs(langs.order) do
        if texts[code] then return code end
    end
    local first
    for code in pairs(texts) do
        if not first or code < first then first = code end
    end
    return first
end

local function copyTexts(texts)
    local out = {}
    for code, t in pairs(texts) do out[code] = { title = t.title, body = t.body } end
    return out
end

-- { id, date, author, lang, title, body, texts } for a reader of `lang`
local function copy(a, lang, langs)
    local code = resolveLang(a.texts, lang, langs)
    local t = code and a.texts[code] or { title = "", body = "" }
    return { id = a.id, date = a.date, author = a.author, lang = code, title = t.title, body = t.body,
             texts = copyTexts(a.texts) }
end

--------------------------------------------------------------------------------

local function sortArticles()
    table.sort(articles, function(a, b)
        if a.date ~= b.date then return a.date > b.date end
        return a.id > b.id
    end)
end

local function currentPublicIds()
    local t, ids = now(), {}
    for _, a in ipairs(articles) do
        if a.date <= t then ids[#ids + 1] = a.id end
    end
    return table.concat(ids, ",")
end

local function changed()
    publicIds = currentPublicIds()
    triggerEvent("onNewsChanged", resourceRoot)
end

function STORE.isLoaded() return loaded end

function STORE.load()
    if not dbReady() then return false end
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. NEWS.TABLE .. [[` (
        `id`           INT AUTO_INCREMENT PRIMARY KEY,
        `published_at` INT          NOT NULL DEFAULT 0,
        `title`        VARCHAR(255) NOT NULL DEFAULT '',
        `body`         TEXT         NOT NULL,
        `author`       VARCHAR(64)  NOT NULL DEFAULT '',
        `created_at`   INT          NOT NULL DEFAULT 0,
        `updated_at`   INT          NOT NULL DEFAULT 0,
        `deleted_at`   INT          NOT NULL DEFAULT 0,
        KEY `idx_published` (`published_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    exports.v_mysql:mysqlExec([[CREATE TABLE IF NOT EXISTS `]] .. NEWS.TEXTS_TABLE .. [[` (
        `news_id` INT          NOT NULL,
        `lang`    VARCHAR(8)   NOT NULL,
        `title`   VARCHAR(255) NOT NULL DEFAULT '',
        `body`    TEXT         NOT NULL,
        PRIMARY KEY (`news_id`, `lang`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- articles from before the languages: their title / body is the English version
    exports.v_mysql:mysqlExec("INSERT INTO `" .. NEWS.TEXTS_TABLE .. "` (news_id, lang, title, body) SELECT n.id, ?, n.title, n.body FROM `"
        .. NEWS.TABLE .. "` n WHERE n.title <> '' AND NOT EXISTS (SELECT 1 FROM `" .. NEWS.TEXTS_TABLE .. "` t WHERE t.news_id = n.id)",
        NEWS.DEFAULT_LANG)

    local rows = exports.v_mysql:mysqlQuerySync("SELECT id, published_at, title, body, author FROM `"
        .. NEWS.TABLE .. "` WHERE deleted_at = 0")
    if type(rows) ~= "table" then return false end
    local textRows = exports.v_mysql:mysqlQuerySync("SELECT t.news_id, t.lang, t.title, t.body FROM `" .. NEWS.TEXTS_TABLE
        .. "` t JOIN `" .. NEWS.TABLE .. "` n ON n.id = t.news_id WHERE n.deleted_at = 0")
    if type(textRows) ~= "table" then return false end

    local byId = {}
    articles = {}
    for _, row in ipairs(rows) do
        local a = { id = tonumber(row.id), date = tonumber(row.published_at) or 0, author = tostring(row.author or ""), texts = {} }
        byId[a.id] = a
        articles[#articles + 1] = a
    end
    for _, row in ipairs(textRows) do
        local a = byId[tonumber(row.news_id)]
        if a and type(row.lang) == "string" then
            a.texts[row.lang] = { title = tostring(row.title or ""), body = tostring(row.body or "") }
        end
    end
    -- the copy above has not run yet (same round) or failed: use the old columns
    for _, row in ipairs(rows) do
        local a = byId[tonumber(row.id)]
        if not next(a.texts) and tostring(row.title or "") ~= "" then
            a.texts[NEWS.DEFAULT_LANG] = { title = tostring(row.title), body = tostring(row.body or "") }
        end
    end
    sortArticles()
    loaded = true
    publicIds = currentPublicIds()
    return true
end

-- Every article (scheduled ones too), newest first, for a reader of `who`.
function STORE.all(who)
    local lang, langs, out = langOf(who), languages(), {}
    for i, a in ipairs(articles) do out[i] = copy(a, lang, langs) end
    return out
end

-- The newest `n` published articles for a reader of `who` (player | language code | nil = default).
function STORE.latest(n, who)
    n = math.max(1, math.floor(tonumber(n) or 5))
    local lang, langs = langOf(who), languages()
    local t, out = now(), {}
    for _, a in ipairs(articles) do
        if a.date <= t then
            out[#out + 1] = copy(a, lang, langs)
            if #out >= n then break end
        end
    end
    return out
end

local function find(id)
    for i, a in ipairs(articles) do
        if a.id == id then return a, i end
    end
end

local function writeTexts(id, texts)
    exports.v_mysql:mysqlExec("DELETE FROM `" .. NEWS.TEXTS_TABLE .. "` WHERE news_id = ?", id)
    local marks, args = {}, {}
    for code, t in pairs(texts) do
        marks[#marks + 1] = "(?, ?, ?, ?)"
        args[#args + 1], args[#args + 2], args[#args + 3], args[#args + 4] = id, code, t.title, t.body
    end
    if #marks == 0 then return true end
    return exports.v_mysql:mysqlExec("INSERT INTO `" .. NEWS.TEXTS_TABLE .. "` (news_id, lang, title, body) VALUES "
        .. table.concat(marks, ", "), unpack(args))
end

-- Creates (id = nil) or updates an article; `texts` = { [lang] = { title, body } }
-- (every language of the article: the missing ones are removed). Returns the id or false.
function STORE.save(id, date, texts, author)
    if not dbReady() then return false end
    local t = now()
    -- `news`.title / body keep the default version, so the table stays readable on its own
    local main = texts[resolveLang(texts, NEWS.DEFAULT_LANG, languages())]
    if id then
        local a = find(id)
        if not a then return false end
        if not exports.v_mysql:mysqlExec("UPDATE `" .. NEWS.TABLE
            .. "` SET published_at = ?, title = ?, body = ?, updated_at = ? WHERE id = ?",
            date, main.title, main.body, t, id) then return false end
        if not writeTexts(id, texts) then return false end
        a.date, a.texts = date, copyTexts(texts)
    else
        id = exports.v_mysql:mysqlInsert("INSERT INTO `" .. NEWS.TABLE
            .. "` (published_at, title, body, author, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)",
            date, main.title, main.body, author, t, t)
        if type(id) ~= "number" then return false end
        if not writeTexts(id, texts) then return false end
        articles[#articles + 1] = { id = id, date = date, author = author, texts = copyTexts(texts) }
    end
    sortArticles()
    changed()
    return id
end

function STORE.delete(id)
    local _, i = find(id)
    if not i or not dbReady() then return false end
    if not exports.v_mysql:mysqlExec("UPDATE `" .. NEWS.TABLE .. "` SET deleted_at = ? WHERE id = ?", now(), id) then
        return false
    end
    table.remove(articles, i)
    changed()
    return true
end

--------------------------------------------------------------------------------
-- exports
--------------------------------------------------------------------------------

function getLatestNews(n, who) return STORE.latest(n, who) end
function getAllNews(who) return STORE.all(who) end

--------------------------------------------------------------------------------

addEvent("mysql:connected")

addEventHandler("onResourceStart", resourceRoot, function()
    if not STORE.load() then
        outputServerLog("[v_news] v_mysql not connected yet, waiting for mysql:connected")
    end
end)

-- v_mysql (re)connected: load the table if we could not do it yet
addEventHandler("mysql:connected", root, function()
    if not loaded and STORE.load() then changed() end
end)

-- a scheduled article became public
setTimer(function()
    if loaded and currentPublicIds() ~= publicIds then changed() end
end, NEWS.DUE_CHECK, 0)
